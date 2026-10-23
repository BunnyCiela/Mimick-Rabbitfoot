-- files/isf/worldgen/discover.lua
--
-- NEUTRAL region discovery: seed + profile + assets -> placement records.
--
-- This module exists so a consumer that only needs "what did the generator place
-- in this region" (puzzles, chests, collectibles, shops) does not have to go
-- through the wild-wand provider, whose biome set and scoring scope are R1's.
-- It reports every record `files/isf/worldgen/scan.lua` produces, unchanged, and
-- it scores NOTHING. In particular:
--
--   * Snowy Depths (snowcave) is discoverable here. PRD section 2 gives Snowy
--     Depths puzzles and shops but no wild-wand body, no in-wand spell share, no
--     chest score and no R5 item score. This module never turns a record into
--     points, so it cannot leak those.
--   * The four Mines-region biomes keep exactly the behaviour they had: the same
--     tile pipeline, the same scan, the same record set.
--
-- Two entry points:
--
--   discover.region( seed, profile, biome, assets[, opts] )   -- one key
--   discover.all( seed, profile, assets[, opts] )             -- every biome
--
-- `biome` accepts the generator key ("coalmine", "snowcave", ...) or the PRD
-- display name ("Mines", "Snowy Depths", ...). Unknown names return nil + reason;
-- they are never silently treated as an empty region.
--
-- Backwards compatibility: `files/isf/providers/wild_wands.lua` keeps its own
-- `discover_biome` entry point with the same arguments and return shape, and now
-- delegates the pipeline to this module.
--
-- Coverage honesty: `region()` reports whether the REAL pipeline ran. It never
-- reports a region as enumerated when no assets were supplied.
--
-- Standalone Lua 5.1 / LuaJIT: no FFI, no external process. The only file access
-- is through the injected `assets.scene_image` resolver, i.e. through the game's
-- own content API or a test-provided fixture loader.
--
-- Native-game parity is unverified for every claim here.

local M = {}
local profile_lib = dofile_once("mods/interesting_seed_filter/files/isf/adapters/profile.lua")

M.SCHEMA_VERSION = 1

-- Generator keys this build can run the full tile + scene + spawn pipeline for.
-- Deliberately a closed set: an unlisted biome is `unsupported`, not empty.
M.SUPPORTED_BIOMES = {
	coalmine = true,
	coalmine_alt = true,
	excavationsite = true,
	fungicave = true,
	snowcave = true,
}

-- Generator key -> PRD display name. Kept here (not in a provider) so the
-- neutral module has no dependency on R1 scoring tables.
M.BIOME_NAMES = {
	coalmine = "Mines",
	coalmine_alt = "Collapsed Mines",
	excavationsite = "Coal Pits",
	fungicave = "Fungal Caverns",
	snowcave = "Snowy Depths",
}

-- Display name -> generator key (accepts the lower-case forms too).
M.KEY_BY_NAME = {
	Mines = "coalmine",
	["mines"] = "coalmine",
	["Collapsed Mines"] = "coalmine_alt",
	["collapsed mines"] = "coalmine_alt",
	["Coal Pits"] = "excavationsite",
	["coal pits"] = "excavationsite",
	["Fungal Caverns"] = "fungicave",
	["fungal caverns"] = "fungicave",
	["Snowy Depths"] = "snowcave",
	["snowy depths"] = "snowcave",
}

-- Resolve a biome key or display name to the generator key, or nil.
function M.resolve_biome( value )
	if ( type( value ) ~= "string" or value == "" ) then
		return nil
	end
	if ( M.SUPPORTED_BIOMES[ value ] ) then
		return value
	end
	return M.KEY_BY_NAME[ value ]
end

-- Injected module dependencies. Kept as explicit state (rather than captured
-- locals) so `configure` can rebuild the stack when the asset set changes.
local deps = nil

-- deps:
--   prng_new(seed)            -- files/isf/random/prng.lua .new
--   png, stbhw, pathfind      -- worldgen components
--   region_map, scan          -- loaded worldgen modules
--   biome_data                -- generated biome_data.lua
function M.init( d )
	if ( type( d ) ~= "table" ) then
		error( "discover.init expects a dependency table" )
	end
	deps = d
	return M
end

