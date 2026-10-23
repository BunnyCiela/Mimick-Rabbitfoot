-- files/isf/worldgen/scan.lua
--
-- Biome-agnostic spawn-function discovery for a generated terrain layer: finds
-- the spawn pixels the terrain contains, converts them to world coordinates,
-- places the nested pixel scenes they request, and resolves the objects those
-- scenes and generic spawn functions represent.
--
-- Substantial reuse: noita-telescope
--   js/poi_scanner.js             (prescanSpawnFunctions, scanSpawnFunctions)
--   js/spawn_functions.js         (spawnSwitch dispatch + all biome branches)
--   js/pixel_scene_generation.js  (loadRandomPixelScene, prescanPixelScene)
--   js/wand_generation.js         (spawnWandAltar / checkWandAltar / spawnWand)
--   js/utils.js                   (tileToWorldCoordinates, getBiomeAtWorldCoordinates)
--   MIT License, Copyright (c) 2026 Lymm
--
-- TWO-TIER RECORDS (important for downstream consumers)
--   A record is either
--     * a VERIFIED GENERATED object -- the generating function was fully
--       evaluated and the object exists with known coordinates; or
--     * a POTENTIAL MARKER -- a spawn pixel whose function is recognised but
--       whose content/success cannot be resolved offline. `generated` is false
--       and `unresolved_reason` says why.
--   Consumers MUST NOT treat a potential marker as a guaranteed object.
--   See .scratch/interesting-seed-filter/worldgen/DISCOVERY_CONTRACT.md.
--
-- WHAT `generated = true` IS ALLOWED TO MEAN
--   Only two things can justify it:
--     1. the vanilla spawn function UNCONDITIONALLY performs the EntityLoad /
--        LoadPixelScene the marker names (recorded in biome_data
--        .existence_proven_functions, transcribed from the installed scripts);
--        or
--     2. a deterministic probability gate was EVALUATED and passed (recorded in
--        biome_data.gated_functions), e.g. Coal Pits meditation cube
--        `Random(1,100) > 96` at the exact marker coordinates.
--   A recognised function whose content belongs to another provider stays
--   `generated = false` with a reason. Nothing is upgraded by assumption.
--
-- OBJECT IDENTITY
--   `source_id` is the stable provenance id of the *marker that produced this
--   record*. `object_id` is the identity of the *physical object*: two markers
--   belonging to one scene placement share the scene part of it, and a consumer
--   that needs "one score per physical object" keys on `object_id`.
--   A scene placement and the entity markers inside it always have DIFFERENT
--   object_ids (they are different physical objects), and a scene's inner
--   marker is emitted regardless of whether the enclosing scene record itself
--   was fully resolved, so an entrance can be required without assuming the
--   hidden room.
--
-- Standalone Lua 5.1: no FFI, no external process, no filesystem access.

local M = {}
local prop_containers=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/prop_containers.lua")

local CHUNK_SIZE = 512
local TILE_SIZE = 10
local TILE_OFFSET_X = 5
local TILE_OFFSET_Y = -13
local WORLD_CHUNK_CENTER_X = 35
local WORLD_CHUNK_CENTER_Y = 14

M.CHUNK_SIZE = CHUNK_SIZE
M.TILE_SIZE = TILE_SIZE

-- Functions that must ALWAYS produce a record for their terrain marker, even
-- when the scene roll selects "no scene", because a downstream owner needs to
-- distinguish "marker absent" from "marker present but produced nothing".
-- `spawn_meditation_cube` is NOT here: it has no scene list of its own, it is
-- handled by the gate branch (see biome_data.gated_functions).
M.ALWAYS_REPORT_FUNCTIONS = {
	load_puzzleroom = true,
	load_puzzle_capsule = true,
	load_puzzle_capsule_b = true,
}

local deps = nil
local color_indexes={}
local scene_cache=setmetatable({},{__mode="k"})

-- deps:
--   prng_new(seed)
--   biome_data    -- generated biome_data.lua
--   biome_map     -- decoded biome map
--   biome_name_by_color -- [color24] = biome key
--   scene_image(biome, name) -> decoded png | nil
--
-- `init` is module-level state. Callers that evaluate more than one asset set
-- must re-call it (the providers do this per evaluation).
function M.init( d )
	if not deps or deps.biome_data~=d.biome_data then
		color_indexes={};scene_cache=setmetatable({},{__mode="k"})
	end
	deps = d
	return M
end

-- ---------------------------------------------------------------------------
-- Coordinate conversion
-- ---------------------------------------------------------------------------

-- tileToWorldCoordinates for a main-world NG0 tile layer (PW 0).
-- Reproduced exactly, including sign handling for negative chunk bases.
function M.tile_to_world( chunk_base_x, chunk_base_y, tile_x, tile_y )
	local small_chunk = math.floor( CHUNK_SIZE / TILE_SIZE )

	local div5_x = 5 * CHUNK_SIZE * math.floor( ( chunk_base_x - WORLD_CHUNK_CENTER_X ) / 5 )
	local mod5_x = ( ( chunk_base_x - WORLD_CHUNK_CENTER_X ) % 5 + 5 ) % 5
	local world_base_x = div5_x + mod5_x * small_chunk * TILE_SIZE
	local world_x = -TILE_SIZE + world_base_x + tile_x * TILE_SIZE + TILE_OFFSET_X

	local div5_y = 5 * CHUNK_SIZE * math.floor( ( chunk_base_y - WORLD_CHUNK_CENTER_Y ) / 5 )
	local mod5_y = ( ( chunk_base_y - WORLD_CHUNK_CENTER_Y ) % 5 + 5 ) % 5
	local world_base_y = div5_y + mod5_y * small_chunk * TILE_SIZE
	if ( mod5_y > 0 ) then
		world_base_y = world_base_y + TILE_SIZE
	end
	local world_y = -TILE_SIZE + world_base_y + tile_y * TILE_SIZE + TILE_OFFSET_Y + TILE_SIZE

	return world_x, world_y
end

-- Terrain markers must belong to a chunk whose 10px scan grid actually visits
-- that Wang cell. Near a 512px seam, tile_to_world alone can emit a point in
-- the previous chunk even though only the next chunk scans the cell. Native
-- seed49 confirms (325,507) is skipped and (335,577) is called. This gate is
-- for terrain markers only; nested pixel-scene markers use a 1:1 pixel grid.
-- NG0 main-world geometry; no biome-edge-noise parity is implied here.
local function axis_scanned(emit,offset)
	local cell=math.floor((emit+TILE_SIZE/2+offset)/TILE_SIZE+0.5)
	local lo=cell*TILE_SIZE-offset-1
	local hi=cell*TILE_SIZE-offset+TILE_SIZE+1
	for s=math.ceil(lo),hi do
		local base=math.floor(s/CHUNK_SIZE)*CHUNK_SIZE
		if math.floor((s+offset+0.5)/TILE_SIZE)==cell
			and (s-base)%TILE_SIZE==0
			and base<=emit and emit<base+CHUNK_SIZE-1 then return true end
	end
	return false
end
function M.passes_spawn_chunk_gate(x,y)
	return axis_scanned(x,WORLD_CHUNK_CENTER_X*CHUNK_SIZE)
		and axis_scanned(y,WORLD_CHUNK_CENTER_Y*CHUNK_SIZE)
end

-- ---------------------------------------------------------------------------
-- Biome lookup
-- ---------------------------------------------------------------------------

function M.biome_at( world_x, world_y, use_noise )
	if ( deps.biome_map == nil ) then return nil end
	if deps.edge_noise then
		local color=deps.edge_noise.lookup(deps.biome_map,world_x,world_y,use_noise==true)
		return deps.biome_name_by_color[color]
	end
	local map_w = deps.biome_map.width
	local map_h = deps.biome_map.height
	local world_size = 70 * 512
	local world_center = world_size / 2
	local mod_x = ( ( world_x + world_center ) % world_size + world_size ) % world_size
	local mod_y = ( ( world_y + 14 * 512 ) % 24576 + 24576 ) % 24576
	local px = math.floor( mod_x / 512 )
	local py = math.floor( mod_y / 512 )
	px = ( px % map_w + map_w ) % map_w
	if ( py < 0 ) then py = 0 end
	if ( py > map_h - 1 ) then py = map_h - 1 end
	local i = ( py * map_w + px ) * 3 + 1
	local r, g, b = deps.biome_map.rgb:byte( i, i + 2 )
	return deps.biome_name_by_color[ r * 65536 + g * 256 + b ]
end

-- Chunk-seam visitation and biome-edge acceptance are independent engine gates.
-- Test-injected scanners may omit edge_noise; production discovery always
-- supplies it alongside the installed 70x48 map and all biome edge flags.
function M.passes_spawn_biome_gate(x,y)
	if not deps.edge_noise then return true end
	local sx,sy=deps.edge_noise.tile_scan_point(x,y)
	local resolved,original=deps.edge_noise.resolve(deps.biome_map,sx,sy)
	return deps.biome_name_by_color[resolved]==deps.biome_name_by_color[original]
end

function M.scene_dispatch(img,x,y,source_biome)
	local biome=source_biome
	if deps.edge_noise then biome=M.biome_at(x+img.width/2,y+img.height/2,true)end
	local cfg=biome and M.biome_config(biome)
	if not cfg then return biome,{},{} end
	return biome,M.prescan_pixel_scene(img,biome),cfg.spawns
end

-- ---------------------------------------------------------------------------
-- Spawn function lookup
-- ---------------------------------------------------------------------------

function M.biome_config( biome )
	return deps.biome_data.biomes[ biome ]
end

-- The generated table is the game's real dispatch array; its INDICES are what
-- the game uses, so order must be preserved.
function M.spawn_table( biome )
	local cfg = M.biome_config( biome )
	return cfg and cfg.spawns
end

function M.spawn_index( biome, color )
	return M.spawn_color_index(biome)[color]
end
function M.spawn_color_index(biome)
	local list = M.spawn_table( biome )
	if list==nil then return {}end
	local cached=color_indexes[list]
	if cached then return cached end
	local index={}
	for i = 1, #list do
		local color=list[i].color
		if index[color]==nil then index[color]=i end
	end
	color_indexes[list]=index
	return index
end

-- ---------------------------------------------------------------------------
-- Source-justified metadata (from biome_data)
-- ---------------------------------------------------------------------------

