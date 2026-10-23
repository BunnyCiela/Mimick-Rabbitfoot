-- files/isf/adapters/game_profile.lua
--
-- Read-only bridge from the running game to a profile snapshot
-- (ISF-01 acceptance: "reads the actual game version, unlock conditions and
-- runtime information"; PRD section 5 input contract).
--
-- Everything here is strictly read-only:
--   * persistent unlock state is read with HasFlagPersistent(), which never
--     writes to the save;
--   * no SetWorldSeed / SetRandomSeed / AddFlagPersistent / GlobalsSetValue
--     call appears in this file;
--   * the snapshot is copied into the immutable profile adapter, so later game
--     state changes cannot alter an evaluation already in progress.
--
-- The host API table is injected (`api`) rather than read from _G, so tests can
-- supply a fake game with zero side effects and can prove that only the
-- documented read functions are touched.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process.

local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "game_profile: files/isf/adapters/profile.lua did not return a table" )
end

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" ) then
	error( "game_profile: files/isf/data/spells.lua did not return a table" )
end

local M = {}

-- Functions the adapter is allowed to call on the host. Keeping this list
-- explicit documents the read-only contract and lets tests assert it.
M.REQUIRED_READERS = {
	"HasFlagPersistent",
	"GameGetDateAndTimeUTC",
	"GameGetFrameNum",
}

M.OPTIONAL_READERS = {
	"GameGetDateAndTimeLocal",
	"ModGetAPIVersion",
	"GameIsDailyRun",
	"GameIsModeFullyDeterministic",
	"GameIsBetaBuild",
}

local function has_function( api, name )
	return type( api ) == "table" and type( api[ name ] ) == "function"
end

local function call( api, name, ... )
	if ( not has_function( api, name ) ) then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall( api[ name ], ... )
	if ( not ok ) then
		return nil
	end
	return a, b, c, d, e, f, g, h
end

-- Default host: the real game's globals. Only called when the caller does not
-- inject an api table (i.e. inside the mod runtime).
function M.game_api()
	if ( type( _G ) ~= "table" ) then
		return nil
	end
	return _G
end

-- Collect every persistent flag that gates a spell. The pool data knows the
-- exact set (`spells.gated_flag_list`), so the snapshot is bounded and
-- reproducible rather than "whatever the save happens to contain".
function M.read_unlocked_flags( api )
	local flags = {}
	for i = 1, #spells.gated_flag_list do
		local flag = spells.gated_flag_list[ i ]
		flags[ flag ] = call( api, "HasFlagPersistent", flag ) == true
	end
	return flags
end

-- Persistent non-unlock markers relevant to generation. Kept minimal and
-- explicit: anything not listed here is out of model and is reported as such.
M.PERSISTENT_MARKERS = {
	"biome_0_secret_unlocked",
	"TEMPLE_PEACE_WITH_GODS",
}

function M.read_persistent_flags( api )
	local flags = {}
	for i = 1, #M.PERSISTENT_MARKERS do
		local flag = M.PERSISTENT_MARKERS[ i ]
		flags[ flag ] = call( api, "HasFlagPersistent", flag ) == true
	end
	return flags
end

function M.read_calendar( api )
	local name = has_function(api,"GameGetDateAndTimeLocal") and "GameGetDateAndTimeLocal" or "GameGetDateAndTimeUTC"
	local year, month, day, hour, minute, second, jussi, mammi = call( api, name )
	if type(jussi) ~= "boolean" then jussi = nil end
	if type(mammi) ~= "boolean" then mammi = nil end
	if ( year == nil ) then
		return {}
	end
	return {
		year = year,
		month = month,
		day = day,
		hour = hour,
		minute = minute,
		second = second,
		jussi = jussi,
		mammi = mammi,
		source = name,
	}
end

