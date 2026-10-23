-- files/isf/items/content.lua
--
-- ISF-09 / PRD R5: exact container-content predictors.
--
-- These functions answer one question only: "given the world seed and the exact
-- transform the game seeds this container with, which material does it start
-- containing?" They are the only place that may claim to know a container's
-- initial material.
--
-- Faithfulness notes (every branch mirrors the installed scripts; see
-- files/isf/data/containers.lua for the provenance of each list):
--
--   potion.lua init()
--     SetRandomSeed( x, y )
--     Random(0,100) <= 75 ?  (magic path)
--         Random(0,100000) <= 50   -> magic_liquid_hp_regeneration
--         Random(200,100000) <= 250 -> purifying_powder
--         Random(250,100000) <= 500 -> magic_liquid_weakness
--         else random_from_array(materials_magic)
--       : random_from_array(materials_standard)
--     then the calendar overrides, each of which only draws when its date
--     condition already matched (Lua `and` short-circuits).
--   potion_secret.lua init()  : random_from_array(potions) (13 entries)
--   powder_stash.lua init()   : Random(0,100) <= 75 ? magic list : standard list
--
-- `random_from_array` is `Random(1, #t)` in data/scripts/lib/utilities.lua; the
-- upstream `cost`/`weight` fields are never read by the game, so the lists are
-- uniform and their file order is load-bearing.
--
-- Everything else (random-material potions, starting flasks, jars) has no
-- reproducible offline generator and is reported as unresolved, never guessed.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.
--
-- Licensing / provenance (MIT reuse):
--   * material pools and the branch structure mirror the installed game scripts
--     (data/scripts/items/potion.lua, potion_secret.lua, powder_stash.lua).
--   * cross-checked against noita-tools, Copyright (c) 2022 Seva Maltsev
--     <me@seva.dev> (pin 0c7f27cf…) and noita-telescope, Copyright (c) 2026 Lymm
--     (pin ca0282fb…), both MIT.
--   * the PRNG is not implemented here: the shared mod module is consumed.

