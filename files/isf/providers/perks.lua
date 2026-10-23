-- ISF-11 / PRD R8: perk opportunity provider.
--
-- Predicts the perk choices offered by the first two Holy Mountains plus the
-- first three rounds of the *independent* refresh sequence, then scores the
-- deduplicated opportunity set once per perk type.
--
-- Model (PRD R8):
--   * Initial sequence: the first two Holy Mountains consume the deck forward
--     through the global TEMPLE_NEXT_PERK_INDEX, 3 perks per altar.
--   * Refresh sequence: a *separate*, global budget of 3 refreshes, walked
--     backward from the end of the deck via TEMPLE_REROLL_PERK_INDEX,
--     3 perks per round. Which altar is refreshed is deliberately not
--     enumerated: the refresh index is global, so the walked sequence is the
--     same either way.
--   * Both sequences are merged and deduplicated per perk *type*. A perk type
--     contributes its R8 score once, no matter how often it is offered.
--   * Baseline: no perk is ever picked. No `PERK_PICKED_*_PICKUP_COUNT` flags
--     exist, so the deck contains no blanked slots, no EXTRA_PERK row growth,
--     no perk lottery effects, and no GAMBLE resolution.
--
-- Ported from:
--   * Noita shipped Lua: data/scripts/perks/perk.lua
--       perk_get_spawn_order, perk_spawn_many, perk_reroll_perks
--     (read-only reference copy kept under
--      .scratch/interesting-seed-filter/perks/extracted/).
--   * noita-tools src/services/SeedInfo/infoHandler/InfoProviders/Perk/index.ts
--       MIT License, Copyright (c) 2022 Seva Maltsev <me@seva.dev>
--       upstream pin: 0c7f27cf9b28ffcf2d8e6a5e41b3a007fe8ad21f
--   * noita-telescope js/perks.js
--       MIT License, Copyright (c) 2026 Lymm
--   Upstream JS/TS ports were used as the algorithmic reference; this file is a
--   Lua 5.1 reimplementation with integer score_units and a report schema.
--   Agreement with those upstreams is oracle parity, NOT game validation.
--
-- Runtime constraints (WORKER_CONTRACT.md):
--   * Pure Lua 5.1; no FFI, no native code, no external processes, no require
--     of external packages.
--   * The random number generator is owned by the worldgen workflow
--     (files/isf/random/prng.lua). This module never reimplements or writes it;
--     it consumes an injected instance and validates the interface it needs.
--   * No game globals, world seed, unlocks or persistent state are read or
--     written. The same seed + profile + options always produces the same
--     report.

-- NOTE ON PATHS: dofile_once resolves against the GAME virtual filesystem root,
-- where this mod's files are addressed as
-- "mods/interesting_seed_filter/files/...". Bare project-relative paths do not
-- resolve at runtime, so every load below is mod-namespaced.

local MOD_ID = "interesting_seed_filter"
local MOD_PREFIX = "mods/" .. MOD_ID .. "/"

