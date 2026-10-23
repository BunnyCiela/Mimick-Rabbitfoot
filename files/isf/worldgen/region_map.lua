-- files/isf/worldgen/region_map.lua
--
-- Per-biome terrain pipeline for the Mines-region areas the PRD scores:
--   Mines (coalmine), Collapsed Mines (coalmine_alt), Coal Pits
--   (excavationsite), Fungal Caverns (fungicave).
--
-- Substantial reuse: noita-telescope
--   js/tile_generator.js, js/pathfinding.js, js/biome_hacks.js,
--   js/pixel_scene_generation.js (blockOutRooms / applyMasking)
--   MIT License, Copyright (c) 2026 Lymm
--
-- Stage order is load-bearing and mirrors generateRawTileBuffer /
-- generateBiomeTiles exactly:
--   1. Wang generation                       (all biomes)
--   2. blockOutRooms                         (Mines template, or excavationsite)
--   3. applyMainBiomeHack                    (non-Mines biomes only)
--   4. applyCoalmineHack                     (Mines template only)
--   5. findMinPath                           (BFS corridor)
--   6. rooms restored to air
--   7. coalmine overlay undone               (Mines template only)
--   8. clearPath
--   9. coffee hack
--  10. chunk masking
--
-- Differences between biomes are DATA, not branches where possible:
--   * which wang tileset to use
--   * whether the Mines template applies (fixed path start, no main-biome hack,
--     coalmine overlay hack + undo)
--   * whether rooms are blocked out (Mines template OR the excavationsite tileset)
--   * the pathfinding retry loop runs per region
--
-- Standalone Lua 5.1: no FFI, no external process.

local M = {}

local CHUNK = 512
local TILE = 10
local WORLD_CHUNK_CENTER_X = 35

M.CHUNK_SIZE = CHUNK
M.TILE_SIZE = TILE
M.WORLD_CHUNK_CENTER_X = WORLD_CHUNK_CENTER_X

M.MAX_PATHFINDING_ATTEMPTS = 99
M.BIOME_PATH_HEIGHT_LIMIT_CHUNKS = 4

-- Per-biome terrain configuration.
--
-- `scored` says whether PRD section 2 grants this region ANY scoring scope.
-- Snowy Depths is discoverable but NOT scored: it earns puzzle and shop points
-- through Other providers, never a wild-wand body, in-wand spell share, chest or
-- R5 item. Keeping the flag here lets a consumer that only has a biome key ask
-- "may this region score X" instead of re-deriving PRD section 2.
M.BIOMES = {
	coalmine = {
		key = "coalmine", name = "Mines", color = 0xd57917,
		wang = "coalmine.png",
		uses_mines_template = true,
		blocks_rooms = true,
		scored = true,
		body_bonus = true, wand_spells = true,
	},
	coalmine_alt = {
		key = "coalmine_alt", name = "Collapsed Mines", color = 0xd56517,
		wang = "coalmine_alt.png",
		uses_mines_template = false,
		blocks_rooms = false,
		scored = true,
		body_bonus = true, wand_spells = true,
	},
	excavationsite = {
		key = "excavationsite", name = "Coal Pits", color = 0x124445,
		wang = "excavationsite.png",
		uses_mines_template = false,
		-- Upstream blocks rooms for the excavationsite TILESET specifically.
		blocks_rooms = true,
		scored = true,
		body_bonus = true, wand_spells = true,
	},
	fungicave = {
		key = "fungicave", name = "Fungal Caverns", color = 0xe861f0,
		wang = "fungicave.png",
		uses_mines_template = false,
		blocks_rooms = false,
		-- PRD R1: Fungal Caverns contributes in-wand spells only.
		scored = true,
		body_bonus = false, wand_spells = true,
	},
	-- Snowy Depths. Tile pipeline settings are the same generic path as
	-- Collapsed Mines / Fungal Caverns: no Mines template, no room blocking (its
	-- only blocked-colour usage would be the shared list, and upstream's
	-- `shouldBlockOutRooms` is keyed on the coalmine/excavationsite templates).
	-- Discoverable, NOT R1-scored.
	snowcave = {
		key = "snowcave", name = "Snowy Depths", color = 0x1775d5,
		wang = "snowcave.png",
		uses_mines_template = false,
		blocks_rooms = false,
		scored = false,
		body_bonus = false, wand_spells = false,
	},
}

