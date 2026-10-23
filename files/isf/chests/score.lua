-- files/isf/chests/score.lua
--
-- ISF-05 / PRD R2 scoring: turns a chest plus its predicted (or supplied) loot
-- into exact per-rule report entries.
--
-- This module owns R2 ARITHMETIC ONLY. It deliberately does not:
--   * reimplement normal-spell values  -> shared files/isf/core/spell_score.lua
--     (context "wild_direct", PRD R2: full G10/G20/G50, per card);
--   * reimplement wild-wand values     -> the wild_wands provider's
--     score_wand() (R1: body + Always Cast region gates, in-wand 1/4);
--   * reimplement R5 container values  -> the collectibles provider consumes
--     the records the chest provider forwards.
--
-- PRD R2, verbatim requirements this file implements:
--   R2.1  each real chest in Mines / Collapsed Mines / Coal Pits / Fungal
--         Caverns: +2.
--   R2.2  a chest that dropped at least one loose spell card: +5, ONCE.
--   R2.3  each loose target card: full G10/G20/G50 value, per card.
--   R2.4  each max-HP pickup inside a chest: +2. Heal-only pickups never count.
--   R2.5  a dropped wand never triggers R2.2; its cards use the R1 1/4 rate and
--         its body / Always Cast follow the R1 region limits.
--   R2.6  nested sources keep provenance, and one real object is counted once.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "chests/score: files/isf/core/units.lua did not return a table" )
end

local spell_score = dofile_once( "mods/interesting_seed_filter/files/isf/core/spell_score.lua" )
if ( type( spell_score ) ~= "table" ) then
	error( "chests/score: files/isf/core/spell_score.lua did not return a table" )
end

