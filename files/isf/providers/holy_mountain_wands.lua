-- files/isf/providers/holy_mountain_wands.lua
--
-- ISF-10: sold wands in the first three Holy Mountains (PRD rules R6 and R7,
-- Holy Mountain rows of PRD section 2).
--
-- This module is the *Holy Mountain shop* wiring only. Wand generation itself is
-- owned by the worldgen workflow and consumed strictly read-only here:
--
--   files/isf/worldgen/wand_gen.lua            init(deps) / generate(seed, ng, type, x, y, opts)
--   files/isf/worldgen/spell_select.lua        init(deps) / get_random_action(...)
--   files/isf/worldgen/data/wand_config.lua    wand_types / spell_types / spell_type_by_id
--
-- Vanilla behaviour this reproduces (established from the extracted shipped Lua,
-- data/scripts/biomes/temple_altar.lua and data/scripts/items/generate_shop_item.lua
-- — not assumed):
--
--   temple_altar.lua : spawn_all_shopitems(x, y)
--     SetRandomSeed( x, y )
--     count      = 5                              -- TEMPLE_SHOP_ITEM_COUNT default
--     width      = 132 ; item_width = width / count
--     sale_item_i = Random( 1, count )
--     if Random( 0, 100 ) <= 50 then              -- SPELL shop: two rows
--         ...
--     else                                        -- WAND shop: ONE row, no y-30 row
--         for i = 1, count do
--             generate_shop_wand( x + (i-1)*item_width, y, cheap, nil )
--         end
--     end
--
--   generate_shop_item.lua : generate_shop_wand( x, y, cheap_item, biomeid_ )
--     SetRandomSeed( x, y )                       -- the WAND's own slot position
--     biomeid = biomes[ floor(y/512) ] or 0       -- then clamp to 1..6
--     r = Random( 0, 100 )
--     r <= 50  -> data/entities/items/wand_level_0<biomeid>.xml
--     else     -> data/entities/items/wand_unshuffle_0<biomeid>.xml
--
-- Two consequences that matter, and that an earlier sketch in RESULT.md got
-- wrong: the shuffle roll is a *per-wand* draw seeded at the wand's own
-- coordinates (not reused from the shop seed), and a wand shop has a single row
-- of `count` wands.
--
-- Scoring (PRD R6/R7), all in integer score_units (4 units = 1 point):
--   * every sold wand with at least one Always Cast: +5  (20 units);
--   * that Always Cast being REGENERATION_FIELD (Circle of Vigour): +100 more
--     (400 units), so a Vigour sold wand is 105 points (+5 +100);
--   * each ordinary target card inside a sold wand: H2 +2, G20 +20, G50 +50
--     (8 / 80 / 200 units) — full value, no 1/4 discount;
--   * no wild "wand body +1" and no wild shop "+5 base" (R6/R7 exclude them);
--   * Always Cast is never also scored as an ordinary card.
--
-- NOTE on the 106 figure: PRD section 4's "106 points" case is a MINES wand
-- (body +1, Always Cast +5, Vigour +100). PRD R6 explicitly gives sold Holy
-- Mountain wands no body bonus, so the correct sold-wand total is 105. The two
-- numbers are different rules, not a discrepancy.
--
-- Native default HM1/2/3 shops (seed7) and AC Vigour (seed7482) are verified.
-- The five-slot ordinary-mode category is complete; other modes/counts remain
-- partial. This says nothing about exhaustive wild-resource discovery.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no game globals.

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" ) then
	error( "holy_mountain_wands: files/isf/data/spells.lua did not return a table" )
end
local spell_score = dofile_once( "mods/interesting_seed_filter/files/isf/core/spell_score.lua" )
if ( type( spell_score ) ~= "table" ) then
	error( "holy_mountain_wands: files/isf/core/spell_score.lua did not return a table" )
end
local report_lib = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
if ( type( report_lib ) ~= "table" ) then
	error( "holy_mountain_wands: files/isf/core/report.lua did not return a table" )
end
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "holy_mountain_wands: files/isf/adapters/profile.lua did not return a table" )
end
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "holy_mountain_wands: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.PROVIDER_ID = "holy_mountain_wands"
M.CATEGORY = "holy_mountain.sold_wands"

