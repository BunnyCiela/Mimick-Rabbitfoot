-- files/isf/core/cli_report.lua
--
-- Runnable validation entrypoint for a fixed seed (ISF-01: "repeatable
-- development validation entry").
--
-- This is plain Lua 5.1 with no game API dependency: it can be run by any Lua
-- 5.1 host, including a LuaJIT sandbox, to produce the same report the mod
-- computes. It performs no I/O itself; the host passes a `write` callback so the
-- module stays free of file/process access.
--
-- In-game usage (from a mod script):
--   local cli = dofile_once( "mods/interesting_seed_filter/files/isf/core/cli_report.lua" )
--   cli.run( 123, { write = function(s) print(s) end } )
--
-- Development usage:
--   python tools/foundation/run_report.py 123
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local evaluate = dofile_once( "mods/interesting_seed_filter/files/isf/core/evaluate.lua" )
if ( type( evaluate ) ~= "table" ) then
	error( "cli_report: files/isf/core/evaluate.lua did not return a table" )
end
local serialize = dofile_once( "mods/interesting_seed_filter/files/isf/core/serialize.lua" )
if ( type( serialize ) ~= "table" ) then
	error( "cli_report: files/isf/core/serialize.lua did not return a table" )
end
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "cli_report: files/isf/adapters/profile.lua did not return a table" )
end
local game_profile = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/game_profile.lua" )
if ( type( game_profile ) ~= "table" ) then
	error( "cli_report: files/isf/adapters/game_profile.lua did not return a table" )
end

local M = {}

M.USAGE = [[
ISF fixed-seed report (ISF-01, partial coverage)
  seed      : required, integer 0..4294967295
  options   : optional table
    format           : "text" (default) or "json"
    game_api         : host table to snapshot unlocks from; omit for "none unlocked"
    unlocked_flags   : explicit unlock map (overrides game_api)
    profile_id       : explicit snapshot id
    holy_mountains   : how many Holy Mountains to evaluate (default 3)
    write            : function(string) sink; defaults to print()
]]

local function default_write( s )
	if ( type( print ) == "function" ) then
		print( s )
	end
end

-- Parse argv-style string list into (seed, options). Kept tiny and
-- dependency-free so the same entrypoint works in-game and in tests.
function M.parse_args( argv )
	local seed = nil
	local options = { format = "text" }
	for i = 1, #argv do
		local a = argv[ i ]
		if ( a == "--json" ) then
			options.format = "json"
		elseif ( a == "--text" ) then
			options.format = "text"
		elseif ( a == "--all-unlocked" ) then
			options.all_unlocked = true
		elseif ( string.sub( a, 1, 7 ) == "--seed=" ) then
			seed = tonumber( string.sub( a, 8 ) )
		elseif ( string.sub( a, 1, 17 ) == "--holy-mountains=" ) then
			options.holy_mountains = tonumber( string.sub( a, 18 ) )
		elseif ( seed == nil ) then
			seed = tonumber( a )
		end
	end
	return seed, options
end