local function ensure_deps( assets )
	if ( deps ~= nil ) then return deps end
	if ( type( assets ) ~= "table" ) then
		return nil, "no worldgen assets supplied"
	end
	local ok, err = pcall( function()
		local prng = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
		local png = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/png.lua" )
		local stbhw = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/stbhw.lua" )
		local pathfind = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/pathfind.lua" )
		local region_map = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/region_map.lua" )
		local scan = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/scan.lua" )
		local biome_data = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/data/biome_data.lua" )

		region_map.init( {
			png = png, stbhw = stbhw, pathfind = pathfind, prng_new = prng.new,
		} )

		-- 24-bit RGB keys, derived from the generated biome table so there is
		-- one source of truth.
		local by_color = {}
		for key, cfg in pairs( biome_data.biomes ) do
			by_color[ cfg.color ] = key
		end
		local edge_noise=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/edge_noise.lua")
		for color,row in pairs(edge_noise.biomes)do by_color[color]=row.name end

		scan.init( {
			prng_new = prng.new,
			biome_data = biome_data,
			biome_map = assets.biome_map,
			biome_name_by_color = by_color,
			edge_noise = edge_noise,
			scene_image = assets.scene_image,
		} )

		deps = {
			prng = prng,
			prng_new = prng.new,
			png = png, stbhw = stbhw, pathfind = pathfind,
			region_map = region_map, scan = scan,
			biome_data = biome_data,
		}
	end )
	if ( not ok ) then
		return nil, "worldgen discovery stack failed to load: " .. tostring( err )
	end
	return deps
end

-- Drop the injected stack. Tests use this between asset sets; production code
-- only needs it if it wants a fully fresh load.
function M.reset()
	deps = nil
end

-- Cache of built tile layers, keyed on (assets identity, biome, seed, ng, region).
-- The stack itself is rebuilt whenever the asset table identity OR the scene
-- resolver changes, because both feed the scan.
local stack_assets = nil
local stack_stack = nil
local stack_fingerprint = nil

local function load_stack( assets )
	if ( type( assets ) ~= "table" ) then
		return nil, "no worldgen assets supplied"
	end
	if ( assets.biome_map == nil ) then
		return nil, "assets.biome_map is required for discovery"
	end
	if ( type( assets.wang ) ~= "table" ) then
		return nil, "assets.wang (per-biome tilesets) is required for discovery"
	end
	if ( type( assets.scene_image ) ~= "function" ) then
		return nil, "assets.scene_image(resolver function) is required for discovery"
	end
	local fingerprint = dofile_once("mods/interesting_seed_filter/files/isf/core/assets.lua").fingerprint(assets)
	if ( stack_stack ~= nil and stack_assets == assets and deps ~= nil and stack_fingerprint == fingerprint ) then
		return stack_stack
	end

	local d, reason = ensure_deps( assets )
	if ( d == nil ) then return nil, reason end

	-- scan.init holds module-level state (the biome map and scene resolver), so
	-- it must be re-pointed at THIS asset set even when the modules themselves
	-- were already loaded for a previous one.
	d.scan.init( {
		prng_new = d.prng_new,
		biome_data = d.biome_data,
		biome_map = assets.biome_map,
		biome_name_by_color = ( function()
			local by_color = {}
			for key, cfg in pairs( d.biome_data.biomes ) do
				by_color[ cfg.color ] = key
			end
			local edge=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/edge_noise.lua")
			for color,row in pairs(edge.biomes)do by_color[color]=row.name end
			return by_color
		end )(),
		edge_noise=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/edge_noise.lua"),
		scene_image = assets.scene_image,
	} )

	stack_assets = assets
	stack_fingerprint = fingerprint
	stack_stack = {
		deps = d,
		assets = {
			biome_map = assets.biome_map,
			wang = assets.wang,
			coalmine_overlay = assets.coalmine_overlay or assets.overlay,
			-- Tilesets are immutable across seeds, so build them once per stack.
			tilesets = assets.tilesets or {},
			scene_image = assets.scene_image,
		},
	}
	return stack_stack
end
M.load_stack = load_stack

-- ---------------------------------------------------------------- io
-- Which wang tilesets must be present for a biome to be discoverable.
local function required_wang( assets, biome_key )
	if ( type( assets ) ~= "table" or type( assets.wang ) ~= "table" ) then
		return false
	end
	return assets.wang[ biome_key ] ~= nil
end

-- discover.region( seed, profile, biome, assets[, opts] )
--
-- opts:
--   ng_plus        NG+ count (default 0; only 0 is supported)
--   region_index   which region of a multi-region biome (default 1)
--   with_layer     when true, also return the tile layer (tooling only)
--   generation_context  frozen conditions a vanilla dispatch reads:
--                  { calendar = { month = , day = },
--                    persistent_flags = { FLAG = true },
--                    is_flag_set = function(flag) -> bool }
--
--                  Normally DERIVED from the `profile` snapshot (see
--                  generation_context_of). Passing it explicitly lets a caller
--                  withhold it on purpose, to observe the unresolved paths.
--                  **It is never read from the live game clock or save.**
--
-- Returns a table:
--   biome_key, biome_name, records, scenes_placed, wand_altars, trap_wands,
--   wild_wands, potential, spawn_pixel_count, record_count, potential_count,
--   scene_marker_count, region_index, region_count, extra_rerolls, coverage,
--   scoped (PRD scope table), scored (boolean), context_supplied, note
-- or nil + reason. A nil return is ALWAYS an unavailability, never "empty region".