--------------------------------------------------------------------------------
-- Shop geometry
--------------------------------------------------------------------------------

-- Shop geometry, identical to the spell provider and to vanilla.
M.SHOP_OFFSET_X = -299
M.SHOP_OFFSET_Y = -15
M.SHOP_WIDTH = 132
M.DEFAULT_ITEM_COUNT = 5

-- UNRESOLVED COORDINATE QUESTION (documented, not guessed away).
--
-- generate_shop_wand seeds its shuffle roll at the slot's own `(x, y)`, where x is
-- a fractional value (`shop_x + (i-1)*132/5`). The wand's *contents* are then
-- generated by data/scripts/gun/procedural/gun_procedural.lua, which does
-- `local x, y = EntityGetTransform(entity_id); SetRandomSeed(x, y)` — i.e. the
-- engine's stored position of the loaded entity, not a Lua-side rounded value.
--
-- How that fractional spawn x reaches the C++ seed is not observable from the
-- shipped scripts, and the candidates disagree materially: over 3000 in-scope
-- slot positions, the shuffle roll differs between the raw double and a
-- float32-narrowed value 2369 times (79%), and between the raw double and
-- round-half-to-even 2378 times. The shuffle roll is not cosmetic — it selects
-- wand_level vs wand_unshuffle *and* consumes a PRNG draw, shifting every
-- subsequent stat and card.
--
-- The reference implementation (noita-telescope temple_generation.js
-- getShopWand) seeds the roll with the raw fractional x, then passes
-- `Math.round(x)` to createWand (which floors it). That is a modelling choice,
-- not evidence about the engine.
--
-- Keep the old candidates for replaying frozen failed predictions. Native
-- seed11 HM1 now establishes a two-stage pipeline for the default five slots;
-- broader native coverage remains PARTIAL. Modes:
--   "engine"         -- raw Lua-double template roll, integer entity transform
--                       for generate_gun; fixed by seed11 and seed48 native data
--   "exact"          -- raw double position (default; matches the reference tool
--                       for the shuffle roll)
--   "float32"        -- binary32-narrowed, as a C++ float position would be
--   "round_half_even"-- round-half-to-even, as the reference tool does for createWand
-- Native seed48 HM1 fifth wand distinguishes raw-double template selection
-- from binary32: raw selects wand_level_01 (observed), binary32 unshuffle_01.
-- Unlike the engine's GetRandomAction card path, this Lua function invokes
-- SetRandomSeed directly. generate_gun sees an integer entity transform.
-- Default five-slot shops have no half-integer ties; tie behaviour is unverified.
M.COORDINATE_MODES = { engine = true, exact = true, float32 = true, round_half_even = true }
M.DEFAULT_COORDINATE_MODE = "engine"

-- PRD R6 reward tiers in score_units.
M.ALWAYS_CAST_UNITS = units.points( 5 )        -- 20
M.ALWAYS_CAST_VIGOUR_UNITS = units.points( 100 ) -- 400
M.ALWAYS_CAST_VIGOUR_SPELL = "REGENERATION_FIELD"

-- NG0 normal-mode Holy Mountain anchors (main world only; PRD scope).
M.TEMPLES = {
	{ index = 1, x = -32, y = 1410 },
	{ index = 2, x = -32, y = 2946 },
	{ index = 3, x = -32, y = 4994 },
	{ index = 4, x = -32, y = 6530 },
	{ index = 5, x = -32, y = 8578 },
	{ index = 6, x = -32, y = 10626 },
	{ index = 7, x = 2560, y = 13181 },
}

-- generate_shop_item.lua's depth -> biome tier table (keys are floor(y/512)).
local BIOMES = {
	[ 1 ] = 0, [ 2 ] = 0, [ 3 ] = 0,
	[ 4 ] = 1, [ 5 ] = 1, [ 6 ] = 1,
	[ 7 ] = 2, [ 8 ] = 2, [ 9 ] = 2, [ 10 ] = 2, [ 11 ] = 2, [ 12 ] = 2,
	[ 13 ] = 3, [ 14 ] = 3, [ 15 ] = 3, [ 16 ] = 3,
	[ 17 ] = 4, [ 18 ] = 4, [ 19 ] = 4, [ 20 ] = 4,
	[ 21 ] = 5, [ 22 ] = 5, [ 23 ] = 5, [ 24 ] = 5,
	[ 25 ] = 6, [ 26 ] = 6, [ 27 ] = 6, [ 28 ] = 6, [ 29 ] = 6, [ 30 ] = 6,
	[ 31 ] = 6, [ 32 ] = 6, [ 33 ] = 6,
}