local containers = dofile_once( "mods/interesting_seed_filter/files/isf/data/containers.lua" )
if ( type( containers ) ~= "table" ) then
	error( "items/content: files/isf/data/containers.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

local MOD_RNG_PATH = "mods/interesting_seed_filter/files/isf/random/prng.lua"
M.MOD_RNG_PATH = MOD_RNG_PATH

--------------------------------------------------------------------------------
-- Shared PRNG plumbing (consumed, never reimplemented)
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
--   1. rng_factory : function(world_seed) -> instance
--   2. rng_module  : table exposing new(world_seed)
--   3. rng_path    : path for dofile_once (tests / development only)
--   4. MOD_RNG_PATH: the mod-namespaced production default
--
-- dofile_once resolves the game's virtual root, where mod files live under
-- "mods/<mod>/..."; a bare project-relative "files/..." path would be a bug.
function M.resolve_rng_factory( options )
	options = options or {}
	if ( type( options.rng_factory ) == "function" ) then
		return options.rng_factory, nil
	end
	local module = options.rng_module
	if ( module == nil ) then
		local path = options.rng_path or MOD_RNG_PATH
		local loaded, err = try_dofile( path )
		if ( loaded == nil ) then
			return nil, string.format(
				"shared PRNG unavailable at '%s' (%s); pass options.rng_module or options.rng_factory",
				path, tostring( err ) )
		end
		module = loaded
	end
	if ( type( module ) ~= "table" or type( module.new ) ~= "function" ) then
		return nil, "shared PRNG module must expose new(world_seed)"
	end
	return function( world_seed )
		return module.new( world_seed )
	end, nil
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

M.check_rng_instance = check_rng_instance

-- `random_from_array( t )` in game Lua is `Random( 1, #t )`.
local function random_from_array( rng, list )
	local index = rng:Random( 1, #list )
	return list[ index ]
end

--------------------------------------------------------------------------------
-- Calendar input
--------------------------------------------------------------------------------
--
-- The normal potion generator reads EIGHT values from
-- GameGetDateAndTimeLocal() while tools_modding/lua_api_documentation.txt
-- documents six, so the 7th (`jussi`) and 8th (`mammi`) values are engine
-- internals. They are therefore never guessed from month/day: the caller passes
-- them explicitly, and their absence is reported as an unresolved condition.
--
-- The two fixed-date overrides (Apr 30 / May 1 and Feb 14) *are* fully specified
-- by potion.lua itself and only need month/day.
--
-- normalize_calendar returns:
--   { month, day, jussi, mammi, jussi_known, mammi_known, month_day_known }
-- Invalid input never raises: the caller decides how strict to be, and every
-- unknown is visible in the returned table.
function M.normalize_calendar( calendar )
	local out = {
		month = nil, day = nil,
		-- nil (not false) means "not supplied": an unknown engine flag must stay
		-- distinguishable from a supplied false after re-normalization.
		jussi = nil, mammi = nil,
		jussi_known = false, mammi_known = false,
		month_day_known = false,
	}
	if ( type( calendar ) ~= "table" ) then
		return out, "calendar is not a table"
	end
	local month = tonumber( calendar.month )
	local day = tonumber( calendar.day )
	if ( month ~= nil and day ~= nil
		and month == math.floor( month ) and day == math.floor( day )
		and month >= 1 and month <= 12 and day >= 1 and day <= 31 ) then
		out.month = month
		out.day = day
		out.month_day_known = true
	end
	local problems = {}
	if ( not out.month_day_known ) then
		problems[ #problems + 1 ] = "calendar month/day missing or out of range"
	end
	if ( type( calendar.jussi ) == "boolean" ) then
		out.jussi = calendar.jussi
		out.jussi_known = true
	end
	if ( type( calendar.mammi ) == "boolean" ) then
		out.mammi = calendar.mammi
		out.mammi_known = true
	end
	if ( not out.jussi_known ) then
		problems[ #problems + 1 ] = "calendar.jussi (engine 7th date value) not supplied"
	end
	if ( not out.mammi_known ) then
		problems[ #problems + 1 ] = "calendar.mammi (engine 8th date value) not supplied"
	end
	if ( #problems == 0 ) then
		return out, nil
	end
	return out, table.concat( problems, "; " )
end

--------------------------------------------------------------------------------
-- Predictors
--------------------------------------------------------------------------------

-- potion.lua init(): normal potion, including the calendar overrides.
-- Returns material, details. `details.calendar_complete` is false when the
-- caller did not pin the engine-only jussi/mammi flags; the result then assumes
-- both are false and is only valid for that assumption.
function M.predict_potion_material( rng, x, y, calendar )
	rng:SetRandomSeed( x, y )

	local cal, cal_problem = M.normalize_calendar( calendar )
	local overrides = {}
	local standard_path = false
	local rare = nil

	if ( rng:Random( 0, 100 ) <= 75 ) then
		if ( rng:Random( 0, 100000 ) <= 50 ) then
			rare = "magic_liquid_hp_regeneration"
		elseif ( rng:Random( 200, 100000 ) <= 250 ) then
			rare = "purifying_powder"
		elseif ( rng:Random( 250, 100000 ) <= 500 ) then
			rare = "magic_liquid_weakness"
		end
	else
		standard_path = true
	end

	local material
	if ( rare ~= nil ) then
		material = rare
	elseif ( standard_path ) then
		material = random_from_array( rng, containers.POTION_STANDARD )
	else
		material = random_from_array( rng, containers.POTION_MAGIC )
	end

	-- Calendar overrides, exactly in potion.lua's order. Lua's `and`
	-- short-circuit is reproduced by nesting the draws.
	if ( cal.month_day_known
		and ( ( cal.month == 5 and cal.day == 1 ) or ( cal.month == 4 and cal.day == 30 ) )
		and rng:Random( 0, 100 ) <= 20 ) then
		if ( rng:Random( 0, 5 ) <= 4 ) then
			material = "sima"
		else
			material = "beer"
		end
		overrides[ #overrides + 1 ] = "vappu"
	end

	if ( cal.jussi and rng:Random( 0, 100 ) <= 9 ) then
		if ( rng:Random( 0, 3 ) <= 2 ) then
			material = "juhannussima"
		else
			material = "beer"
		end
		overrides[ #overrides + 1 ] = "jussi"
	end

	if ( cal.mammi and rng:Random( 0, 100 ) <= 10 ) then
		material = "mammi"
		overrides[ #overrides + 1 ] = "mammi"
	end

	if ( cal.month_day_known and cal.month == 2 and cal.day == 14
		and rng:Random( 0, 100 ) <= 8 ) then
		material = "magic_liquid_charm"
		overrides[ #overrides + 1 ] = "valentine"
	end

	return material, {
		generator = "potion",
		calendar_complete = ( cal.month_day_known and cal.jussi_known and cal.mammi_known ),
		calendar_problem = cal_problem,
		calendar_overrides = overrides,
		rare_branch = rare,
		standard_branch = standard_path and rare == nil,
	}
end

-- potion_secret.lua init(): a fixed 13-entry uniform draw; no calendar terms.
function M.predict_secret_potion_material( rng, x, y )
	rng:SetRandomSeed( x, y )
	local material = random_from_array( rng, containers.POTION_SECRET )
	return material, {
		generator = "potion_secret",
		calendar_complete = true,
		calendar_overrides = {},
	}
end

-- powder_stash.lua init(): the pouch's initial powder.
function M.predict_pouch_material( rng, x, y )
	rng:SetRandomSeed( x, y )
	local magic = rng:Random( 0, 100 ) <= 75
	local material
	if ( magic ) then
		material = random_from_array( rng, containers.POUCH_MAGIC )
	else
		material = random_from_array( rng, containers.POUCH_STANDARD )
	end
	return material, {
		generator = "powder_stash",
		calendar_complete = true,
		calendar_overrides = {},
		magic_branch = magic,
	}
end

-- Generic entry point used by the provider.
--   kind          : "potion" | "powder_pouch" (canonical R5 container kind)
--   generator     : one of containers.GENERATORS keys; when nil it is derived
--                   from `entity_file`
--   x, y          : the EXACT entity transform (containers.SEED_FRAME)
--   calendar      : explicit calendar input table (see normalize_calendar)
-- Returns material, details  or  nil, reason.
function M.predict( rng, kind, generator, x, y, calendar )
	if ( type( rng ) ~= "table" ) then
		return nil, "no PRNG instance"
	end
	local problem = check_rng_instance( rng )
	if ( problem ~= nil ) then
		return nil, problem
	end
	if ( type( x ) ~= "number" or type( y ) ~= "number" ) then
		return nil, "seed position must be numeric"
	end
	if ( generator == nil ) then
		return nil, "no content generator resolved for this container"
	end
	if ( generator == "potion" ) then
		if ( kind ~= nil and kind ~= "potion" ) then
			return nil, "generator 'potion' does not produce a " .. tostring( kind )
		end
		return M.predict_potion_material( rng, x, y, calendar )
	elseif ( generator == "potion_secret" ) then
		if ( kind ~= nil and kind ~= "potion" ) then
			return nil, "generator 'potion_secret' does not produce a " .. tostring( kind )
		end
		return M.predict_secret_potion_material( rng, x, y )
	elseif ( generator == "powder_stash" ) then
		if ( kind ~= nil and kind ~= "powder_pouch" ) then
			return nil, "generator 'powder_stash' does not produce a " .. tostring( kind )
		end
		return M.predict_pouch_material( rng, x, y )
	end
	local info = containers.GENERATORS[ generator ]
	if ( info ~= nil and info.supported == false ) then
		return nil, info.reason or ( "content generator '" .. tostring( generator ) .. "' is unsupported" )
	end
	return nil, "unknown content generator '" .. tostring( generator ) .. "'"
end

return M
