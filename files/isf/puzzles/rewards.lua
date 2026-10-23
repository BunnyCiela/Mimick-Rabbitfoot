-- files/isf/puzzles/rewards.lua
--
-- Deterministic, source-justified reward prediction for the puzzles recognised by
-- files/isf/puzzles/recognize.lua.
--
-- SUBSTANTIAL REUSE / ATTRIBUTION
--   The reward-room chunk derivation reproduces noita-telescope's altar
--   positions for both hidden rooms:
--     js/misc_generation.js  (meditationCubePosition, snowyRoomPositions)
--     MIT License, Copyright (c) 2026 Lymm
--   Every PRESENCE claim, however, comes from the installed vanilla Lua/XML
--   (EntityLoad calls quoted per reward spec below), not from upstream.
--
-- DESIGN CONSTRAINT (PRD R3 + WORKER_CONTRACT)
--   * A reward is only predicted when the corresponding ENTRANCE exists. The
--     caller passes instances from recognize.lua, so a fixed hidden reward room
--     can never contribute on its own: there is no code path from this module
--     that takes a room coordinate without an instance.
--   * A reward's region is the ENTRANCE's region, never the hidden room's own
--     biome and never the physical room coordinate's region. So a Snowy Depths
--     puzzle reward is Snowy Depths for resource-scope purposes, which means R1
--     wand body / in-wand spell / R2 chest / R5 item scores do NOT switch on.
--   * This module does not port R1, R2 or R5. It emits LINKED REWARD RECORDS
--     with a stable identity, a precise coordinate frame and a delegated owner,
--     and it scores nothing itself unless the PRD gives the puzzle provider a
--     rule for it. R3 existence and the cube/eye bonuses are scored in
--     providers/puzzles.lua; every other reward here is explicitly unscored with
--     the reason recorded.
--   * Presence and content are SEPARATE fields. `presence` says why an object is
--     believed to exist; `content_status` says whether its contents are known.
--     A reward whose marker mapping is unresolved is emitted with an explicit
--     unresolved flag instead of being dropped.
--
-- Lua 5.1 / LuaJIT 2.0 compatible. No I/O, no RNG, no globals.

