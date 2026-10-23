-- files/isf/worldgen/mines_map.lua
--
-- DEPRECATED SHIM. Mines terrain generation now lives in
-- files/isf/worldgen/region_map.lua, which implements all four Mines-region
-- biomes (Mines, Collapsed Mines, Coal Pits, Fungal Caverns) with the correct
-- upstream staging order.
--
-- WHY THIS FILE WAS REWRITTEN
--   The earlier revision implemented the Mines pipeline here and ran the corridor
--   search on the RAW Wang buffer -- before blockOutRooms and the coalmine
--   overlay hack. Upstream stages those first: generateRawTileBuffer applies
--   blockOutRooms / applyMainBiomeHack / applyCoalmineHack, and only then does
--   generateBiomeTiles call findMinPath on that staged buffer. So the reroll
--   counts and the accepted buffer could differ from the game.
--   The oracle fixture used at the time repeated the same mistake, which is why
--   the tests passed: a shared blind spot, not agreement with the game. That is
--   exactly the failure mode oracle comparison is supposed to catch, and it did
--   only once a second, independently written oracle existed.
--
-- The implementation is retained only so existing callers keep working; it
-- forwards to region_map.lua. New code should require region_map.lua directly.
--
-- Standalone Lua 5.1: no FFI, no external process.

local M = {}

local region_map = nil

function M.init( deps )
	region_map = deps.region_map
	if ( region_map == nil ) then
		region_map = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/region_map.lua" )
	end
	region_map.init( {
		png = deps.png,
		stbhw = deps.stbhw,
		pathfind = deps.pathfind,
		prng_new = deps.prng_new,
	} )
	return M
end

-- Delegated constants (kept for callers that read them off this module).
M.CHUNK_SIZE = 512
M.TILE_SIZE = 10
M.MAX_PATHFINDING_ATTEMPTS = 99
M.BIOME_PATH_HEIGHT_LIMIT_CHUNKS = 4

M.BIOMES = {
	coalmine = { color = 0xffd57917, name = "Mines", wang = "coalmine" },
	coalmine_alt = { color = 0xffd56517, name = "Collapsed Mines", wang = "coalmine_alt" },
}

M.coverage = {
	status = "superseded",
	note = "see files/isf/worldgen/region_map.lua",
}

function M.calculate_map_dimensions( minx, miny, maxx, maxy )
	return region_map.calculate_map_dimensions( minx, miny, maxx, maxy )
end

function M.find_biome_regions( biome_img, target_color )
	return region_map.find_biome_regions( biome_img, target_color )
end

function M.seed_wang_prng( rng, world_seed, ng_plus, map_w, extra_rerolls )
	return region_map.seed_wang_prng( rng, world_seed, ng_plus, map_w, extra_rerolls )
end

function M.block_out_rooms( buf, width, height )
	return region_map.block_out_rooms( buf, width, height )
end

function M.apply_masking( buf, width, bbox, valid_chunks )
	return region_map.apply_masking( buf, width, bbox, valid_chunks )
end

function M.apply_coalmine_overlay( buf, width, height, overlay_img, undo )
	return region_map.apply_coalmine_overlay( buf, width, height, overlay_img, undo )
end

function M.clear_path( buf, width, height, path )
	return region_map.clear_path( buf, width, height, path )
end

function M.apply_coffee_hack( buf, width, height, world_seed )
	return region_map.apply_coffee_hack( buf, width, height, world_seed )
end

function M.to_buf( rgb ) return region_map.to_buf( rgb ) end
function M.to_rgb( buf, n ) return region_map.to_rgb( buf, n ) end

-- Mines-only entry point, preserved for existing callers.
-- Accepts the legacy asset shape (`assets.overlay`) and maps it onto
-- region_map's `assets.coalmine_overlay`.
function M.build_mines_layer( assets, world_seed, ng_plus )
	if ( assets.wang == nil or assets.wang.coalmine == nil ) then
		return nil, "missing wang tileset for coalmine"
	end
	local mapped = {
		biome_map = assets.biome_map,
		wang = assets.wang,
		coalmine_overlay = assets.coalmine_overlay or assets.overlay,
		tilesets = assets.tilesets,
	}
	return region_map.build_layer( mapped, "coalmine", world_seed, ng_plus )
end

return M