-- Wand tier for a shop row, matching generate_shop_wand's biomeid handling.
--
-- VANILLA ASYMMETRY, verified against the extracted scripts: the SPELL path
-- (generate_shop_item) has `if biomepixel > 35 then biomeid = 7 end`, but the
-- WAND path (generate_shop_wand) does NOT. A deep wand row therefore falls back
-- to the table default (0) and lands on tier 1 after the clamp, not tier 7.
-- Copying the spell path's override here would be wrong.
function M.wand_tier( y )
	local biomepixel = math.floor( y / 512 )
	local tier = BIOMES[ biomepixel ] or 0
	if ( tier < 1 ) then
		tier = 1
	end
	if ( tier > 6 ) then
		tier = 6
	end
	return tier, biomepixel
end

--------------------------------------------------------------------------------
-- Worldgen dependencies (read-only)
--------------------------------------------------------------------------------

local MOD_PREFIX = "mods/interesting_seed_filter/"
M.WAND_GEN_PATH = MOD_PREFIX .. "files/isf/worldgen/wand_gen.lua"
M.SPELL_SELECT_PATH = MOD_PREFIX .. "files/isf/worldgen/spell_select.lua"
M.WAND_CONFIG_PATH = MOD_PREFIX .. "files/isf/worldgen/data/wand_config.lua"
M.PRNG_PATH = MOD_PREFIX .. "files/isf/random/prng.lua"

local function try_load( path )
	if ( type( dofile_once ) ~= "function" ) then
		return nil, "dofile_once unavailable in this host"
	end
	local ok, value = pcall( dofile_once, path )
	if ( not ok ) then
		return nil, tostring( value )
	end
	if ( type( value ) ~= "table" ) then
		return nil, "module at '" .. path .. "' did not return a table"
	end
	return value
end

-- Build the unlock predicate the worldgen modules expect.
local function make_unlock_fn( profile )
	return function( spell_id )
		local entry = spells.by_id[ spell_id ]
		if ( entry == nil ) then
			return false
		end
		if ( entry.requires_flag == nil ) then
			return true
		end
		return profile_lib.has_flag( profile, entry.requires_flag )
	end
end

-- Resolve and initialise the worldgen stack. Returns a bundle or nil + reason.
-- `opts` may inject pre-initialised modules for tests (`opts.wand_gen` etc.).
function M.load_generator( opts )
	opts = opts or {}

	local prng = opts.prng_module
	if ( prng == nil ) then
		local loaded, err = try_load( opts.prng_path or M.PRNG_PATH )
		if ( loaded == nil ) then
			return nil, "shared PRNG unavailable (" .. tostring( err ) .. ")"
		end
		prng = loaded
	end
	if ( type( prng.new ) ~= "function" ) then
		return nil, "shared PRNG module must expose new(world_seed)"
	end

	local wand_config = opts.wand_config
	if ( wand_config == nil ) then
		local loaded, err = try_load( opts.wand_config_path or M.WAND_CONFIG_PATH )
		if ( loaded == nil ) then
			return nil, "wand config unavailable (" .. tostring( err ) .. ")"
		end
		wand_config = loaded
	end

	local spell_select = opts.spell_select
	if ( spell_select == nil ) then
		local loaded, err = try_load( opts.spell_select_path or M.SPELL_SELECT_PATH )
		if ( loaded == nil ) then
			return nil, "spell selector unavailable (" .. tostring( err ) .. ")"
		end
		spell_select = loaded
	end

	local wand_gen = opts.wand_gen
	if ( wand_gen == nil ) then
		local loaded, err = try_load( opts.wand_gen_path or M.WAND_GEN_PATH )
		if ( loaded == nil ) then
			return nil, "wand generator unavailable (" .. tostring( err ) .. ")"
		end
		wand_gen = loaded
	end

	if ( type( wand_gen.generate ) ~= "function" ) then
		return nil, "wand generator must expose generate(seed, ng, type, x, y, opts)"
	end
	if ( type( wand_gen.init ) ~= "function" ) then
		return nil, "wand generator must expose init(deps)"
	end
	if ( type( spell_select.init ) ~= "function" ) then
		return nil, "spell selector must expose init(deps)"
	end

	local profile = opts.profile
	local is_unlocked = make_unlock_fn( profile )

	-- Initialise the worldgen modules exactly as tests/worldgen does.
	spell_select.init( {
		prng_new = prng.new,
		pool = spells.pool,
		spell_types = wand_config.spell_types,
		type_by_id = wand_config.spell_type_by_id,
		is_unlocked = is_unlocked,
	} )
	wand_gen.init( {
		prng_new = prng.new,
		wand_config = wand_config,
		spell_select = spell_select,
		is_unlocked = is_unlocked,
	} )

	return {
		wand_gen = wand_gen,
		spell_select = spell_select,
		wand_config = wand_config,
		prng = prng,
		unlock_fn = is_unlocked,
	}
