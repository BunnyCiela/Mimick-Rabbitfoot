-- files/isf/shops/validate.lua
--
-- ISF-08 shop-scene and shop-slot validation, plus the two identities that make
-- dedup and accumulation correct:
--
--   scene identity  -- one PHYSICAL shop scene placement. R4.1 (+5) is awarded
--                      once per scene identity, no matter how many slots it has
--                      and no matter how many views of it arrive.
--   slot identity   -- one PHYSICAL sale position inside a scene. The same card
--                      at two different slot identities accumulates; the same
--                      slot seen twice (scene marker + nested record, or two
--                      identical inputs) does not.
--
-- Why "same coordinates" is not enough on its own: equal world coordinates can
-- belong to two different regions or two different scene placements. Identity
-- therefore always names the region and, when known, the enclosing scene.
--
-- Coordinate-frame discipline. Three positions exist for a shop slot:
--
--   scene_x/scene_y              placement origin of the pixel scene
--   marker_offset_x/offset_y     pixel offset of the spawn marker inside it
--   world_x/world_y              the slot position the game seeds content with
--
-- For a wild spell shop the vanilla relation is exactly
--     world = scene + marker_offset
-- and content is seeded from `world`. The adapter REFUSES a record whose numbers
-- disagree with that relation, rather than picking one and hoping: a record with
-- a permuted frame would otherwise predict cards for the wrong position.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local shops_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/shops.lua" )
if ( type( shops_data ) ~= "table" ) then
	error( "shops/validate: files/isf/data/shops.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.ERRORS = {
	bad_shop = "shop record is not a table",
	missing_scene = "shop record does not name its pixel scene",
	unknown_region = "shop record is not in an R4 wild spell shop region",
	excluded_region = "shop record is in a region PRD R4 excludes",
	unknown_scene = "scene name is not a vanilla wild spell shop in this region",
	bad_scene_position = "shop scene position is not an integer pair",
	bad_slot_position = "shop slot position is not an integer pair",
	frame_mismatch = "slot world position does not equal scene origin + marker offset",
	bad_level = "shop card level is not an integer in [0, 10]",
	no_slots = "shop record lists no sale slots",
	bad_slots = "shop record slot list is malformed",
}