-- Build the generation context from a frozen profile. Never touches the game.
-- `calendar` is copied field-by-field for the two fields the vanilla bodies
-- read (month, day); `persistent_flags` is only accepted as a plain table,
-- because a frozen proxy's `pairs` is not a flag map (see the profile contract).
function M.generation_context_of( profile )
	if ( type( profile ) ~= "table" ) then return nil end
	local ctx = {}
	local cal = profile.calendar
	if ( type( cal ) == "table" ) then
		if ( type( cal.month ) == "number" and type( cal.day ) == "number" ) then
			ctx.calendar = { month = cal.month, day = cal.day }
		end
	end
	local flags = profile.persistent_flags
	if ( type( flags ) == "table" ) then
		flags = profile_lib.flags(flags)
		local copy = {}
		local ok = pcall( function()
			for k, v in pairs( flags ) do
				if ( type( k ) == "string" and type( v ) == "boolean" ) then
					copy[ k ] = v
				end
			end
		end )
		if ( ok ) then ctx.persistent_flags = copy end
	end
	return ctx
end

function M.region( seed, profile, biome, assets, opts )
	opts = opts or {}
	local biome_key = M.resolve_biome( biome )
	if ( biome_key == nil ) then
		return nil, "unknown biome " .. tostring( biome )
	end
	if ( not M.SUPPORTED_BIOMES[ biome_key ] ) then
		return nil, "discovery not implemented for biome " .. biome_key
	end
	if ( required_wang( assets, biome_key ) == false ) then
		return nil, "assets.wang." .. biome_key .. " is required for discovery"
	end

	local stack, reason = load_stack( assets )
	if ( stack == nil ) then
		return nil, reason
	end

	local ng_plus = opts.ng_plus or 0
	local d = stack.deps

	local layer, err = d.region_map.build_layer( stack.assets, biome_key,
		seed, ng_plus, opts.region_index, {
			resource_only=opts.resource_only~=false and not opts.with_layer,
			marker_index=d.scan.spawn_color_index(biome_key),
		} )
	if ( layer == nil ) then
		return nil, string.format( "%s tile pipeline failed: %s", biome_key, tostring( err ) )
	end

	-- Explicit context wins; otherwise derive it from the profile snapshot.
	local ctx = opts.generation_context or M.generation_context_of( profile )

	local result, scan_err = d.scan.scan_layer( layer, biome_key, seed, ng_plus, ctx )
	if ( result == nil ) then
		return nil, tostring( scan_err )
	end

	local cfg = d.biome_data.biomes[ biome_key ]
	local out = {
		biome_key = biome_key,
		biome_name = M.BIOME_NAMES[ biome_key ] or biome_key,
		records = result.records,
		scenes_placed = result.scenes_placed,
		scene_markers = result.scene_markers,
		wand_altars = result.wand_altars,
		trap_wands = result.trap_wands,
		wild_wands = result.wild_wands,
		potential = result.potential,
		spawn_pixels = result.spawn_pixels,
		spawn_pixel_count = result.spawn_pixel_count,
		record_count = #result.records,
		potential_count = #result.potential,
		scene_marker_count = #result.scene_markers,
		scene_placement_count = #result.scenes_placed,
		region_index = layer.region_index,
		region_count = layer.region_count,
		extra_rerolls = layer.extra_rerolls,
		-- PRD section 2 scope for this region. `scored` = any scope at all.
		scored = cfg ~= nil and cfg.scored == true,
		scoped = cfg ~= nil and cfg.scope or nil,
		-- Which frozen conditions were available, so a consumer can tell an
		-- unresolved record from a wrong one.
		context_supplied = {
			calendar = ctx ~= nil and ctx.calendar ~= nil,
			persistent_flags = ctx ~= nil and ctx.persistent_flags ~= nil,
		},
		coverage = "complete",
		note = "tile pipeline + spawn scan + nested pixel scenes complete for "
			.. biome_key .. " at NG" .. tostring( ng_plus ),
	}
	if ( opts.with_layer ) then
		out.layer = layer
	end
	return out
end

-- discover.all( seed, profile, assets[, opts] ) -> { [key] = region result }, errors
--
-- Every supported biome is attempted. A biome whose assets are missing appears
-- in `errors` with its reason and is ABSENT from the results -- it is never
-- reported as an empty region.
function M.all( seed, profile, assets, opts )
	opts = opts or {}
	local results = {}
	local errors = {}
	local order = { "coalmine", "coalmine_alt", "excavationsite", "fungicave", "snowcave" }
	for i = 1, #order do
		local key = order[ i ]
		local result, reason = M.region( seed, profile, key, assets, {
			ng_plus = opts.ng_plus,
			region_index = opts.region_index,
			with_layer = opts.with_layer,
			resource_only = opts.resource_only,
			generation_context = opts.generation_context,
		} )
		if ( result == nil ) then
			errors[ #errors + 1 ] = { biome_key = key, reason = reason }
		else
			results[ key ] = result
		end
	end
	return results, errors
end

return M