local perks_data = dofile_once( MOD_PREFIX .. "files/isf/data/perks.lua" )
if ( type( perks_data ) ~= "table" ) then
	error( "perks provider: " .. MOD_PREFIX
		.. "files/isf/data/perks.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.RULE_ID = "R8"
M.PROVIDER_ID = "perks"

-- Game build the perk data was extracted from, for report provenance.
M.DATA_GAME_VERSION_HASH = "9dbd52ced019a643169a2db02f46c77f8766c6e5"
M.DATA_SOURCE = "data/scripts/perks/perk_list.lua"

-- Native constants from data/scripts/perks/perk.lua.
local MIN_DISTANCE_BETWEEN_DUPLICATE_PERKS = 4
local DEFAULT_MAX_STACKABLE_PERK_COUNT = 128

-- Fixed NG0 Holy Mountain positions (x = -32, y from temple-locations.json).
-- Only y is needed for reporting because the perk row walks are deck-driven;
-- the per-slot x is derived exactly as perk_spawn_many does.
local HOLY_MOUNTAIN_X = -32
local HOLY_MOUNTAIN_Y = { 1410, 2946, 4994, 6530, 8578, 10626, 13181 }
local HOLY_MOUNTAIN_WIDTH = 60

M.MODEL = {
	name = "independent_opportunity_sets",
	initial_source = "holy_mountain_initial",
	refresh_source = "holy_mountain_refresh_sequence",
	dedup_unit = "perk_type",
	picks_modelled = false,
	refresh_allocation_enumerated = false,
	refresh_budget = 3,
	row_size = 3,
	initial_altars = 2,
}

--------------------------------------------------------------------------------
-- Deterministic PRNG plumbing
--------------------------------------------------------------------------------

-- Rounds half to even, matching Noita's round_half_of_even for perk slot x.
local function round_half_of_even( value )
	local floor = math.floor( value )
	local diff = value - floor
	if ( diff > 0.5 ) then
		return floor + 1
	elseif ( diff < 0.5 ) then
		return floor
	elseif ( floor % 2 == 0 ) then
		return floor
	end
	return floor + 1
end

M.round_half_of_even = round_half_of_even

-- Resolve the shared PRNG module table without creating one of our own.
-- Accepted, in priority order:
--   1. options.rng_module  : a table with .new(world_seed)
--   2. options.rng_factory : a function(world_seed) -> rng instance
--   3. options.rng_path    : path handed to dofile_once (dev / tests only)
--   4. MOD_RNG_PATH, the mod-namespaced default below
--
-- CRITICAL: dofile_once addresses the game's virtual filesystem root, whose data
-- files live under "data/..." and whose mod files live under "mods/<mod>/...".
-- A bare project-relative path such as "files/isf/random/prng.lua" does NOT
-- resolve in that namespace, so the production default must be mod-prefixed.
local MOD_RNG_PATH = MOD_PREFIX .. "files/isf/random/prng.lua"

M.MOD_RNG_PATH = MOD_RNG_PATH

local function try_dofile( path )
	if ( type( dofile_once ) ~= "function" ) then
		return nil, "dofile_once is unavailable"
	end
	-- dofile_once returns (value) or (nil, error_string). The second return is the
	-- only diagnostic the game gives for a bad path, so it must be surfaced;
	-- otherwise a path-namespace mistake looks like "module did not return a table".
	local ok, result, load_error = pcall( dofile_once, path )
	if ( not ok ) then
		return nil, tostring( result )
	end
	if ( type( result ) ~= "table" ) then
		if ( load_error ~= nil and load_error ~= "" ) then
			return nil, tostring( load_error )
		end
		return nil, "module did not return a table"
	end
	return result
end

local function resolve_rng( options )
	if ( type( options.rng_factory ) == "function" ) then
		return options.rng_factory
	end
	local module = options.rng_module
	if ( module == nil ) then
		local path = options.rng_path or MOD_RNG_PATH
		local loaded, err = try_dofile( path )
		if ( loaded == nil ) then
			return nil, string.format(
				"shared PRNG unavailable at '%s' (%s); pass options.rng_module, "
					.. "options.rng_factory or options.rng_path",
				path,
				tostring( err )
			)
		end
		module = loaded
	end
	if ( type( module ) ~= "table" or type( module.new ) ~= "function" ) then
		return nil, "shared PRNG module must expose new(world_seed)"
	end
	return function( world_seed )
		return module.new( world_seed )
	end
end

local function check_rng_instance( rng )
	if ( type( rng ) ~= "table" ) then
		return "PRNG factory did not return a table instance"
	end
	if ( type( rng.SetRandomSeed ) ~= "function" and
		type( rng[ "SetRandomSeed" ] ) ~= "function" ) then
		return "PRNG instance is missing SetRandomSeed(x, y)"
	end
	if ( type( rng.Random ) ~= "function" ) then
		return "PRNG instance is missing Random(a, b)"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Perk deck construction (perk_get_spawn_order, baseline with no picks)
--------------------------------------------------------------------------------

-- Builds the deterministic perk deck for a world seed.
-- Returns deck (array of perk ids), stackable_count map, and diagnostics.
function M.build_deck( seed, rng )
	rng:SetRandomSeed( 1, 2 )

	local perk_deck = {}
	local stackable_distances = {}
	local stackable_count = {}

	for _, perk_data in ipairs( perks_data.perk_list ) do
		local not_in_pool = ( perk_data.not_in_default_perk_pool == true )
		if ( not not_in_pool ) then
			local perk_name = perk_data.id
			local how_many_times = 1

			-- Native sets these for every perk before the stackable branch.
			stackable_distances[ perk_name ] = -1
			stackable_count[ perk_name ] = -1

			if ( perk_data.stackable == true ) then
				local max_perks = rng:Random( 1, 2 )
				if ( perk_data.max_in_perk_pool ~= nil ) then
					max_perks = rng:Random( 1, perk_data.max_in_perk_pool )
				end

				if ( perk_data.stackable_maximum ~= nil ) then
					stackable_count[ perk_name ] = perk_data.stackable_maximum
				else
					stackable_count[ perk_name ] = DEFAULT_MAX_STACKABLE_PERK_COUNT
				end

				if ( perk_data.stackable_is_rare == true ) then
					max_perks = 1
				end

				if ( perk_data.stackable_how_often_reappears ~= nil ) then
					stackable_distances[ perk_name ] = perk_data.stackable_how_often_reappears
				else
					stackable_distances[ perk_name ] = MIN_DISTANCE_BETWEEN_DUPLICATE_PERKS
				end

				how_many_times = rng:Random( 1, max_perks )
			end

			for _ = 1, how_many_times do
				perk_deck[ #perk_deck + 1 ] = perk_name
			end
		end
	end

	-- 2) Shuffle the deck (Fisher-Yates; native uses Random(1, i)).
	for i = #perk_deck, 2, -1 do
		local j = rng:Random( 1, i )
		perk_deck[ i ], perk_deck[ j ] = perk_deck[ j ], perk_deck[ i ]
	end

	-- 3) Remove stackable duplicates that are too close to each other.
	for i = #perk_deck, 1, -1 do
		local perk = perk_deck[ i ]
		if ( stackable_distances[ perk ] ~= -1 ) then
			local min_distance = stackable_distances[ perk ]
			local remove_me = false
			for ri = i - min_distance, i - 1 do
				if ( ri >= 1 and perk_deck[ ri ] == perk ) then
					remove_me = true
					break
				end
			end
			if ( remove_me ) then
				table.remove( perk_deck, i )
			end
		end
	end

	-- 4) Blank out perks already picked up. The R8 baseline has no picks, so this
	--    is a no-op; it is kept so the port stays faithful if a profile ever
	--    supplies pickup counts.
	return perk_deck, stackable_count