local data = dofile_once( "mods/interesting_seed_filter/files/isf/data/puzzles.lua" )
if ( type( data ) ~= "table" ) then
	error( "rewards: files/isf/data/puzzles.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

-- Coordinate frames, so a downstream consumer never has to guess which anchor a
-- number came from.
M.FRAME_ENTRANCE_MARKER = "entrance_marker_offset"
M.FRAME_REWARD_ROOM = "reward_room_marker"

-- Presence vocabulary.
M.PRESENCE_CONDITIONAL = "conditional_on_solution"      -- created only when solved
M.PRESENCE_DETERMINISTIC = "deterministic_on_load"      -- created with the entrance
M.PRESENCE_ENGINE_DEFAULT = "source_justified_engine_default_marker"
M.PRESENCE_ROOM = "deterministic_if_entrance"

-- Content vocabulary.
M.CONTENT_DELEGATED = "delegated"
M.CONTENT_FIXED_ENTITY = "fixed_entity_procedural_cards"
M.CONTENT_EMPTY = "empty"
M.CONTENT_UNRESOLVED = "unresolved"

-- The room teleport targets, read out of the installed entity XML:
--   data/entities/buildings/teleport_meditation_cube.xml  target (-4345, 2365)
--   data/entities/buildings/teleport_snowcave_buried_eye.xml target (3895, 4510)
--
-- Reward rooms occupy one 512-unit chunk. The room's placement origin is the
-- chunk-aligned corner below that target; subtracting it from the target leaves
-- an interior arrival offset. This derivation reproduces upstream Telescope's
-- altar positions exactly for BOTH rooms:
--   cube  (-4608 + 350, 2048 + 303)  = (-4258, 2351)
--   eye   ( 3584 + 333, 4096 + 297)  = ( 3917, 4393)
-- and (3584 + 439, 4096 + 324) = (4023, 4420).
-- Upstream: js/misc_generation.js meditationCubePosition / snowyRoomPositions.
-- It is derived evidence, not native-game verification.
M.ROOM_CHUNK = 512

function M.room_origin( target_x, target_y )
	return math.floor( target_x / M.ROOM_CHUNK ) * M.ROOM_CHUNK,
		math.floor( target_y / M.ROOM_CHUNK ) * M.ROOM_CHUNK
end

-- ---------------------------------------------------------------------------
-- Resource scope gate
-- ---------------------------------------------------------------------------

-- The per-resource PRD section 2 column, applied through the ENTRANCE region.
-- Returns true | false, reason.
function M.scope_allows( resource_scope, resource )
	if ( resource_scope == nil ) then
		return false, "entrance region has no resource scope recorded"
	end
	local allowed
	if ( resource == "wand" ) then
		allowed = resource_scope.wand_body
	elseif ( resource == "wand_inner_spell" ) then
		allowed = resource_scope.wand_inner_spells
	elseif ( resource == "chest" ) then
		allowed = resource_scope.chest
	elseif ( resource == "potion" or resource == "powder_pouch" or resource == "r5" ) then
		allowed = resource_scope.r5_items
	else
		return false, "unknown resource kind " .. tostring( resource )
	end
	if ( allowed == true ) then
		return true
	end
	return false, "entrance region's resource scope does not grant this resource kind"
end

-- ---------------------------------------------------------------------------
-- Reward record construction
-- ---------------------------------------------------------------------------

local function reward_id( instance, index, resource, suffix )
	-- Stable across runs: instance identity + stable ordinal + resource + suffix.
	return string.format( "%s/reward%d/%s%s", instance.id, index, resource,
		suffix and ( "/" .. suffix ) or "" )
end

-- A potion or pouch record in the collectibles RECORD_CONTRACT shape, so the
-- collectibles provider can consume it without translation. Fixed contents are
-- carried verbatim and never rerolled.
local function collectible_record( instance, spec, x, y, frame, id )
	return {
		id = id,
		object_id = id, -- two views of one object share this identity
		kind = spec.record_kind or "potion",
		biome = data.REGIONS[ instance.biome_key ].name,
		entrance_biome = data.REGIONS[ instance.biome_key ].name,
		x = x,
		y = y,
		coordinate_frame = frame,
		entity_file = spec.entity,
		material = spec.material,
		visit = "puzzle_reward",
		source_id = instance.id,
		source_kind = spec.source_kind,
		spawned_during = "initial_generation",
	}
end

-- Expand one reward spec of a recognised instance into a linked reward record.
--
-- Returns a record. Never returns nil: an unresolvable reward is still emitted,
-- with `resolved = false` and the reason, because dropping it silently would
-- turn "unknown" into "absent" (PRD: 未知不能伪装成不存在).
function M.build_reward( instance, spec, index )
	local entrance_region = data.REGIONS[ instance.biome_key ]
	local entrance_name = entrance_region and entrance_region.name or instance.biome_key
	local record = {
		puzzle_id = instance.id,
		puzzle_kind = instance.kind_id,
		puzzle_type = instance.puzzle_type,
		mechanism = instance.mechanism,
		biome = entrance_name,
		entrance_biome = entrance_name,
		entrance_generated = instance.verified == true,
		biome_key = instance.biome_key,
		entrance_biome_key = instance.biome_key,
		entrance_x = instance.x,
		entrance_y = instance.y,
		resource = spec.resource,
		kind = spec.kind,
		entity = spec.entity,
		presence = spec.presence,
		presence_status = "predicted",
		content_status = spec.content or M.CONTENT_UNRESOLVED,
		delegated_to = spec.delegated_to,
		scoring_rule = spec.scoring_rule,
		score_units = 0,
		resolved = true,
		provenance = spec.provenance,
	}

	-- ---- coordinate derivation -------------------------------------------------
	if ( spec.anchor == "reward_room" ) then
		local base_x, base_y = M.room_origin( spec.room_target_x, spec.room_target_y )
		local marker_rgb = spec.room_marker_rgb
		local marker = data.ENGINE_DEFAULT_MARKERS[ marker_rgb ]
		local ox = spec.room_marker_offset_x
		local oy = spec.room_marker_offset_y
		if ( ox == nil or oy == nil ) then
			-- The buried eye room carries TWO wand markers. Emit every derived
			-- coordinate so no consumer silently picks one, and make the FIRST
			-- (lowest x) the primary record so the record always points at a
			-- real marker rather than at the room's empty corner.
			record.coordinate_frame = M.FRAME_REWARD_ROOM
			record.room_base_x = base_x
			record.room_base_y = base_y
			record.room_target_x = spec.room_target_x
			record.room_target_y = spec.room_target_y
			record.room_marker_rgb = marker_rgb
			record.marker_count = spec.room_marker_count
			record.alternate_coordinates = {}
			local offsets = spec.room_marker_offsets or {}
			local best = nil
			for i = 1, #offsets do
				local o = offsets[ i ]
				local coord = { x = base_x + o[ 1 ], y = base_y + o[ 2 ],
					dx = o[ 1 ], dy = o[ 2 ] }
				record.alternate_coordinates[ i ] = coord
				if ( best == nil or coord.x < best.x
					or ( coord.x == best.x and coord.y < best.y ) ) then
					best = coord
				end
			end
			if ( best ~= nil ) then
				record.x = best.x
				record.y = best.y
				record.marker_offset_x = best.dx
				record.marker_offset_y = best.dy
				record.coordinate_confidence =
					"derived_from_teleport_target_and_512_room_grid"
				record.primary_coordinate_is = "first_of_" .. #offsets .. "_markers"
			else
				record.x = base_x
				record.y = base_y
				record.coordinate_confidence = "room_base_only"
			end
		else
			record.coordinate_frame = M.FRAME_REWARD_ROOM
			record.room_base_x = base_x
			record.room_base_y = base_y
			record.room_target_x = spec.room_target_x
			record.room_target_y = spec.room_target_y
			record.room_marker_rgb = marker_rgb
			record.x = base_x + ox
			record.y = base_y + oy
			record.coordinate_confidence = "derived_from_teleport_target_and_512_room_grid"
		end
		-- The room is a place; the REGION is still the entrance's.
		record.room_biome_key = spec.room_biome_key
		record.room_biome = spec.room_biome_key
		record.room_biome_name = data.REGIONS[ spec.room_biome_key ]
			and data.REGIONS[ spec.room_biome_key ].name or spec.room_biome_key
		if ( marker ~= nil and marker.unresolved ~= nil ) then
			record.marker_mapping = "unresolved_engine_default"
			record.marker_mapping_reason = marker.unresolved
			record.marker_evidence = marker.evidence
		end
	elseif ( spec.anchor == "scene_marker" ) then
		-- Marker pixel inside the puzzle's own bitmap. The scene origin is known
		-- whenever the entrance record carried it; otherwise the marker offset is
		-- reported relative to the entrance marker instead of pretending to be an
		-- absolute coordinate.
		local marker = data.ENGINE_DEFAULT_MARKERS[ spec.scene_marker_rgb ]
		record.coordinate_frame = "scene_bitmap_marker"
		record.scene_marker_rgb = spec.scene_marker_rgb
		record.scene_marker_offset_x = spec.scene_marker_offset_x
		record.scene_marker_offset_y = spec.scene_marker_offset_y
		if ( instance.scene_x ~= nil and instance.scene_y ~= nil ) then
			record.scene_x = instance.scene_x
			record.scene_y = instance.scene_y
			record.x = instance.scene_x + spec.scene_marker_offset_x
			record.y = instance.scene_y + spec.scene_marker_offset_y
			record.coordinate_confidence = "scene_origin_plus_marker_offset"
		else
			record.coordinate_confidence = "scene_origin_unknown"
			record.resolved = false
			record.presence_status = "coordinate_unresolved"
			record.unresolved_reason = "the entrance record did not carry "
				.. "scene_x/scene_y, so the in-scene marker offset cannot become a "
				.. "world coordinate"
		end
		if ( marker ~= nil and marker.unresolved ~= nil ) then
			record.marker_mapping = "unresolved_engine_default"
			record.marker_mapping_reason = marker.unresolved
			record.marker_evidence = marker.evidence
		end
	else
		-- Entrance-marker-relative offset: the reward is created at a fixed
		-- offset from the marker whose Lua body loads it.
		record.coordinate_frame = M.FRAME_ENTRANCE_MARKER
		record.dx = spec.dx or 0
		record.dy = spec.dy or 0
		record.anchor_marker = spec.anchor_marker
		record.x = instance.x + record.dx
		record.y = instance.y + record.dy
		record.coordinate_confidence = "entrance_marker_plus_source_offset"
	end

	-- ---- marker mapping uncertainty is preserved, not hidden ------------------
	if ( record.marker_mapping == "unresolved_engine_default" and record.resolved ) then
		record.presence_status = "presence_source_justified_mapping_unresolved"
		record.resolved = false
		record.unresolved_reason = record.marker_mapping_reason
	end

	-- ---- resource scope: applied through the ENTRANCE region -----------------
	local allowed, why = M.scope_allows( instance.resource_scope, spec.resource )
	record.region_scope_allowed = allowed == true
	if ( not allowed ) then
		record.score_units = 0
		record.not_scored_reason = string.format(
			"reward region inherits the entrance region %s; %s",
			entrance_name, why )
	end

	-- ---- explicit zero-score reasons -----------------------------------------
	if ( spec.not_scored_reason ~= nil ) then
		record.not_scored_reason = spec.not_scored_reason
		record.score_units = 0
	end
	if ( spec.delegated_to ~= nil ) then
		record.scoring_owner = spec.delegated_to
		if ( record.not_scored_reason == nil ) then
			record.not_scored_reason = tostring( spec.scoring_rule )
				.. " scoring is owned by the '" .. spec.delegated_to
				.. "' provider; this provider emits the linked record only"
		end
	end

	record.id = reward_id( instance, index, spec.resource, spec.kind )

	-- A collectibles-shaped view for potion/pouch rewards, so nothing has to
	-- re-derive the transform or the fixed contents.
	if ( spec.resource == "potion" or spec.resource == "powder_pouch" ) then
		record.collectibles_record = collectible_record( instance, spec,
			record.x, record.y, record.coordinate_frame, record.id )
	end

	return record
end

-- build( instance, options ) -> { rewards, status, reasons, unresolved }
--
-- `status` is the honest reward coverage for THIS instance:
--   "complete"    every reward was resolved and every owner is known
--   "partial"     some reward is predicted but not resolved/scored here
--   "unsupported" the kind has no source-justified reward at all
function M.build( instance )
	if ( type( instance ) ~= "table" or type( instance.kind ) ~= "table" ) then
		error( "rewards.build expects a recognised instance" )
	end
	local kind = instance.kind
	local rewards = {}
	local reasons = {}
	local unresolved = 0

	local specs = kind.rewards or {}
	if ( kind.reward_status == "delegated_to_region_scan" ) then
		return {
			rewards = {}, status = "delegated", unresolved = 0, spec_count = 0,
			reasons = { kind.reward_reason },
			-- This describes ownership, not an assertion that a supplied entrance
			-- came from an exhaustive scan. Discovery coverage is checked separately.
			delegated_to = "region_scan",
		}
	end
	if ( kind.reward_status == "unsupported" or #specs == 0 ) then
		return {
			rewards = {},
			status = "unsupported",
			reasons = {
				kind.reward_reason
					or "no deterministic reward object can be derived from source for this puzzle",
			},
			unresolved = 0,
			spec_count = 0,
		}
	end

	for i = 1, #specs do
		local record = M.build_reward( instance, specs[ i ], i )
		rewards[ #rewards + 1 ] = record
		if ( not record.resolved ) then
			unresolved = unresolved + 1
			if ( record.unresolved_reason ~= nil ) then
				reasons[ #reasons + 1 ] = record.id .. ": " .. record.unresolved_reason
			end
		end
		if ( record.not_scored_reason ~= nil ) then
			reasons[ #reasons + 1 ] = record.id .. ": " .. record.not_scored_reason
		end
	end

	local status
	if ( unresolved == 0 and #rewards > 0 ) then
		status = "complete"
	elseif ( #rewards > 0 ) then
		status = "partial"
	else
		status = "unsupported"
	end

	return {
		rewards = rewards,
		status = status,
		reasons = reasons,
		unresolved = unresolved,
		spec_count = #specs,
	}
end

return M