-- Compose a snapshot id that is stable for identical conditions and distinct
-- between different ones, so reports can be grouped by condition without
-- embedding the whole flag map.
function M.snapshot_id( profile_fields )
	local profile = profile_lib.new( profile_fields )
	if ( profile == nil ) then
		return nil
	end
	return "live:" .. profile_lib.identity( profile )
end

-- build( options ) -> profile, diagnostics
--   options.api       : host table (defaults to the game globals)
--   options.id        : override the generated snapshot id
--   options.game_version : override the detected build string
--   options.calendar  : override the calendar fields
--
-- The returned profile is a frozen snapshot. `diagnostics` records exactly what
-- was read, what was unavailable, and which runtime facts could not be
-- obtained, so a report never has to guess.
function M.build( options )
	options = options or {}
	local api = options.api or M.game_api()
	local diagnostics = {
		missing_readers = {},
		optional_missing = {},
		readers_used = {},
		notes = {},
	}

	if ( type( api ) ~= "table" ) then
		return nil, {
			missing_readers = M.REQUIRED_READERS,
			optional_missing = M.OPTIONAL_READERS,
			readers_used = {},
			notes = { "no host api available (not running inside the game)" },
		}
	end

	for _, name in ipairs( M.REQUIRED_READERS ) do
		if ( has_function( api, name ) ) then
			diagnostics.readers_used[ #diagnostics.readers_used + 1 ] = name
		else
			diagnostics.missing_readers[ #diagnostics.missing_readers + 1 ] = name
		end
	end
	for _, name in ipairs( M.OPTIONAL_READERS ) do
		if ( has_function( api, name ) ) then
			diagnostics.readers_used[ #diagnostics.readers_used + 1 ] = name
		else
			diagnostics.optional_missing[ #diagnostics.optional_missing + 1 ] = name
		end
	end

	local unlocked
	if ( has_function( api, "HasFlagPersistent" ) ) then
		unlocked = M.read_unlocked_flags( api )
	else
		unlocked = {}
		diagnostics.notes[ #diagnostics.notes + 1 ] =
			"HasFlagPersistent unavailable: all gated spells treated as locked "
			.. "(this is a degraded, explicitly-flagged snapshot)"
	end

	local persistent = {}
	if ( has_function( api, "HasFlagPersistent" ) ) then
		persistent = M.read_persistent_flags( api )
	end

	local calendar = options.calendar or M.read_calendar( api )

	-- Runtime facts we can obtain without touching the save.
	local runtime = {
		api_version = call( api, "ModGetAPIVersion" ),
		is_daily_run = call( api, "GameIsDailyRun" ),
		is_fully_deterministic = call( api, "GameIsModeFullyDeterministic" ),
		is_beta_build = call( api, "GameIsBetaBuild" ),
		frame = call( api, "GameGetFrameNum" ),
	}
	diagnostics.runtime = runtime

	-- The world seed is not exposed by the documented Lua API, and the PRD
	-- requires the seed to be an explicit input; diagnostics says so plainly
	-- instead of silently scraping an internal value.
	diagnostics.notes[ #diagnostics.notes + 1 ] =
		"world seed is supplied by the caller; it is not read from game state"

	if ( runtime.is_daily_run == true ) then
		diagnostics.notes[ #diagnostics.notes + 1 ] =
			"daily run detected: daily runs unlock all cards, so this snapshot "
			.. "does not describe ordinary NG0 generation"
	end

	local fields = {
		id = options.id,
		game_version = options.game_version or spells.GAME_VERSION_HASH,
		unlocked_flags = unlocked,
		persistent_flags = persistent,
		calendar = calendar,
	}
	fields.id = fields.id or M.snapshot_id( fields ) or "live:unknown"

	local profile, errors = profile_lib.new( fields )
	if ( profile == nil ) then
		diagnostics.errors = errors
		return nil, diagnostics
	end
	diagnostics.profile_identity = profile_lib.identity( profile )
	return profile, diagnostics
end

return M
