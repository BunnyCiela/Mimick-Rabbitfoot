-- files/isf/providers/holy_mountains.lua
--
-- ISF-01: first three Holy Mountains (PRD section 2 "Holy Mountain" column,
-- rules R6/R7; ISF-01 scope = independently sold spell cards).
--
-- What is modelled, exactly as the installed build does it:
--
--   data/scripts/biomes/temple_altar.lua : spawn_all_shopitems(x, y)
--     SetRandomSeed( x, y )
--     count      = tonumber( GlobalsGetValue( "TEMPLE_SHOP_ITEM_COUNT", "5" ) )
--     width      = 132
--     item_width = width / count
--     sale_item_i = Random( 1, count )
--     if Random( 0, 100 ) <= 50 then
--         for i = 1, count do
--             generate_shop_item( x + (i-1)*item_width, y,      i == sale_item_i, nil, true )
--             generate_shop_item( x + (i-1)*item_width, y - 30, false,             nil, true )
--         end
--     else
--         -- a wand shop: every slot is generate_shop_wand(...) (ISF-10, deferred)
--     end
--
--   data/scripts/items/generate_shop_item.lua : generate_shop_item(x, y, ...)
--     SetRandomSeed( x, y )
--     biomepixel = floor( y / 512 )
--     biomeid    = biomes[ biomepixel ] or 0        (biomepixel > 35 -> 7)
--     level      = biomeid
--     item       = GetRandomAction( x, y, level, 0 )
--
--   GetRandomAction walks data/scripts/gun/gun_actions.lua in order, using a
--   per-entity seed of world_seed + offset (offset 0 here) and the per-level
--   spawn weights, skipping actions whose `spawn_requires_flag` is not set.
--
-- Scoring (PRD R7): each independently sold card in a Holy Mountain scores by
-- the H2 / G20 / G50 whitelist at full value, with no wild "wand body" bonus and
-- no wild-shop base score. Always Cast is a wand property and is never routed
-- through normal-spell scoring (ISF-10 owns it).
--
-- Precision: the engine narrows the shop slot's fractional x to binary32 before
-- seeding (both reference ports do the same; see the oracle check in
-- tools/foundation). This module narrows with `prng.f32` and records the exact
-- seeded x, so a report can be replayed bit-for-bit.
--
-- Coverage: the provider inspects *all* shop slots, so a wand shop is
-- detectable and reported as "wand shop, contents deferred", never as
-- "zero target cards". Categories not modelled by ISF-01 are claimed as
-- unsupported so the report can never be mistaken for a complete seed score.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" ) then
	error( "holy_mountains: files/isf/data/spells.lua did not return a table" )
end
local spell_score = dofile_once( "mods/interesting_seed_filter/files/isf/core/spell_score.lua" )
if ( type( spell_score ) ~= "table" ) then
	error( "holy_mountains: files/isf/core/spell_score.lua did not return a table" )
end
local report_lib = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
if ( type( report_lib ) ~= "table" ) then
	error( "holy_mountains: files/isf/core/report.lua did not return a table" )
end
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "holy_mountains: files/isf/adapters/profile.lua did not return a table" )
end
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "holy_mountains: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.PROVIDER_ID = "holy_mountains"

local MOD_ID = "interesting_seed_filter"
local MOD_RNG_PATH = "mods/" .. MOD_ID .. "/files/isf/random/prng.lua"
M.MOD_RNG_PATH = MOD_RNG_PATH

-- NG0 normal-mode Holy Mountain anchor positions (PRD scope: main world NG0).
-- Values match the shipped `data/biome_impl/static_tile/temples.psd` anchor set
-- used by both reference tools; only the first three are in ISF-01 scope.
M.TEMPLES = {
	{ index = 1, x = -32, y = 1410 },
	{ index = 2, x = -32, y = 2946 },
	{ index = 3, x = -32, y = 4994 },
	-- Kept for oracle cross-checks against upstream fixtures (out of ISF-01 scope).
	{ index = 4, x = -32, y = 6530 },
	{ index = 5, x = -32, y = 8578 },
	{ index = 6, x = -32, y = 10626 },
	{ index = 7, x = 2560, y = 13181 },
}