end

-- Applies the native pickup blanking rule for a given pickup-count map.
-- Exposed for tests; the R8 opportunity model always calls it with {}.
function M.blank_picked_perks( perk_deck, stackable_count, pickup_counts )
	if ( pickup_counts == nil ) then
		return perk_deck
	end
	for i = 1, #perk_deck do
		local perk_name = perk_deck[ i ]
		local pickup_count = pickup_counts[ perk_name ] or 0
		if ( pickup_count > 0 ) then
			local stack_count = stackable_count[ perk_name ] or -1
			if ( stack_count == -1 or pickup_count >= stack_count ) then
				perk_deck[ i ] = ""
			end
		end
	end
	return perk_deck
end

local function clone_deck( perk_deck )
	local copy = {}
	for i = 1, #perk_deck do
		copy[ i ] = perk_deck[ i ]
	end
	return copy
end

-- Forward walk used by perk_spawn_many (initial Holy Mountain rows).
local function next_perk_forward( perk_deck, index )
	local n = #perk_deck
	local perk_id = perk_deck[ index ]

	while ( perk_id == nil or perk_id == "" ) do
		-- Native replaces an exhausted slot with LEGGY_FEET and keeps walking.
		perk_deck[ index ] = "LEGGY_FEET"
		index = index + 1
		if ( index > n ) then
			index = 1
		end
		perk_id = perk_deck[ index ]
	end

	local next_index = index + 1
	if ( next_index > n ) then
		next_index = 1
	end
	return perk_id, next_index