-- The entity a marker function unconditionally loads, or nil.
-- Keyed by "biome/function" because the same function name loads different
-- entities in different biomes.
function M.existence_proven( biome, func )
	local map = deps.biome_data.existence_proven_functions
	if ( map == nil or func == nil ) then return nil end
	return map[ biome .. "/" .. func ]
end

-- The deterministic probability gate a marker function applies, or nil.
function M.gate_spec( biome, func )
	local map = deps.biome_data.gated_functions
	if ( map == nil or func == nil ) then return nil end
	return map[ biome .. "/" .. func ]
end

-- Marker-relative pixel-scene placement offset, or nil.
function M.placement_offset( func )
	local map = deps.biome_data.scene_placement_offsets
	if ( map == nil or func == nil ) then return nil end
	return map[ func ]
end

-- True when a placed scene's PLACEMENT must be reported even if the bitmap
-- carries no registered spawn-marker pixel.
function M.is_tracked_scene( name )
	local map = deps.biome_data.tracked_scene_names
	if ( map == nil ) then return false end
	return map[ name ] == true
end

-- Evaluate a `random_gt` gate. Returns passed, roll, spec | nil, reason.
--
-- The gate is deterministic in (world_seed, x, y): vanilla does
-- `SetRandomSeed(x,y)` then `Random(min,max)` in one function body, so the
-- world seed belongs to the PRNG instance and the position is the seed.
function M.evaluate_gate( biome, func, world_seed, ng_plus, x, y )
	local spec = M.gate_spec( biome, func )
	if ( spec == nil ) then return nil, "no gate spec for this marker" end
	if ( spec.gate ~= "random_gt" ) then
		return nil, "unsupported gate kind " .. tostring( spec.gate )
	end
	local rng = deps.prng_new( world_seed + ng_plus )
	rng:SetRandomSeed( x, y )
	local roll = rng:Random( spec.random_min, spec.random_max )
	return roll > spec.threshold, roll, spec
end

-- ---------------------------------------------------------------------------
-- Generation context (calendar + persistent flags)
-- ---------------------------------------------------------------------------
--
-- Some vanilla branches read the wall clock (`GameGetDateAndTimeLocal`) or a
-- persistent unlock flag (`HasFlagPersistent`). Both are inputs to the
-- prediction, so they come from the caller's frozen profile and NEVER from the
-- live game/save. `scan_layer`'s 5th argument is an optional context table:
--
--   { calendar = { month = , day = },        -- from the profile snapshot
--     persistent_flags = { FLAG = true },     -- frozen profile flags
--     is_flag_set = function(flag) -> bool end -- explicit override }
--
-- With no context, calendar-dependent and flag-dependent branches are reported
-- as UNRESOLVED with a reason rather than guessed at.
--
-- The context is captured per scan_layer call (not module state) so concurrent
-- evaluations cannot leak one profile into another.

local function calendar_month_day( ctx )
	if ( type( ctx ) ~= "table" ) then return nil end
	local cal = ctx.calendar
	if ( type( cal ) ~= "table" ) then return nil end
	local month, day = cal.month, cal.day
	if ( type( month ) ~= "number" or type( day ) ~= "number" ) then return nil end
	return month, day
end

-- True/false when the profile answers, nil when it does not.
local function flag_value( ctx, name )
	if ( type( ctx ) ~= "table" or name == nil ) then return nil end
	if ( type( ctx.is_flag_set ) == "function" ) then
		local ok, value = pcall( ctx.is_flag_set, name )
		if ( ok and type( value ) == "boolean" ) then return value end
		return nil
	end
	local flags = ctx.persistent_flags
	if ( type( flags ) ~= "table" ) then return nil end
	local value = flags[ name ]
	if ( type( value ) == "boolean" ) then return value end
	return nil
end

-- ---------------------------------------------------------------------------
-- spawn_heart resolution
-- ---------------------------------------------------------------------------
--
-- spawn_heart is a DISPATCH, not an entity: `ProceduralRandom(x,y)` selects a
-- heart, a chest (normal/super), a mimic, a leggy chest, or nothing. Reporting
-- "a heart exists" from the marker alone over-reports hearts and silently loses
-- chests (both real defects in this build before this change).
--
-- Resolution is exact when the calendar is known. Vanilla lowers the heart
-- threshold on 14 February, so without a calendar snapshot the heart/chest
-- boundary is ambiguous for 0.35 < r <= 0.7 and that band is reported as
-- UNRESOLVED rather than guessed.
--
-- Returns a table:
--   outcome        "heart" | "chest" | "chest_mimic" | "chest_leggy" | "nothing"
--                  | "unresolved"
--   entity         entity path for a resolved outcome (nil otherwise)
--   r              the ProceduralRandom draw
--   threshold      the heart threshold actually used (nil if unresolved)
--   branch_roll, chest_roll, chest_kind, enemy_roll   as applicable
--   mimic_sign     true when the vanilla mimic-sign draw fired
--   reason         why the outcome is unresolved
function M.resolve_heart( world_seed, ng_plus, x, y, ctx )
	local spec = deps.biome_data.heart_source
	if ( spec == nil ) then
		return { outcome = "unresolved", reason = "no spawn_heart source spec" }
	end

	local rng = deps.prng_new( world_seed + ng_plus )
	local r = rng:ProceduralRandom( x, y )
	local out = { r = r }

	local month, day = calendar_month_day( ctx )
	local calendar_known = month ~= nil
	local threshold = spec.heart_threshold
	if ( calendar_known
		and month == spec.calendar_override_month
		and day == spec.calendar_override_day ) then
		threshold = spec.calendar_override_threshold
	end
	out.threshold = threshold

	if ( r > threshold ) then
		out.outcome = "heart"
		out.entity = spec.entities.heart
		return out
	end

	if ( r <= spec.chest_branch_requires_r_gt ) then
		out.outcome = "nothing"
		return out
	end

	-- r is in the chest band, but the *heart* boundary is calendar-dependent:
	-- when the calendar is unknown, this band could still have been a heart on
	-- 14 February. Say so instead of asserting a chest.
	if ( not calendar_known ) then
		out.outcome = "unresolved"
		out.calendar_dependent = true
		out.reason = string.format(
			"spawn_heart outcome at (%d, %d) depends on the calendar: "
				.. "0.35 < r = %.6f <= 0.7 is a heart on Feb 14 and a chest otherwise; "
				.. "supply ctx.calendar to resolve", x, y, r )
		return out
	end

	local chest_spec = spec
	rng:SetRandomSeed( x + chest_spec.chest_reseed_dx, y + chest_spec.chest_reseed_dy )
	local branch = rng:Random( chest_spec.branch_rand_min, chest_spec.branch_rand_max )
	out.branch_roll = branch

	local deep = ( branch <= chest_spec.branch_deep_le )
		or ( y < chest_spec.deep_y_threshold )
	out.deep_branch = deep

	if ( deep ) then
		local chest_roll = rng:Random( chest_spec.deep_rand_min, chest_spec.deep_rand_max )
		out.chest_roll = chest_roll
		-- Draw order matters: vanilla takes the chest type first, then the
		-- mimic-sign roll, then compares the type.
		if ( rng:Random( chest_spec.mimic_sign_rand_min,
			chest_spec.mimic_sign_rand_max ) == chest_spec.mimic_sign_on ) then
			out.mimic_sign = true
		end
		out.outcome = "chest"
		if ( chest_roll >= chest_spec.deep_super_from ) then
			out.chest_kind = "super"
			out.entity = chest_spec.entities.chest_super
		else
			out.chest_kind = "normal"
			out.entity = chest_spec.entities.chest_normal
		end
		return out
	end

	local enemy = rng:Random( chest_spec.shallow_rand_min, chest_spec.shallow_rand_max )
	out.enemy_roll = enemy
	if ( rng:Random( chest_spec.shallow_rand_min,
		chest_spec.shallow_mimic_sign_rand_max or chest_spec.mimic_sign_rand_max )
		== chest_spec.mimic_sign_on ) then
		out.mimic_sign = true
	end
	if ( enemy <= chest_spec.shallow_mimic_le ) then
		out.outcome = "chest_mimic"
		out.entity = chest_spec.entities.chest_mimic
	else
		out.outcome = "chest_leggy"
		out.entity = chest_spec.entities.chest_leggy
	end
	return out
end

-- ---------------------------------------------------------------------------
-- spawn_from_list container resolution
-- ---------------------------------------------------------------------------
--
-- spawn_from_list reseeds at (x + seed_dx, y + seed_dy), draws ONE band roll, and
-- the matching band loads its entity at (x + offset_x, y + offset_y). Bands that
-- declare `spawn_requires_flag` consult the caller's frozen flags.
--
-- Returns:
--   outcome    "container" | "other" | "no_band" | "flag_blocked" | "unresolved"
--   kind       the band's kind ("potion", "powder_pouch", ...)
--   entity     exact entity path the band loads
--   roll       the band draw
--   load_x/y   the proven EntityLoad argument (x + offset, y + offset)
--   offset_x/y the band's offsets
function M.resolve_spawn_list( list_name, world_seed, ng_plus, x, y, ctx )
	local list = deps.biome_data.container_lists[ list_name ]
	if ( list == nil ) then
		return { outcome = "unresolved", reason = "no such container list: "
			.. tostring( list_name ) }
	end

	local rng = deps.prng_new( world_seed + ng_plus )
	rng:SetRandomSeed( x + list.seed_dx, y + list.seed_dy )
	local roll = rng:Random( list.rnd_min, list.rnd_max )

	for i = 1, #list.entries do
		local e = list.entries[ i ]
		if ( roll >= e.value_min and roll <= e.value_max ) then
			local out = {
				roll = roll,
				kind = e.kind,
				entity = e.entity,
				offset_x = e.offset_x,
				offset_y = e.offset_y,
				load_x = x + e.offset_x,
				load_y = y + e.offset_y,
				list_name = list_name,
				value_min = e.value_min,
				value_max = e.value_max,
			}
			if ( e.spawn_requires_flag ~= nil ) then
				local set = flag_value( ctx, e.spawn_requires_flag )
				out.requires_flag = e.spawn_requires_flag
				if ( set == nil ) then
					out.outcome = "unresolved"
					out.reason = "band " .. e.kind .. " requires persistent flag '"
						.. e.spawn_requires_flag .. "', which the caller's frozen "
						.. "profile does not answer"
					return out
				end
				if ( set ~= true ) then
					-- Vanilla returns WITHOUT loading anything.
					out.outcome = "flag_blocked"
					out.reason = "persistent flag '" .. e.spawn_requires_flag
						.. "' is not set, so the band loads nothing"
					return out
				end
			end
			if ( e.kind == "potion" or e.kind == "powder_pouch" ) then
				out.outcome = "container"
			else
				out.outcome = "other"
			end
			return out
		end
	end
	return { outcome = "no_band", roll = roll }