end

--------------------------------------------------------------------------------
-- Vanilla shop-wand generation
--------------------------------------------------------------------------------

-- Deterministic per-shop kind and sale slot, exactly as spawn_all_shopitems does.
-- Uses its own PRNG instance so no state is shared with the spell provider.
function M.shop_header( prng, seed, shop_x, shop_y, count )
	local rng = prng.new( seed )
	rng:SetRandomSeed( shop_x, shop_y )
	local sale_item = rng:Random( 1, count )
	local kind_roll = rng:Random( 0, 100 )
	return {
		sale_item = sale_item,
		kind_roll = kind_roll,
		kind = kind_roll <= 50 and "spell" or "wand",
	}
end

-- One generate_shop_wand( x, y, cheap, nil ) call.
-- Returns the shop slot record; `wand` is nil when generation failed.
function M.generate_shop_wand( bundle, seed, x, y, opts )
	opts = opts or {}
	local tier, biomepixel = M.wand_tier( y )

-- Template selection coordinates are distinct from entity initialization.
	local mode = opts.coordinate_mode or M.DEFAULT_COORDINATE_MODE
	if ( not M.COORDINATE_MODES[ mode ] ) then
		error( "holy_mountain_wands: unknown coordinate_mode '" .. tostring( mode ) .. "'", 3 )
	end
	local pos_x = x
	if ( mode == "float32" and type( bundle.prng.f32 ) == "function" ) then
		pos_x = bundle.prng.f32( x )
	elseif ( mode == "round_half_even" ) then
		pos_x = bundle.wand_gen.round_half_even( x )
	end

	-- The per-wand shuffle roll, seeded at the wand's OWN (x, y). The game redraws
	-- this inside the wand's own SetRandomSeed, so it is not the shop-level roll.
	local rng = bundle.prng.new( seed )
	rng:SetRandomSeed( pos_x, y )
	local roll = rng:Random( 0, 100 )
	local shuffle = roll <= 50
	local prefix = shuffle and "wand_level_" or "wand_unshuffle_"
	local wand_type = prefix .. "0" .. tostring( tier )

	local gen_x,gen_y=pos_x,y
	if mode=="engine" then
		gen_x=bundle.wand_gen.round_half_even(pos_x)
		gen_y=bundle.wand_gen.round_half_even(y)
	end
	local wand, err = bundle.wand_gen.generate( seed, 0, wand_type, gen_x, gen_y, {} )
	return {
		x = x,
		y = y,
		selector_x = pos_x,
		selector_y = y,
		gen_x = gen_x,
		gen_y = gen_y,
		coordinate_mode = mode,
		tier = tier,
		biomepixel = biomepixel,
		roll = roll,
		shuffle = shuffle,
		wand_type = wand_type,
		wand = wand,
		error = err,
	}
end

