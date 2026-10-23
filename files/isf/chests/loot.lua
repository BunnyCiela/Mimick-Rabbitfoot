-- files/isf/chests/loot.lua
--
-- ISF-05 chest-loot predictor: a deterministic, side-effect-free port of the
-- vanilla reward loops.
--
-- Primary source (read out of the installed data.wak, read-only):
--   data/scripts/items/chest_random.lua        drop_random_reward / on_open
--   data/scripts/items/chest_random_super.lua  drop_random_reward / on_open
--   data/scripts/biomes/coalmine.lua           spawn_chest (chest type lottery)
--   data/scripts/biome_scripts.lua             spawn_heart (second chest source)
--   data/scripts/gun/procedural/gun_procedural.lua  wand content seeding
--
-- MIT-licensed upstream references used for cross-checking only (never as
-- truth): noita-telescope js/chest_generation.js (Copyright (c) 2026 Lymm) and
-- noita-tools InfoProviders/ChestRandom.ts (Copyright (c) 2022 Seva Maltsev).
--
-- ---------------------------------------------------------------------------
-- WHAT THE GAME ACTUALLY DOES (each point verified in the files above)
-- ---------------------------------------------------------------------------
--
-- 1. `on_open` reads the chest's PositionSeedComponent. `rand_x`/`rand_y` come
--    from that component (i.e. the SPAWN position), NOT from the chest's
--    physical position at open time. A normal chest then adds (509.7, 683.1) and
--    a great chest adds (0, 0), and calls SetRandomSeed(rand_x, rand_y).
--
--    Consequence: chest CONTENT does not depend on where the chest has been
--    pushed to. Only the drop POSITIONS use the physical (x, y).
--
-- 2. The whole reward TABLE is rolled first, on that one stream: item kinds,
--    counts, gold amounts, loose-card draws and wand TYPES. Only afterwards are
--    the entities loaded ("deferred loading ... so that the SetRandomSeed() of
--    those entities will be deterministic").
--
-- 3. Loose cards are the exception: `make_random_card` runs inline and draws
--    `Random(1, #actions)` from the chest stream until it hits a valid action.
--    Validity (vanilla, exactly):
--        no spawn_requires_flag                  -> valid
--        has spawn_requires_flag                 -> valid iff HasFlagPersistent(flag)
--                                                   and spawn_probability ~= "0"
--    Note the `spawn_probability == "0"` test sits INSIDE the flag branch, so
--    the two unflagged probability-0 slots (SEA_SWAMP, SUMMON_PORTAL) ARE
--    droppable. Both upstream libraries model this differently.
--
-- 4. Wands and potions are loaded at (rand_x, rand_y), so their own content
--    generators seed from that same point -- every wand/potion dropped by one
--    chest shares one seed. `EntityApplyTransform` is applied *after* the load,
--    so the jitter never changes generated content.
--
-- 5. Deferred loads can reseed the global stream (potion.lua / the wand script
--    both call SetRandomSeed). That cannot affect the chest's composition
--    because every composition decision was already drawn in step 2. It DOES
--    make post-loop drop positions depend on engine details we do not model.
--    Positions are not scored by PRD R2, and this module never pretends to know
--    them.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local prng = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
if ( type( prng ) ~= "table" ) then
	error( "chests/loot: files/isf/random/prng.lua did not return a table" )
end

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" or type( spells.pool ) ~= "table" ) then
	error( "chests/loot: files/isf/data/spells.lua did not return the spell pool" )
end

local chest_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/chests.lua" )
if ( type( chest_data ) ~= "table" ) then
	error( "chests/loot: files/isf/data/chests.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

-- Hard safety bounds. Vanilla has no iteration cap (the reward table can only
-- grow by +2/+3 per iteration), so a real chest terminates; a cap exists purely
-- so a corrupted action table or a future game change cannot hang a scan. The
-- provider turns a hit cap into an error + partial coverage, never into a
-- silently truncated loot list.
M.MAX_REWARD_ITERATIONS = 4096
M.MAX_CARD_RETRIES = 4096

M.CHEST_NORMAL = "normal"
M.CHEST_SUPER = "super"

-- #actions in the game's action table. spells.pool is the same table in the
-- same order (tests/chests/data_spec.lua asserts that against the independent
-- extraction in tests/chests/fixtures/action_table.json).
M.ACTION_COUNT = #spells.pool

-- Reward-loop outcomes that are not items.
M.OUTCOME_ITEMS = "items"
M.OUTCOME_SAMPO = "sampo"          -- great chest, very-special shortcut
M.OUTCOME_CONVERTED_TO_GOLD = "converted_to_gold" -- normal chest, "chest turns
                                                  -- into gold", emits no items

-------------------------------------------------------------------------------
-- Card draws
-------------------------------------------------------------------------------

-- Card validity, exactly as chest_random.lua make_random_card() decides it.
--   entry.requires_flag ~= nil  -> the flag must be set AND the slot must not be
--                                  a probability-0 slot
--   entry.requires_flag == nil  -> always valid (even if spawn_probability is
--                                  "0"; see the module header, point 3)
local function card_slot_valid( entry, is_flag_set )
	if ( entry.requires_flag == nil ) then
		return true
	end
	if ( not is_flag_set( entry.requires_flag ) ) then
		return false
	end
	if ( chest_data.CARD_PROBABILITY_ZERO[ entry.id ] == true ) then
		return false
	end
	return true
end

-- make_random_card()'s rejection loop. Returns
--   spell_id, canonical upper-case id, retry_count
-- or nil, error_code, detail.
function M.draw_card( rng, is_flag_set )
	local pool = spells.pool
	local count = M.ACTION_COUNT
	for attempt = 1, M.MAX_CARD_RETRIES do
		local index = rng:Random( 1, count )
		-- The game indexes `actions` 1-based, so index is in [1, #actions].
		local entry = pool[ index ]
		if ( entry == nil ) then
			return nil, "bad_action_index", tostring( index )
		end
		if ( card_slot_valid( entry, is_flag_set ) ) then
			return entry.id, attempt
		end
	end
	return nil, "card_retry_limit",
		"no valid action after " .. tostring( M.MAX_CARD_RETRIES ) .. " draws"
end

-------------------------------------------------------------------------------
-- Seed frames
-------------------------------------------------------------------------------

-- The exact value `on_open` feeds to SetRandomSeed, per chest kind.
-- `x, y` must be the chest's SPAWN position (PositionSeedComponent pos_x/pos_y).
function M.chest_seed_frame( kind, x, y )
	local frame = chest_data.SEED_FRAME[ kind ]
	if ( frame == nil ) then
		return nil, "unknown chest kind " .. tostring( kind )
	end
	return {
		x = x + frame.offset_x,
		y = y + frame.offset_y,
		offset_x = frame.offset_x,
		offset_y = frame.offset_y,
		kind = kind,
	}
end

-- Chest type lottery of a biome `spawn_chest` marker (coalmine.lua:1193).
-- `Random(1, rate) >= rate-1` selects the great chest, i.e. 2/2000 in the
-- no-perk baseline (PRD's baseline: no perks picked, so no greed curse).
function M.roll_spawn_chest_type( seed, x, y, opts )
	opts = opts or {}
	local rate = opts.super_chest_rate or chest_data.BASELINE.super_chest_rate
	local rng = prng.new( seed )
	rng:SetRandomSeed( x, y )
	local rnd = rng:Random( 1, rate )
	return {
		kind = ( rnd >= rate - 1 ) and M.CHEST_SUPER or M.CHEST_NORMAL,
		roll = rnd,
		rate = rate,
		rng_state_after = rng:GetSeed(),
	}
end

-- `spawn_heart` (biome_scripts.lua:144) is a DISPATCH, not an entity:
--
--   r = ProceduralRandom(x, y)
--   heart_spawn_percent = 0.7;  if month==2 and day==14 then 0.35 end
--   r > percent          -> heart.xml
--   0.3 < r <= percent   -> reseed (x+45, y-2123); Random(1,100)
--                           deep (<=90 or y < 1536): Random(1,1000)
--                               <1000 -> normal chest, ==1000 -> great chest
--                           shallow: Random(1,100) <=95 ? chest_mimic : leggy
--   r <= 0.3             -> nothing at all
--
-- CALENDAR: the threshold is 0.35 on 14 February, so the band (0.35, 0.7] is
-- genuinely ambiguous without a date: it is a heart on 14 Feb and a chest
-- otherwise. `(0.3, 0.35]` is a chest branch on BOTH dates. When the band is
-- ambiguous and no calendar was supplied this returns kind = "unresolved" with
-- the reason — never a guess in either direction.
--
-- A `Random(1,300)` mimic-sign draw happens before the branch decision; it does
-- not change which object appears, so only the type-relevant draws are modelled.
--
-- Returns a table with `kind` in:
--   "heart_pickup" | "chest" | "chest_mimic" | "chest_leggy" | "nothing" | "unresolved"
function M.roll_heart_source( seed, x, y, opts )
	opts = opts or {}
	local rng = prng.new( seed )
	local r = rng:ProceduralRandom( x, y )

	-- Threshold from the vanilla calendar override, only when the caller pinned
	-- the date. An absent calendar does NOT default to 0.7: it makes the
	-- ambiguous band explicitly unresolved.
	local threshold = 0.7
	local calendar_applied = false
	local cal = opts.calendar
	if ( type( cal ) == "table" ) then
		if ( type( cal.month ) == "number" and type( cal.day ) == "number" ) then
			calendar_applied = true
			if ( cal.month == 2 and cal.day == 14 ) then
				threshold = 0.35
			end
		end
	end

	local result = {
		r = r,
		heart_spawn_percent = threshold,
		calendar_applied = calendar_applied,
		kind = "nothing",
		entity = nil,
		chest_kind = nil,
	}

	if ( r > threshold ) then
		result.kind = "heart_pickup"
		result.entity = "data/entities/items/pickup/heart.xml"
		return result
	end
	if ( r <= 0.3 ) then
		result.kind = "nothing"
		return result
	end

	-- 0.3 < r <= threshold. On 14 Feb this is always the chest branch; on other
	-- dates it is too. Only the (0.35, 0.7] band differs between the two dates.
	if ( not calendar_applied and r > 0.35 ) then
		result.kind = "unresolved"
		result.reason = string.format(
			"spawn_heart r=%.6f is in the (0.35, 0.7] band, which is a heart on 14 "
				.. "February and a chest on any other date; no calendar was supplied",
			r )
		return result
	end

	rng:SetRandomSeed( x + 45, y - 2123 )
	local rnd = rng:Random( 1, 100 )
	result.branch_roll = rnd
	result.deep_branch = ( rnd <= 90 ) or ( y < 512 * 3 )
	if ( result.deep_branch ) then
		local chest_roll = rng:Random( 1, 1000 )
		result.chest_roll = chest_roll
		result.kind = "chest"
		if ( chest_roll >= 1000 ) then
			result.chest_kind = M.CHEST_SUPER
		else
			result.chest_kind = M.CHEST_NORMAL
		end
		return result
	end

	local enemy_roll = rng:Random( 1, 100 )
	result.enemy_roll = enemy_roll
	if ( enemy_roll <= 95 ) then
		result.kind = "chest_mimic"
		result.entity = "data/entities/animals/chest_mimic.xml"
	else
		result.kind = "chest_leggy"
		result.entity = "data/entities/items/pickup/chest_leggy.xml"
	end
	return result
end

-- `spawn_bbqbox` (coalmine.lua:1226) is a Mines-only chest source: on <= 99 it
-- spawns enemies and then calls spawn_heart(x + 10, y + 10), so the *heart*
-- classification above decides whether a chest appears and at which position.
function M.roll_bbqbox_source( seed, x, y, opts )
	local rng = prng.new( seed )
	rng:SetRandomSeed( x, y )
	local rnd = rng:Random( 1, 100 )
	-- `kind` mirrors the heart vocabulary, plus the bbqbox-only branches:
	--   "urine_jar"  -> the else branch, no heart is drawn at all
	--   "else_branch"-> enemy branch guard, kept for clarity
	local result = { roll = rnd, kind = "none" }
	if ( rnd > 99 ) then
		result.kind = "urine_jar"
		result.entity = "data/entities/items/pickup/jar_of_urine.xml"
		result.outcome = "else_branch"
		return result
	end
	result.outcome = "enemy_branch"
	local heart = M.roll_heart_source( seed, x + 10, y + 10, opts )
	result.heart = heart
	result.kind = heart.kind
	result.entity = heart.entity
	result.chest_kind = heart.chest_kind
	result.reason = heart.reason
	-- EXACTLY ONE nested source position. There is no separate child record, and
	-- a caller must never add a second chest for the same bbqbox.
	result.chest_x = x + 10
	result.chest_y = y + 10
	return result
end

-------------------------------------------------------------------------------
-- Loot list helpers
-------------------------------------------------------------------------------

local function new_loot( kind, frame )
	return {
		chest_kind = kind,
		seed_frame = { x = frame.x, y = frame.y },
		items = {},
		iterations = 0,
		outcome = M.OUTCOME_ITEMS,
	}
end

local function push( loot, item )
	item.order = #loot.items + 1
	loot.items[ #loot.items + 1 ] = item
	return item
end

-------------------------------------------------------------------------------
-- Normal chest reward loop (chest_random.lua drop_random_reward)
-------------------------------------------------------------------------------
--
-- `x, y` is the chest's PHYSICAL position (used only for drop positions, which
-- are not scored); the RNG is seeded from the spawn-position frame, exactly as
-- `on_open` does.
function M.generate_normal( seed, frame_x, frame_y, x, y, opts )
	opts = opts or {}
	local is_flag_set = opts.is_flag_set or function() return false end
	local loot = new_loot( M.CHEST_NORMAL, { x = frame_x, y = frame_y } )

	local rng = prng.new( seed )
	rng:SetRandomSeed( frame_x, frame_y )

	local count = 1
	while ( count > 0 ) do
		count = count - 1
		loot.iterations = loot.iterations + 1
		if ( loot.iterations > M.MAX_REWARD_ITERATIONS ) then
			return nil, "reward_iteration_limit",
				"normal chest exceeded " .. tostring( M.MAX_REWARD_ITERATIONS ) .. " reward iterations"
		end

		local rnd = rng:Random( 1, 100 )

		if ( rnd <= 7 ) then
			-- Bomb. Queued without a position; loaded at the chest frame and
			-- then jittered (position not modelled, not scored).
			push( loot, {
				entity = "data/entities/projectiles/bomb_small.xml",
				reward_kind = "none",
				positioned = false,
			} )

		elseif ( rnd <= 40 ) then
			-- Gold. EVERY nugget position draw happens inline in the loop, so
			-- the stream advance here is load-bearing for what follows.
			local amount = 5
			rnd = rng:Random( 0, 100 )
			if ( rnd <= 80 ) then
				amount = 7
			elseif ( rnd <= 95 ) then
				amount = 10
			elseif ( rnd <= 100 ) then
				amount = 20
			end

			local function drop_gold( entity )
				push( loot, {
					entity = entity,
					reward_kind = "gold",
					positioned = true,
					x = x + rng:Random( -10, 10 ),
					y = y - 4 + rng:Random( -10, 5 ),
				} )
			end

			rnd = rng:Random( 0, 100 )
			if ( rnd > 30 and rnd <= 80 ) then
				drop_gold( "data/entities/items/pickup/goldnugget_50.xml" )
			elseif ( rnd <= 95 ) then
				drop_gold( "data/entities/items/pickup/goldnugget_200.xml" )
			elseif ( rnd <= 99 ) then
				drop_gold( "data/entities/items/pickup/goldnugget_1000.xml" )
			else
				local tamount = rng:Random( 1, 3 )
				for _ = 1, tamount do
					drop_gold( "data/entities/items/pickup/goldnugget_50.xml" )
				end
				if ( rng:Random( 0, 100 ) > 50 ) then
					tamount = rng:Random( 1, 3 )
					for _ = 1, tamount do
						drop_gold( "data/entities/items/pickup/goldnugget_200.xml" )
					end
				end
				if ( rng:Random( 0, 100 ) > 80 ) then
					tamount = rng:Random( 1, 3 )
					for _ = 1, tamount do
						drop_gold( "data/entities/items/pickup/goldnugget_1000.xml" )
					end
				end
			end

			for _ = 1, amount do
				drop_gold( "data/entities/items/pickup/goldnugget.xml" )
			end

		elseif ( rnd <= 50 ) then
			-- Potion / pouch.
			rnd = rng:Random( 0, 100 )
			local entity
			if ( rnd <= 94 ) then
				entity = "data/entities/items/pickup/potion.xml"
			elseif ( rnd <= 98 ) then
				entity = "data/entities/items/pickup/powder_stash.xml"
			elseif ( rnd <= 100 ) then
				rnd = rng:Random( 0, 100 )
				if ( rnd <= 98 ) then
					entity = "data/entities/items/pickup/potion_secret.xml"
				elseif ( rnd <= 100 ) then
					entity = "data/entities/items/pickup/potion_random_material.xml"
				end
			end
			if ( entity ~= nil ) then
				push( loot, {
					entity = entity,
					reward_kind = "none",
					positioned = false,
					container = true,
				} )
			end

		elseif ( rnd <= 54 ) then
			-- Spell refresh / illusion enemy.
			rnd = rng:Random( 0, 100 )
			local entity
			if ( rnd <= 98 ) then
				entity = "data/entities/items/pickup/spell_refresh.xml"
			else
				entity = "data/entities/animals/illusions/shaman_wind.xml"
			end
			push( loot, {
				entity = entity,
				reward_kind = "none",
				positioned = false,
			} )

		elseif ( rnd <= 60 ) then
			-- Misc items. `Random(1, #opts)` picks the slot; the die and orb
			-- slots additionally branch on persistent/run flags (no draw), the
			-- runestone slot consumes one `Random(1, 7)`.
			local opts_list = {
				"data/entities/items/pickup/safe_haven.xml",
				"data/entities/items/pickup/moon.xml",
				"data/entities/items/pickup/thunderstone.xml",
				"data/entities/items/pickup/evil_eye.xml",
				"data/entities/items/pickup/brimstone.xml",
				"runestone",
				"die",
				"orb",
			}
			rnd = rng:Random( 1, #opts_list )
			local opt = opts_list[ rnd ]
			if ( opt == "die" ) then
				-- HasFlagPersistent("card_unlocked_duplicate"); the greed-curse
				-- variant is out of the no-perk baseline.
				if ( is_flag_set( "card_unlocked_duplicate" ) ) then
					opt = "data/entities/items/pickup/physics_die.xml"
				else
					-- vanilla falls back to a plain potion
					opt = "data/entities/items/pickup/potion.xml"
				end
			elseif ( opt == "runestone" ) then
				local r_opts = { "laser", "fireball", "lava", "slow", "null", "disc", "metal" }
				rnd = rng:Random( 1, #r_opts )
				opt = "data/entities/items/pickup/runestones/runestone_" .. r_opts[ rnd ] .. ".xml"
			elseif ( opt == "orb" ) then
				opt = "data/entities/items/pickup/physics_gold_orb.xml"
			end
			push( loot, {
				entity = opt,
				reward_kind = "none",
				positioned = true,
				x = x,
				y = y - 10,
			} )

		elseif ( rnd <= 65 ) then
			-- Loose spell cards: the only inline, score-relevant RNG branch.
			local amount = 1
			rnd = rng:Random( 0, 100 )
			if ( rnd <= 50 ) then
				amount = 1
			elseif ( rnd <= 70 ) then
				amount = 2
			elseif ( rnd <= 80 ) then
				amount = 3
			elseif ( rnd <= 90 ) then
				amount = 4
			else
				amount = 5
			end

			for i = 1, amount do
				-- Argument evaluation order in vanilla: the jitter draw happens
				-- before make_random_card runs.
				local card_x = x + ( i - amount / 2 ) * 8
				local card_y = y - 4 + rng:Random( -5, 5 )
				local spell_id, retries_or_code, detail = M.draw_card( rng, is_flag_set )
				if ( spell_id == nil ) then
					return nil, retries_or_code, detail
				end
				push( loot, {
					entity = "Spell",
					reward_kind = "card_direct",
					positioned = true,
					spell_id = spell_id,
					card_slot = i,
					card_slot_count = amount,
					retries = retries_or_code,
					x = card_x,
					y = card_y,
				} )
			end

		elseif ( rnd <= 84 ) then
			-- Wand. Only the TYPE is rolled here; contents come from the wand
			-- generator at the chest seed frame (see the module header, 4).
			rnd = rng:Random( 0, 100 )
			local wand_type
			if ( rnd <= 25 ) then
				wand_type = "wand_level_01"
			elseif ( rnd <= 50 ) then
				wand_type = "wand_unshuffle_01"
			elseif ( rnd <= 75 ) then
				wand_type = "wand_level_02"
			elseif ( rnd <= 90 ) then
				wand_type = "wand_unshuffle_02"
			elseif ( rnd <= 96 ) then
				wand_type = "wand_level_03"
			elseif ( rnd <= 98 ) then
				wand_type = "wand_unshuffle_03"
			elseif ( rnd <= 99 ) then
				wand_type = "wand_level_04"
			elseif ( rnd <= 100 ) then
				wand_type = "wand_unshuffle_04"
			end
			push( loot, {
				entity = "data/entities/items/" .. wand_type .. ".xml",
				reward_kind = "wand",
				positioned = false,
				wand_type = wand_type,
				content_frame = { x = frame_x, y = frame_y },
			} )

		elseif ( rnd <= 95 ) then
			-- Hearts. `heart_fullhp` only refills hp and is NOT a max-HP pickup.
			rnd = rng:Random( 0, 100 )
			local entity, reward
			if ( rnd <= 88 ) then
				entity, reward = "data/entities/items/pickup/heart.xml", "maxhp"
			elseif ( rnd <= 89 ) then
				entity, reward = "data/entities/animals/illusions/dark_alchemist.xml", "none"
			elseif ( rnd <= 99 ) then
				entity, reward = "data/entities/items/pickup/heart_better.xml", "maxhp"
			else
				entity, reward = "data/entities/items/pickup/heart_fullhp.xml", "heal_only"
			end
			push( loot, {
				entity = entity,
				reward_kind = reward,
				positioned = false,
			} )

		elseif ( rnd <= 98 ) then
			-- EntityConvertToMaterial(entity_id, "gold"): the chest becomes
			-- gold. No item is created.
			loot.outcome = M.OUTCOME_CONVERTED_TO_GOLD

		elseif ( rnd <= 99 ) then
			count = count + 2

		else
			count = count + 3
		end
	end

	loot.rng_state_after = rng:GetSeed()
	return loot
end

-------------------------------------------------------------------------------
-- Great chest reward loop (chest_random_super.lua drop_random_reward)
-------------------------------------------------------------------------------

function M.generate_super( seed, frame_x, frame_y, x, y, opts )
	opts = opts or {}
	local loot = new_loot( M.CHEST_SUPER, { x = frame_x, y = frame_y } )

	local rng = prng.new( seed )
	rng:SetRandomSeed( frame_x, frame_y )

	-- Very-special shortcut: only a draw of exactly 100000 (1/100001) triggers
	-- it, and it REPLACES the whole reward table with the sampo.
	if ( rng:Random( 0, 100000 ) >= 100000 ) then
		loot.outcome = M.OUTCOME_SAMPO
		push( loot, {
			entity = "data/entities/animals/boss_centipede/sampo.xml",
			reward_kind = "none",
			positioned = true,
			x = x,
			y = y,
		} )
		loot.rng_state_after = rng:GetSeed()
		return loot
	end

	local count = 1
	while ( count > 0 ) do
		count = count - 1
		loot.iterations = loot.iterations + 1
		if ( loot.iterations > M.MAX_REWARD_ITERATIONS ) then
			return nil, "reward_iteration_limit",
				"great chest exceeded " .. tostring( M.MAX_REWARD_ITERATIONS ) .. " reward iterations"
		end

		local rnd = rng:Random( 1, 100 )

		if ( rnd <= 10 ) then
			-- Potions: two copies of one entity plus a third variant.
			rnd = rng:Random( 0, 100 )
			local first, third
			if ( rnd <= 30 ) then
				first = "data/entities/items/pickup/potion.xml"
				third = "data/entities/items/pickup/potion_secret.xml"
			else
				first = "data/entities/items/pickup/potion_secret.xml"
				third = "data/entities/items/pickup/potion_random_material.xml"
			end
			for _ = 1, 2 do
				push( loot, {
					entity = first, reward_kind = "none",
					positioned = false, container = true,
				} )
			end
			push( loot, {
				entity = third, reward_kind = "none",
				positioned = false, container = true,
			} )

		elseif ( rnd <= 15 ) then
			push( loot, {
				entity = "data/entities/projectiles/rain_gold.xml",
				reward_kind = "none", positioned = false,
			} )

		elseif ( rnd <= 18 ) then
			local rnd2 = rng:Random( 1, 30 )
			local entity
			if ( rnd2 ~= 30 ) then
				entity = "data/entities/items/pickup/waterstone.xml"
			else
				entity = "data/entities/items/pickup/poopstone.xml"
			end
			push( loot, { entity = entity, reward_kind = "none", positioned = false } )

		elseif ( rnd <= 39 ) then
			rnd = rng:Random( 0, 100 )
			local wand_type
			if ( rnd <= 25 ) then
				wand_type = "wand_level_04"
			elseif ( rnd <= 50 ) then
				wand_type = "wand_unshuffle_04"
			elseif ( rnd <= 75 ) then
				wand_type = "wand_level_05"
			elseif ( rnd <= 90 ) then
				wand_type = "wand_unshuffle_05"
			elseif ( rnd <= 96 ) then
				wand_type = "wand_level_06"
			elseif ( rnd <= 98 ) then
				wand_type = "wand_unshuffle_06"
			elseif ( rnd <= 99 ) then
				wand_type = "wand_level_06"
			elseif ( rnd <= 100 ) then
				wand_type = "wand_level_10"
			end
			push( loot, {
				entity = "data/entities/items/" .. wand_type .. ".xml",
				reward_kind = "wand",
				positioned = false,
				wand_type = wand_type,
				content_frame = { x = frame_x, y = frame_y },
			} )

		elseif ( rnd <= 60 ) then
			rnd = rng:Random( 0, 100 )
			local entity, reward
			if ( rnd <= 89 ) then
				entity, reward = "data/entities/items/pickup/heart.xml", "maxhp"
			elseif ( rnd <= 99 ) then
				entity, reward = "data/entities/items/pickup/heart_better.xml", "maxhp"
			else
				entity, reward = "data/entities/items/pickup/heart_fullhp.xml", "heal_only"
			end
			push( loot, { entity = entity, reward_kind = reward, positioned = false } )

		elseif ( rnd <= 98 ) then
			count = count + 2

		else
			count = count + 3
		end
	end

	loot.rng_state_after = rng:GetSeed()
	return loot
end

-- Dispatch on chest kind. `x, y` = chest spawn position (used for positions).
function M.generate( seed, kind, x, y, opts )
	opts = opts or {}
	local frame, err = M.chest_seed_frame( kind, x, y )
	if ( frame == nil ) then
		return nil, "bad_chest_kind", err
	end
	if ( kind == M.CHEST_SUPER ) then
		return M.generate_super( seed, frame.x, frame.y, x, y, opts )
	end
	return M.generate_normal( seed, frame.x, frame.y, x, y, opts )
end

-- Only the SEED FRAME is enough to predict content; expose a helper for callers
-- that already hold a frame (tests, nested records).
function M.generate_at_frame( seed, kind, frame_x, frame_y, x, y, opts )
	if ( kind == M.CHEST_SUPER ) then
		return M.generate_super( seed, frame_x, frame_y, x, y, opts )
	end
	return M.generate_normal( seed, frame_x, frame_y, x, y, opts )
end

-------------------------------------------------------------------------------
-- Normalisation of externally supplied loot
-------------------------------------------------------------------------------
--
-- A caller may supply an exact loot list (a fixture, or in-game observation).
-- It is scored through the same contract, but it is never reported as a
-- prediction. Unknown entities are kept and marked `unknown`, never dropped:
-- "unknown content cannot become absence".
function M.normalize_items( items )
	local out = {}
	for i = 1, #( items or {} ) do
		local raw = items[ i ]
		if ( type( raw ) == "table" ) then
			local entity = raw.entity
			local reward = raw.reward_kind
			if ( reward == nil ) then
				if ( raw.spell_id ~= nil or entity == "Spell" ) then
					reward = "card_direct"
				else
					reward = chest_data.reward_kind( entity )
				end
			end
			out[ #out + 1 ] = {
				order = i,
				entity = entity,
				reward_kind = reward,
				spell_id = raw.spell_id,
				wand_type = raw.wand_type,
				positioned = raw.positioned == true,
				x = raw.x,
				y = raw.y,
				container = raw.container == true,
				material = raw.material,
				amount = raw.amount,
				cards = raw.cards,
				always_casts = raw.always_casts,
				-- Identity is preserved verbatim: two views of the same real
				-- object must be deduplicated by `object_id`, never by position.
				object_id = raw.object_id,
				supplied = true,
			}
		end
	end
	return out
end

return M