-- Biome display name -> key, for provider/report plumbing.
M.NAME_TO_KEY = {
	Mines = "coalmine",
	["Collapsed Mines"] = "coalmine_alt",
	["Coal Pits"] = "excavationsite",
	["Fungal Caverns"] = "fungicave",
	["Snowy Depths"] = "snowcave",
}

M.coverage = {
	status = "partial",
	implemented = {
		"biome_region_detection",
		"wang_seeding",
		"herringbone_tile_generation",
		"tile_index_grid",
		"rendered_tile_buffer",
		"block_out_rooms",
		"main_biome_hack",
		"coalmine_overlay_hack",
		"pathfinding",
		"pathfinding_retry_loop",
		"blocked_room_restore",
		"overlay_undo",
		"path_clear",
		"coffee_hack",
		"chunk_masking",
	},
	not_implemented = {
		-- Separate concerns, implemented (or not) in scan.lua / providers.
		"pixel_scene_placement",
		"spawn_function_scan",
		"wand_chest_shop_objects",
	},
}

local png, stbhw, pathfind, new_prng
function M.init( deps )
	png = deps.png
	stbhw = deps.stbhw
	pathfind = deps.pathfind
	new_prng = deps.prng_new
	return M
end

-- Mirrors tile_generator.js:calculateMapDimensions.
local function calculate_map_dimensions( minx, miny, maxx, maxy )
	local function td( n ) return math.floor( n / 10 ) end
	return {
		width = td( ( maxx + 1 ) * CHUNK ) - td( minx * CHUNK ),
		height = td( ( maxy + 1 ) * CHUNK ) - td( miny * CHUNK ),
	}
end
M.calculate_map_dimensions = calculate_map_dimensions

-- ---------------------------------------------------------------------------
-- Region detection
-- ---------------------------------------------------------------------------