local function is_int( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
		and v == math.floor( v )
end

local function is_finite( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Stable identity of one physical shop scene placement.
--
-- Shape matches files/isf/worldgen/scan.lua `scene_object_id`
-- ("<biome>/scene/<scene_name>/<x>,<y>") on purpose: a worldgen scene record and
-- a shop-scene record for the same placement then share one identity string.
function M.scene_identity( region, scene_name, scene_x, scene_y )
	local key = region and region.biome_key or "unknown"
	return string.format( "%s/scene/%s/%s,%s", tostring( key ), tostring( scene_name ),
		tostring( scene_x ), tostring( scene_y ) )
end

-- Stable identity of one physical sale slot.
function M.slot_identity( region, scene_name, scene_x, scene_y, slot_x, slot_y )
	return string.format( "%s/slot/%s,%s",
		M.scene_identity( region, scene_name, scene_x, scene_y ),
		tostring( slot_x ), tostring( slot_y ) )
end

-- validate_scene( raw, opts ) -> scene | nil, errors[], fatal
--
-- Accepted shape (all fields documented; nothing else is interpreted):
--
--   region        "Mines" | "Coal Pits" | "Snowy Depths" (or the generator key).
--                 REQUIRED.
--   scene_name    exact vanilla scene name ("shop" / "shop_alt"). REQUIRED.
--   scene_x, scene_y   integer placement origin of the scene. REQUIRED.
--   biome_key     optional; when present it must match the region's key.
--   object_id     optional identity override. When present it wins, so a caller
--                 that already holds the worldgen identity is never re-derived.
--   level         optional card level override (default: the region's).
--   slots         array of { x = <int>, y = <int> } slot positions, or
--                 array of { marker_x = <int>, marker_y = <int> } scene-local
--                 offsets to be resolved with the scene origin.
--   origin        "discovered" | "supplied", set by the caller (diagnostics).
--
-- `fatal` is true when the record is not a shop at all (so a caller can treat
-- "definitely not a shop" separately from "malformed shop").
function M.validate_scene( raw, opts )
	opts = opts or {}
	local errors = {}
	local function err( code, message )
		errors[ #errors + 1 ] = { code = code, message = message }
	end

	if ( type( raw ) ~= "table" ) then
		return nil, { { code = "bad_shop", message = M.ERRORS.bad_shop } }, true
	end

	local region, region_name = shops_data.region( raw.region )
	if ( region == nil ) then
		local excluded = shops_data.EXCLUDED_REGIONS[ tostring( raw.region ) ]
		if ( excluded ~= nil ) then
			return nil, { { code = "excluded_region",
				message = string.format( "%s: %s", tostring( raw.region ), excluded.reason ) } }, true
		end
		err( "unknown_region", string.format( "%s: %s", M.ERRORS.unknown_region,
			tostring( raw.region ) ) )
	end

	if ( type( raw.scene_name ) ~= "string" or raw.scene_name == "" ) then
		err( "missing_scene", M.ERRORS.missing_scene )
	elseif ( region ~= nil and not shops_data.is_wild_shop_scene( region, raw.scene_name ) ) then
		-- A shop-looking name is not enough: only the exact allowlisted scene is
		-- a wild spell shop. This is what keeps "any scene with shop in the
		-- name" (the upstream heuristic) out of R4.
		err( "unknown_scene", string.format(
			"%s: '%s' (region scenes: %s)", M.ERRORS.unknown_scene,
			tostring( raw.scene_name ), shops_data.region_scope_note( region_name ) ) )
	end

	if ( not is_int( raw.scene_x ) or not is_int( raw.scene_y ) ) then
		err( "bad_scene_position", M.ERRORS.bad_scene_position )
	end

	if ( raw.biome_key ~= nil and region ~= nil and raw.biome_key ~= region.biome_key ) then
		err( "unknown_region", string.format(
			"biome_key '%s' does not belong to region '%s' (expected '%s')",
			tostring( raw.biome_key ), tostring( region_name ), region.biome_key ) )
	end

	local level = raw.level
	if ( level == nil and region ~= nil ) then
		level = region.level
	end
	if ( level ~= nil and ( not is_int( level ) or level < 0 or level > 10 ) ) then
		err( "bad_level", M.ERRORS.bad_level )
	end

	if ( region ~= nil and raw.scene_name ~= nil ) then
		local layout = shops_data.scene_layout( region, raw.scene_name )
		if ( layout ~= nil and layout.scene_width ~= nil and is_int( raw.scene_x )
			and is_int( raw.scene_y ) ) then
			-- A scene whose declared size contradicts the installed bitmap is a
			-- different (or mis-framed) object. Record it, do not guess.
			if ( raw.scene_width ~= nil and raw.scene_width ~= layout.scene_width ) then
				err( "bad_scene_position", string.format(
					"scene_width %s contradicts the installed bitmap width %d",
					tostring( raw.scene_width ), layout.scene_width ) )
			end
			if ( raw.scene_height ~= nil and raw.scene_height ~= layout.scene_height ) then
				err( "bad_scene_position", string.format(
					"scene_height %s contradicts the installed bitmap height %d",
					tostring( raw.scene_height ), layout.scene_height ) )
			end
		end
	end

	if ( #errors > 0 or region == nil ) then
		return nil, errors, false
	end

	local scene = {
		region = region_name,
		region_biome = region.biome,
		biome_key = region.biome_key,
		scene_name = raw.scene_name,
		scene_x = raw.scene_x,
		scene_y = raw.scene_y,
		level = level,
		origin = raw.origin or opts.origin or "supplied",
		slot_source = nil,
		declared_object_id = raw.object_id,
		-- Slot RECORDS are carried through untouched; they are validated by
		-- validate_slot() one by one. An absent/empty list means "the caller did
		-- not list slots", which the provider resolves from the installed scene
		-- layout rather than treating as "this shop sold nothing".
		slots = ( type( raw.slots ) == "table" and #raw.slots > 0 ) and raw.slots or nil,
	}
	scene.object_id = ( type( raw.object_id ) == "string" and raw.object_id ~= "" )
		and raw.object_id
		or M.scene_identity( region, scene.scene_name, scene.scene_x, scene.scene_y )

	return scene, errors, false
end

-- validate_slot( scene, raw ) -> slot | nil, errors[]
--
-- Accepted shapes for one slot:
--   { x, y }                       -- already in the slot world frame
--   { marker_x, marker_y }         -- scene-local offset resolved with the scene
--   { world_x, world_y, marker_offset_x, marker_offset_y }
--                                  -- both frames present; they must agree
-- A slot may also carry `spell_id` (an explicit, already-known card) — the
-- scoring layer uses it instead of predicting one.
function M.validate_slot( scene, raw, index )
	local errors = {}
	local function err( code, message )
		errors[ #errors + 1 ] = { code = code, message = message }
	end

	if ( type( raw ) ~= "table" ) then
		return nil, { { code = "bad_slots", message = "slot is not a table" } }
	end

	local x = raw.x
	local y = raw.y
	if ( x == nil and raw.world_x ~= nil ) then
		x, y = raw.world_x, raw.world_y
	end
	if ( x == nil and raw.marker_x ~= nil ) then
		if ( is_int( raw.marker_x ) and is_int( raw.marker_y ) ) then
			x = scene.scene_x + raw.marker_x
			y = scene.scene_y + raw.marker_y
		end
	end

	if ( not is_int( x ) or not is_int( y ) ) then
		err( "bad_slot_position", M.ERRORS.bad_slot_position
			.. string.format( " (slot %d: %s, %s)", index or 0,
				tostring( x ), tostring( y ) ) )
		return nil, errors
	end

	-- Frame cross-check when the marker offset is present as well.
	if ( is_int( raw.marker_offset_x ) and is_int( raw.marker_offset_y ) ) then
		local expected_x = scene.scene_x + raw.marker_offset_x
		local expected_y = scene.scene_y + raw.marker_offset_y
		if ( expected_x ~= x or expected_y ~= y ) then
			err( "frame_mismatch", string.format(
				"%s: slot %d world (%d, %d) but scene (%d, %d) + offset (%d, %d) = (%d, %d)",
				M.ERRORS.frame_mismatch, index or 0, x, y, scene.scene_x, scene.scene_y,
				raw.marker_offset_x, raw.marker_offset_y, expected_x, expected_y ) )
			return nil, errors
		end
	end

	local slot = {
		index = index,
		x = x,
		y = y,
		spell_id = ( type( raw.spell_id ) == "string" and raw.spell_id ~= "" )
			and raw.spell_id or nil,
		content_source = ( type( raw.spell_id ) == "string" and raw.spell_id ~= "" )
			and "supplied" or "predicted",
		declared_object_id = raw.object_id,
	}
	slot.object_id = ( type( raw.object_id ) == "string" and raw.object_id ~= "" )
		and raw.object_id
		or M.slot_identity( shops_data.region( scene.region ), scene.scene_name,
			scene.scene_x, scene.scene_y, slot.x, slot.y )
	return slot, errors
end

-- Fill in the canonical slot set for a validated scene from the installed
-- scene layout, so a caller that only knows "this scene exists" still gets every
-- real sale slot (and therefore every real card).
function M.layout_slots( scene )
	if ( type( scene ) ~= "table" ) then
		return nil, "no validated shop scene was supplied"
	end
	local region = shops_data.region( scene.region )
	if ( region == nil ) then
		return nil, "shop scene is not in an R4 region"
	end
	local layout = shops_data.scene_layout( region, scene.scene_name )
	if ( layout == nil ) then
		return nil, "no installed layout for this scene"
	end
	local slots = {}
	for i = 1, #layout.slots do
		local s = layout.slots[ i ]
		local slot, errors = M.validate_slot( scene, {
			marker_x = s[ 1 ], marker_y = s[ 2 ],
			object_id = nil,
		}, i )
		if ( slot == nil ) then
			return nil, errors[ 1 ] and errors[ 1 ].message or "layout slot failed validation"
		end
		slots[ #slots + 1 ] = slot
	end
	return slots
end

-- Report whether a supplied value could be a slot position at all. Used by the
-- provider to distinguish "malformed" from "absent".
M.is_int = is_int
M.is_finite = is_finite

return M
