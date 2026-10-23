-- files/isf/core/assets.lua
--
-- Read-only worldgen asset bundle, built once and shared by every resource
-- adapter (ISF-12).
--
-- Why this module exists
-- ----------------------
-- `files/isf/worldgen/discover.lua` needs a bundle of decoded images:
--   biome_map     decoded biome map
--   wang[key]     decoded wang tileset per biome
--   overlay       optional decoded coalmine overlay
--   scene_image   resolver function(biome, name) -> image|nil
--
-- Decoding PNGs is the single most expensive offline step, and every provider
-- that enumerates a region wants the same images. So the bundle is built once,
-- cached, and handed to discovery unchanged. This module never scans a map and
-- never scores anything.
--
-- Injection, not ambient I/O
-- ---------------------------
-- The runtime has no documented general-purpose file reader. Callers therefore
-- inject a reader:
--
--   assets.build( { read = function(relpath) -> bytes|nil end } )
--
-- `relpath` is always mod-namespaced ("mods/interesting_seed_filter/..."), the
-- same namespace `dofile_once` uses. In the game that reader is backed by the
-- mod's own content access; in a development harness it is backed by local
-- files. No provider depends on Python or any external process.
--
-- The resolver is cached by (biome, name) so a repeated scene lookup during one
-- discovery pass decodes each PNG at most once.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local png = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/png.lua" )
if ( type( png ) ~= "table" ) then
	error( "assets: files/isf/worldgen/png.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1

local MOD = "mods/interesting_seed_filter/"
local DATA = MOD .. "files/isf/worldgen/data/"

-- Biome keys with a wang tileset in this build. Snowy Depths is included: the
-- PRD gives it puzzles and shops, and discovery is independent of R1 scope.
M.WANG_BIOMES = {
	"coalmine",
	"coalmine_alt",
	"excavationsite",
	"fungicave",
	"snowcave",
}

-- Scenes that live in the shared `general/` directory rather than a biome
-- directory. Resolved by directory fallback too, but listing them makes the
-- intent explicit and avoids a wasted first lookup.
M.GENERAL_SCENES = {
	wand_altar = true,
	wand_altar_vault = true,
	potion_altar = true,
	potion_altar_vault = true,
	trailer_altar = true,
}

M.DATA_PREFIX = DATA

-- Path of a biome wang tileset.
function M.wang_path( biome_key )
	return DATA .. biome_key .. ".png"
end

-- Candidate paths for a pixel scene, in lookup order.
function M.scene_paths( biome_key, name )
	local paths = {}
	if ( M.GENERAL_SCENES[ name ] ) then
		paths[ #paths + 1 ] = DATA .. "pixel_scenes/general/" .. name .. ".png"
	end
	paths[ #paths + 1 ] = DATA .. "pixel_scenes/" .. biome_key .. "/" .. name .. ".png"
	paths[ #paths + 1 ] = DATA .. "pixel_scenes/general/" .. name .. ".png"
	return paths
end

-- The default reader: nothing. A host that has not injected a reader gets an
-- explicit failure instead of a silent empty asset set, because an empty asset
-- set would make every region look "unsupported" for the wrong reason.
local function no_reader( _relpath )
	return nil, "no asset reader injected"
end

local cache = nil

-- build( options ) -> assets, diagnostics
--
-- options.read      function(relpath) -> bytes|nil [, err]
-- options.biomes    optional subset of M.WANG_BIOMES
-- options.force     rebuild even if a cache exists
--
-- Returns a bundle plus diagnostics describing exactly what loaded and what did
-- not. A partial bundle is valid: discovery reports per-biome availability.
function M.build( options )
	options = options or {}
	local wanted = options.biomes or M.WANG_BIOMES
	local selection = table.concat( wanted, "," )
	-- Reader function equality cannot establish content equality. Reuse only an
	-- explicitly versioned immutable reader snapshot, with the same biome subset.
	if ( cache ~= nil and options.force ~= true and options.version ~= nil
		and options.version == cache.version and selection == cache.selection
		and options.read == cache.reader ) then
		return cache.assets, cache.diagnostics
	end

	local read = options.read
	if ( type( read ) ~= "function" ) then
		read = no_reader
	end

	local diagnostics = {
		reader = ( read ~= no_reader ) and "injected" or "none",
		loaded = {},
		missing = {},
		scene_cache_hits = 0,
		scene_cache_misses = 0,
	}
	-- Capture raw PNG bytes once, including lazily decoded scenes. A reader may
	-- change after this call; it cannot then mix old terrain with new scene data.
	local manifest = dofile_once(MOD.."files/isf/worldgen/data/asset_manifest.lua")
	local raw = {}
	local identity_parts = {}
	local function checksum(bytes)
		local a,b=1,0
		for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
		return string.format("%08x",b*65536+a)
	end
	for _,relpath in ipairs(manifest) do
		local path=MOD..relpath
		local ok,bytes=pcall(read,path)
		if ok and type(bytes)=="string" then raw[path]=bytes else raw[path]=false end
		identity_parts[#identity_parts+1]=relpath..":"..(raw[path] and checksum(raw[path]) or "missing")
	end
	local content_identity=table.concat(identity_parts,"|")

	local function decode( relpath )
		local bytes=raw[relpath]
		if ( type(bytes) ~= "string" ) then
			return nil
		end
		local decoded, err = png.decode( bytes )
		if ( decoded == nil ) then
			return nil, err
		end
		return decoded
	end

	local biome_map, map_err = decode( DATA .. "biome_map.png" )
	if ( biome_map == nil ) then
		diagnostics.missing[ #diagnostics.missing + 1 ] = {
			path = DATA .. "biome_map.png",
			reason = tostring( map_err or "unreadable" ),
		}
	end

	local wang = {}
	for i = 1, #wanted do
		local key = wanted[ i ]
		local image, err = decode( M.wang_path( key ) )
		if ( image ~= nil ) then
			wang[ key ] = image
			diagnostics.loaded[ #diagnostics.loaded + 1 ] = key
		else
			diagnostics.missing[ #diagnostics.missing + 1 ] = {
				path = M.wang_path( key ),
				reason = tostring( err or "unreadable" ),
			}
		end
	end

	local overlay = decode( DATA .. "coalmine_overlay.png" )

	-- Scene resolver, memoised per (biome, name). A miss is cached as false so the
	-- same absent scene is not re-read many times in one pass.
	local scene_cache = {}
	local function scene_image( biome_key, name )
		local key = tostring( biome_key ) .. "/" .. tostring( name )
		local hit = scene_cache[ key ]
		if ( hit ~= nil ) then
			diagnostics.scene_cache_hits = diagnostics.scene_cache_hits + 1
			if ( hit == false ) then
				return nil
			end
			return hit
		end
		diagnostics.scene_cache_misses = diagnostics.scene_cache_misses + 1
		local paths = M.scene_paths( biome_key, name )
		for j = 1, #paths do
			local image = decode( paths[ j ] )
			if ( image ~= nil ) then
				scene_cache[ key ] = image
				return image
			end
		end
		scene_cache[ key ] = false
		return nil
	end

	local assets = {
		biome_map = biome_map,
		wang = wang,
		coalmine_overlay = overlay,
		scene_image = scene_image,
		reader = read,
		version = options.version,
		content_identity = content_identity,
	}

	cache = {
		reader = read,
		version = options.version,
		selection = selection,
		assets = assets,
		diagnostics = diagnostics,
	}
	return assets, diagnostics
end

-- A compact description for a report: which biomes are discoverable right now.
function M.describe( assets )
	if ( type( assets ) ~= "table" ) then
		return { usable = false, reason = "no asset bundle" }
	end
	local biomes = {}
	for i = 1, #M.WANG_BIOMES do
		local key = M.WANG_BIOMES[ i ]
		biomes[ key ] = ( type( assets.wang ) == "table" and assets.wang[ key ] ~= nil )
	end
	return {
		usable = ( assets.biome_map ~= nil and type( assets.scene_image ) == "function" ),
		has_biome_map = assets.biome_map ~= nil,
		has_scene_resolver = type( assets.scene_image ) == "function",
		biomes = biomes,
		content_identity = assets.content_identity,
	}
end

-- A stable fingerprint of a bundle's identity, for cache keys.
--
-- Discovery results depend on the decoded images, so a cache keyed only on
-- (seed, profile, biome) would silently serve a result computed from a DIFFERENT
-- asset set -- e.g. after a game update changes a tileset. Callers must not have
-- to remember to call discovery.reset(); the key carries the bundle identity.
--
-- The key binds decoded bundle, image and resolver object identities plus an
-- explicit version/revision. Dimensions alone never identify content. Raw PNG
-- bytes are captured at build time; consumers treat decoded bundles as read-only.
-- Build a new bundle for changed content; manually injected mutable bundles must
-- change their revision whenever their content changes.
function M.fingerprint( assets )
	if ( type( assets ) ~= "table" ) then
		return "no-assets"
	end
	local function dims( image )
		if ( type( image ) ~= "table" ) then
			return "none"
		end
		return tostring( image.width ) .. "x" .. tostring( image.height )
	end

	-- Object identities bind the cache to the actual decoded bundle/resolver,
	-- not to dimensions shared by unrelated images. Bundles are read-only;
	-- changed content must be built as a new bundle (or use a new revision).
	local parts = { "v2", tostring(assets), tostring(assets.version),
		tostring(assets.revision), tostring(assets.scene_image),
		"map:" .. tostring(assets.biome_map) .. ":" .. dims( assets.biome_map ) }
	local keys = {}
	if ( type( assets.wang ) == "table" ) then
		for key in pairs( assets.wang ) do
			keys[ #keys + 1 ] = tostring( key )
		end
	end
	table.sort( keys )
	for i = 1, #keys do
		parts[ #parts + 1 ] = keys[ i ] .. "=" .. tostring(assets.wang[keys[i]]) .. ":" .. dims( assets.wang[ keys[ i ] ] )
	end
	parts[ #parts + 1 ] = "overlay:" .. tostring(assets.coalmine_overlay) .. ":" .. dims( assets.coalmine_overlay )
	return table.concat( parts, "|" )
end

function M.reset()
	cache = nil
end

-- True when a bundle is minimally usable for discovery.
function M.is_usable( assets )
	if ( type( assets ) ~= "table" ) then
		return false, "no asset bundle"
	end
	if ( assets.biome_map == nil ) then
		return false, "assets.biome_map is missing"
	end
	if ( type( assets.wang ) ~= "table" ) then
		return false, "assets.wang is missing"
	end
	if ( type( assets.scene_image ) ~= "function" ) then
		return false, "assets.scene_image is missing"
	end
	return true, nil
end

return M