end

-- ---------------------------------------------------------------------------
-- spawn_potions resolution
-- ---------------------------------------------------------------------------
--
-- spawn_potions draws `Random(1,1000)` and either delegates to
-- spawn_from_list("potion_spawnlist") or loads a potion mimic. Returns the
-- wrapper decision plus the nested list resolution.
function M.resolve_potions( biome, world_seed, ng_plus, x, y, ctx )
	local key = biome .. "/spawn_potions"
	local spec = deps.biome_data.potion_sources[ key ]
		or deps.biome_data.potion_sources[ "general/spawn_potions" ]
	if ( spec == nil ) then
		return { outcome = "unresolved", reason = "no spawn_potions source spec" }
	end

	local rng = deps.prng_new( world_seed + ng_plus )
	rng:SetRandomSeed( x, y )
	local map_roll = rng:Random( spec.map_rand_min, spec.map_rand_max )

	local use_list = ( map_roll <= spec.map_list_le )
		or ( y < spec.deep_y_threshold )
	if ( not use_list ) then
		return {
			outcome = "potion_mimic",
			entity = spec.mimic_entity,
			map_roll = map_roll,
			load_x = x,
			load_y = y,
		}
	end

	local nested = M.resolve_spawn_list( spec.list_name, world_seed, ng_plus, x, y, ctx )
	local out = {}
	for k, v in pairs( nested ) do out[ k ] = v end
	out.map_roll = map_roll
	out.wrapper = "spawn_potions"
	return out
end

-- ---------------------------------------------------------------------------
-- potion_altar gate + placement
-- ---------------------------------------------------------------------------
--
-- spawn_potion_altar is gated by `ProceduralRandom(x,y) > 0.65` for the generic
-- body; fungicave OVERRIDES it with no gate and a (-10,-17) placement offset.
function M.potion_altar_spec( biome )
	local map = deps.biome_data.potion_altar_sources
	if ( map == nil ) then return nil end
	return map[ biome .. "/spawn_potion_altar" ]
		or map[ "general/spawn_potion_altar" ]
end

-- Returns passed, roll|reason, spec.
function M.evaluate_potion_altar_gate( biome, world_seed, ng_plus, x, y )
	local spec = M.potion_altar_spec( biome )
	if ( spec == nil ) then return nil, "no potion altar source spec", nil end
	if ( spec.gate_threshold == nil ) then
		-- An ungated override (fungicave) always places the scene.
		return true, nil, spec
	end
	local rng = deps.prng_new( world_seed + ng_plus )
	local r = rng:ProceduralRandom( x, y )
	return r > spec.gate_threshold, r, spec
end

-- ---------------------------------------------------------------------------
-- Pixel scene prescan
-- ---------------------------------------------------------------------------

function M.prescan_pixel_scene( img, biome )
	local index=M.spawn_color_index(biome)
	local cached=scene_cache[img]
	if cached and cached[index]then return cached[index]end
	local out = {}
	local w, h = img.width, img.height
	local rgb = img.rgb
	local rgba = img.rgba
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local alpha = 255
			if ( rgba ) then
				alpha = rgba:byte( ( y * w + x ) * 4 + 4 )
			end
			if ( alpha ~= 0 ) then
				local i = ( y * w + x ) * 3 + 1
				local r, g, b = rgb:byte( i, i + 2 )
				local color = r * 65536 + g * 256 + b
				if ( color ~= 0x000000 and color ~= 0xffffff ) then
					local idx = M.spawn_index( biome, color )
					if ( idx ~= nil ) then
						out[ #out + 1 ] = { x = x, y = y, spawn_function_index = idx,
							color = color }
					end
				end
			end
		end
	end
	if not cached then cached={};scene_cache[img]=cached end
	cached[index]=out
	return out
end

-- ---------------------------------------------------------------------------
-- Tile layer scan
-- ---------------------------------------------------------------------------