-- Build the profile for a run:
--   * options.unlocked_flags  -> explicit snapshot, no game reads
--   * options.all_unlocked    -> every gating flag set (for oracle comparison)
--   * options.game_api        -> read-only snapshot of that host
--   * otherwise               -> empty snapshot (nothing unlocked), stated
function M.build_profile( options, diagnostics_out )
	local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )

	if ( options.unlocked_flags ~= nil ) then
		return profile_lib.new( {
			id = options.profile_id or "explicit_flags",
			game_version = spells.GAME_VERSION_HASH,
			unlocked_flags = options.unlocked_flags,
			calendar = options.calendar or {},
		} )
	end

	if ( options.all_unlocked == true ) then
		local flags = {}
		for i = 1, #spells.gated_flag_list do
			flags[ spells.gated_flag_list[ i ] ] = true
		end
		return profile_lib.new( {
			id = options.profile_id or "all_spells_unlocked",
			game_version = spells.GAME_VERSION_HASH,
			unlocked_flags = flags,
			calendar = options.calendar or {},
		} )
	end

	if ( options.game_api ~= nil ) then
		local profile, diag = game_profile.build( {
			api = options.game_api,
			id = options.profile_id,
			calendar = options.calendar,
		} )
		if ( diagnostics_out ~= nil and type( diag ) == "table" ) then
			for k, v in pairs( diag ) do
				diagnostics_out[ k ] = v
			end
		end
		return profile, diag
	end

	local profile = profile_lib.new( {
		id = options.profile_id or "no_unlocks",
		game_version = spells.GAME_VERSION_HASH,
		unlocked_flags = {},
		calendar = options.calendar or {},
	} )
	if ( diagnostics_out ~= nil ) then
		diagnostics_out.notes = {
			"no game_api and no unlocked_flags supplied: modelling a fresh save "
				.. "with no spell unlocks (gated cards cannot spawn)",
		}
	end
	profile = profile
	if ( diagnostics_out ~= nil and profile ~= nil and diagnostics_out.profile_identity == nil ) then
		diagnostics_out.profile_identity = profile_lib.identity( profile )
	end
	return profile
end
-- Route a shared-PRNG selection into each provider that accepts one.
--
-- The CLI exposes one `rng_path` / `rng_factory` knob; providers take it as their
-- own option. Providers that consume the PRNG are listed here so a caller does
-- not have to know which one needs which field.
local PRNG_PROVIDERS = {
	"holy_mountains",
	"holy_mountain_wands",
	"wild_wands",
	"chests",
	"collectibles",
}

local function provider_options_for( options )
	if ( options.rng_path == nil and options.rng_factory == nil
		and options.rng_module == nil ) then
		return nil
	end
	local out = {}
	for i = 1, #PRNG_PROVIDERS do
		local name = PRNG_PROVIDERS[ i ]
		local base = {}
		if ( options.rng_module ~= nil ) then base.rng_module = options.rng_module end
		if ( options.rng_factory ~= nil ) then base.rng_factory = options.rng_factory end
		if ( options.rng_path ~= nil ) then base.rng_path = options.rng_path end
		-- `puzzles` names its PRNG option `prng`, and takes the module itself.
		if ( name == "puzzles" ) then
			base.prng = options.rng_module
		end
		out[ name ] = base
	end
	-- puzzles takes the module directly through `prng`.
	if ( options.rng_module ~= nil ) then
		out.puzzles = { prng = options.rng_module }
	end
	return out
end

-- run( seed, options ) -> report, rendered_text_or_json
--
-- options.assets: worldgen bundle (files/isf/core/assets.lua). When absent, the
-- region-scoped categories (R1/R2/R3/R5) are reported unsupported with a stated
-- reason, never as "this seed has no resources".
function M.run( seed, options )
	options = options or {}
	local write = options.write or default_write
	local diagnostics = {}
	local profile = M.build_profile( options, diagnostics )

	if ( profile == nil ) then
		write( "error: could not build a generation-condition snapshot\n" )
		return nil, nil
	end

	local report = evaluate.evaluate( seed, profile, {
		assets = options.assets,
		rng_module = options.rng_module,
		rng_factory = options.rng_factory,
		rng_path = options.rng_path,
		holy_mountains = options.holy_mountains,
		item_count = options.item_count,
		include_details = options.include_details,
		provider_options = provider_options_for( options ),
	} )

	-- Attach the snapshot diagnostics whenever anything was recorded. The table is
	-- map-shaped (notes/missing_readers/...), so `#` would be 0; use next().
	if ( next( diagnostics ) ~= nil ) then
		report.snapshot_diagnostics = diagnostics
	end
	local rendered
	if ( options.format == "json" ) then
		rendered = serialize.render_json( report )
	else
		rendered = serialize.render_text( report )
	end
	write( rendered )
	return report, rendered
end

return M
