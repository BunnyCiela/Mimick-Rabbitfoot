-- files/isf/core/discovery.lua
--
-- One discovery per (seed, profile, region), reused by every resource adapter.
--
-- Why this module exists
-- ----------------------
-- `files/isf/worldgen/discover.lua` enumerates a region's spawn records. Four
-- different resource adapters want that same enumeration:
--
--   wild_wands   -> wand placements
--   chests       -> chest records
--   puzzles      -> puzzle entrance records
--   collectibles -> container records
--
-- Running the tile + scene + spawn pipeline once per provider would multiply the
-- cost by four and, worse, could let two providers disagree about the same seed
-- if they were configured differently. So discovery is performed once per
-- (seed, profile, region) and the result object is handed to every adapter.
--
-- What is cached, and what is not
-- -------------------------------
-- Cached: the neutral `discover.region()` result, keyed by the inputs that can
-- change it -- seed, profile identity, biome key, region index, NG+ count, and
-- the asset bundle identity. A cache hit returns the SAME table, so a caller must
-- treat it as read-only (adapters only ever read it).
--
-- Not cached: anything provider-specific. Scoring, provider report objects and
-- PRNG instances are rebuilt by each provider, so a provider cannot leak state
-- into another through this module.
--
-- Keep at most 32 regions (six complete candidates plus two recent regions).
-- Hits refresh recency. A long seed search must not retain every candidate.
-- Failure is cached too, deliberately: an unavailable region (missing tileset,
-- bad asset) must not be retried by four adapters, and must never be reported as
-- an empty region. `M.region()` returns `nil, reason` and callers mark the
-- capability unsupported/partial.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local discover = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/discover.lua" )
if ( type( discover ) ~= "table" ) then
	error( "discovery: files/isf/worldgen/discover.lua did not return a table" )
end

local assets_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/assets.lua" )
if ( type( assets_mod ) ~= "table" ) then
	error( "discovery: files/isf/core/assets.lua did not return a table" )
end

local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "discovery: files/isf/adapters/profile.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1

-- PRD region display names, in report order. Discovery's own order is the
-- generator's; reports must be stable, so this is the presentation order.
M.REGION_ORDER = {
	{ key = "coalmine", name = "Mines" },
	{ key = "coalmine_alt", name = "Collapsed Mines" },
	{ key = "excavationsite", name = "Coal Pits" },
	{ key = "fungicave", name = "Fungal Caverns" },
	{ key = "snowcave", name = "Snowy Depths" },
}

M.NAME_BY_KEY = {}
M.KEY_BY_NAME = {}
for i = 1, #M.REGION_ORDER do
	M.NAME_BY_KEY[ M.REGION_ORDER[ i ].key ] = M.REGION_ORDER[ i ].name
	M.KEY_BY_NAME[ M.REGION_ORDER[ i ].name ] = M.REGION_ORDER[ i ].key
end

-- Cache: key -> { result = region|nil, reason = string|nil, hits = n }
local cache = {}
M.CACHE_LIMIT = 32
local cache_size = 0
local stats = { requests = 0, hits = 0, misses = 0, failures = 0, evictions = 0 }

-- Stable cache key. Uses the profile's own identity digest, so two different
-- unlock snapshots can never share a discovery result.
-- Cache key.
--
-- It must include the ASSET BUNDLE IDENTITY, not just the seed: a region's tiles
-- come from the decoded images, so serving a cached result after the asset set
-- changed would report tiles that belong to a different build. Callers therefore
-- do not have to remember to call reset() when assets change.
--
-- Everything that can change a region's output is in the key:
--   seed | profile identity | biome | region index | NG+ | asset fingerprint
--
-- The profile identity digest covers the unlock/persistent/calendar snapshot, so
-- two partial capability sets with different flags cannot collide.
local function cache_key( seed, profile, biome_key, opts, assets )
	local identity = "invalid"
	if ( type( profile ) == "table" ) then
		local ok, value = pcall( profile_lib.identity, profile )
		identity = ok and value or "identity-error"
	end
	return table.concat( {
		"r2",
		tostring( seed ),
		identity,
		tostring( biome_key ),
		tostring( opts.region_index or 1 ),
		tostring( opts.ng_plus or 0 ),
		assets_mod.fingerprint( assets ),
	}, "|" )
end

function M.reset()
	cache = {}
	cache_size = 0
	stats = { requests = 0, hits = 0, misses = 0, failures = 0, evictions = 0 }
end

function M.stats()
	return {
		requests = stats.requests,
		hits = stats.hits,
		misses = stats.misses,
		failures = stats.failures,
		evictions = stats.evictions,
		size = cache_size,
		limit = M.CACHE_LIMIT,
	}