local chest_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/chests.lua" )
if ( type( chest_data ) ~= "table" ) then
	error( "chests/score: files/isf/data/chests.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.CATEGORY = "wild.chests"

M.RULES = chest_data.RULES

-- Error codes this module can report. Kept as data so callers/tests enumerate
-- them instead of matching message text.
M.ERRORS = {
	bad_chest = "chest record is not a table",
	missing_chest_id = "chest record has no stable string id",
	missing_coordinates = "chest record needs numeric x and y",
	bad_chest_kind = "chest kind must be normal or super",
	unknown_region = "chest region is not a documented R2 region",
	out_of_scope_region = "chest region is outside PRD R2 (no award)",
	unsupported_provenance = "chest provenance is not an R2 chest",
	entrance_not_authorized = "puzzle chest entrance is not proven generated / coherent",
	unknown_reward_entity = "loot entity is not classified (kept, not scored)",
	duplicate_object = "the same real object was already scored",
	recursive_chest_cycle = "chest source graph contains a cycle",
	chest_depth_limit = "chest source graph exceeded the recursion depth limit",
	reward_iteration_limit = "reward loop exceeded the safety iteration limit",
	card_retry_limit = "loose-card draw exceeded the safety retry limit",
	bad_action_index = "loose-card draw produced an out-of-range action index",
	wand_generation_failed = "wand content could not be generated",
}

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------

local function is_finite( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function label( value )
	if ( value == nil ) then
		return "nil"
	end
	return tostring( value )
end

-- Stable identity of the real chest object. Two views of one chest (e.g. a
-- chest record and an entity scan hit) must share `object_id`; nothing else may
-- collapse them, because equal coordinates do not prove "same object".
function M.chest_identity( chest )
	if ( type( chest ) == "table" ) then
		if ( type( chest.object_id ) == "string" and chest.object_id ~= "" ) then
			return "object:" .. chest.object_id
		end
		if ( type( chest.id ) == "string" and chest.id ~= "" ) then
			return "chest:" .. chest.id
		end
	end
	return "chest:<invalid>"
end

-- Identity of one loot item, for cross-entry dedup of loose objects that are
-- also reachable through an entity scan.
local function item_identity( chest, item )
	if ( type( item.object_id ) == "string" and item.object_id ~= "" ) then
		return "object:" .. item.object_id
	end
	return nil -- no asserted identity: always counted
end

-------------------------------------------------------------------------------
-- Chest validation
-------------------------------------------------------------------------------

-- validate_chest( chest ) -> normalized | nil, errors[]
--
-- Accepted shape (all documented; nothing else is interpreted):
--   id          string, REQUIRED. Stable id of this chest record.
--   object_id   string, optional. Identity of the REAL chest object.
--   kind        "normal" | "super", optional (default "normal").
--   entity      exact entity path, optional. When present it must be one of the
--               two R2 chest entities (a mimic path is rejected, not folded).
--   biome       REQUIRED. R2 region name or a documented alias.
--   provenance  one of data/chests.lua SOURCES_BY_PROVENANCE
--               (default "biome_spawn"). Only in_r2 provenances award R2.1.
--   x, y        REQUIRED numbers. The chest SPAWN position (the value the
--               vanilla PositionSeedComponent carries). Drop positions use it;
--               content seeding uses it plus the kind's seed-frame offset.
--   frame_x, frame_y  optional explicit seed frame. When present it WINS over
--               x + offset, so a caller that already computed the frame (or
--               observed it in-game) is never re-offset.
--   chain       optional array of provenance steps: { source, source_id, x, y }
--   parent_id   optional id of the source that produced this chest.
--   loot        optional loot table (see loot.normalize_items)
--   supplied_loot  boolean: true when `loot` came from outside (fixture/game),
--               so the report says "supplied", not "predicted".
function M.validate_chest( chest )
	local errors = {}
	if ( type( chest ) ~= "table" ) then
		return nil, { { code = "bad_chest", message = M.ERRORS.bad_chest } }
	end

	if ( type( chest.id ) ~= "string" or chest.id == "" ) then
		errors[ #errors + 1 ] = { code = "missing_chest_id",
			message = M.ERRORS.missing_chest_id }
	end
	if ( not is_finite( chest.x ) or not is_finite( chest.y ) ) then
		errors[ #errors + 1 ] = { code = "missing_coordinates",
			message = M.ERRORS.missing_coordinates }
	end

	local kind = chest.kind or "normal"
	if ( chest_data.CHEST_KINDS[ kind ] == nil ) then
		errors[ #errors + 1 ] = { code = "bad_chest_kind",
			message = M.ERRORS.bad_chest_kind .. ": " .. label( kind ) }
		kind = "normal"
	end

	if ( chest.entity ~= nil ) then
		local non_chest = chest_data.NON_CHEST_ENTITIES[ chest.entity ]
		if ( non_chest ~= nil ) then
			errors[ #errors + 1 ] = { code = "unsupported_provenance",
				message = non_chest .. " (entity " .. tostring( chest.entity ) .. ")" }
		else
			local entity_kind = chest_data.CHEST_ENTITY_TO_KIND[ chest.entity ]
			if ( entity_kind == nil ) then
				errors[ #errors + 1 ] = { code = "unsupported_provenance",
					message = "entity " .. tostring( chest.entity ) .. " is not an R2 chest entity" }
			else
				kind = entity_kind
			end
		end
	end

	local region, region_info = chest_data.region( chest.biome )
	if ( region == nil ) then
		errors[ #errors + 1 ] = { code = "unknown_region",
			message = M.ERRORS.unknown_region .. ": " .. label( chest.biome ) }
	end

	local provenance = chest.provenance or "biome_spawn"
	local provenance_info = chest_data.SOURCES_BY_PROVENANCE[ provenance ]
	if ( provenance_info == nil ) then
		errors[ #errors + 1 ] = { code = "unsupported_provenance",
			message = "unknown provenance " .. label( provenance ) }
		provenance_info = chest_data.SOURCES_BY_PROVENANCE.unknown
		provenance = "unknown"
	end

	if ( #errors > 0 ) then
		return nil, errors
	end

	local frame = chest_data.SEED_FRAME[ kind ]
	local frame_x = chest.frame_x
	local frame_y = chest.frame_y
	local frame_supplied = ( frame_x ~= nil or frame_y ~= nil )
	if ( frame_x == nil ) then frame_x = chest.x + frame.offset_x end
	if ( frame_y == nil ) then frame_y = chest.y + frame.offset_y end

	return {
		id = chest.id,
		object_id = chest.object_id,
		kind = kind,
		entity = chest.entity,
		biome = region,
		biome_info = region_info,
		provenance = provenance,
		provenance_info = provenance_info,
		x = chest.x,
		y = chest.y,
		frame_x = frame_x,
		frame_y = frame_y,
		frame_supplied = frame_supplied,
		chain = chest.chain,
		parent_id = chest.parent_id,
		loot = chest.loot,
		supplied_loot = chest.supplied_loot == true,
		-- R3 entrance authorization. Carried verbatim: `check_entrance` decides
		-- at score time so the verdict is recorded in the report.
		entrance_generated = chest.entrance_generated,
		entrance_biome = chest.entrance_biome,
		puzzle_id = chest.puzzle_id,
	}, nil
end

-------------------------------------------------------------------------------
-- Scoring one chest
-------------------------------------------------------------------------------

-- score_chest( chest, loot, opts ) -> result
--
--   chest : normalized chest (M.validate_chest output)
--   loot  : { items = {...}, outcome = ... } or nil (chest exists, loot unknown)
--   opts.wand_provider : {
--       generate = function( chest, item ) -> wand | nil, reason
--       score    = function( wand, biome, source_id, index ) -> {entries, score_units} | nil, reason
--   }
--   opts.is_flag_set : function(flag) -> boolean (wand generation unlocks)
--
-- result = {
--   entries,          -- report entries for this chest
--   score_units,      -- their exact sum
--   counts,           -- what was seen (for details/diagnostics)
--   errors,           -- hard failures for this chest
--   warnings,         -- non-fatal statements
--   r5_records,       -- potion/pouch records for the collectibles provider
--   unknown_entities, -- loot paths this build cannot classify
-- }
function M.score_chest( chest, loot, opts )
	opts = opts or {}
	local result = {
		entries = {},
		score_units = 0,
		counts = {
			chest = 0,
			loose_cards = 0,
			loose_target_cards = 0,
			maxhp_pickups = 0,
			heal_only_pickups = 0,
			wands = 0,
			gold_items = 0,
			other_items = 0,
			unknown_items = 0,
		},
		errors = {},
		warnings = {},
		r5_records = {},
		unknown_entities = {},
	}

	local function add( entry )
		result.entries[ #result.entries + 1 ] = entry
		result.score_units = result.score_units + entry.score_units
		return entry
	end

	local function fail( code, message )
		result.errors[ #result.errors + 1 ] = { code = code, message = message }
	end

	local function warn( code, message )
		result.warnings[ #result.warnings + 1 ] = { code = code, message = message }
	end

	local base = {
		category = M.CATEGORY,
		biome = chest.biome,
		source_id = chest.id,
		x = chest.x,
		y = chest.y,
		chest_id = chest.id,
		chest_kind = chest.kind,
		provenance = chest.provenance,
	}

	-- Provenance gate FIRST, and it can be total. PRD R2 excludes the pacifist
	-- and Holy Mountain chests outright, so they must contribute NOTHING
	-- chest-derived: no base, no loose-card bonus, no card, no wand, no max-HP,
	-- and no R5 forwarding. Returning here is what makes that total rather than
	-- letting derived awards leak through from the loot loop below.
	if ( chest.provenance_info.blocks_derived_scores == true ) then
		warn( "unsupported_provenance",
			string.format( "chest %s provenance '%s' is excluded from R2 entirely: %s",
				chest.id, chest.provenance,
				tostring( chest.provenance_info.note or "no R2 award" ) ) )
		return result
	end

	-- An R3-authorized puzzle chest must prove its entrance before any award.
	-- A missing or negative authorization is a rejection, never a silent pass:
	-- "只有对应谜题入口实际生成时，才计入其奖励".
	if ( chest.provenance_info.requires_entrance_authorization == true ) then
		local status, reason = chest_data.check_entrance( chest )
		base.entrance_status = status
		base.entrance_biome = chest.entrance_biome
		base.puzzle_id = chest.puzzle_id
		if ( status ~= chest_data.ENTRANCE_STATUS.authorized ) then
			-- Not an error in the report's sense: the caller supplied a record and
			-- the record correctly earns nothing. It IS an unresolved coverage
			-- fact, so it is surfaced as a warning the provider can escalate.
			warn( "entrance_not_authorized",
				string.format( "chest %s puzzle entrance is '%s': %s",
					chest.id, tostring( status ), tostring( reason ) ) )
			result.entrance_status = status
			return result
		end
		result.entrance_status = status
	end

	if ( chest.biome_info.in_scope ~= true ) then
		-- Out-of-scope region: the chest is real, but PRD R2 gives it no award.
		-- This is a documented zero, never an "unknown".
		warn( "out_of_scope_region",
			string.format( "chest %s in %s earns nothing under R2: %s",
				chest.id, chest.biome,
				tostring( chest.biome_info.reason or "region outside R2" ) ) )
		return result
	end

	-- R2.1 -- the chest itself. The provenance gate above already returned for
	-- excluded provenances, so reaching here with in_r2 means this is a real R2
	-- chest (including an entrance-authorized puzzle chest).
	if ( chest.provenance_info.in_r2 == true ) then
		local entry = {}
		for k, v in pairs( base ) do entry[ k ] = v end
		entry.id = chest.id .. "/chest"
		entry.rule_id = M.RULES.R2_1.rule_id
		entry.score_units = M.RULES.R2_1.score_units
		entry.reason = string.format( "real %s chest in %s (+%s)",
			chest.kind == "super" and "great" or "standard",
			chest.biome, units.to_string( M.RULES.R2_1.score_units ) )
		if ( chest.provenance == "puzzle_reward" ) then
			entry.reason = string.format(
				"puzzle-generated %s chest in %s via a generated entrance (+%s)",
				chest.kind == "super" and "great" or "standard",
				chest.biome, units.to_string( M.RULES.R2_1.score_units ) )
		end
		add( entry )
		result.counts.chest = 1
	else
		warn( "unsupported_provenance",
			string.format( "chest %s provenance '%s' is not an R2 chest: %s",
				chest.id, chest.provenance,
				tostring( chest.provenance_info.note or "no R2 award" ) ) )
	end

	if ( loot == nil ) then
		-- The chest exists but its contents were not determined. R2.1 stands;
		-- everything content-derived is unknown, which the caller must report
		-- as partial coverage rather than as "no cards, no maxHP".
		warn( "loot_unknown",
			string.format( "chest %s: contents were not determined, so only the "
				.. "chest award is known", chest.id ) )
		return result
	end

	if ( loot.outcome == "converted_to_gold" ) then
		warn( "converted_to_gold",
			string.format( "chest %s was converted to gold by the reward loop; "
				.. "no items dropped", chest.id ) )
	end

	local items = loot.items or {}
	local has_loose_card = false
	local wand_index = 0

	for i = 1, #items do
		local item = items[ i ]
		local reward = item.reward_kind
		local item_id = string.format( "%s/loot%d", chest.id, item.order or i )

		if ( reward == "card_direct" ) then
			has_loose_card = true
			result.counts.loose_cards = result.counts.loose_cards + 1
			local spell_units = 0
			local info = nil
			if ( item.spell_id ~= nil ) then
				info = spell_score.classify( item.spell_id, spell_score.CONTEXT_WILD_DIRECT )
				if ( info ~= nil ) then
					spell_units = info.score_units
				end
			end
			if ( item.deduplicated == true ) then
				-- Another entry already awarded this exact card. It still counts
				-- as evidence that THIS chest dropped a loose card (so R2.2
				-- fires), but it must not add points twice.
				warn( "duplicate_loot_object",
					string.format( "chest %s landed loose card %s again, already "
						.. "scored through another entry; no second award",
						chest.id, label( item.spell_id ) ) )
				spell_units = 0
			end
			if ( spell_units > 0 ) then
				result.counts.loose_target_cards = result.counts.loose_target_cards + 1
				local entry = {}
				for k, v in pairs( base ) do entry[ k ] = v end
				entry.id = item_id .. "/card"
				entry.rule_id = M.RULES.R2_3.rule_id
				entry.score_units = spell_units
				entry.reason = string.format(
					"loose %s target card %s from chest (+%s, full wild-direct value)",
					info.group, tostring( item.spell_id ), units.to_string( spell_units ) )
				entry.spell_id = item.spell_id
				entry.spell_group = info.group
				entry.loot_order = item.order or i
				entry.object_id = item.object_id
				add( entry )
			else
				-- A loose card that is not a target scores nothing itself but
				-- still triggers the once-per-chest base award below.
				warn( "non_target_card",
					string.format( "chest %s dropped loose card %s, which is not a "
						.. "PRD target (0 units)", chest.id, label( item.spell_id ) ) )
			end

		elseif ( reward == "maxhp" ) then
			result.counts.maxhp_pickups = result.counts.maxhp_pickups + 1
			if ( item.deduplicated == true ) then
				warn( "duplicate_loot_object",
					string.format( "chest %s landed max-HP pickup %s again, already "
						.. "scored through another entry; no second award",
						chest.id, tostring( item.entity ) ) )
			else
				local entry = {}
				for k, v in pairs( base ) do entry[ k ] = v end
				entry.id = item_id .. "/maxhp"
				entry.rule_id = M.RULES.R2_4.rule_id
				entry.score_units = M.RULES.R2_4.score_units
				entry.reason = string.format( "max-HP pickup %s from chest (+%s)",
					tostring( item.entity ), units.to_string( M.RULES.R2_4.score_units ) )
				entry.entity = item.entity
				entry.loot_order = item.order or i
				entry.object_id = item.object_id
				add( entry )
			end

		elseif ( reward == "heal_only" ) then
			-- Documented zero: heart_fullhp.lua only refills hp.
			result.counts.heal_only_pickups = result.counts.heal_only_pickups + 1
			warn( "heal_only_not_maxhp",
				string.format( "chest %s dropped %s, which only heals and never "
					.. "raises max HP (0 units)", chest.id, tostring( item.entity ) ) )

		elseif reward == "wand" and item.deduplicated == true then
			warn("duplicate_loot_object","physical wand already counted through another view")
		elseif ( reward == "wand" ) then
			wand_index = wand_index + 1
			result.counts.wands = result.counts.wands + 1
			local provider = opts.wand_provider
			if ( provider == nil ) then
				fail( "wand_generation_failed",
					string.format( "chest %s dropped a wand (%s) but no wand provider "
						.. "was supplied", chest.id, label( item.wand_type ) ) )
			else
				local identity = item_identity( chest, item )
				local wand, reason = provider.generate( chest, item )
				if ( wand == nil ) then
					fail( "wand_generation_failed",
						string.format( "chest %s wand %d (%s): %s", chest.id,
							wand_index, label( item.wand_type ), tostring( reason ) ) )
				else
					-- wild_wands.score_wand builds `<source_id>/wand<n>/<suffix>`.
					-- Passing the chest-scoped source keeps ids stable and unique.
					local scored, why = provider.score( wand, chest.biome,
						item_id, wand_index )
					if ( scored == nil ) then
						fail( "wand_generation_failed",
							string.format( "chest %s wand %d could not be scored: %s",
								chest.id, wand_index, tostring( why ) ) )
					else
						local seen = {}
						for _, entry in ipairs( scored.entries or {} ) do
							if ( not seen[ entry.id ] ) then
								seen[ entry.id ] = true
								entry.chest_id = chest.id
								entry.chest_kind = chest.kind
								entry.provenance = chest.provenance
								entry.object_id = identity
								entry.loot_order = item.order or i
								add( entry )
							end
						end
					end
				end
			end

		elseif ( reward == "gold" ) then
			result.counts.gold_items = result.counts.gold_items + 1

		elseif ( reward == "none" ) then
			result.counts.other_items = result.counts.other_items + 1

		else
			-- Unknown entity: kept and reported. It is NOT silently zeroed and
			-- it is NOT counted as absence.
			result.counts.unknown_items = result.counts.unknown_items + 1
			result.unknown_entities[ #result.unknown_entities + 1 ] = item.entity
			warn( "unknown_reward_entity",
				string.format( "chest %s looted %s, which this build cannot classify "
					.. "(kept as unknown, not scored)", chest.id, label( item.entity ) ) )
		end

		if ( chest_data.CONTENT_SEEDED_AT_CHEST_FRAME[ item.entity or "" ] ) then
			local record = M.container_record( chest, item, opts.sprite_offsets )
			if ( record ~= nil ) then
				result.r5_records[ #result.r5_records + 1 ] = record
			end
		end
	end

	-- R2.2 -- once per chest, only for LOOSE cards. A wand drop never triggers
	-- it (that is why this is evaluated outside the item loop, from a flag only
	-- the `card_direct` branch sets).
	if ( has_loose_card ) then
		local entry = {}
		for k, v in pairs( base ) do entry[ k ] = v end
		entry.id = chest.id .. "/direct_bonus"
		entry.rule_id = M.RULES.R2_2.rule_id
		entry.score_units = M.RULES.R2_2.score_units
		entry.reason = string.format(
			"chest dropped at least one loose spell card (+%s, once per chest)",
			units.to_string( M.RULES.R2_2.score_units ) )
		entry.loose_card_count = result.counts.loose_cards
		add( entry )
	end

	return result
end

-------------------------------------------------------------------------------
-- R5 hand-off (records only; the collectibles provider does the scoring)
-------------------------------------------------------------------------------

-- Build a collectibles object record for a potion / pouch dropped by a chest.
--
-- COORDINATE HONESTY (see .scratch/.../chests/COORDINATE_HANDOFF.md)
--
-- The shipped vanilla proves the LOAD POINT and nothing beyond it:
--
--   chest_random.lua drop_random_reward():
--       table.insert( entities, { "data/entities/items/pickup/potion.xml" } )
--       ...
--       eid = EntityLoad( entity[1], rand_x, rand_y )
--       EntityApplyTransform( eid, x + Random(-10,10), y - 4 + Random(-5,5) )
--
-- so the container is loaded at the chest seed frame and moved AFTERWARDS. The
-- vanilla comment says this is deliberate so the content generator's
-- SetRandomSeed() stays deterministic.
--
-- What the source does NOT prove is whether the engine makes the transform
-- visible to `init()` equal to the EntityLoad argument or equal to that minus
-- half the sprite. The collectibles contract assumes `load - sprite/2`; we
-- previously asserted `load` exactly. Neither is engine-proven, so this record
-- carries BOTH quantities with explicit labels instead of claiming one:
--
--   load_x / load_y            -- proven EntityLoad argument
--   x / y                      -- the same proven load point (the contract
--                                 requires numeric x/y; NOT labelled as the
--                                 seed transform)
--   coordinate_frame           -- which quantity x/y denote
--   init_seed_frame            -- "unresolved" until a native probe settles it
--   init_seed_candidate_x/y    -- the collectibles-compatible hypothesis
--   coordinate_confidence      -- machine-readable summary
--
-- This module deliberately does NOT call containers.seed_position_from_load():
-- importing another owner's hypothesis here would disguise a disagreement as
-- agreement.
M.COORDINATE_FRAME_LOAD_POINT = "entity_load_point"
M.INIT_SEED_UNRESOLVED = "unresolved"

function M.container_record( chest, item, sprite_offsets )
	local entity = item.entity
	local kind, generator
	if ( entity == "data/entities/items/pickup/powder_stash.xml" ) then
		kind, generator = "powder_pouch", "powder_stash"
	elseif ( entity == "data/entities/items/pickup/potion_secret.xml" ) then
		kind, generator = "potion", "potion_secret"
	elseif ( entity == "data/entities/items/pickup/potion.xml" ) then
		kind, generator = "potion", "potion"
	elseif ( entity == "data/entities/items/pickup/potion_random_material.xml" ) then
		-- No reproducible offline generator: forwarded so the collectibles
		-- provider reports it as unresolved, never as "no potion".
		kind, generator = "potion", "random_material"
	end
	if ( kind == nil ) then
		return nil
	end
	local order = item.order or 0
	local record = {
		id = string.format( "%s/loot%d/%s", chest.id, order, kind ),
		object_id = item.object_id,
		kind = kind,
		biome = chest.biome,
		-- Proven quantity: the EntityLoad argument, which is exactly the seed
		-- frame this module computes (position + the kind's vanilla offsets).
		x = chest.frame_x,
		y = chest.frame_y,
		load_x = chest.frame_x,
		load_y = chest.frame_y,
		coordinate_frame = M.COORDINATE_FRAME_LOAD_POINT,
		entity_file = entity,
		generator = generator,
		material = item.material,
		amount = item.amount,
		visit = "chest_reward",
		source_id = chest.id,
		spawned_during = "initial_generation",
		-- The engine relationship is NOT proven, so it stays open.
		init_seed_frame = M.INIT_SEED_UNRESOLVED,
		coordinate_confidence = "load_point_proven_init_seed_unresolved",
		coordinate_note = "content seeds with the entity transform observed inside "
			.. "the container's init(); the load point is proven, the engine's "
			.. "load->transform offset is not (see COORDINATE_HANDOFF.md)",
	}

	-- Candidate transform per the collectibles convention, carried as a
	-- hypothesis only. `sprite_offsets` is passed in by the provider so this
	-- module does not read another owner's data file for a number it does not own.
	if ( type( sprite_offsets ) == "table" ) then
		local off = sprite_offsets[ kind ]
		if ( off ~= nil and type( off.width ) == "number" and type( off.height ) == "number" ) then
			record.init_seed_candidate_x = record.x - off.width / 2
			record.init_seed_candidate_y = record.y - off.height / 2
			record.init_seed_candidate_source =
				"collectibles RECORD_CONTRACT: load - sprite/2 (hypothesis)"
		end
	end

	return record
end

return M