end

-- Backward walk used by perk_reroll_perks (refresh rounds).
local function next_perk_backward( perk_deck, index )
	local n = #perk_deck
	local perk_id = perk_deck[ index ]

	while ( perk_id == nil or perk_id == "" ) do
		perk_deck[ index ] = "LEGGY_FEET"
		index = index - 1
		if ( index <= 0 ) then
			index = n
		end
		perk_id = perk_deck[ index ]
	end

	local next_index = index - 1
	if ( next_index <= 0 ) then
		next_index = n
	end
	return perk_id, next_index
end

M.next_perk_forward = next_perk_forward
M.next_perk_backward = next_perk_backward

--------------------------------------------------------------------------------
-- Opportunity sequence assembly
--------------------------------------------------------------------------------

-- Returns the initial Holy Mountain rows and the independent refresh rows.
-- Each row is { source_id = ..., label = ..., kind = "initial"|"refresh",
--               round = n, perks = { ... }, x = {..}, y = number|nil }
function M.build_opportunities( seed, rng, options )
	local deck, stackable_count = M.build_deck( seed, rng )
	local rows = {}

	local altar_count = options.initial_altars
	local rounds = options.refresh_rounds
	local row_size = options.row_size

	-- Reset any blanking that a profile-supplied pickup map could have applied.
	-- (Baseline: pickup counts are always empty.)
	M.blank_picked_perks( deck, stackable_count, options.pickup_counts )

	local temple_y = HOLY_MOUNTAIN_Y[ 1 ]

	-- Initial sequence: TEMPLE_NEXT_PERK_INDEX starts at 1 and is global.
	local forward_index = 1
	for altar = 1, altar_count do
		local working = clone_deck( deck )
		local row_perks = {}
		local row_x = {}
		local y = HOLY_MOUNTAIN_Y[ altar ] or temple_y
		local step = HOLY_MOUNTAIN_WIDTH / row_size
		for slot = 1, row_size do
			local perk_id
			perk_id, forward_index = next_perk_forward( working, forward_index )
			row_perks[ slot ] = perk_id
			local altar_x = altar == 7 and 2560 or HOLY_MOUNTAIN_X
			local raw_x = altar_x + ( slot - 1 + 0.5 ) * step
			row_x[ slot ] = round_half_of_even( raw_x )
		end
		rows[ #rows + 1 ] = {
			source_id = string.format( "holy_mountain_%d_initial", altar ),
			label = string.format( "Holy Mountain %d initial choices", altar ),
			kind = "initial",
			altar = altar,
			round = 1,
			perks = row_perks,
			x = row_x,
			y = y,
			coordinate_model = "holy_mountain_slot",
		}
	end

	-- Refresh sequence: TEMPLE_REROLL_PERK_INDEX starts at #perks and is global.
	local backward_index = #deck
	for round = 1, rounds do
		local working = clone_deck( deck )
		local row_perks = {}
		for slot = 1, row_size do
			local perk_id
			perk_id, backward_index = next_perk_backward( working, backward_index )
			row_perks[ slot ] = perk_id
		end
		rows[ #rows + 1 ] = {
			source_id = string.format( "refresh_round_%d", round ),
			label = string.format( "Independent refresh round %d", round ),
			kind = "refresh",
			round = round,
			perks = row_perks,
			coordinate_model = "shared_refresh_sequence",
		}
	end

	return rows, deck