-- spawn_all_shopitems(x, y) for one Holy Mountain, wand-shop branch only.
function M.generate_shop( bundle, seed, temple, opts )
	local shop_x = temple.x + M.SHOP_OFFSET_X
	local shop_y = temple.y + M.SHOP_OFFSET_Y
	local count = opts.item_count or M.DEFAULT_ITEM_COUNT
	local item_width = M.SHOP_WIDTH / count

	local header = M.shop_header( bundle.prng, seed, shop_x, shop_y, count )
	local shop = {
		temple_index = temple.index,
		x = shop_x,
		y = shop_y,
		count = count,
		item_width = item_width,
		sale_item = header.sale_item,
		kind_roll = header.kind_roll,
		kind = header.kind,
		slots = {},
	}

	if ( shop.kind ~= "wand" ) then
		return shop
	end

	-- Wand shops are a SINGLE row: there is no y-30 second row in this branch.
	for i = 1, count do
		local slot_x = shop_x + ( i - 1 ) * item_width
		local slot = M.generate_shop_wand( bundle, seed, slot_x, shop_y, opts )
		slot.slot = i
		slot.is_sale = ( i == header.sale_item )
		shop.slots[ #shop.slots + 1 ] = slot
	end
	return shop
end

--------------------------------------------------------------------------------
-- R6 / R7 scoring
--------------------------------------------------------------------------------

-- Score one generated wand. Returns the list of awards for that wand.
-- `max_slots` caps how many deck cards are physically present; upstream leaves
-- deck_capacity fractional, so floor() is the real slot count.
function M.score_wand( wand, shop, slot )
	local awards = {}
	if ( wand == nil ) then
		return awards
	end

	local wand_key = string.format( "hm%d.wand%02d", shop.temple_index, slot.slot )
	local always_casts = wand.always_casts or {}
	local has_always_cast = #always_casts > 0

	-- PRD R6: any Always Cast sold wand is +5; Vigour is +100 more.
	if ( has_always_cast ) then
		awards[ #awards + 1 ] = {
			id = wand_key .. ".always_cast",
			rule_id = "R6",
			category = M.CATEGORY,
			biome = "holy_mountain",
			source_id = "holy_mountain_wand",
			x = slot.gen_x,
			y = slot.gen_y,
			score_units = M.ALWAYS_CAST_UNITS,
			reason = "sold wand has an Always Cast (+5)",
			wand_id = wand_key,
			wand_type = slot.wand_type,
			slot = slot.slot,
			is_sale = slot.is_sale,
			always_cast = always_casts[ 1 ],
			kind = "always_cast_present",
		}
	end

	for i = 1, #always_casts do
		if ( always_casts[ i ] == M.ALWAYS_CAST_VIGOUR_SPELL ) then
			awards[ #awards + 1 ] = {
				id = wand_key .. ".always_cast_vigour",
				rule_id = "R6",
				category = M.CATEGORY,
				biome = "holy_mountain",
				source_id = "holy_mountain_wand",
				x = slot.gen_x,
				y = slot.gen_y,
				score_units = M.ALWAYS_CAST_VIGOUR_UNITS,
				reason = "Always Cast is Circle of Vigour (+100)",
				wand_id = wand_key,
				wand_type = slot.wand_type,
				slot = slot.slot,
				is_sale = slot.is_sale,
				always_cast = always_casts[ i ],
				spell_id = always_casts[ i ],
				kind = "always_cast_vigour",
			}
			break
		end
	end

	-- PRD R7: ordinary cards inside a sold wand score at full Holy Mountain
	-- value. Always Cast is a separate classification and is never re-scored
	-- here: `gun.cards` holds the deck, `always_casts` the Always Cast property.
	local capacity = math.floor( tonumber( wand.deck_capacity ) or 0 )
	local cards = wand.cards or {}
	local limit = #cards
	if ( capacity > 0 and capacity < limit ) then
		limit = capacity
	end

	for k = 1, limit do
		local spell_id = cards[ k ]
		local info = spell_score.classify( spell_id, spell_score.CONTEXT_HOLY_MOUNTAIN )
		if ( info ~= nil ) then
			awards[ #awards + 1 ] = {
				id = string.format( "%s.card%02d", wand_key, k ),
				rule_id = "R7",
				category = M.CATEGORY,
				biome = "holy_mountain",
				source_id = "holy_mountain_wand",
				x = slot.gen_x,
				y = slot.gen_y,
				score_units = info.score_units,
				reason = info.reason .. " (inside a sold wand)",
				wand_id = wand_key,
				wand_type = slot.wand_type,
				slot = slot.slot,
				deck_index = k,
				is_sale = slot.is_sale,
				spell_id = spell_id,
				spell_group = info.group,
				kind = "wand_card",
			}
		end
	end

	return awards
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

local DEFAULT_OPTIONS = {
	holy_mountains = 3,
	item_count = M.DEFAULT_ITEM_COUNT,
	coordinate_mode = M.DEFAULT_COORDINATE_MODE,
}

local function merge_options( options )
	local resolved = {}
	for k, v in pairs( DEFAULT_OPTIONS ) do
		resolved[ k ] = v
	end
	if ( type( options ) == "table" ) then
		for k, v in pairs( options ) do
			resolved[ k ] = v
		end
	end
	return resolved
end

-- evaluate( seed, profile, options ) -> provider report (WORKER_CONTRACT schema).
function M.evaluate( seed, profile, options )
	local resolved = merge_options( options )
	local clock = ( type( os ) == "table" and type( os.clock ) == "function" ) and os.clock or nil
	local started = clock and clock() or nil

	local report = report_lib.new( {
		seed = seed,
		profile_id = type( profile ) == "table" and profile.id or "invalid",
		profile_identity = type( profile ) == "table" and profile_lib.identity( profile ) or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, baseline with no perks picked",
			"rule R6 covers Always Cast rewards on sold wands; R7 covers cards inside them",
			"no wild wand body +1 and no wild shop base +5 apply to Holy Mountains",
			"Always Cast is never also scored as an ordinary card",
			"wand generation comes from worldgen-owned files/isf/worldgen/* (read only)",
			"default five-slot engine pipeline has native HM1/2/3 parity, including AC Vigour; other slot counts/modes remain unverified",
		},
		meta = {
			provider = M.PROVIDER_ID,
			provider_version = M.RULE_VERSION,
			schema_version = M.SCHEMA_VERSION,
			data = {
				source = spells.SOURCE,
				game_version_hash = spells.GAME_VERSION_HASH,
				pool_entries = spells.POOL_COUNT,
			},
			options = {
				holy_mountains = resolved.holy_mountains,
				item_count = resolved.item_count,
				coordinate_mode = tostring( resolved.coordinate_mode ),
			},
		},
	} )

	if ( type( seed ) ~= "number" or seed ~= math.floor( seed ) or seed < 0 or seed > 4294967295 ) then
		report:error( "bad_seed", "seed must be an integer in [0, 2^32-1]; got " .. tostring( seed ) )
	end
	if ( type( profile ) ~= "table" ) then
		report:error( "bad_profile", "profile must be a normalized profile table" )
	end
	if ( #report.errors > 0 ) then
		report:claim( M.CATEGORY, report_lib.COVERAGE_UNSUPPORTED, "invalid input" )
		return report:finish()
	end

	local bundle, load_err = M.load_generator( {
		profile = profile,
		prng_module = resolved.prng_module,
		prng_path = resolved.prng_path,
		wand_config = resolved.wand_config,
		wand_config_path = resolved.wand_config_path,
		spell_select = resolved.spell_select,
		spell_select_path = resolved.spell_select_path,
		wand_gen = resolved.wand_gen,
		wand_gen_path = resolved.wand_gen_path,
	} )
	if ( bundle == nil ) then
		-- An unavailable generator is an error and an explicitly unsupported
		-- category: never a score of zero.
		report:error( "wand_generator_unavailable", tostring( load_err ) )
		report:claim( M.CATEGORY, report_lib.COVERAGE_UNSUPPORTED,
			"worldgen wand pipeline unavailable: " .. tostring( load_err ) )
		return report:finish()
	end

	local shops = {}
	local wand_shops = 0
	local spell_shops = 0
	local wands_generated = 0
	local failed_wands = 0
	local ac_wands = 0
	local vigour_wands = 0

	for i = 1, resolved.holy_mountains do
		local temple = M.TEMPLES[ i ]
		if ( temple == nil ) then
			report:error( "unknown_temple", "no anchor position for Holy Mountain " .. tostring( i ) )
		else
			local shop = M.generate_shop( bundle, seed, temple, resolved )
			shops[ #shops + 1 ] = shop
			if ( shop.kind == "wand" ) then
				wand_shops = wand_shops + 1
				for j = 1, #shop.slots do
					local slot = shop.slots[ j ]
					if ( slot.wand == nil ) then
						failed_wands = failed_wands + 1
						report:warning(
							"wand_generation_failed",
							string.format(
								"HM%d slot %d (%s) failed: %s",
								shop.temple_index, slot.slot, tostring( slot.wand_type ),
								tostring( slot.error )
							)
						)
					else
						wands_generated = wands_generated + 1
						if ( #( slot.wand.always_casts or {} ) > 0 ) then
							ac_wands = ac_wands + 1
						end
						local awards = M.score_wand( slot.wand, shop, slot )
						for k = 1, #awards do
							if ( awards[ k ].kind == "always_cast_vigour" ) then
								vigour_wands = vigour_wands + 1
							end
							report:add( awards[ k ] )
						end
					end
				end
			else
				spell_shops = spell_shops + 1
			end
		end
	end

	-- Native seeds11/48/7482 and seed7's fifteen default HM1/2/3 wands
	-- establish raw-double template selection and integer entity initialization.
	-- Default five-slot positions never hit half-integer ties. Keep experimental
	-- modes/counts and incomplete temple requests partial.
	local mode = resolved.coordinate_mode
	if ( failed_wands > 0 ) then
		report:claim( M.CATEGORY, report_lib.COVERAGE_PARTIAL,
			string.format( "%d of %d wand slots failed to generate",
				failed_wands, failed_wands + wands_generated ) )
	elseif ( mode == "engine" and resolved.item_count == 5
		and resolved.holy_mountains == 3 and #report.errors == 0 ) then
		report:claim( M.CATEGORY, report_lib.COVERAGE_COMPLETE,
			string.format("generated %d wands across all three default five-slot shops; "
				.. "two-stage spawn-x pipeline verified natively for HM1/2/3",wands_generated) )
	else
		report:claim( M.CATEGORY, report_lib.COVERAGE_PARTIAL,
			string.format(
				"generated %d wands and applied R6/R7 scoring; non-default modes, slot counts "
					.. "or incomplete temple scope remain unresolved (mode='%s')",
				wands_generated, tostring( mode )
			) )
	end

	local finished = report:finish()
	finished.details = {
		shops = shops,
		coordinate_mode = mode,
		coordinate_question = "native default HM1/2/3 and Vigour verified; "
			.. "non-default slot counts and half-integer ties remain unresolved",
		summary = {
			holy_mountains = resolved.holy_mountains,
			wand_shops = wand_shops,
			spell_shops = spell_shops,
			wands_generated = wands_generated,
			failed_wands = failed_wands,
			always_cast_wands = ac_wands,
			vigour_wands = vigour_wands,
		},
	}

	local elapsed = clock and clock() or nil
	if ( started ~= nil and elapsed ~= nil ) then
		finished.timing_ms = ( elapsed - started ) * 1000.0
	end
	return finished
end

-- Raw wand contents without scoring, for tests and oracle comparison.
function M.content( seed, profile, options )
	local resolved = merge_options( options )
	local bundle, err = M.load_generator( {
		profile = profile,
		prng_module = resolved.prng_module,
		prng_path = resolved.prng_path,
		wand_config = resolved.wand_config,
		wand_config_path = resolved.wand_config_path,
		spell_select = resolved.spell_select,
		spell_select_path = resolved.spell_select_path,
		wand_gen = resolved.wand_gen,
		wand_gen_path = resolved.wand_gen_path,
	} )
	if ( bundle == nil ) then
		return nil, err
	end
	local shops = {}
	for i = 1, resolved.holy_mountains do
		local temple = M.TEMPLES[ i ]
		if ( temple ~= nil ) then
			shops[ #shops + 1 ] = M.generate_shop( bundle, seed, temple, resolved )
		end
	end
	return shops, nil
end

return M