function M.prescan_spawn_functions( layer, biome )
	local out = {}
	if layer.spawn_markers then
		for _,p in ipairs(layer.spawn_markers)do
			local wx,wy=M.tile_to_world(layer.minx,layer.miny,p.tile_x,p.tile_y)
			out[#out+1]={x=wx,y=wy,tile_x=p.tile_x,tile_y=p.tile_y,color=p.color,spawn_function_index=p.spawn_function_index}
		end
		return out
	end
	local width = layer.width
	local height = layer.height
	local buf = layer.buf
	if ( buf == nil ) then
		buf = M.to_buf( layer.rgb )
	end

	for y = 4, height - 1 do
		for x = 0, width - 1 do
			local i = ( y * width + x ) * 3 + 1
			local r = buf[ i ]
			local g = buf[ i + 1 ]
			local b = buf[ i + 2 ]
			local color = r * 65536 + g * 256 + b
			if ( color ~= 0x000000 and color ~= 0xffffff ) then
				local idx = M.spawn_index( biome, color )
				if ( idx ~= nil ) then
					local wx, wy = M.tile_to_world( layer.minx, layer.miny, x, y - 4 )
					out[ #out + 1 ] = {
						x = wx, y = wy,
						tile_x = x, tile_y = y - 4,
						color = color,
						spawn_function_index = idx,
					}
				end
			end
		end
	end

	return out
end

-- ---------------------------------------------------------------------------
-- Pixel scene placement
-- ---------------------------------------------------------------------------

-- load_random_pixel_scene: roll the weighted list, then apply the biome-bounds
-- check the engine/upstream applies to all four corners.
--
-- Returns placed | nil, reason where reason is one of
--   "empty_list", "zero_weight", "no_scene", "missing_image", "out_of_biome".
function M.load_random_pixel_scene( biome, scene_list, world_seed, ng_plus, x, y )
	if ( scene_list == nil or #scene_list == 0 ) then return nil, "empty_list" end

	local rng = deps.prng_new( world_seed + ng_plus )
	local total = 0
	for i = 1, #scene_list do
		total = total + scene_list[ i ].prob
	end
	if ( total <= 0 ) then return nil, "zero_weight" end
	local r = rng:ProceduralRandom( x, y ) * total

	for i = 1, #scene_list do
		local scene = scene_list[ i ]
		if ( scene.prob > 0 ) then
			if ( r <= scene.prob ) then
				if ( scene.name == "" ) then return nil, "no_scene" end
				local img = deps.scene_image( biome, scene.name )
				if ( img == nil ) then
					return nil, "missing_image:" .. scene.name
				end
				local w, h = img.width, img.height

				local corners = { { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h } }
				for c = 1, 4 do
					if ( M.biome_at( corners[ c ][ 1 ], corners[ c ][ 2 ] ) ~= biome ) then
						return nil, "out_of_biome"
					end
				end

				local material = nil
				if ( scene.color_material ) then
					local keys = {}
					for k in pairs( scene.color_material ) do keys[ #keys + 1 ] = k end
					table.sort( keys, function( a, b )
						return ( tonumber( a, 16 ) or 0 ) < ( tonumber( b, 16 ) or 0 )
					end )
					for _, key in ipairs( keys ) do
						local materials = scene.color_material[ key ]
						local mrng = deps.prng_new( world_seed + ng_plus )
						mrng:SetRandomSeed( x + 11, y - 21 )
						local rr = mrng:ProceduralRandom( x + 11, y - 21 )
						local mi = math.ceil( rr * #materials ) - 1
						if ( mi < 0 ) then mi = 0 end
						if ( mi > #materials - 1 ) then mi = #materials - 1 end
						material = materials[ mi + 1 ]
					end
				end

				return {
					name = scene.name, width = w, height = h,
					x = x, y = y, material = material, biome = biome,
					-- One-shot scenes: the engine places these at most once per
					-- world. It is NOT a persistent-flag gate and no Lua/profile
					-- flag selects an alternative; see the shipped
					-- data/scripts/biomes/coalmine_alt.lua (is_unique = 1 on
					-- shrine01_alt) and the absence of any flag check there.
					is_unique = scene.is_unique == true,
				}
			end
			r = r - scene.prob
		end
	end
	return nil, "no_scene"
end

-- Which scene list a marker function requests, and the marker-relative
-- placement offset its vanilla body applies.
-- Returns scene_list | nil, dx, dy, list_name.
local function scene_list_for( biome, func, world_seed, ng_plus, x, y )
	local cfg = M.biome_config( biome )
	if ( cfg == nil ) then return nil end
	local scenes = cfg.scenes or {}
	local off = M.placement_offset( func )
	local dx = off and off.x or 0
	local dy = off and off.y or 0

	local function ret( list, name )
		return list, dx, dy, name
	end

	if ( func == "load_pixel_scene" ) then
		-- Mines has a special two-list branch; other biomes use the plain list.
		if ( biome == "coalmine" ) then
			local rng = deps.prng_new( world_seed + ng_plus )
			rng:SetRandomSeed( x, y )
			local pick = ( rng:Random( 1, 100 ) > 50 ) and "g_oiltank" or "g_pixel_scene_01"
			return ret( scenes[ pick ], pick )
		end
		return ret( scenes[ "g_pixel_scene_01" ], "g_pixel_scene_01" )
	elseif ( func == "load_pixel_scene2" ) then
		return ret( scenes[ "g_pixel_scene_02" ], "g_pixel_scene_02" )
	elseif ( func == "load_pixel_scene3" ) then
		return ret( scenes[ "g_pixel_scene_03" ], "g_pixel_scene_03" )
	elseif ( func == "load_pixel_scene4" ) then
		return ret( scenes[ "g_pixel_scene_04" ], "g_pixel_scene_04" )
	elseif ( func == "load_pixel_scene4_alt" ) then
		return ret( scenes[ "g_pixel_scene_04_alt" ], "g_pixel_scene_04_alt" )
	elseif ( func == "load_pixel_scene_alt" ) then
		return ret( scenes[ "g_pixel_scene_01_alt" ], "g_pixel_scene_01_alt" )
	elseif ( func == "load_puzzleroom" ) then
		return ret( scenes[ "g_puzzleroom" ], "g_puzzleroom" )
	elseif ( func == "load_puzzle_capsule" ) then
		return ret( scenes[ "g_puzzle_capsule" ], "g_puzzle_capsule" )
	elseif ( func == "load_puzzle_capsule_b" ) then
		return ret( scenes[ "g_puzzle_capsule_b" ], "g_puzzle_capsule_b" )
	elseif ( func == "load_acidtank_right" ) then
		return ret( scenes[ "g_acidtank_right" ], "g_acidtank_right" )
	elseif ( func == "load_acidtank_left" ) then
		return ret( scenes[ "g_acidtank_left" ], "g_acidtank_left" )
	elseif ( func == "load_gunpowderpool_01" ) then
		return ret( scenes[ "g_gunpowderpool_01" ], "g_gunpowderpool_01" )
	elseif ( func == "load_gunpowderpool_02" ) then
		return ret( scenes[ "g_gunpowderpool_02" ], "g_gunpowderpool_02" )
	elseif ( func == "load_gunpowderpool_03" ) then
		return ret( scenes[ "g_gunpowderpool_03" ], "g_gunpowderpool_03" )
	elseif ( func == "load_gunpowderpool_04" ) then
		return ret( scenes[ "g_gunpowderpool_04" ], "g_gunpowderpool_04" )
	elseif ( func == "load_oiltank" ) then
		local rng = deps.prng_new( world_seed + ng_plus )
		rng:SetRandomSeed( x, y )
		local pick = ( rng:Random( 1, 100 ) <= 50 ) and "g_oiltank" or "g_pixel_scene_01"
		return ret( scenes[ pick ], pick )
	elseif ( func == "load_oiltank_alt" ) then
		return ret( scenes[ "g_oiltank_alt" ], "g_oiltank_alt" )
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Probability gates
-- ---------------------------------------------------------------------------

-- check_wand_altar(biome, world_seed, ng_plus, x, y) -> true|false|"utility_box"|nil
function M.check_wand_altar( biome, world_seed, ng_plus, x, y )
	local cfg = M.biome_config( biome )
	if ( cfg == nil or cfg.altar == nil ) then return nil end
	local data = cfg.altar

	local rng = deps.prng_new( world_seed + ng_plus )
	if ( data.gx ~= nil and data.gy ~= nil ) then
		x = x + data.gx
		y = y + data.gy
	end

	if ( data.r0 ~= nil ) then
		local r0 = rng:ProceduralRandom( x, y )
		if ( r0 < data.r0 ) then return false end
	end

	local tx = x + ( data.xoff or 0 )
	local ty = y + ( data.yoff or 0 )
	if ( data.tx ~= nil and data.ty ~= nil ) then
		tx = x + data.tx
		ty = y + data.ty
	end

	local r = rng:ProceduralRandom( tx, ty )
	if ( data.rl ~= nil and r < data.rl ) then return false end
	if ( data.rg ~= nil and r >= data.rg ) then
		if ( data.ru ~= nil and r < data.ru ) then return "utility_box" end
		return false
	end
	return true
end

-- Wand altar scene offsets. Default is (-10, -17), overridden per biome.
function M.wand_altar_offset( biome )
	local o = deps.biome_data.wand_altar_offsets
		and deps.biome_data.wand_altar_offsets[ biome ]
	if ( o ~= nil ) then return o.x, o.y end
	return -10, -17
end

function M.is_small_altar( biome )
	local cfg = M.biome_config( biome )
	return cfg ~= nil and cfg.small_altar == true
end

-- ---------------------------------------------------------------------------
-- Wand type lotteries
-- ---------------------------------------------------------------------------

-- spawn_trapwand picks from a fixed 10-entry list (premade_1..9, level_01).
function M.trap_wand_type( world_seed, ng_plus, x, y )
	local rng = deps.prng_new( world_seed + ng_plus )
	rng:SetRandomSeed( x, y )
	local rnd = rng:Random( 1, 10 )
	local options = {
		"premade_1", "premade_2", "premade_3", "premade_4", "premade_5",
		"premade_6", "premade_7", "premade_8", "premade_9", "wand_level_01",
	}
	return options[ rnd ]
end

-- spawn_wands / spawn_wand: the biome's wand-type lottery, seeded at (x-5, y).
function M.wild_wand_type( biome, world_seed, ng_plus, x, y )
	local cfg = M.biome_config( biome )
	if ( cfg == nil or cfg.wand_lottery == nil ) then return nil end
	local data = cfg.wand_lottery
	local total = 0
	for i = 1, #data.weights do
		total = total + data.weights[ i ]
	end
	local rng = deps.prng_new( world_seed + ng_plus )
	local r = rng:ProceduralRandom( x - 5, y ) * total
	for i = 1, #data.weights do
		if ( r <= data.weights[ i ] ) then
			return data.types[ i ]
		end
		r = r - data.weights[ i ]
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Container / dispatch record emitters
-- ---------------------------------------------------------------------------
--
-- These turn a resolved vanilla dispatch into records. They are shared by the
-- terrain-level arms and by the nested-scene arms so the two can never drift.
--
-- THE LIBERAL-CONTRACT RULE (see DISCOVERY_CONTRACT.md §5.3):
--   `spawn_kind`, `generated`, `world_x/y` and `source_id` keep their MEANING.
--   The record always describes the MARKER; `outcome`/`outcome_status` say what
--   the marker actually produced. A released outcome (heart, chest) is a
--   verified object. An unresolved outcome is a POTENTIAL marker.
--
-- `extra_objects` is how a marker that loads something at a DIFFERENT position
-- reports it (the bbqbox's nested heart at +10,+10) without either lying about
-- the marker position or hiding the child.

-- Emit the record(s) for one resolved spawn_heart marker at (x, y).
--
-- `parent` (optional) describes the enclosing marker when this heart is nested:
--   { source_id = ..., object_id = ..., dx = , dy = , source_function = }
function M.emit_heart( push, marker, biome, func, base, s, world_seed, ng_plus,
	ctx, parent )
	local x, y = s.x, s.y
	local resolved = M.resolve_heart( world_seed, ng_plus, x, y, ctx )

	local sid = base .. "/heart"
	local oid = string.format( "%s/heart/%d,%d", biome, x, y )
	if ( parent ~= nil ) then
		sid = parent.source_id .. "/spawn_heart"
		oid = parent.object_id .. "/heart"
	end

	local rec = {
		source_id = sid,
		object_id = oid,
		biome = biome,
		world_x = x, world_y = y,
		spawn_kind = "heart",
		spawn_function = func,
		marker_rgb = s.color,
		-- Dispatch facts, always present.
		outcome = resolved.outcome,
		outcome_r = resolved.r,
		outcome_threshold = resolved.threshold,
		outcome_source = "data/scripts/biome_scripts.lua spawn_heart",
	}

	if ( resolved.outcome == "heart" or resolved.outcome == "chest" ) then
		-- A released object: existence is proven.
		rec.generated = true
		rec.entity_file = resolved.entity
		rec.outcome_status = "released"
		if ( resolved.outcome == "chest" ) then
			rec.chest_kind = resolved.chest_kind
			rec.branch_roll = resolved.branch_roll
			rec.chest_roll = resolved.chest_roll
			rec.deep_branch = resolved.deep_branch
			-- This is a CHEST, not a heart. The chests worker owns the type
			-- lottery and the loot; this record only proves the object.
			rec.resource_owner = "chests"
		else
			rec.resource_owner = "chests"
		end
		if ( resolved.mimic_sign ) then rec.mimic_sign = true end
	elseif ( resolved.outcome == "chest_mimic" or resolved.outcome == "chest_leggy" ) then
		-- Real entities, but NOT chests: PRD R2 says mimics are not real chests.
		rec.generated = true
		rec.entity_file = resolved.entity
		rec.outcome_status = "released"
		rec.not_a_chest = true
		rec.not_a_chest_reason = resolved.outcome == "chest_mimic"
			and "PRD R2: a mimic is not a real chest" or "leggy chest is not a real chest"
		rec.enemy_roll = resolved.enemy_roll
		rec.branch_roll = resolved.branch_roll
		if ( resolved.mimic_sign ) then rec.mimic_sign = true end
	elseif ( resolved.outcome == "nothing" ) then
		-- Definitive absence: the draw selected no object at all.
		rec.generated = false
		rec.outcome_status = "absent"
		rec.absence_proven = true
		rec.unresolved_reason = "spawn_heart drew no object (r <= 0.3); nothing was loaded"
	else
		-- Calendar-dependent or otherwise unresolvable: a POTENTIAL marker.
		rec.generated = false
		rec.outcome_status = "unresolved"
		rec.calendar_dependent = resolved.calendar_dependent == true
		rec.unresolved_reason = resolved.reason
			or "spawn_heart outcome could not be resolved"
	end

	if ( parent ~= nil ) then
		rec.parent_source_id = parent.source_id
		rec.parent_object_id = parent.object_id
		rec.nested_offset_x = parent.dx
		rec.nested_offset_y = parent.dy
		rec.nested_source_function = parent.source_function
	end

	push( rec )
	return rec, resolved
end

-- Emit the record(s) for one spawn_bbqbox marker.
--
-- Mines only (coalmine.lua). The gate and the nested heart offset are source
-- facts. The enemies are reported as context on the parent record and are NEVER
-- emitted as resources.
function M.emit_bbqbox( push, marker, biome, func, base, s, world_seed, ng_plus, ctx )
	local key = biome .. "/" .. func
	local spec = deps.biome_data.bbqbox_sources
		and deps.biome_data.bbqbox_sources[ key ]
	if ( spec == nil ) then
		push( marker( base .. "/bbqbox", "scene_marker", func, {
			world_x = s.x, world_y = s.y, marker_rgb = s.color,
		}, "no spawn_bbqbox source spec for this biome" ) )
		return
	end

	local rng = deps.prng_new( world_seed + ng_plus )
	rng:SetRandomSeed( s.x, s.y )
	local roll = rng:Random( spec.gate_min, spec.gate_max )

	local rec = {
		source_id = base .. "/bbqbox",
		object_id = string.format( "%s/bbqbox/%d,%d", biome, s.x, s.y ),
		biome = biome,
		world_x = s.x, world_y = s.y,
		-- Its OWN kind, not "scene_marker". Reason: the chests adapter treats a
		-- `scene_marker` kind as a CONCLUSIVE non-chest before it ever looks at
		-- the spawn function, so reusing that kind would make a real chest
		-- source unresolvable for the one consumer this record exists for.
		spawn_kind = "bbqbox",
		spawn_function = func,
		marker_rgb = s.color,
		outcome_source = spec.source,
		gate = "evaluated",
		gate_roll = roll,
		gate_threshold = spec.gate_le,
		gate_note = string.format( "spawn_bbqbox: Random(%d,%d) <= %d selects the "
			.. "enemy+heart branch", spec.gate_min, spec.gate_max, spec.gate_le ),
		-- Enemies are context only; `resource = false` is explicit so no
		-- consumer can mistake them for loot.
		enemy_context = {},
		no_resource_score = true,
	}

	for i = 1, #spec.enemy_offsets do
		local off = spec.enemy_offsets[ i ]
		rec.enemy_context[ #rec.enemy_context + 1 ] = {
			function_name = "spawn_big_enemies",
			world_x = s.x + off.dx,
			world_y = s.y + off.dy,
			dx = off.dx, dy = off.dy,
			resource = false,
			note = "enemy spawn, not a resource",
		}
	end

	if ( roll <= spec.gate_le ) then
		-- `generated` describes what THIS marker loads: enemies (proven) and a
		-- nested spawn_heart whose own outcome is resolved below.
		rec.generated = true
		rec.outcome = "enemy_branch"
		rec.enemies_generated = true

		-- The nested spawn_heart is resolved here but NOT emitted as a separate
		-- top-level record.
		--
		-- Why: a bbqbox yields exactly ONE chest. A consumer that also models
		-- `spawn_bbqbox` natively (the chests adapter does) would resolve the
		-- parent AND a separate child record at the same coordinates into two
		-- chests with different object_ids, and object-identity de-duplication
		-- could not collapse them. Measured before this fix: seed 349 produced
		-- two chest entries at (2015, 517) from one bbqbox.
		--
		-- Nothing is lost: the child's full dispatch resolution is nested below,
		-- so a consumer that does NOT model bbqbox can still read it.
		local heart_spot = {
			x = s.x + spec.nested_heart_dx,
			y = s.y + spec.nested_heart_dy,
			color = s.color,
		}
		local child_holder = {}
		local function child_push( r ) child_holder[ #child_holder + 1 ] = r end
		M.emit_heart( child_push, marker, biome, "spawn_heart", base,
			heart_spot, world_seed, ng_plus, ctx, {
				source_id = rec.source_id,
				object_id = rec.object_id,
				dx = spec.nested_heart_dx,
				dy = spec.nested_heart_dy,
				source_function = func,
			} )

		local child = child_holder[ 1 ]
		rec.nested_heart = {
			world_x = heart_spot.x,
			world_y = heart_spot.y,
			dx = spec.nested_heart_dx,
			dy = spec.nested_heart_dy,
			function_name = "spawn_heart",
			source = spec.source .. " -> spawn_heart(x+10, y+10)",
			object_id = child.object_id,
			outcome = child.outcome,
			outcome_r = child.outcome_r,
			outcome_threshold = child.outcome_threshold,
			generated = child.generated == true,
			entity_file = child.entity_file,
			chest_kind = child.chest_kind,
			absence_proven = child.absence_proven == true,
			not_a_chest = child.not_a_chest,
			calendar_dependent = child.calendar_dependent,
			unresolved_reason = child.unresolved_reason,
			resource_owner = child.resource_owner,
			-- Explicit, so no consumer counts this source twice.
			separate_record = false,
			dedup_note = "a bbqbox yields one chest; count the parent record once",
		}
		push( rec )
		return
	end

	-- else branch: a urine jar and a weak shotgunner, no heart, no chest.
	rec.generated = true
	rec.outcome = "else_branch"
	rec.else_objects = {}
	for i = 1, #spec.else_entities do
		local e = spec.else_entities[ i ]
		rec.else_objects[ #rec.else_objects + 1 ] = {
			entity = e.entity,
			world_x = s.x + e.dx,
			world_y = s.y + e.dy,
			dx = e.dx, dy = e.dy,
			resource = false,
		}
	end
	push( rec )
end

-- Emit the record(s) for one resolved spawn_potions marker.
--
-- The wrapper decides mimic vs list; the list decides the container. Only a
-- potion or powder-pouch band becomes a container record; every other band is a
-- non-container object and is reported as such (never as an R5 resource).
function M.emit_container( push, marker, biome, func, base, s, world_seed, ng_plus,
	ctx, extra )
	local x, y = s.x, s.y
	local resolved = M.resolve_potions( biome, world_seed, ng_plus, x, y, ctx )

	local rec = {
		source_id = base .. "/potion",
		object_id = string.format( "%s/container/%d,%d", biome, x, y ),
		biome = biome,
		world_x = x, world_y = y,
		spawn_kind = "potion",
		spawn_function = func,
		marker_rgb = s.color,
		outcome = resolved.outcome,
		outcome_source = "data/scripts/biome_scripts.lua spawn_potions -> "
			.. "spawn_from_list",
		map_roll = resolved.map_roll,
		container_kind = resolved.kind,
	}
	if ( extra ) then
		for k, v in pairs( extra ) do rec[ k ] = v end
	end

	if ( resolved.outcome == "container" ) then
		-- A real container object. The ENTITY LOAD POINT is proven; whether the
		-- container's init() sees that transform or a sprite-offset variant is
		-- NOT resolved (see DISCOVERY_CONTRACT §7 / chests COORDINATE_HANDOFF).
		rec.generated = true
		rec.entity_file = resolved.entity
		rec.load_x = resolved.load_x
		rec.load_y = resolved.load_y
		rec.offset_x = resolved.offset_x
		rec.offset_y = resolved.offset_y
		rec.list_name = resolved.list_name
		rec.list_roll = resolved.roll
		rec.list_band = { min = resolved.value_min, max = resolved.value_max }
		rec.coordinate_frame = "entity_load_point"
		rec.init_seed_frame = "unresolved"
		rec.coordinate_confidence = "load_point_proven_init_seed_unresolved"
		rec.container_owner = "collectibles"
		rec.not_scored_reason = "content, material and R5 scoring belong to the "
			.. "collectibles provider"
		if ( resolved.requires_flag ~= nil ) then
			rec.requires_flag = resolved.requires_flag
			rec.requires_flag_state = "set"
		end
	elseif ( resolved.outcome == "potion_mimic" ) then
		-- A real entity, but not a container: PRD R5 does not score it.
		rec.generated = true
		rec.entity_file = resolved.entity
		rec.outcome_status = "released"
		rec.not_a_container = true
		rec.not_scored_reason = "potion_mimic is an enemy, not a potion"
	elseif ( resolved.outcome == "flag_blocked" ) then
		-- Vanilla returns without loading anything when the persistent flag is
		-- unset. Definitive absence.
		rec.generated = false
		rec.outcome_status = "absent"
		rec.absence_proven = true
		rec.requires_flag = resolved.requires_flag
		rec.unresolved_reason = resolved.reason
	elseif ( resolved.outcome == "other" ) then
		-- A real object from the same list, but not a container this build
		-- scores (gold orb, broken wand, eggs, runestone, die, ...).
		rec.generated = true
		rec.entity_file = resolved.entity
		rec.load_x = resolved.load_x
		rec.load_y = resolved.load_y
		rec.offset_x = resolved.offset_x
		rec.offset_y = resolved.offset_y
		rec.list_name = resolved.list_name
		rec.list_roll = resolved.roll
		rec.not_a_container = true
		rec.not_scored_reason = "list band '" .. tostring( resolved.kind )
			.. "' is not a potion or powder pouch"
	else
		-- Unresolved (unknown flag state) or no band matched: a POTENTIAL
		-- marker, never an invented container.
		rec.generated = false
		rec.outcome_status = "unresolved"
		rec.unresolved_reason = resolved.reason
			or "spawn_potions outcome could not be resolved"
		if ( resolved.requires_flag ~= nil ) then
			rec.requires_flag = resolved.requires_flag
		end
	end

	push( rec )
	return rec, resolved
end


-- Identity of a physical scene placement. Markers belonging to one placement
-- share it; the scene and each entity inside it remain distinct objects.
function M.scene_object_id( biome, scene_name, scene_x, scene_y )
	return string.format( "%s/scene/%s/%d,%d", biome, scene_name, scene_x, scene_y )
end

-- Every record carries:
--   source_id     stable id of the marker that produced this record
--   object_id     identity of the PHYSICAL object (see file header)
--   biome         exact biome key
--   world_x/y     world coordinates in the same frame the game seeds from
--   frame         "world" (the frame of world_x/world_y)
--   spawn_kind    what this is (see DISCOVERY_CONTRACT.md)
--   spawn_function  the registered generator function name
--   generated     true = verified object; false = potential marker
--   marker_rgb    the 24-bit spawn-marker colour this came from
--   entity_file / wand_type / scene_name / scene_x,y as applicable
--   marker_offset_x/y  pixel offset of the marker inside its scene bitmap
--   gate / gate_roll / gate_threshold   when a probability gate was evaluated
--   unresolved_reason  when generated == false
--
-- `ctx` (5th argument, optional) supplies the frozen generation conditions a
-- vanilla branch reads: `{ calendar = {...}, persistent_flags = {...},
-- is_flag_set = function(flag) -> bool }`. It is per-call state, never module
-- state, and it never reads the live game clock or save.
function M.scan_layer( layer, biome, world_seed, ng_plus, ctx )
	ng_plus = ng_plus or 0
	local cfg = M.biome_config( biome )
	if ( cfg == nil ) then
		return nil, "unknown biome " .. tostring( biome )
	end

	local spawns = M.prescan_spawn_functions( layer, biome )
	local table_ = cfg.spawns

	local records = {}
	local scene_markers = {}
	local trap_wands = {}
	local wild_wands = {}
	local wand_altars = {}
	local potential = {}
	local scenes_placed = {}
	local by_kind = {}
	-- One-shot scenes already placed, keyed by scene name (engine `is_unique`).
	local unique_placed = {}

	local function push( rec )
		if ( rec.object_id == nil ) then rec.object_id = rec.source_id end
		if ( rec.frame == nil ) then rec.frame = "world" end
		records[ #records + 1 ] = rec
		by_kind[ rec.spawn_kind ] = ( by_kind[ rec.spawn_kind ] or 0 ) + 1
		if ( rec.generated ~= true ) then
			potential[ #potential + 1 ] = rec
		end
	end

	local function marker( sid, kind, func, extra, reason )
		local rec = {
			source_id = sid, biome = biome,
			spawn_kind = kind, spawn_function = func,
			generated = false,
			unresolved_reason = reason,
		}
		if ( extra ) then
			for k, v in pairs( extra ) do rec[ k ] = v end
		end
		return rec
	end

	-- Emit the placement record of a scene whose NAME is on the tracked list.
	-- This is how a puzzle whose bitmap carries no registered marker (all three
	-- Coal Pits puzzlerooms, the meditation cube) becomes visible at all.
	--
	-- Coordinate fields, all in the world frame:
	--   world_x/y      the terrain MARKER that requested the scene
	--   scene_x/y      where the scene bitmap was placed
	--   placement_dx/dy  vanilla offset applied to the marker (scene - marker)
	--   marker_offset_x/y  how far the marker sits from the scene origin
	--                      (marker - scene), the same direction the inner
	--                      marker offsets use
	local function report_tracked_scene( placed, func, marker_x, marker_y, extra )
		if ( not M.is_tracked_scene( placed.name ) ) then return end
		local rec = {
			source_id = string.format( "%s/%d,%d/scene_placement/%s",
				biome, placed.x, placed.y, placed.name ),
			object_id = M.scene_object_id( biome, placed.name, placed.x, placed.y ),
			biome = biome,
			world_x = marker_x, world_y = marker_y,
			spawn_kind = "pixel_scene", generated = true,
			spawn_function = func,
			scene_name = placed.name,
			scene_x = placed.x, scene_y = placed.y,
			scene_width = placed.width, scene_height = placed.height,
			placement_dx = placed.x - marker_x,
			placement_dy = placed.y - marker_y,
			marker_offset_x = marker_x - placed.x,
			marker_offset_y = marker_y - placed.y,
			material = placed.material,
		}
		if ( extra ) then
			for k, v in pairs( extra ) do rec[ k ] = v end
		end
		scenes_placed[ #scenes_placed + 1 ] = rec
		push( rec )
	end

	-- An altar placed inside another pixel scene is still a new pixel scene.
	-- Its handlers use ITS center/bitmap, never the parent's coordinates. Both
	-- direct and nested altar content share these physical scene/entity IDs.
	local function scan_altar_contents(placement,kind,source_biome)
		local img=deps.scene_image("general",placement.scene_name)
			or deps.scene_image(source_biome,placement.scene_name)
		if not img then
			push(marker(placement.source_id.."/missing_bitmap","scene_marker",placement.spawn_function,
				{world_x=placement.scene_x,world_y=placement.scene_y},"placed altar bitmap unavailable"))
			return
		end
		local target,markers,handlers=M.scene_dispatch(img,placement.scene_x,placement.scene_y,source_biome)
		for _,mk in ipairs(markers)do
			local fn=handlers[mk.spawn_function_index]
			if fn and fn.active then
				local x,y=placement.scene_x+mk.x,placement.scene_y+mk.y
				local sid=string.format("%s/%d,%d/scene/%s/%d,%d",target,placement.scene_x,placement.scene_y,placement.scene_name,mk.x,mk.y)
				local extra={object_id=string.format("%s/entity/%s/%d,%d",placement.object_id,fn.func,mk.x,mk.y),
					world_x=x,world_y=y,scene_name=placement.scene_name,scene_x=placement.scene_x,scene_y=placement.scene_y,
					marker_offset_x=mk.x,marker_offset_y=mk.y,marker_rgb=mk.color,
					entrance_source_id=placement.source_id,entrance_object_id=placement.object_id,
					parent_scene_name=placement.parent_scene_name,parent_scene_x=placement.parent_scene_x,parent_scene_y=placement.parent_scene_y}
				if kind=="potion" and (fn.func=="spawn_potions" or fn.func=="spawn_potion")then
					M.emit_container(push,marker,target,fn.func,sid,{x=x,y=y,color=mk.color},world_seed,ng_plus,ctx,extra)
				elseif kind=="wand" and (fn.func=="spawn_wands" or fn.func=="spawn_wand")then
					local typ=M.wild_wand_type(target,world_seed,ng_plus,x,y)
					local rec={source_id=sid.."/altar_wand",biome=target,spawn_kind="altar_wand",spawn_function=fn.func,
						generated=typ~=nil,wand_type=typ,seed_x=x-5,seed_y=y,gate="passed"}
					for k,v in pairs(extra)do rec[k]=v end
					if typ then wild_wands[#wild_wands+1]=rec else rec.unresolved_reason="no wand lottery for altar handler biome"end
					push(rec)
				end
			end
		end
	end
	local function emit_prop_container(source_biome,func,sid,x,y,extra)
		local result=prop_containers.resolve(source_biome,func,world_seed,x,y,ng_plus)
		if not result then return end
		local rec={source_id=sid.."/prop_container",object_id=sid,biome=source_biome,world_x=x,world_y=y,
			spawn_function=func,spawn_kind=result.generated and "potion"or "gate_blocked",
			outcome_source=prop_containers.SOURCE,coordinate_frame="entity_load_point",init_seed_frame="unresolved",
			coordinate_confidence="load_point_proven_init_seed_unresolved",container_owner="collectibles"}
		for k,v in pairs(result)do rec[k]=v end
		for k,v in pairs(extra or {})do rec[k]=v end
		if not result.generated then rec.unresolved_reason="prop lottery selected empty band; no entity loaded"end
		push(rec)
	end

	for i = 1, #spawns do
		local s = spawns[ i ]
		local entry = table_[ s.spawn_function_index ]
		if ( entry ~= nil and entry.active and M.passes_spawn_chunk_gate(s.x,s.y)
			and M.passes_spawn_biome_gate(s.x,s.y) ) then
			local func = entry.func
			local base = string.format( "%s/%d,%d", biome, s.x, s.y )

			-- ---- direct (non-scene) spawn functions -----------------------
			if ( func == "spawn_trapwand" ) then
				local wand_type = M.trap_wand_type( world_seed, ng_plus, s.x, s.y )
				local rec = {
					source_id = base .. "/trap_wand",
					biome = biome, world_x = s.x, world_y = s.y,
					spawn_kind = "trap_wand", generated = true,
					spawn_function = func, wand_type = wand_type,
					wand_entity = "data/entities/items/wand_level_01.xml",
					marker_rgb = s.color,
				}
				trap_wands[ #trap_wands + 1 ] = rec
				push( rec )
			elseif ( func == "spawn_wands" or func == "spawn_wand" ) then
				-- A wild wand drop. Content comes from the biome lottery seeded
				-- at (x - 5, y); this is a VERIFIED generated wand.
				local wand_type = M.wild_wand_type( biome, world_seed, ng_plus, s.x, s.y )
				local rec = {
					source_id = base .. "/wild_wand",
					biome = biome, world_x = s.x, world_y = s.y,
					spawn_kind = "wild_wand", generated = wand_type ~= nil,
					spawn_function = func, wand_type = wand_type,
					seed_x = s.x - 5, seed_y = s.y,
					marker_rgb = s.color,
				}
				if ( wand_type == nil ) then
					rec.unresolved_reason = "no wand type lottery configured for biome"
				else
					wild_wands[ #wild_wands + 1 ] = rec
				end
				push( rec )
			elseif ( func == "spawn_items" or func == "spawn_wand_altar" ) then
				-- NOT a plain item: this is the WAND ALTAR path, gated by
				-- checkWandAltar. If the gate passes, the altar pixel scene is
				-- placed and it contains a spawn_wands marker.
				local gate = M.check_wand_altar( biome, world_seed, ng_plus, s.x, s.y )
				if ( gate == true ) then
					local ox, oy = M.wand_altar_offset( biome )
					local scene_name = M.is_small_altar( biome ) and "wand_altar_vault" or "wand_altar"
					local scene_x, scene_y = s.x + ox, s.y + oy
					local rec = {
						source_id = base .. "/wand_altar",
						biome = biome, world_x = s.x, world_y = s.y,
						spawn_kind = "wand_altar", generated = true,
						spawn_function = func,
						scene_name = scene_name,
						scene_x = scene_x, scene_y = scene_y,
						gate = "passed",
						marker_rgb = s.color,
					}
					wand_altars[ #wand_altars + 1 ] = rec
					push( rec )

					-- The altar scene itself carries the wand.
					local img = deps.scene_image( "general", scene_name )
					if ( img ~= nil ) then
						local biome,markers,table_ = M.scene_dispatch(img,scene_x,scene_y,biome)
						for m = 1, #markers do
							local mk = markers[ m ]
							local mx = scene_x + mk.x
							local my = scene_y + mk.y
							local fn = table_[ mk.spawn_function_index ]
							if ( fn ~= nil and fn.active
								and ( fn.func == "spawn_wands" or fn.func == "spawn_wand" ) ) then
								local wand_type = M.wild_wand_type( biome, world_seed, ng_plus, mx, my )
								local wrec = {
									source_id = string.format( "%s/%d,%d/altar_wand", biome, mx, my ),
									object_id = string.format( "%s/entity/%s/%d,%d",
										M.scene_object_id( biome, scene_name, scene_x, scene_y ),
										fn.func, mk.x, mk.y ),
									biome = biome, world_x = mx, world_y = my,
									spawn_kind = "altar_wand", generated = wand_type ~= nil,
									spawn_function = fn.func, wand_type = wand_type,
									scene_name = scene_name,
									scene_x = scene_x, scene_y = scene_y,
									marker_offset_x = mk.x, marker_offset_y = mk.y,
									marker_rgb = mk.color,
									seed_x = mx - 5, seed_y = my,
									gate = "passed",
								}
								if ( wand_type == nil ) then
									wrec.unresolved_reason = "no wand type lottery configured for biome"
								else
									wild_wands[ #wild_wands + 1 ] = wrec
								end
								push( wrec )
								scene_markers[ #scene_markers + 1 ] = wrec
							end
						end
					end
				elseif ( gate == "utility_box" ) then
					push( marker( base .. "/utility_box", "utility_box", func, {
						world_x = s.x, world_y = s.y, marker_rgb = s.color,
					}, "utility box, not a wand altar" ) )
				elseif ( gate == false ) then
					-- The gate rejected it: NO altar, so emit nothing. This is the
					-- important negative case: a `spawn_items` marker is not a wand.
				else
					push( marker( base .. "/wand_altar", "wand_altar", func, {
						world_x = s.x, world_y = s.y, marker_rgb = s.color,
					}, "wand altar gate could not be evaluated for this biome" ) )
				end
			elseif ( func == "spawn_potion_altar" ) then
				-- spawn_potion_altar is a GATED pixel scene: the gate and the
				-- placement offset are vanilla facts (fungicave overrides both),
				-- so they are evaluated here. The container inside the scene is
				-- NOT resolved here: the scene's own spawn_potions marker is
				-- emitted below and resolves against `spawn_from_list`.
				local passed, roll_or_reason, spec = M.evaluate_potion_altar_gate(
					biome, world_seed, ng_plus, s.x, s.y )
				local extra = {
					world_x = s.x, world_y = s.y,
					marker_rgb = s.color,
					gate = passed == true and "passed"
						or ( passed == false and "failed" or "unevaluated" ),
					gate_roll = type( roll_or_reason ) == "number" and roll_or_reason or nil,
					gate_threshold = spec and spec.gate_threshold or nil,
					gate_function = spec and spec.source or nil,
					source_function = "spawn_potion_altar",
				}
				if ( passed == true ) then
					local scene_x = s.x + ( spec.scene_dx or 0 )
					local scene_y = s.y + ( spec.scene_dy or 0 )
					local rec = {
						source_id = base .. "/" .. spec.scene_name,
						object_id = M.scene_object_id( biome, spec.scene_name,
							scene_x, scene_y ),
						biome = biome,
						spawn_kind = "pixel_scene", generated = true,
						spawn_function = func,
						scene_name = spec.scene_name,
						scene_x = scene_x, scene_y = scene_y,
						placement_dx = spec.scene_dx,
						placement_dy = spec.scene_dy,
					}
					for k, v in pairs( extra ) do rec[ k ] = v end
					scenes_placed[ #scenes_placed + 1 ] = rec
					push( rec )

					-- The placed potion-altar bitmap carries its own
					-- `spawn_potions` marker (0xbca0f0 at (10,11) in the vendored
					-- general/potion_altar.png). Scan it here: the container lives
					-- INSIDE the scene, so skipping this would silently lose every
					-- R5 potion/pouch that a potion altar produces.
					local img = deps.scene_image( "general", spec.scene_name )
					if ( img == nil ) then
						img = deps.scene_image( biome, spec.scene_name )
					end
					if ( img ~= nil ) then
						local biome,markers,table_ = M.scene_dispatch(img,scene_x,scene_y,biome)
						for m = 1, #markers do
							local mk = markers[ m ]
							local fn = table_[ mk.spawn_function_index ]
							if ( fn ~= nil and fn.active
								and ( fn.func == "spawn_potions"
									or fn.func == "spawn_potion" ) ) then
								local mx = scene_x + mk.x
								local my = scene_y + mk.y
								local sid = string.format( "%s/%d,%d/scene/%s/%d,%d",
									biome, scene_x, scene_y, spec.scene_name, mk.x, mk.y )
								M.emit_container( push, marker, biome, fn.func, sid,
									{ x = mx, y = my, color = mk.color }, world_seed,
									ng_plus, ctx, {
										object_id = string.format( "%s/entity/%s/%d,%d",
											rec.object_id, fn.func, mk.x, mk.y ),
										scene_name = spec.scene_name,
										scene_x = scene_x, scene_y = scene_y,
										marker_offset_x = mk.x, marker_offset_y = mk.y,
										marker_rgb = mk.color,
										entrance_source_id = rec.source_id,
										entrance_object_id = rec.object_id,
									} )
							end
						end
					end
				elseif ( passed == false ) then
					-- Definitive absence: the gate ran and rejected the scene.
					extra.absence_proven = true
					push( marker( base .. "/potion_altar", "gate_blocked", func, extra,
						string.format(
							"spawn_potion_altar gate failed: ProceduralRandom(%d,%d)="
								.. "%s is not > %s, so no potion altar was placed",
							s.x, s.y, tostring( roll_or_reason ),
							tostring( spec and spec.gate_threshold ) ) ) )
				else
					push( marker( base .. "/potion_altar", "potion_altar", func, extra,
						"potion altar gate could not be evaluated: "
							.. tostring( roll_or_reason ) ) )
				end
			elseif prop_containers.handles(biome,func)then
				emit_prop_container(biome,func,base,s.x,s.y,{marker_rgb=s.color})
			elseif ( func == "spawn_chest" ) then
				push( marker( base .. "/chest", "chest", func, {
					world_x = s.x, world_y = s.y, marker_rgb = s.color,
				}, "chest content requires the chests worker's content generator" ) )
			elseif ( func == "spawn_heart" ) then
				-- spawn_heart is a DISPATCH. Resolve which object (if any) it
				-- really loads instead of asserting a heart.
				M.emit_heart( push, marker, biome, func, base, s, world_seed,
					ng_plus, ctx, nil )
			elseif ( func == "spawn_bbqbox" ) then
				-- spawn_bbqbox gates on Random(1,100) <= 99 and then nests
				-- spawn_heart at (+10, +10). The enemies it also spawns are
				-- CONTEXT, never resources and never scored.
				M.emit_bbqbox( push, marker, biome, func, base, s, world_seed,
					ng_plus, ctx )
			elseif ( func == "spawn_shopitem" ) then
				push( marker( base .. "/shop_item", "shop_item", func, {
					world_x = s.x, world_y = s.y, marker_rgb = s.color,
				}, "shop slot content requires the shop/spell provider" ) )
			elseif ( func == "load_altar" ) then
				-- Vanilla LoadPixelScene( altar.png, ..., x-92, y-96 ) plus
				-- EntityLoad( altar.xml, x, y-32 ). Upstream models the bitmap as
				-- the shared `trailer_altar` scene; record both the placement
				-- origin and the marker offset so the frame is unambiguous.
				push( {
					source_id = base .. "/trailer_altar",
					object_id = M.scene_object_id( biome, "trailer_altar", s.x - 92, s.y - 96 ),
					biome = biome, world_x = s.x, world_y = s.y,
					spawn_kind = "pixel_scene", generated = true,
					spawn_function = func, scene_name = "trailer_altar",
					scene_x = s.x - 92, scene_y = s.y - 96,
					marker_rgb = s.color,
				} )
			end

			-- ---- deterministic probability gates -------------------------
			local gate_spec = M.gate_spec( biome, func )
			if ( gate_spec ~= nil ) then
				local passed, roll_or_reason = M.evaluate_gate( biome, func,
					world_seed, ng_plus, s.x, s.y )
				local gate_extra = {
					world_x = s.x, world_y = s.y,
					marker_rgb = s.color,
					gate = passed == true and "passed" or ( passed == false and "failed" or "unevaluated" ),
					gate_roll = type( roll_or_reason ) == "number" and roll_or_reason or nil,
					gate_threshold = gate_spec.threshold,
					gate_function = gate_spec.source,
				}
				if ( passed == true ) then
					local scene_x = s.x + ( gate_spec.scene_dx or 0 )
					local scene_y = s.y + ( gate_spec.scene_dy or 0 )
					gate_extra.scene_name = gate_spec.scene_name
					gate_extra.scene_x = scene_x
					gate_extra.scene_y = scene_y
					local rec = {
						source_id = base .. "/" .. gate_spec.scene_name,
						object_id = M.scene_object_id( biome, gate_spec.scene_name,
							scene_x, scene_y ),
						biome = biome,
						spawn_kind = "pixel_scene", generated = true,
						spawn_function = func,
					}
					for k, v in pairs( gate_extra ) do rec[ k ] = v end
					scenes_placed[ #scenes_placed + 1 ] = rec
					push( rec )

					-- The gated entity that shares the gate.
					push( {
						source_id = base .. "/" .. gate_spec.scene_name .. "/entity",
						object_id = M.scene_object_id( biome, gate_spec.scene_name,
							scene_x, scene_y ) .. "/entity",
						biome = biome,
						world_x = s.x + ( gate_spec.entity_dx or 0 ),
						world_y = s.y + ( gate_spec.entity_dy or 0 ),
						spawn_kind = "scene_marker", generated = true,
						spawn_function = func,
						entity_file = gate_spec.entity,
						scene_name = gate_spec.scene_name,
						scene_x = scene_x, scene_y = scene_y,
						marker_rgb = s.color,
						gate = "passed",
						gate_roll = type( roll_or_reason ) == "number" and roll_or_reason or nil,
						gate_threshold = gate_spec.threshold,
					} )
				elseif ( passed == false ) then
					-- A failed gate is a DEFINITIVE non-existence, not an
					-- unknown. Emit it as `gate_blocked` with `absence_proven`
					-- so no consumer can mistake silence for "unresolved", and
					-- no consumer can mistake it for an object either.
					gate_extra.absence_proven = true
					push( marker( base .. "/" .. tostring( gate_spec.scene_name ),
						"gate_blocked", func, gate_extra,
						string.format(
							"%s gate failed: Random(%d,%d)=%s is not > %d at (%d, %d), "
								.. "so the object does not exist",
							tostring( gate_spec.scene_name ),
							gate_spec.random_min, gate_spec.random_max,
							tostring( roll_or_reason ), gate_spec.threshold, s.x, s.y ) ) )
				else
					push( marker( base .. "/" .. tostring( gate_spec.scene_name ),
						"scene_marker", func, gate_extra,
						"probability gate could not be evaluated: "
							.. tostring( roll_or_reason ) ) )
				end
			end

			-- ---- nested pixel scenes -------------------------------------
			local scenes, dx, dy, list_name = scene_list_for( biome, func,
				world_seed, ng_plus, s.x, s.y )
			if ( scenes ~= nil ) then
				local scene_x = s.x + dx
				local scene_y = s.y + dy
				local placed, why = M.load_random_pixel_scene( biome, scenes,
					world_seed, ng_plus, scene_x, scene_y )
				-- The game places an `is_unique` scene at most once per world. The
				-- engine enforces that in C++, so we model it by suppressing a
				-- repeat pick. This is a one-shot rule, NOT a persistent flag.
				if ( placed ~= nil and placed.is_unique ) then
					if ( unique_placed[ placed.name ] ) then
						placed, why = nil, "unique_already_placed"
					else
						unique_placed[ placed.name ] = true
					end
				end

				if ( placed ~= nil ) then
					report_tracked_scene( placed, func, s.x, s.y, {
						marker_rgb = s.color,
						scene_list = list_name,
					} )

					local img = deps.scene_image( biome, placed.name )
					if ( img ~= nil ) then
						local biome,markers,table_ = M.scene_dispatch(img,placed.x,placed.y,biome)
						for m = 1, #markers do
							local mk = markers[ m ]
							local mx = placed.x + mk.x
							local my = placed.y + mk.y
							local fn = table_[ mk.spawn_function_index ]
							if ( fn ~= nil and fn.active ) then
								local sid = string.format( "%s/%d,%d/scene/%s/%d,%d",
									biome, placed.x, placed.y, placed.name, mk.x, mk.y )
								local scene_id = M.scene_object_id( biome, placed.name,
									placed.x, placed.y )
								local object_id = string.format( "%s/entity/%s/%d,%d",
									scene_id, fn.func, mk.x, mk.y )
								local scene_extra = {
									object_id = object_id,
									world_x = mx, world_y = my,
									scene_name = placed.name,
									scene_x = placed.x, scene_y = placed.y,
									marker_offset_x = mk.x, marker_offset_y = mk.y,
									marker_rgb = mk.color,
									material = placed.material,
								}
								-- Existence proof: the vanilla body of THIS
								-- function unconditionally loads the entity.
								local proof = M.existence_proven( biome, fn.func )
								local entity_file = proof and proof.entity or nil

								if ( fn.func == "spawn_trapwand" ) then
									local wand_type = M.trap_wand_type( world_seed, ng_plus, mx, my )
									local rec = {
										source_id = sid .. "/trap_wand",
										biome = biome, world_x = mx, world_y = my,
										spawn_kind = "trap_wand", generated = true,
										spawn_function = fn.func, wand_type = wand_type,
										scene_name = placed.name,
										scene_x = placed.x, scene_y = placed.y,
										marker_rgb = mk.color,
										object_id = object_id,
									}
									trap_wands[ #trap_wands + 1 ] = rec
									push( rec )
								elseif ( fn.func == "spawn_wands" or fn.func == "spawn_wand" ) then
									local wand_type = M.wild_wand_type( biome, world_seed, ng_plus, mx, my )
									local rec = {
										source_id = sid .. "/scene_wand",
										biome = biome, world_x = mx, world_y = my,
										spawn_kind = "scene_wand", generated = wand_type ~= nil,
										spawn_function = fn.func, wand_type = wand_type,
										scene_name = placed.name,
										scene_x = placed.x, scene_y = placed.y,
										marker_rgb = mk.color,
										seed_x = mx - 5, seed_y = my,
										object_id = object_id,
									}
									-- A wand drop with no content lottery cannot
									-- be claimed as a generated wand.
									if ( wand_type == nil ) then
										rec.unresolved_reason = "no wand type lottery configured for biome"
									else
										wild_wands[ #wild_wands + 1 ] = rec
									end
									push( rec )
								elseif prop_containers.handles(biome,fn.func)then
									emit_prop_container(biome,fn.func,sid,mx,my,scene_extra)
								elseif ( fn.func == "spawn_chest" ) then
									push( marker( sid .. "/chest", "chest", fn.func, scene_extra,
										"chest content requires the chests worker's content generator" ) )
								elseif ( fn.func == "spawn_potions" or fn.func == "spawn_potion" ) then
									-- Resolve the container dispatch: the scene marker
									-- sits at a proven position and the list band
									-- decides which entity (if any) is loaded.
									M.emit_container( push, marker, biome, fn.func, sid,
										{ x = mx, y = my, color = mk.color }, world_seed,
										ng_plus, ctx, scene_extra )
								elseif ( fn.func == "spawn_potion_altar" ) then
									-- A potion altar nested inside a scene: gate it the
									-- same way the terrain arm does.
									local passed, roll_or_reason, spec =
										M.evaluate_potion_altar_gate( biome, world_seed,
											ng_plus, mx, my )
									local extra = {}
									for k, v in pairs( scene_extra ) do extra[ k ] = v end
									extra.gate = passed == true and "passed"
										or ( passed == false and "failed" or "unevaluated" )
									extra.gate_roll = type( roll_or_reason ) == "number"
										and roll_or_reason or nil
									extra.gate_threshold = spec and spec.gate_threshold or nil
									if ( passed == true ) then
										local sx = mx + ( spec.scene_dx or 0 )
										local sy = my + ( spec.scene_dy or 0 )
										local rec = {
											source_id = sid .. "/" .. spec.scene_name,
											object_id = M.scene_object_id( biome,
												spec.scene_name, sx, sy ),
											biome = biome,
											spawn_kind = "pixel_scene", generated = true,
											spawn_function = fn.func,
											scene_name = spec.scene_name,
											scene_x = sx, scene_y = sy,
											placement_dx = spec.scene_dx,
											placement_dy = spec.scene_dy,
											world_x=mx,world_y=my,
											marker_offset_x=mx-sx,marker_offset_y=my-sy,
											parent_scene_name=placed.name,parent_scene_x=placed.x,parent_scene_y=placed.y,
										}
										for k,v in pairs(extra)do if rec[k]==nil then rec[k]=v end end
										scenes_placed[ #scenes_placed + 1 ] = rec
										push( rec )
										scan_altar_contents(rec,"potion",biome)
									elseif ( passed == false ) then
										extra.absence_proven = true
										push( marker( sid .. "/potion_altar", "gate_blocked",
											fn.func, extra,
											"nested spawn_potion_altar gate failed: "
												.. tostring( roll_or_reason ) ) )
									else
										push( marker( sid .. "/potion_altar", "potion_altar",
											fn.func, extra,
											"nested potion altar gate could not be evaluated: "
												.. tostring( roll_or_reason ) ) )
									end
								elseif ( fn.func == "spawn_heart" ) then
									M.emit_heart( push, marker, biome, fn.func, sid,
										{ x = mx, y = my, color = mk.color }, world_seed,
										ng_plus, ctx, nil )
								elseif ( fn.func == "spawn_bbqbox" ) then
									M.emit_bbqbox( push, marker, biome, fn.func, sid,
										{ x = mx, y = my, color = mk.color }, world_seed,
										ng_plus, ctx )
								elseif ( fn.func == "spawn_shopitem" ) then
									push( marker( sid .. "/shop_item", "shop_item", fn.func, scene_extra,
										"shop slot content requires the shop/spell provider" ) )
								elseif ( entity_file ~= nil ) then
									-- The vanilla function unconditionally loads this
									-- entity: existence is proven, content is not.
									local rec = {
										source_id = sid .. "/" .. fn.func,
										biome = biome,
										spawn_kind = "scene_marker", generated = true,
										spawn_function = fn.func,
										entity_file = entity_file,
									}
									for k, v in pairs( scene_extra ) do rec[ k ] = v end
									if ( proof.extra ) then
										local extra_entities = {}
										for e = 1, #proof.extra do
											local spec = proof.extra[ e ]
											extra_entities[ e ] = {
												entity = spec.entity,
												world_x = mx + ( spec.dx or 0 ),
												world_y = my + ( spec.dy or 0 ),
												dx = spec.dx or 0, dy = spec.dy or 0,
												source = spec.source,
											}
										end
										rec.extra_entities = extra_entities
									end
									rec.existence = "proven"
									rec.existence_source = proof.source
									push( rec )
								elseif ( fn.func == "spawn_wand_altar" or fn.func == "spawn_items" ) then
									local gate=M.check_wand_altar(biome,world_seed,ng_plus,mx,my)
									if gate==true then
										local dx,dy=M.wand_altar_offset(biome)
										local name=M.is_small_altar(biome)and "wand_altar_vault"or "wand_altar"
										local sx,sy=mx+dx,my+dy
										local rec={source_id=sid.."/wand_altar",object_id=M.scene_object_id(biome,name,sx,sy),
											biome=biome,world_x=mx,world_y=my,spawn_kind="wand_altar",spawn_function=fn.func,
											generated=true,gate="passed",scene_name=name,scene_x=sx,scene_y=sy,
											parent_scene_name=placed.name,parent_scene_x=placed.x,parent_scene_y=placed.y}
										wand_altars[#wand_altars+1]=rec;push(rec);scan_altar_contents(rec,"wand",biome)
									elseif gate==false then
										scene_extra.absence_proven=true
										push(marker(sid.."/wand_altar","gate_blocked",fn.func,scene_extra,"nested wand altar gate failed"))
									else
										push(marker(sid.."/wand_altar",gate=="utility_box"and "utility_box"or "wand_altar",fn.func,scene_extra,
											gate=="utility_box"and "utility box, not a wand altar"or "nested wand altar gate unavailable"))
									end
								else
									push( marker( sid .. "/scene_marker", "scene_marker", fn.func, scene_extra,
										"scene marker has no offline content resolver in this build" ) )
								end
							end
						end
					end
				elseif ( M.ALWAYS_REPORT_FUNCTIONS[ func ] ) then
					-- The terrain marker existed but produced no scene. Report it
					-- so a consumer can tell "marker absent" from "marker present,
					-- scene roll empty / rejected". It is a potential marker: no
					-- object exists.
					push( marker( base .. "/" .. func .. "/no_scene", "scene_marker", func, {
						world_x = s.x, world_y = s.y,
						marker_rgb = s.color,
						scene_list = list_name,
						scene_roll_reason = why,
					}, string.format(
						"marker present but its scene list produced no placement (%s)",
						tostring( why ) ) ) )
				end
			end
		end
	end

	return {
		biome = biome,
		spawn_pixels = spawns,
		spawn_pixel_count = #spawns,
		scene_markers = scene_markers,
		scenes_placed = scenes_placed,
		wand_altars = wand_altars,
		trap_wands = trap_wands,
		wild_wands = wild_wands,
		potential = potential,
		records = records,
		by_function = by_kind,
	}
end

function M.to_buf( rgb )
	local n = #rgb
	local buf = {}
	for i = 1, n do buf[ i ] = rgb:byte( i ) end
	return buf
end

return M