end

-- Deduplicated target list in canonical PRD order.
-- Declared before the scoring helpers because they report through it.
local summarise_targets

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

-- Scores a list of opportunity rows under R8.
-- Public because ISF-12 aggregates provider entries and because R8's exact
-- point table must be checkable on a constructed opportunity set (a random seed
-- will not offer all fourteen targets at once). `rows` entries need
-- source_id, kind, perks (array). Optional: x (array), y, coordinate_model.
--
-- Returns entries, total_units, counted_map.
local function count_targets( rows, targets )
	local counted = {}      -- perk_id -> first entry id that scored it
	local entries = {}
	local total_units = 0

	for _, row in ipairs( rows ) do
		for slot, perk_id in ipairs( row.perks ) do
			local score_units = targets[ perk_id ]
			local is_target = ( score_units ~= nil )
			local entry = {
				id = string.format( "%s.%s.%d.%s", M.RULE_ID, row.source_id, slot, perk_id ),
				rule_id = M.RULE_ID,
				category = "perk_opportunity",
				biome = "holy_mountain",
				source_id = row.source_id,
				source_kind = row.kind,
				slot = slot,
				perk_id = perk_id,
				coordinate_model = row.coordinate_model,
				score_units = 0,
				counted = false,
			}
			if ( row.x ~= nil ) then
				entry.x = row.x[ slot ]
				entry.y = row.y
			end

			if ( is_target ) then
				if ( counted[ perk_id ] ) then
					entry.reason = string.format(
						"%s already counted from %s; R8 deduplicates by perk type",
						perk_id,
						counted[ perk_id ]
					)
					entry.duplicate_of = counted[ perk_id ]
				else
					counted[ perk_id ] = entry.id
					entry.counted = true
					entry.score_units = score_units
					total_units = total_units + score_units
					local meta = perks_data.target_meta[ perk_id ]
					entry.reason = string.format(
						"R8 target %s (%s) offered in %s slot %d",
						perk_id,
						meta and meta.name or perk_id,
						row.source_id,
						slot
					)
				end
			else
				entry.reason = string.format(
					"%s is not an R8 target and scores 0",
					tostring( perk_id )
				)
			end

			entries[ #entries + 1 ] = entry
		end
	end

	return entries, total_units, counted
end

-- Public wrapper: score a caller-supplied opportunity set under R8.
-- Returns a table with entries, totals and the deduplicated target list.
function M.score_rows( rows )
	if ( type( rows ) ~= "table" ) then
		error( "score_rows expects a table of opportunity rows" )
	end
	local entries, total_units, counted = count_targets( rows, perks_data.targets )
	local targets, target_total = summarise_targets( counted )
	if ( target_total ~= total_units ) then
		error( string.format(
			"score_rows bookkeeping mismatch: entries=%d targets=%d",
			total_units,
			target_total
		) )
	end
	return {
		entries = entries,
		targets = targets,
		score_units = total_units,
		score = total_units / perks_data.UNITS_PER_POINT,
	}
end

-- Deduplicated target list in canonical PRD order.
summarise_targets = function( counted )
	local list = {}
	local total = 0
	for _, perk_id in ipairs( perks_data.target_order ) do
		local first_id = counted[ perk_id ]
		local meta = perks_data.target_meta[ perk_id ]
		local units = perks_data.targets[ perk_id ]
		list[ #list + 1 ] = {
			perk_id = perk_id,
			name = meta and meta.name or perk_id,
			score_units = units,
			awarded = first_id ~= nil,
			first_entry_id = first_id,
		}
		if ( first_id ~= nil ) then
			total = total + units
		end
	end
	return list, total
end

--------------------------------------------------------------------------------
-- Public evaluation entry point
--------------------------------------------------------------------------------

local function normalise_options( options, errors, warnings )
	local resolved = {
		initial_altars = 2,
		refresh_rounds = 3,
		row_size = 3,
		pickup_counts = {},
		rng_module = nil,
		rng_factory = nil,
		rng_path = nil,
	}

	if ( options == nil ) then
		return resolved
	end
	if ( type( options ) ~= "table" ) then
		errors[ #errors + 1 ] = { code = "bad_options", message = "options must be a table or nil" }
		return resolved
	end

	local function positive_int( name, value, default )
		if ( value == nil ) then
			return default
		end
		if ( type( value ) ~= "number" or value ~= math.floor( value ) or value < 1 ) then
			errors[ #errors + 1 ] = {
				code = "bad_option_" .. name,
				message = string.format( "%s must be a positive integer", name ),
			}
			return default
		end
		return value
	end

	resolved.initial_altars = positive_int( "initial_altars", options.initial_altars, 2 )
	resolved.refresh_rounds = positive_int( "refresh_rounds", options.refresh_rounds, 3 )
	resolved.row_size = positive_int( "row_size", options.row_size, 3 )

	if ( options.initial_altars ~= nil and options.initial_altars ~= 2 ) then
		warnings[ #warnings + 1 ] = {
			code = "non_default_initial_altars",
			message = "R8 defines the first two Holy Mountains; overriding initial_altars "
				.. "produces a non-R8 report",
		}
	end
	if ( options.refresh_rounds ~= nil and options.refresh_rounds ~= 3 ) then
		warnings[ #warnings + 1 ] = {
			code = "non_default_refresh_rounds",
			message = "R8 defines three refresh rounds; overriding refresh_rounds "
				.. "produces a non-R8 report",
		}
	end
	if ( options.row_size ~= nil and options.row_size ~= 3 ) then
		warnings[ #warnings + 1 ] = {
			code = "non_default_row_size",
			message = "vanilla TEMPLE_PERK_COUNT defaults to 3; overriding row_size "
				.. "produces a non-R8 report",
		}
	end

	if ( options.pickup_counts ~= nil ) then
		if ( type( options.pickup_counts ) ~= "table" ) then
			errors[ #errors + 1 ] = {
				code = "bad_pickup_counts",
				message = "pickup_counts must be a table",
			}
		else
			for perk_id, count in pairs( options.pickup_counts ) do
				resolved.pickup_counts[ perk_id ] = count
			end
			warnings[ #warnings + 1 ] = {
				code = "pickup_counts_present",
				message = "pickup_counts deviates from the R8 no-picks baseline",
			}
		end
	end

	resolved.rng_module = options.rng_module
	resolved.rng_factory = options.rng_factory
	resolved.rng_path = options.rng_path
	return resolved
end

local function empty_report( seed, profile_id, errors, warnings )
	return {
		schema_version = M.SCHEMA_VERSION,
		rule_version = M.RULE_VERSION,
		provider = M.PROVIDER_ID,
		seed = seed,
		profile_id = profile_id,
		coverage = {
			status = "unsupported",
			rules = { M.RULE_ID },
			reasons = { "evaluation did not complete" },
		},
		entries = {},
		errors = errors,
		warnings = warnings,
	}
end

-- evaluate(seed, profile, options) -> report table.
-- Deterministic: identical inputs produce identical reports.
function M.evaluate( seed, profile, options )
	local errors = {}
	local warnings = {}

	if ( type( seed ) ~= "number" or seed ~= math.floor( seed ) or seed < 0 ) then
		errors[ #errors + 1 ] = {
			code = "bad_seed",
			message = "seed must be a non-negative integer",
		}
	end

	local profile_id = "unspecified"
	if ( profile == nil ) then
		warnings[ #warnings + 1 ] = {
			code = "missing_profile",
			message = "no generation-condition profile supplied; profile_id set to 'unspecified'",
		}
	elseif ( type( profile ) ~= "table" ) then
		errors[ #errors + 1 ] = { code = "bad_profile", message = "profile must be a table" }
	else
		if ( type( profile.id ) == "string" and profile.id ~= "" ) then
			profile_id = profile.id
		else
			warnings[ #warnings + 1 ] = {
				code = "missing_profile_id",
				message = "profile has no id; profile_id set to 'unspecified'",
			}
		end
		if ( profile.game_version ~= nil and profile.game_version ~= M.DATA_GAME_VERSION_HASH ) then
			warnings[ #warnings + 1 ] = {
				code = "game_version_mismatch",
				message = string.format(
					"profile game_version '%s' differs from the perk data version '%s'; "
						.. "the perk pool may differ in that build",
					tostring( profile.game_version ),
					M.DATA_GAME_VERSION_HASH
				),
			}
		end
	end

	local resolved = normalise_options( options, errors, warnings )

	if ( #errors > 0 ) then
		return empty_report( seed, profile_id, errors, warnings )
	end

	local factory, factory_err = resolve_rng( resolved )
	if ( factory == nil ) then
		errors[ #errors + 1 ] = { code = "rng_unavailable", message = factory_err }
		local report = empty_report( seed, profile_id, errors, warnings )
		report.coverage.reasons = { factory_err }
		return report
	end

	local ok, rng = pcall( factory, seed )
	if ( not ok ) then
		errors[ #errors + 1 ] = {
			code = "rng_factory_failed",
			message = tostring( rng ),
		}
		return empty_report( seed, profile_id, errors, warnings )
	end

	local rng_err = check_rng_instance( rng )
	if ( rng_err ~= nil ) then
		errors[ #errors + 1 ] = { code = "rng_interface", message = rng_err }
		return empty_report( seed, profile_id, errors, warnings )
	end

	local build_ok, rows, deck = pcall( M.build_opportunities, seed, rng, resolved )
	if ( not build_ok ) then
		errors[ #errors + 1 ] = {
			code = "generation_failed",
			message = tostring( rows ),
		}
		return empty_report( seed, profile_id, errors, warnings )
	end

	local entries, total_units, counted = count_targets( rows, perks_data.targets )
	local targets, target_total = summarise_targets( counted )

	-- The two totals must agree; a divergence means scoring bookkeeping is wrong.
	if ( target_total ~= total_units ) then
		errors[ #errors + 1 ] = {
			code = "score_mismatch",
			message = string.format(
				"entry total %d does not match deduplicated target total %d",
				total_units,
				target_total
			),
		}
	end

	return {
		schema_version = M.SCHEMA_VERSION,
		rule_version = M.RULE_VERSION,
		provider = M.PROVIDER_ID,
		seed = seed,
		profile_id = profile_id,
		coverage = {
			status = "complete",
			rules = { M.RULE_ID },
			baseline = "no_perks_picked",
			reasons = {},
			notes = {
				"initial choices from the first two Holy Mountains are evaluated",
				"three independent refresh rounds are evaluated as one shared sequence",
				"opportunities are deduplicated per perk type",
				"perk pickup effects, EXTRA_PERK row growth and GAMBLE are out of model",
				"native sequence parity is validated against an upstream oracle, "
					.. "not against an actual game session",
			},
		},
		model = M.MODEL,
		data = {
			source = M.DATA_SOURCE,
			game_version_hash = M.DATA_GAME_VERSION_HASH,
			pool_entries = #perks_data.perk_list,
			deck_entries = #deck,
			max_score_units = perks_data.max_score_units,
		},
		totals = {
			score_units = total_units,
			score = total_units / perks_data.UNITS_PER_POINT,
			max_score_units = perks_data.max_score_units,
		},
		opportunities = {
			rows = rows,
			targets = targets,
		},
		entries = entries,
		errors = errors,
		warnings = warnings,
	}
end

-- Convenience: deck as a plain array (tests and diagnostics).
function M.deck( seed, rng )
	local deck = M.build_deck( seed, rng )
	return deck
end

return M