-- Temple-local shop offsets from temple_altar.lua's spawn function placement:
-- the shop anchor is 299 px left of and 15 px above the altar anchor.
M.SHOP_OFFSET_X = -299
M.SHOP_OFFSET_Y = -15
M.SHOP_WIDTH = 132
M.DEFAULT_ITEM_COUNT = 5
M.UPPER_ROW_DY = -30

-- generate_shop_item.lua's depth -> biome tier table, indexed by floor(y/512).
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

-- Shop tier from a y coordinate, matching generate_shop_item.lua.
function M.shop_level( y )
	local biomepixel = math.floor( y / 512 )
	local level = BIOMES[ biomepixel ] or 0
	if ( biomepixel > 35 ) then
		level = 7
	end
	return level, biomepixel
end

--------------------------------------------------------------------------------
-- PRNG plumbing: consume the shared module, never implement one here
--------------------------------------------------------------------------------

local function try_dofile( path )
	if ( type( dofile_once ) ~= "function" ) then
		return nil, "dofile_once unavailable in this host"
	end
	local ok, value = pcall( dofile_once, path )
	if ( not ok ) then
		return nil, tostring( value )
	end
	return value
end

-- Accepted, in priority order:
--   1. options.rng_module  : table with .new(world_seed)
--   2. options.rng_factory : function(world_seed) -> rng instance
--   3. options.rng_path    : path handed to dofile_once (dev / tests only)
--   4. MOD_RNG_PATH        : mod-namespaced production default
--
-- dofile_once addresses the game's virtual filesystem root, where mod files
-- live under "mods/<mod>/...". A bare project-relative "files/isf/..." path does
-- NOT resolve there, so the production default is mod-prefixed on purpose.
-- Returns factory, f32 (or nil), error.
local function resolve_rng_factory( options )
	if ( type( options.rng_factory ) == "function" ) then
		return options.rng_factory, options.f32, nil
	end

	local module = options.rng_module
	if ( module == nil ) then
		local path = options.rng_path or MOD_RNG_PATH
		local loaded, err = try_dofile( path )
		if ( loaded == nil ) then
			return nil, nil, string.format(
				"shared PRNG unavailable at '%s' (%s); pass options.rng_module, "
					.. "options.rng_factory or options.rng_path",
				path,
				tostring( err )
			)
		end
		module = loaded
	end

	if ( type( module ) ~= "table" or type( module.new ) ~= "function" ) then
		return nil, nil, "shared PRNG module must expose new(world_seed)"
	end
	return function( world_seed )
		return module.new( world_seed )
	end, ( type( module.f32 ) == "function" and module.f32 or nil ), nil
end

local function check_rng_instance( rng )
	if ( type( rng ) ~= "table" ) then
		return "PRNG factory did not return a table instance"
	end
	if ( type( rng.SetRandomSeed ) ~= "function" ) then
		return "PRNG instance is missing SetRandomSeed(x, y)"
	end
	if ( type( rng.Random ) ~= "function" ) then
		return "PRNG instance is missing Random(a, b)"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Game-faithful shop generation
--------------------------------------------------------------------------------