-- Connected chunk regions of one biome colour, row-major flood-fill order.
function M.find_biome_regions( biome_img, target_color )
	local tr = math.floor( target_color / 65536 ) % 256
	local tg = math.floor( target_color / 256 ) % 256
	local tb = target_color % 256

	local W, H = biome_img.width, biome_img.height
	local pixels = biome_img.rgb
	local visited = {}
	local regions = {}

	local function at( x, y )
		local i = ( y * W + x ) * 3 + 1
		local r, g, b = pixels:byte( i, i + 2 )
		return r == tr and g == tg and b == tb
	end

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local vi = y * W + x
			if ( not visited[ vi ] and at( x, y ) ) then
				local queue = { x, y }
				local head = 1
				visited[ vi ] = true
				local minx, maxx, miny, maxy = x, x, y, y
				local cells = {}
				local count = 0
				while ( head <= #queue ) do
					local cx, cy = queue[ head ], queue[ head + 1 ]
					head = head + 2
					count = count + 1
					cells[ #cells + 1 ] = { cx, cy }
					if ( cx < minx ) then minx = cx end
					if ( cx > maxx ) then maxx = cx end
					if ( cy < miny ) then miny = cy end
					if ( cy > maxy ) then maxy = cy end
					local nx, ny
					nx, ny = cx + 1, cy
					if ( nx < W and not visited[ ny * W + nx ] and at( nx, ny ) ) then
						visited[ ny * W + nx ] = true
						queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
					end
					nx, ny = cx - 1, cy
					if ( nx >= 0 and not visited[ ny * W + nx ] and at( nx, ny ) ) then
						visited[ ny * W + nx ] = true
						queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
					end
					nx, ny = cx, cy + 1
					if ( ny < H and not visited[ ny * W + nx ] and at( nx, ny ) ) then
						visited[ ny * W + nx ] = true
						queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
					end
					nx, ny = cx, cy - 1
					if ( ny >= 0 and not visited[ ny * W + nx ] and at( nx, ny ) ) then
						visited[ ny * W + nx ] = true
						queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
					end
				end
				regions[ #regions + 1 ] = {
					minx = minx, miny = miny, maxx = maxx, maxy = maxy,
					chunks = count, cells = cells,
				}
			end
		end
	end

	return regions
end

-- ---------------------------------------------------------------------------
-- Wang seeding
-- ---------------------------------------------------------------------------

function M.seed_wang_prng( rng, world_seed, ng_plus, map_w, extra_rerolls )
	rng:SetRandomFromWorldSeed( world_seed + ( ng_plus or 0 ) )
	rng:Next()

	local effective_w = math.min( map_w, 1024 )
	local iters = effective_w + ( world_seed + ( ng_plus or 0 ) )
		- 11 * math.floor( effective_w / 11 )
		- 12 * math.floor( ( world_seed + ( ng_plus or 0 ) ) / 12 )
	for _ = 1, iters do rng:Next() end
	for _ = 1, ( extra_rerolls or 0 ) do rng:Next() end

	rng.Seed = rng:NextU()
	rng:Next()
end

local function generate_raw_tile_buffer( tileset, world_seed, ng_plus, map_w, map_h, extra_rerolls, options )
	local out_h = map_h + 4
	local rng = new_prng( 0 )
	M.seed_wang_prng( rng, world_seed, ng_plus or 0, map_w, extra_rerolls )
	local result, err = stbhw.generate( tileset, rng, map_w, out_h, options )
	if ( not result ) then
		return nil, err
	end
	return result
end

-- ---------------------------------------------------------------------------
-- Room blocking / masking
-- ---------------------------------------------------------------------------

M.BLOCKED_COLORS = {
	[ 0x00ac6e ] = true, [ 0x70d79e ] = true, [ 0x70d79f ] = true,
	[ 0x70d7a0 ] = true, [ 0x70d7a1 ] = true, [ 0x7868ff ] = true,
	[ 0xc35700 ] = true, [ 0xff0080 ] = true, [ 0xff00ff ] = true,
	[ 0xff0aff ] = true, [ 0x00ac64 ] = true,
}

function M.block_out_rooms( buf, width, height )
	local rooms = {}
	-- JS reads `pixels[idx]` even past the end of the buffer, where it yields
	-- `undefined`; `(undefined << 16) | (undefined << 8) | undefined` is 0, i.e.
	-- the read behaves as BLACK. Room probing legitimately walks one past the
	-- last row/column, so replicate that: out-of-range means 0, not an error.
	local n = #buf
	local function byte_at( idx )
		if ( idx < 1 or idx > n ) then return 0 end
		return buf[ idx ] or 0
	end

	for y = 4, height - 1 do
		for x = 0, width - 1 do
			local idx = ( y * width + x ) * 3 + 1
			local color = byte_at( idx ) * 65536 + byte_at( idx + 1 ) * 256 + byte_at( idx + 2 )
			if ( color ~= 0x000000 and color ~= 0xffffff and M.BLOCKED_COLORS[ color ] ) then
				local start_x, start_y = x + 1, y + 1
				local end_x, end_y = x + 1, y + 1
				local found_end = false
				while ( not found_end and end_x < width ) do
					local ti = ( start_y * width + end_x ) * 3 + 1
					local tc = byte_at( ti ) * 65536 + byte_at( ti + 1 ) * 256 + byte_at( ti + 2 )
					if ( tc == 0x000000 or tc == 0x323232 ) then
						end_x = end_x + 1
					else
						end_x = end_x - 1
						found_end = true
					end
				end
				if ( end_x >= width ) then end_x = width - 1 end
				found_end = false
				while ( not found_end and end_y < height ) do
					local ti = ( end_y * width + start_x ) * 3 + 1
					local tc = byte_at( ti ) * 65536 + byte_at( ti + 1 ) * 256 + byte_at( ti + 2 )
					if ( tc == 0x000000 or tc == 0x323232 ) then
						end_y = end_y + 1
					else
						end_y = end_y - 1
						found_end = true
					end
				end
				if ( end_y >= height ) then end_y = height - 1 end

				if ( end_x > start_x and end_y > start_y ) then
					for by = start_y, end_y do
						for bx = start_x, end_x do
							local b_idx = ( by * width + bx ) * 3 + 1
							buf[ b_idx ] = 0xff
							buf[ b_idx + 1 ] = 0x01
							buf[ b_idx + 2 ] = 0xff
						end
					end
				end

				rooms[ #rooms + 1 ] = {
					color = color,
					start_x = start_x, start_y = start_y,
					end_x = end_x, end_y = end_y,
				}
			end
		end
	end
	return rooms
end

function M.apply_masking( buf, width, bbox, valid_chunks )
	local min_cx, min_cy, max_cx, max_cy = bbox[ 1 ], bbox[ 2 ], bbox[ 3 ], bbox[ 4 ]
	local tx = 0
	for cx = min_cx, max_cx do
		local cw = 51
		if ( cx % 5 == 4 ) then cw = cw + 1 end
		local ty = 0
		for cy = min_cy, max_cy do
			local ch = 51
			if ( cy % 5 == 4 ) then ch = ch + 1 end
			if ( not valid_chunks[ cx .. "," .. cy ] ) then
				for y = 0, ch - 1 do
					for x = 0, cw - 1 do
						local si = ( ( ty + y + 4 ) * width + ( tx + x ) ) * 3 + 1
						buf[ si ] = 0
						buf[ si + 1 ] = 0
						buf[ si + 2 ] = 0
					end
				end
			end
			ty = ty + ch
		end
		tx = tx + cw
	end
end

-- ---------------------------------------------------------------------------
-- Biome hacks
-- ---------------------------------------------------------------------------

-- applyMainBiomeHack: clears a 7 x 11 opening at the corridor start for biomes
-- that are not built from the Mines template. Upstream applies this AFTER
-- room blocking and BEFORE pathfinding, so the corridor has somewhere to start.
function M.apply_main_biome_hack( start_x, buf, width, height )
	for y = 0, 10 do
		for x = start_x, start_x + 6 do
			if ( x >= 0 and x < width and y < height ) then
				local idx = ( y * width + x ) * 3 + 1
				buf[ idx ] = 0
				buf[ idx + 1 ] = 0
				buf[ idx + 2 ] = 0
			end
		end
	end
end

-- The coalmine overlay is RGBA. Non-transparent pixels re-colour the buffer at a
-- +4 row offset. 0x000042 becomes air; other non-white becomes solid (or air
-- when undoing, because the game leaves those cells empty).
function M.apply_coalmine_overlay( buf, width, height, overlay_img, undo )
	local ow, oh = overlay_img.width, overlay_img.height
	local limit_y = math.min( height, oh )
	local limit_x = math.min( width, ow )
	local rgba = overlay_img.rgba
	for y = 0, limit_y - 1 do
		for x = 0, limit_x - 1 do
			local oi = ( y * ow + x ) * 4 + 1
			local r, g, b, a = rgba:byte( oi, oi + 3 )
			if ( a and a ~= 0 ) then
				local hex = r * 65536 + g * 256 + b
				local pi = ( ( y + 4 ) * width + x ) * 3 + 1
				if ( pi + 2 <= #buf ) then
					if ( hex == 0x000042 ) then
						buf[ pi ], buf[ pi + 1 ], buf[ pi + 2 ] = 0, 0, 0
					elseif ( hex ~= 0xffffff ) then
						if ( undo ) then
							buf[ pi ], buf[ pi + 1 ], buf[ pi + 2 ] = 0, 0, 0
						else
							buf[ pi ], buf[ pi + 1 ], buf[ pi + 2 ] = 1, 1, 1
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Coffee / path clearing
-- ---------------------------------------------------------------------------

local function flood_replace( buf, width, height, sx, sy, to )
	local queue = { sx, sy }
	local head = 1
	local seen = { [ sy * width + sx ] = true }
	while ( head <= #queue ) do
		local cx, cy = queue[ head ], queue[ head + 1 ]
		head = head + 2
		local idx = ( cy * width + cx ) * 3 + 1
		buf[ idx ], buf[ idx + 1 ], buf[ idx + 2 ] = to, to, to
		local nx, ny
		nx, ny = cx + 1, cy
		if ( nx < width ) then
			local k = ny * width + nx
			if ( not seen[ k ] ) then
				local i = k * 3 + 1
				if ( buf[ i ] == 0xc0 and buf[ i + 1 ] == 0xff and buf[ i + 2 ] == 0xee ) then
					seen[ k ] = true; queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
				end
			end
		end
		nx, ny = cx - 1, cy
		if ( nx >= 0 ) then
			local k = ny * width + nx
			if ( not seen[ k ] ) then
				local i = k * 3 + 1
				if ( buf[ i ] == 0xc0 and buf[ i + 1 ] == 0xff and buf[ i + 2 ] == 0xee ) then
					seen[ k ] = true; queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
				end
			end
		end
		nx, ny = cx, cy + 1
		if ( ny < height ) then
			local k = ny * width + nx
			if ( not seen[ k ] ) then
				local i = k * 3 + 1
				if ( buf[ i ] == 0xc0 and buf[ i + 1 ] == 0xff and buf[ i + 2 ] == 0xee ) then
					seen[ k ] = true; queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
				end
			end
		end
		nx, ny = cx, cy - 1
		if ( ny >= 0 ) then
			local k = ny * width + nx
			if ( not seen[ k ] ) then
				local i = k * 3 + 1
				if ( buf[ i ] == 0xc0 and buf[ i + 1 ] == 0xff and buf[ i + 2 ] == 0xee ) then
					seen[ k ] = true; queue[ #queue + 1 ] = nx; queue[ #queue + 1 ] = ny
				end
			end
		end
	end
end

function M.clear_path( buf, width, height, path )
	if ( path == nil ) then return end
	for i = 1, #path do
		local x, y = path[ i ].x, path[ i ].y
		if ( x >= 0 and x < width and y >= 0 and y < height ) then
			local idx = ( y * width + x ) * 3 + 1
			if ( buf[ idx ] == 0xc0 and buf[ idx + 1 ] == 0xff and buf[ idx + 2 ] == 0xee ) then
				flood_replace( buf, width, height, x, y, 0x00 )
			end
		end
	end
end

function M.apply_coffee_hack( buf, width, height, world_seed )
	local rng = nil
	for y = 4, height - 1 do
		for x = 0, width - 1 do
			local idx = ( y * width + x ) * 3 + 1
			if ( buf[ idx ] == 0xc0 and buf[ idx + 1 ] == 0xff and buf[ idx + 2 ] == 0xee ) then
				if ( rng == nil ) then
					rng = new_prng( 0 )
					rng:SetRandomFromWorldSeed( world_seed )
					rng:Next()
				end
				local selected = rng:Next() < 0.5 and 0xff or 0x00
				flood_replace( buf, width, height, x, y, selected )
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Buffer helpers
-- ---------------------------------------------------------------------------

function M.to_buf( rgb )
	local n = #rgb
	local buf = {}
	for i = 1, n do
		buf[ i ] = rgb:byte( i )
	end
	return buf
end

function M.to_rgb( buf, n )
	local parts = {}
	local chunk = {}
	local cn = 0
	for i = 1, n do
		cn = cn + 1
		chunk[ cn ] = string.char( buf[ i ] or 0 )
		if ( cn >= 8192 ) then
			parts[ #parts + 1 ] = table.concat( chunk )
			chunk = {}
			cn = 0
		end
	end
	if ( cn > 0 ) then parts[ #parts + 1 ] = table.concat( chunk ) end
	return table.concat( parts )
end

-- ---------------------------------------------------------------------------
-- Full pipeline
-- ---------------------------------------------------------------------------

-- build_layer( assets, biome_key, world_seed[, ng_plus, region_index] )
--   -> layer | nil, err
--
-- assets = {
--   biome_map   = <decoded png>,
--   wang        = { [biome_key] = <decoded png> },
--   coalmine_overlay = <decoded RGBA png>   (only needed for the Mines template),
--   tilesets    = { [biome_key] = <prebuilt stbhw tileset> }  (optional cache),
-- }
function M.build_layer( assets, biome_key, world_seed, ng_plus, region_index, options )
	options=options or {}
	local resource_only=options.resource_only==true
	local ops=resource_only and dofile_once("mods/interesting_seed_filter/files/isf/worldgen/resource_grid.lua")or M
	if resource_only then assert(type(options.marker_index)=="table","resource marker index required")end
	ng_plus = ng_plus or 0
	local cfg = M.BIOMES[ biome_key ]
	if ( cfg == nil ) then
		return nil, "unsupported biome " .. tostring( biome_key )
	end

	local regions = M.find_biome_regions( assets.biome_map, cfg.color )
	if ( #regions == 0 ) then
		return nil, "no " .. biome_key .. " region on this biome map"
	end
	local idx = region_index or 1
	local region = regions[ idx ]
	if ( region == nil ) then
		return nil, string.format( "biome %s has %d region(s), requested #%d",
			biome_key, #regions, idx )
	end
	local bbox = { region.minx, region.miny, region.maxx, region.maxy }

	local wang_img = assets.wang and assets.wang[ biome_key ]
	if ( wang_img == nil ) then
		return nil, "missing wang tileset for " .. biome_key
	end

	local tileset = assets.tilesets and assets.tilesets[ biome_key ]
	if ( tileset == nil ) then
		tileset = stbhw.new_tileset()
		local ok, err = stbhw.build( tileset, wang_img )
		if ( not ok ) then
			return nil, err
		end
		if ( assets.tilesets ) then
			assets.tilesets[ biome_key ] = tileset
		end
	end

	local dims = calculate_map_dimensions( region.minx, region.miny, region.maxx, region.maxy )
	local map_w, map_h = dims.width, dims.height
	local out_h = map_h + 4

	local path_start = pathfind.get_path_start_segment( bbox, map_w, map_h,
		cfg.wang, ng_plus > 0 )
	local use_path = ( 1 + bbox[ 4 ] - bbox[ 2 ] ) <= M.BIOME_PATH_HEIGHT_LIMIT_CHUNKS

	-- --- retry loop: accept the first Wang roll that has a corridor ---------
	local rerolls = 0
	local attempts = 0
	local result = nil
	local path = nil
	local accepted = false
	local prepared_buf,prepared_rooms

	while ( attempts < M.MAX_PATHFINDING_ATTEMPTS ) do
		local gen, err = generate_raw_tile_buffer( tileset, world_seed, ng_plus,
			map_w, map_h, rerolls, options )
		if ( not gen ) then
			return nil, err
		end
		result = gen

		-- Per-attempt staging must be redone from scratch, because the hacks
		-- mutate the buffer and pathfinding depends on them.
		local buf = resource_only and gen.cells or M.to_buf( gen.rgb )
		local rooms = {}
		if ( cfg.blocks_rooms ) then
			rooms = ops.block_out_rooms( buf, map_w, out_h )
		end
		if ( path_start ~= nil and not cfg.uses_mines_template ) then
			ops.apply_main_biome_hack( path_start.x, buf, map_w, out_h )
		end
		if ( cfg.uses_mines_template and assets.coalmine_overlay ~= nil ) then
			ops.apply_coalmine_overlay( buf, map_w, out_h, assets.coalmine_overlay, false )
		end

		local candidate
		prepared_buf,prepared_rooms=buf,rooms
		if ( use_path ) then
			if resource_only then
				if pathfind.has_path(buf,map_w,out_h,path_start)then candidate={}end
			else
				candidate = pathfind.find_min_path( buf, map_w, out_h, path_start )
			end
		else
			candidate = {}
		end

		if ( candidate ~= nil ) then
			path = candidate
			accepted = true
			break
		end
		rerolls = rerolls + 1
		attempts = attempts + 1
	end

	-- --- final postprocessing from scratch on the accepted roll ------------
	local buf = resource_only and prepared_buf or M.to_buf( result.rgb )
	local stages = {}
	if not resource_only then stages.wang_fnv = stbhw.fnv1a( result.rgb )end
	stages.extra_rerolls = rerolls
	stages.attempts = attempts

	local rooms = resource_only and prepared_rooms or {}
	if ( not resource_only and cfg.blocks_rooms ) then
		rooms = M.block_out_rooms( buf, map_w, out_h )
	end
	stages.room_count = #rooms

	if ( not resource_only and path_start ~= nil and not cfg.uses_mines_template ) then
		M.apply_main_biome_hack( path_start.x, buf, map_w, out_h )
	end
	if ( not resource_only and cfg.uses_mines_template and assets.coalmine_overlay ~= nil ) then
		M.apply_coalmine_overlay( buf, map_w, out_h, assets.coalmine_overlay, false )
	end

	-- Rooms restored to air.
	if resource_only then ops.restore_rooms(buf,map_w,rooms)else
	for r = 1, #rooms do
		local room = rooms[ r ]
		for y = room.start_y, room.end_y do
			for x = room.start_x, room.end_x do
				local oi = ( y * map_w + x ) * 3 + 1
				buf[ oi ] = 0
				buf[ oi + 1 ] = 0
				buf[ oi + 2 ] = 0
			end
		end
	end
	end

	if ( cfg.uses_mines_template and assets.coalmine_overlay ~= nil ) then
		ops.apply_coalmine_overlay( buf, map_w, out_h, assets.coalmine_overlay, true )
	end

	path = path or {}
	if not resource_only then
		M.clear_path( buf, map_w, out_h, path )
		M.apply_coffee_hack( buf, map_w, out_h, world_seed + ng_plus )
	end

	local valid_chunks = {}
	for i = 1, #region.cells do
		local cell = region.cells[ i ]
		valid_chunks[ cell[ 1 ] .. "," .. cell[ 2 ] ] = true
	end
	ops.apply_masking( buf, map_w, bbox, valid_chunks )

	local n = #buf
	local final_rgb
	if not resource_only then
		final_rgb = M.to_rgb( buf, n )
		stages.final_fnv = stbhw.fnv1a( final_rgb )
	end
	if resource_only then
		stages.path_check = "acceptance-only"
	else
		stages.path_length = #path
		stages.path_head = {}
		for i = 1, math.min( 24, #path ) do
			stages.path_head[ i ] = { x = path[ i ].x, y = path[ i ].y }
		end
	end

	return {
		resource_only=resource_only or nil,
		cells=resource_only and buf or nil,
		spawn_markers=resource_only and ops.markers(result,buf,map_w,out_h,options.marker_index)or nil,
		biome = biome_key,
		biome_name = cfg.name,
		rgb = final_rgb,
		buf = not resource_only and buf or nil,
		width = map_w,
		height = out_h,
		map_h = map_h,
		xmax = result.xmax,
		ymax = result.ymax,
		tile_indices = result.tile_indices,
		tile_index_count = result.tile_index_count,
		minx = region.minx,
		miny = region.miny,
		bbox = bbox,
		region = region,
		region_index = idx,
		region_count = #regions,
		path = not resource_only and path or nil,
		path_start = path_start,
		rooms = rooms,
		extra_rerolls = rerolls,
		stages = stages,
		tileset = {
			is_corner = tileset.is_corner,
			short_side_len = tileset.short_side_len,
			num_color = tileset.num_color,
			num_vary_x = tileset.num_vary_x,
			num_vary_y = tileset.num_vary_y,
			num_h_tiles = tileset.num_h_tiles,
			num_v_tiles = tileset.num_v_tiles,
		},
	}
end

-- Backwards-compatible alias for the Mines-only entry point.
function M.build_mines_layer( assets, world_seed, ng_plus )
	local layers = assets.wang.coalmine ~= nil and assets or assets
	return M.build_layer( layers, "coalmine", world_seed, ng_plus )
end

return M