end

-- region( seed, profile, biome, assets, opts ) -> result | nil, reason
--
-- `biome` accepts a generator key or a PRD display name. The result is the
-- neutral discovery table (see discover.region) and MUST be treated as
-- read-only; every adapter in this build only reads it.
function M.region( seed, profile, biome, assets, opts )
	opts = opts or {}
	stats.requests = stats.requests + 1

	local biome_key = M.KEY_BY_NAME[ biome ] or biome
	if ( M.NAME_BY_KEY[ biome_key ] == nil ) then
		return nil, "unknown region " .. tostring( biome )
	end

	local usable, why = assets_mod.is_usable( assets )
	if ( not usable ) then
		stats.failures = stats.failures + 1
		return nil, "assets unusable: " .. tostring( why )
	end

	local key = cache_key( seed, profile, biome_key, opts, assets )
	local entry = cache[ key ]
	if ( entry ~= nil ) then
		stats.hits = stats.hits + 1
		entry.hits = entry.hits + 1
		entry.last_used = stats.requests
		if ( entry.result == nil ) then
			return nil, entry.reason
		end
		return entry.result
	end

	stats.misses = stats.misses + 1
	local result, reason = discover.region( seed, profile, biome_key, assets, {
		ng_plus = opts.ng_plus or 0,
		region_index = opts.region_index,
	} )

	-- A failure is cached as a failure so four adapters do not retry it and so it
	-- can never later look like an empty region.
	if ( cache_size >= M.CACHE_LIMIT ) then
		local oldest_key, oldest_time
		for candidate, saved in pairs( cache ) do
			if ( oldest_time == nil or saved.last_used < oldest_time ) then
				oldest_key, oldest_time = candidate, saved.last_used
			end
		end
		cache[ oldest_key ] = nil
		cache_size = cache_size - 1
		stats.evictions = stats.evictions + 1
	end
	cache[ key ] = { result = result, reason = reason, hits = 0, last_used = stats.requests }
	cache_size = cache_size + 1
	if ( result == nil ) then
		stats.failures = stats.failures + 1
		return nil, reason
	end
	return result
end

-- all( seed, profile, assets, opts ) -> results_by_key, errors
--
-- Every region is attempted. A region that cannot be discovered appears in
-- `errors` and is ABSENT from the results -- never an empty region.
function M.all( seed, profile, assets, opts )
	opts = opts or {}
	local results = {}
	local errors = {}
	for i = 1, #M.REGION_ORDER do
		local item = M.REGION_ORDER[ i ]
		local result, reason = M.region( seed, profile, item.key, assets, opts )
		if ( result == nil ) then
			errors[ #errors + 1 ] = {
				biome_key = item.key,
				biome_name = item.name,
				reason = reason,
			}
		else
			results[ item.key ] = result
		end
	end
	return results, errors
end

-- Index a region's records by spawn kind, so adapters do not each re-walk the
-- whole list with their own predicate. Read-only view; the arrays alias the
-- region's own record tables.
--
-- The scan emits `spawn_kind` (altar_wand, chest, heart, potion_altar,
-- scene_marker, shop_item, wand_altar, gate_blocked, scene_wand). Older/newer
-- producers may use `source_kind`, so both are accepted, and records with
-- neither land under "unknown" rather than being dropped.
function M.index_records( region )
	local index = {}
	if ( type( region ) ~= "table" or type( region.records ) ~= "table" ) then
		return index
	end
	for i = 1, #region.records do
		local rec = region.records[ i ]
		local kind = "unknown"
		if ( type( rec ) == "table" ) then
			kind = rec.spawn_kind or rec.source_kind or rec.kind or "unknown"
		end
		index[ kind ] = index[ kind ] or {}
		local bucket = index[ kind ]
		bucket[ #bucket + 1 ] = rec
	end
	return index
end

-- Records of one spawn kind in a region (empty array when none).
function M.records_of_kind( region, spawn_kind )
	if ( type( region ) ~= "table" or type( region.records ) ~= "table" ) then
		return {}
	end
	local out = {}
	for i = 1, #region.records do
		local rec = region.records[ i ]
		if ( type( rec ) == "table" and rec.spawn_kind == spawn_kind ) then
			out[ #out + 1 ] = rec
		end
	end
	return out
end

-- Every region key this build can attempt, in report order.
function M.region_keys()
	local keys = {}
	for i = 1, #M.REGION_ORDER do
		keys[ i ] = M.REGION_ORDER[ i ].key
	end
	return keys
end

return M