-- Which pool entries GetRandomAction may choose, given the unlock snapshot.
-- An entry with `spawn_requires_flag` participates only when that persistent
-- flag is set; everything else is always available.
function M.build_pool( profile )
	local pool = { entries = {}, weight_sum = {}, included = 0, excluded = {} }
	for i = 1, #spells.pool do
		local entry = spells.pool[ i ]
		local allowed = true
		if ( entry.requires_flag ~= nil ) then
			allowed = profile_lib.has_flag( profile, entry.requires_flag )
			if ( not allowed ) then
				pool.excluded[ #pool.excluded + 1 ] = entry.id
			end
		end
		if ( allowed ) then
			pool.entries[ #pool.entries + 1 ] = entry
			pool.included = pool.included + 1
		end
	end
	-- Weight sums are computed from the included set only, so a locked card can
	-- never contribute probability mass (and thus can never shift a draw).
	for level = 0, 10 do
		local sum = 0
		for j = 1, #pool.entries do
			sum = sum + pool.entries[ j ].weights[ level + 1 ]
		end
		pool.weight_sum[ level + 1 ] = sum
	end
	return pool
end

-- GetRandomAction(x, y, level, offset): one weighted draw from the pool.
--
-- The shared PRNG binds the world seed at construction
-- (`prng.new(world_seed)`) and `SetRandomSeed(x, y)` reseeds from position, so
-- the `offset` parameter of the game's GetRandomAction is expressed as a
-- *world seed* change: offset 0 uses `rng`, any other offset needs a separate
-- instance built from `factory(seed + offset)`. Callers that only need the
-- common offset-0 case can pass factory = nil.
--
-- Returns spell_id, or nil plus a reason when the draw is not resolvable.
function M.get_random_action( rng, pool, x, y, level, offset, factory, seed )
	if ( level < 0 or level > 10 ) then
		return nil, "level_out_of_range:" .. tostring( level )
	end
	local sum = pool.weight_sum[ level + 1 ]
	if ( sum == nil or sum <= 0 ) then
		return nil, "level_has_no_weight:" .. tostring( level )
	end

	local draw_rng = rng
	offset = offset or 0
	if ( offset ~= 0 ) then
		if ( type( factory ) ~= "function" ) then
			return nil, "offset_requires_separate_prng_instance"
		end
		draw_rng = factory( seed + offset )
		local problem = check_rng_instance( draw_rng )
		if ( problem ~= nil ) then
			return nil, "offset_prng_unusable:" .. problem
		end
	end

	draw_rng:SetRandomSeed( x, y )
	local acc = sum * draw_rng:Next()

	for j = 1, #pool.entries do
		local entry = pool.entries[ j ]
		local p = entry.weights[ level + 1 ]
		if ( p ~= nil and p > 0 ) then
			if ( p >= acc ) then
				return entry.id, nil
			end
			acc = acc - p
		end
	end
	-- Weighted walk fell through: upstream tools disagree on the fallback, so do
	-- not invent a card. The caller marks the slot unresolved instead.
	return nil, "weighted_walk_fell_through"
end

-- One shop slot. This is `generate_shop_item(x, y, ...)` minus the visual and
-- price work, which cannot affect which card appears.
--   opts.float32_item_x: narrow the slot x to binary32 before seeding (the
--   engine stores the shop slot offset as a float, and both reference ports
--   narrow at this point; see the oracle check in tools/foundation).
--   f32: the shared PRNG module's binary32 narrowing helper (optional).
function M.generate_shop_item( rng, pool, x, y, opts, f32, factory, seed )
	local seeded_x = x
	if ( opts.float32_item_x ~= false and type( f32 ) == "function" ) then
		seeded_x = f32( x )
	end
	local level, biomepixel = M.shop_level( y )
	local spell_id, reason = M.get_random_action( rng, pool, seeded_x, y, level, 0, factory, seed )
	return {
		x = x,
		y = y,
		seeded_x = seeded_x,
		level = level,
		biomepixel = biomepixel,
		spell_id = spell_id,
		unresolved_reason = reason,
	}
end

-- spawn_all_shopitems(x, y) for one Holy Mountain.
-- Returns a shop record: kind = "spell" | "wand", slots = { ... }.
function M.generate_shop( rng, pool, seed, temple, options, f32, factory )
	local shop_x = temple.x + M.SHOP_OFFSET_X
	local shop_y = temple.y + M.SHOP_OFFSET_Y
	local count = options.item_count or M.DEFAULT_ITEM_COUNT
	local item_width = M.SHOP_WIDTH / count

	-- The shop-level seed decides the sale slot and the shop kind.
	rng:SetRandomSeed( shop_x, shop_y )
	local sale_item = rng:Random( 1, count )
	local kind_roll = rng:Random( 0, 100 )
	local kind = kind_roll <= 50 and "spell" or "wand"

	local shop = {
		temple_index = temple.index,
		temple = { x = temple.x, y = temple.y },
		x = shop_x,
		y = shop_y,
		width = M.SHOP_WIDTH,
		count = count,
		item_width = item_width,
		sale_item = sale_item,
		kind_roll = kind_roll,
		kind = kind,
		slots = {},
	}

	if ( kind == "wand" ) then
		-- Wand contents belong to ISF-10; nothing is guessed here.
		return shop
	end

	for i = 1, count do
		local slot_x = shop_x + ( i - 1 ) * item_width
		local front = M.generate_shop_item( rng, pool, slot_x, shop_y, options, f32, factory, seed )
		front.row = "front"
		front.slot = i
		front.is_sale = ( i == sale_item )
		shop.slots[ #shop.slots + 1 ] = front

		local back = M.generate_shop_item( rng, pool, slot_x, shop_y + M.UPPER_ROW_DY, options, f32, factory, seed )
		back.row = "back"
		back.slot = i
		back.is_sale = false
		shop.slots[ #shop.slots + 1 ] = back
	end
	return shop
end

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

local function score_slots( report, shop, options )
	local scored = 0
	local unresolved = 0
	for i = 1, #shop.slots do
		local slot = shop.slots[ i ]
		if ( slot.spell_id == nil ) then
			unresolved = unresolved + 1
			report:warning(
				"unresolved_slot",
				string.format(
					"HM%d %s row slot %d at (%s, %s) could not be resolved (%s)",
					shop.temple_index,
					slot.row,
					slot.slot,
					units.to_string( slot.seeded_x ),
					tostring( slot.y ),
					tostring( slot.unresolved_reason )
				)
			)
		else
			local info = spell_score.classify( slot.spell_id, spell_score.CONTEXT_HOLY_MOUNTAIN )
			if ( info ~= nil ) then
				report:add( {
					id = string.format( "hm%d.%s.%02d", shop.temple_index, slot.row, slot.slot ),
					rule_id = "R7",
					category = "holy_mountain.spell_cards",
					biome = "holy_mountain",
					source_id = "holy_mountain_shop",
					x = slot.seeded_x,
					y = slot.y,
					score_units = info.score_units,
					spell_id = slot.spell_id,
					spell_group = info.group,
					realm = "holy_mountain",
					shop_id = string.format( "hm%d", shop.temple_index ),
					slot = slot.slot,
					row = slot.row,
					is_sale = slot.is_sale,
					reason = info.reason,
				} )
				scored = scored + 1
			end
		end
	end
	return scored, unresolved
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

local DEFAULT_OPTIONS = {
	holy_mountains = 3,
	item_count = M.DEFAULT_ITEM_COUNT,
	float32_item_x = true,
	include_out_of_scope_shops = false,
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

-- evaluate( seed, profile, options ) -> report table (WORKER_CONTRACT.md schema).
function M.evaluate( seed, profile, options )
	local resolved = merge_options( options )
	local clock = ( type( os ) == "table" and type( os.clock ) == "function" ) and os.clock or nil
	local started = clock and clock() or nil

	local errors = {}
	local warnings = {}

	if ( type( seed ) ~= "number" or seed ~= math.floor( seed ) or seed < 0 or seed > 4294967295 ) then
		errors[ #errors + 1 ] = {
			code = "bad_seed",
			message = "seed must be an integer in [0, 2^32-1]; got " .. tostring( seed ),
		}
	end
	if ( type( profile ) ~= "table" ) then
		errors[ #errors + 1 ] = {
			code = "bad_profile",
			message = "profile must be a normalized profile table (see files/isf/adapters/profile.lua)",
		}
	end

	local report = report_lib.new( {
		seed = seed,
		profile_id = type( profile ) == "table" and profile.id or "invalid",
		profile_identity = type( profile ) == "table" and profile_lib.identity( profile ) or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, baseline with no perks picked",
			"rule R7 covers independently sold Holy Mountain spell cards only",
			"wand shops and sold wands are ISF-10 scope and are reported as deferred",
			"Always Cast is a wand property and is never scored as a normal spell",
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
				float32_item_x = resolved.float32_item_x ~= false,
			},
		},
	} )

	for i = 1, #errors do
		report:error( errors[ i ].code, errors[ i ].message )
	end
	for i = 1, #warnings do
		report:warning( warnings[ i ].code, warnings[ i ].message )
	end
	if ( #errors > 0 ) then
		report:claim( "holy_mountain.spell_cards", report_lib.COVERAGE_UNSUPPORTED, "invalid input" )
		return report:finish()
	end

	local factory, f32, rng_err = resolve_rng_factory( resolved )
	if ( factory == nil ) then
		report:error( "rng_unavailable", rng_err )
		report:claim( "holy_mountain.spell_cards", report_lib.COVERAGE_UNSUPPORTED, "shared PRNG unavailable" )
		return report:finish()
	end

	local rng = factory( seed )
	local rng_problem = check_rng_instance( rng )
	if ( rng_problem ~= nil ) then
		report:error( "rng_bad_instance", rng_problem )
		report:claim( "holy_mountain.spell_cards", report_lib.COVERAGE_UNSUPPORTED, "shared PRNG interface mismatch" )
		return report:finish()
	end

	local pool = M.build_pool( profile )
	if ( pool.included == 0 ) then
		report:error( "empty_pool", "no spell can spawn with this unlock snapshot" )
		report:claim( "holy_mountain.spell_cards", report_lib.COVERAGE_UNSUPPORTED, "spell pool empty" )
		return report:finish()
	end

	local shop_count = resolved.holy_mountains
	local shops = {}
	local spell_shops = 0
	local wand_shops = 0
	local unresolved_slots = 0
	local scored_cards = 0

	for i = 1, shop_count do
		local temple = M.TEMPLES[ i ]
		if ( temple == nil ) then
			report:error( "unknown_temple", "no anchor position for Holy Mountain " .. tostring( i ) )
		else
			local shop = M.generate_shop( rng, pool, seed, temple, resolved, f32, factory )
			shops[ #shops + 1 ] = shop
			if ( shop.kind == "wand" ) then
				wand_shops = wand_shops + 1
			else
				spell_shops = spell_shops + 1
				local scored, unresolved = score_slots( report, shop, resolved )
				scored_cards = scored_cards + scored
				unresolved_slots = unresolved_slots + unresolved
			end
		end
	end

	-- Coverage: the independent-card category is complete only when every spell
	-- shop slot resolved. Wand shops do not subtract from it; their contents are
	-- a separate, explicitly unsupported category.
	if ( unresolved_slots == 0 and shop_count == resolved.holy_mountains ) then
		report:claim(
			"holy_mountain.spell_cards",
			report_lib.COVERAGE_COMPLETE,
			"all three Holy Mountain shops generated; every spell-shop slot resolved"
		)
	else
		report:claim(
			"holy_mountain.spell_cards",
			report_lib.COVERAGE_PARTIAL,
			string.format( "%d slot(s) unresolved", unresolved_slots )
		)
	end
	-- SCOPE DISCIPLINE: this provider owns ONLY the independent-card category.
	-- It deliberately makes no claim about sold wands, perks, wild wands, chests,
	-- puzzles, wild shops or liquids. Those belong to other providers (sold wands
	-- -> holy_mountain_wands, perks -> perks), and an out-of-scope `unsupported`
	-- claim here would overwrite a real provider's coverage during aggregation --
	-- exactly what happened to the reviewed perks provider before this fix.
	-- The aggregate evaluator treats an absent claim as unsupported, so nothing
	-- is hidden by staying silent.

	local finished = report:finish()

	-- Details are attached after finish so they never participate in scoring.
	finished.details = {
		shops = shops,
		pool = {
			included = pool.included,
			excluded = pool.excluded,
			excluded_count = #pool.excluded,
			gated_flag_count = #spells.gated_flag_list,
		},
		summary = {
			holy_mountains = shop_count,
			spell_shops = spell_shops,
			wand_shops = wand_shops,
			scored_cards = scored_cards,
			unresolved_slots = unresolved_slots,
		},
	}

	local elapsed = clock and clock() or nil
	if ( started ~= nil and elapsed ~= nil ) then
		-- Timing is recorded OUTSIDE `meta` on purpose: `meta` participates in
		-- the serialized report, and a wall-clock duration would make two runs of
		-- the same seed non-byte-identical. `timing_ms` is diagnostic only.
		finished.timing_ms = ( elapsed - started ) * 1000.0
	end
	return finished
end

-- Deterministically rebuild the raw shop contents without scoring, for tests and
-- for comparing against an upstream oracle.
function M.content( seed, profile, options )
	local resolved = merge_options( options )
	local factory, f32, err = resolve_rng_factory( resolved )
	if ( factory == nil ) then
		return nil, err
	end
	local rng = factory( seed )
	local problem = check_rng_instance( rng )
	if ( problem ~= nil ) then
		return nil, problem
	end
	local pool = M.build_pool( profile )
	local shops = {}
	for i = 1, resolved.holy_mountains do
		local temple = M.TEMPLES[ i ]
		if ( temple ~= nil ) then
			shops[ #shops + 1 ] = M.generate_shop( rng, pool, seed, temple, resolved, f32, factory )
		end
	end
	return shops, nil
end

return M
