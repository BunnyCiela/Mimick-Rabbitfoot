-- files/isf/shops/discovery.lua
--
-- ISF-08 read-only adapter: turn REAL worldgen scan records (and, when a caller
-- has one, an explicit shop record) into concrete WILD SPELL SHOP SCENES.
--
-- ---------------------------------------------------------------------------
-- Why presence alone is not a shop
-- ---------------------------------------------------------------------------
--
-- `files/isf/worldgen/scan.lua` emits, for every `spawn_shopitem` marker inside a
-- successfully placed pixel scene, a record with
--
--   spawn_kind      = "shop_item"
--   spawn_function  = "spawn_shopitem"
--   generated       = false        (content belongs to the shop provider)
--   scene_name, scene_x, scene_y, marker_offset_x, marker_offset_y, world_x, world_y
--
-- That is an OPPORTUNITY record, not an object. It becomes a real sale slot here
-- only after this adapter:
--
--   1. resolves the enclosing scene's region and checks the scene name against
--      the installed, exact allowlist (files/isf/data/shops.lua). A scene whose
--      name merely contains "shop" is NOT accepted;
--   2. checks the coordinate frame: world == scene origin + marker offset, with
--      every value an integer in the pixel-scene frame;
--   3. checks the offset against the installed scene bitmap's marker list, so a
--      scan produced from a different build cannot silently seed the wrong
--      positions;
--   4. groups records by PHYSICAL scene identity, so five slots yield one scene
--      (one R4.1 base award) and duplicate views of one slot stay one slot.
--
-- Records from the three shop scene names of OTHER regions (crypt/vault/temple
-- shops, snowcastle side caverns, `shop_room`) are documented non-shops for R4:
-- they are rejected with a reason, not scored.
--
-- Coverage honesty:
--   * a record set with no shop-bearing record at all is `partial`, never
--     "this seed has no shop" (an empty list can also mean "not scanned");
--   * a shop record this adapter cannot frame keeps coverage `partial` and is
--     listed for the supervisor;
--   * whether the record set is the region's EXHAUSTIVE spawn set is a claim
--     about the worldgen pipeline, so the caller has to declare it
--     (`scan_complete`) exactly like the chests provider does.
--
-- This module never writes to the scan result, never re-runs worldgen, and never
-- moves or opens an entity.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local shops_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/shops.lua" )
if ( type( shops_data ) ~= "table" ) then
	error( "shops/discovery: files/isf/data/shops.lua did not return a table" )
end

local validate = dofile_once( "mods/interesting_seed_filter/files/isf/shops/validate.lua" )
if ( type( validate ) ~= "table" ) then
	error( "shops/discovery: files/isf/shops/validate.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.SHOP_SPAWN_FUNCTION = shops_data.SHOP_SPAWN_FUNCTION
M.SHOP_SPAWN_KIND = "shop_item"

-- Scene names that really do exist in the installed game as shops (or contain
-- shop slots) but are NOT R4 wild spell shops. Naming them makes a rejection
-- conclusive instead of "unknown", which is the difference between a documented
-- zero and a coverage gap.
M.NON_R4_SHOP_SCENES = {
	shop_room = "the Holy Mountain shop scene (data/scripts/biomes/shop_room.lua), PRD R7",
	shop_second_row = "a Holy Mountain shop second row, PRD R7",
	the_end_shop = "the heaven/hell end shop, outside the R4 regions",
	side_cavern_left = "a snowcastle side cavern, outside the R4 regions",
	side_cavern_right = "a snowcastle side cavern, outside the R4 regions",
	shop_b = "the crypt shop variant, outside the R4 regions",
}

-- Spawn KINDS that are conclusively not a wild spell shop slot, so a record of
-- that kind is a documented zero rather than an unknown. Anything not listed
-- (and not `shop_item`) keeps coverage partial.
M.KNOWN_NON_SHOP_SPAWN_KINDS = {
	trap_wand = "a terrain wand, not a shop slot",
	wild_wand = "a free-standing wand, not a shop slot",
	scene_wand = "a scene wand, not a shop slot",
	altar_wand = "a wand on an altar, not a shop slot",
	wand_altar = "a wand altar, not a shop slot",
	pixel_scene = "a scene placement; its own markers arrive as separate records",
	utility_box = "a utility box, not a shop slot",
	potion = "a loose potion marker, not a shop slot",
	potion_altar = "a potion altar, not a shop slot",
	chest = "a chest marker, not a shop slot",
	heart = "a heart/chest spawn, not a shop slot",
	gate_blocked = "a failed probability gate; the object does not exist",
	scene_marker = "a recognised scene marker with no shop resolver",
}

-- Spawn FUNCTIONS this adapter knows about and that are conclusively not a shop
-- slot source. `spawn_shopitem` is deliberately absent: it IS the shop source.
M.KNOWN_NON_SHOP_SPAWN_FUNCTIONS = {
	spawn_cheap_shopitem = "the Holy Mountain cheap shop slot (shop_room.lua), PRD R7",
	spawn_specialshop = "a non-R4 special shop spawn function",
	spawn_chest = "chest spawn",
	spawn_heart = "heart/chest spawn",
	spawn_bbqbox = "enemy box with a nested heart spawn",
	spawn_wands = "wand drop",
	spawn_wand = "wand drop",
	spawn_trapwand = "terrain wand",
	spawn_items = "wand altar pixel-scene path",
	spawn_wand_altar = "wand altar path",
	spawn_potion_altar = "potion altar pixel-scene path",
	spawn_potions = "loose potion spawn",
	spawn_potion = "loose potion spawn",
	spawn_wand_trap = "hazard trap",
	spawn_wand_trap_ignite = "hazard trap",
	spawn_wand_trap_electricity = "hazard trap",
	spawn_wand_trap_electricity_source = "hazard trap",
	load_pixel_scene = "pixel scene placement",
	load_pixel_scene2 = "pixel scene placement",
	load_pixel_scene3 = "pixel scene placement",
	load_pixel_scene4 = "pixel scene placement",
	load_pixel_scene4_alt = "pixel scene placement",
	load_pixel_scene_alt = "pixel scene placement",
	load_puzzleroom = "puzzle room placement",
	load_gunpowderpool_01 = "liquid pool placement",
	load_gunpowderpool_02 = "liquid pool placement",
	load_gunpowderpool_03 = "liquid pool placement",
	load_gunpowderpool_04 = "liquid pool placement",
	load_oiltank = "oil tank placement",
	load_oiltank_alt = "oil tank placement",
	load_altar = "wand altar placement",
	load_structures = "structure placement",
	load_large_structures = "structure placement",
	load_i_structures = "structure placement",
}

-------------------------------------------------------------------------------
-- Enumeration evidence
-------------------------------------------------------------------------------
--
-- "Every record I was given was modelable" is NOT the same claim as "the seed's
-- shop scenes were enumerated". The worldgen scan emits `spawn_shopitem` SLOT
-- records for markers inside a placed scene, but shop scenes are not on
-- `biome_data.tracked_scene_names`, so the scanner does not emit a placement
-- record for the shop scene itself. Consequently:
--
--   * slot records prove slots exist;
--   * they do NOT prove that every shop scene in the region was visited, nor
--     that a region with no slot record contains no shop.
--
-- An empty `unsupported` list therefore says "nothing in this list was
-- unintelligible", NOT "this list is complete". Treating the caller's
-- `scan_complete` boolean as the proof is exactly the over-claim this adapter
-- must refuse: a declaration is not evidence.
--
-- Observed placements and capability-shaped tables are diagnostics only.
-- The producer now traces shop/shop_alt placements, including zero-slot scenes,
-- but no audited source contract yet proves that every vanilla scene path is
-- covered. No current input can promote enumeration to complete.
M.CAPABILITY_SCHEMA = 1

M.EVIDENCE_MODES = {
	PLACEMENTS = "placement_records",
	DECLARED = "declared_capability",
	SLOTS_ONLY = "slots_only",
	NONE = "none",
}

M.GAPS = {
	no_placement_tracking = "shop scenes are tracked but source exhaustiveness is unverified, "
		.. "so observed spawn_shopitem slots and shop SCENE placement "
		.. "records cannot prove that every shop scene was enumerated",
	declaration_missing = "the scan result carries no validated capability declaration "
		.. "for shop scene enumeration (capabilities.schema = 1, "
		.. "enumerates_shop_scene_placements = true, regions covering every R4 biome)",
	declaration_invalid = "the scan result's capability declaration failed validation",
	declaration_contradicted = "the capability declaration claims shop scene placement "
		.. "enumeration, but the scan result contains no placement record for a shop "
		.. "scene whose slots it did emit",
	region_not_declared = "the capability declaration does not cover this region's biome",
}

M.REASONS = {
	no_records = "the scan result contains no records, so no shop source was examined",
	no_shop_function = "the scan result contains no spawn_shopitem slot record",
	unsupported_only = "no record in the scan result could be classified as a shop or a non-shop",
	partial_functions = "the scan result contains records this adapter cannot model",
	unknown_scene = "a shop slot record names a scene that is not an R4 wild spell shop",
	unplaced_shop = "a spawn_shopitem record has no enclosing placed scene",
	frame_rejected = "a shop slot record is not in the pixel-scene integer frame",
	layout_mismatch = "a shop slot offset is not present in the installed scene bitmap",
	no_biome = "the scan result does not name its biome",
}

local function is_int( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
		and v == math.floor( v )
end

-- Resolve the R4 region for a record's biome key.
local function region_for_biome( biome_key )
	local display = shops_data.DISPLAY_BY_KEY[ biome_key ]
	if ( display == nil ) then
		return nil
	end
	return shops_data.REGIONS[ display ], display
end

-- Find the offset pair of a slot inside the installed layout.
local function offset_in_layout( layout, dx, dy )
	if ( layout == nil ) then
		return false
	end
	for i = 1, #layout.slots do
		local s = layout.slots[ i ]
		if ( s[ 1 ] == dx and s[ 2 ] == dy ) then
			return true
		end
	end
	return false
end

-- Classify one scan record.
--
-- Returns one of:
--   { status = "shop_slot", region, region_name, scene_name, scene_x, scene_y,
--     slot = { x, y, marker_offset_x, marker_offset_y }, reason }
--   { status = "not_shop", reason }
--   { status = "unsupported", reason }
--   { status = "invalid", reason }
function M.classify_record( record, opts )
	opts = opts or {}
	if ( type( record ) ~= "table" ) then
		return { status = "invalid", reason = "record is not a table" }
	end

	local kind = record.spawn_kind
	local func = record.spawn_function

	-- A shop-bearing record is recognised by kind OR function; both are checked
	-- so a build that renames one of them is not silently mis-read.
	local looks_like_shop = ( kind == M.SHOP_SPAWN_KIND ) or ( func == M.SHOP_SPAWN_FUNCTION )

	-- A `pixel_scene` placement record can be shop EXISTENCE evidence (a placed
	-- shop scene whose own markers will arrive separately). It is never a slot,
	-- and a placement of a non-shop scene is a conclusive zero.
	if ( kind == "pixel_scene" ) then
		if ( type( record.scene_name ) == "string"
			and shops_data.region( record.biome ) ~= nil ) then
			local region = shops_data.region( record.biome )
			if ( shops_data.is_wild_shop_scene( region, record.scene_name ) ) then
				return M.classify_scene_placement( record, opts )
			end
		end
		return { status = "not_shop", reason = string.format(
			"pixel scene placement '%s' in biome '%s' is not an R4 wild shop scene",
			tostring( record.scene_name ), tostring( record.biome ) ) }
	end

	if ( not looks_like_shop ) then
		if ( kind ~= nil and M.KNOWN_NON_SHOP_SPAWN_KINDS[ kind ] ~= nil ) then
			return { status = "not_shop", reason = string.format(
				"record kind '%s' is not a shop slot: %s", tostring( kind ),
				M.KNOWN_NON_SHOP_SPAWN_KINDS[ kind ] ) }
		end
		if ( func ~= nil and M.KNOWN_NON_SHOP_SPAWN_FUNCTIONS[ func ] ~= nil ) then
			return { status = "not_shop", reason = string.format(
				"spawn function '%s' is not a shop slot source: %s", tostring( func ),
				M.KNOWN_NON_SHOP_SPAWN_FUNCTIONS[ func ] ) }
		end
		return { status = "unsupported", reason = string.format(
			"record kind '%s' / spawn function '%s' is not verified as a shop source",
			tostring( kind ), tostring( func ) ) }
	end

	local biome_key = record.biome
	if ( biome_key == nil ) then
		return { status = "invalid", reason = M.REASONS.no_biome }
	end
	local region, region_name = region_for_biome( biome_key )
	if ( region == nil ) then
		local scene = record.scene_name
		local why = scene and M.NON_R4_SHOP_SCENES[ scene ]
		return { status = "not_shop", reason = string.format(
			"shop slot in biome '%s' is outside the R4 regions%s", tostring( biome_key ),
			why and ( " (" .. why .. ")" ) or "" ) }
	end

	local scene_name = record.scene_name
	if ( type( scene_name ) ~= "string" or scene_name == "" ) then
		-- A `spawn_shopitem` marker that is not inside a placed scene cannot be
		-- tied to an enclosing shop scene, so its base award and its slot
		-- identity are both unprovable.
		return { status = "unsupported", reason = string.format(
			"%s (biome %s at %s,%s)", M.REASONS.unplaced_shop, tostring( biome_key ),
			tostring( record.world_x ), tostring( record.world_y ) ) }
	end

	local non_r4 = M.NON_R4_SHOP_SCENES[ scene_name ]
	if ( non_r4 ~= nil ) then
		return { status = "not_shop", reason = string.format(
			"scene '%s' is not an R4 wild spell shop: %s", scene_name, non_r4 ) }
	end
	if ( not shops_data.is_wild_shop_scene( region, scene_name ) ) then
		return { status = "not_shop", reason = string.format(
			"scene '%s' in %s is not on the installed wild shop allowlist (%s)",
			scene_name, tostring( region_name ), shops_data.region_scope_note( region_name ) ) }
	end

	if ( not is_int( record.scene_x ) or not is_int( record.scene_y ) ) then
		return { status = "invalid", reason = "shop slot record has no integer scene origin" }
	end

	local layout = shops_data.scene_layout( region, scene_name )
	local dx = record.marker_offset_x
	local dy = record.marker_offset_y
	local x = record.world_x
	local y = record.world_y

	if ( is_int( dx ) and is_int( dy ) ) then
		if ( not is_int( x ) or not is_int( y ) ) then
			-- Derive the world position only when the offset frame is complete;
			-- that is exactly what the game does.
			x = record.scene_x + dx
			y = record.scene_y + dy
		elseif ( x ~= record.scene_x + dx or y ~= record.scene_y + dy ) then
			return { status = "invalid", reason = string.format(
				"%s: world (%s,%s) != scene (%d,%d) + offset (%d,%d)",
				M.REASONS.frame_rejected, tostring( x ), tostring( y ),
				record.scene_x, record.scene_y, dx, dy ) }
		end
		if ( not offset_in_layout( layout, dx, dy ) ) then
			return { status = "unsupported", reason = string.format(
				"%s: scene '%s' offset (%d,%d)", M.REASONS.layout_mismatch,
				scene_name, dx, dy ) }
		end
	elseif ( not is_int( x ) or not is_int( y ) ) then
		return { status = "invalid", reason = M.REASONS.frame_rejected }
	end

	return {
		status = "shop_slot",
		region = region,
		region_name = region_name,
		biome_key = biome_key,
		scene_name = scene_name,
		scene_x = record.scene_x,
		scene_y = record.scene_y,
		scene_width = layout and layout.scene_width or nil,
		scene_height = layout and layout.scene_height or nil,
		slot = {
			x = x, y = y,
			marker_offset_x = dx, marker_offset_y = dy,
			source_id = record.source_id,
		},
		reason = string.format(
			"spawn_shopitem slot in %s scene '%s' at (%d, %d)", tostring( region_name ),
			scene_name, x, y ),
	}
end

-- A `pixel_scene` record naming an allowlisted wild shop scene. Its slots are
-- the installed bitmap's markers; the placement proves the markers ran.
function M.classify_scene_placement( record, opts )
	opts = opts or {}
	local biome_key = record.biome
	local region, region_name = region_for_biome( biome_key )
	if ( region == nil ) then
		return { status = "not_shop", reason = string.format(
			"scene placement in biome '%s' is outside the R4 regions",
			tostring( biome_key ) ) }
	end
	local scene_name = record.scene_name
	if ( type( scene_name ) ~= "string" or scene_name == "" ) then
		return { status = "invalid", reason = "scene placement record has no scene name" }
	end
	if ( M.NON_R4_SHOP_SCENES[ scene_name ] ~= nil ) then
		return { status = "not_shop", reason = string.format(
			"scene '%s' is not an R4 wild spell shop: %s", scene_name,
			M.NON_R4_SHOP_SCENES[ scene_name ] ) }
	end
	if ( not shops_data.is_wild_shop_scene( region, scene_name ) ) then
		return { status = "not_shop", reason = string.format(
			"scene '%s' in %s is not a shop scene", scene_name, tostring( region_name ) ) }
	end
	if ( not is_int( record.scene_x or record.world_x )
		or not is_int( record.scene_y or record.world_y ) ) then
		return { status = "invalid", reason = "scene placement has no integer origin" }
	end
	local layout = shops_data.scene_layout( region, scene_name )
	return {
		status = "shop_scene",
		region = region,
		region_name = region_name,
		biome_key = biome_key,
		scene_name = scene_name,
		scene_x = record.scene_x or record.world_x,
		scene_y = record.scene_y or record.world_y,
		scene_width = layout and layout.scene_width or nil,
		scene_height = layout and layout.scene_height or nil,
		reason = string.format( "placed %s wild shop scene '%s'", tostring( region_name ),
			scene_name ),
	}
end

-- validate_capability( scan_result ) -> capability | nil, reason
--
-- Accepts a producer's shop-enumeration declaration ONLY when it is
-- self-describing and internally consistent. Shape:
--
--   capabilities = {
--     schema = 1,
--     enumerates_shop_scene_placements = true,
--     regions = { coalmine = true, excavationsite = true, snowcave = true },
--   }
--
-- Nothing here trusts a bare boolean: `schema` must match this adapter's
-- CAPABILITY_SCHEMA and the region map must be explicit. A declaration that does
-- not say WHICH biomes it covers is indistinguishable from an assertion.
function M.validate_capability( scan_result )
	if ( type( scan_result ) ~= "table" ) then
		return nil, M.GAPS.declaration_missing
	end
	local caps = scan_result.capabilities
	if ( type( caps ) ~= "table" ) then
		return nil, M.GAPS.declaration_missing
	end
	if ( caps.schema ~= M.CAPABILITY_SCHEMA ) then
		return nil, string.format( "%s (schema %s, expected %d)", M.GAPS.declaration_invalid,
			tostring( caps.schema ), M.CAPABILITY_SCHEMA )
	end
	if ( caps.enumerates_shop_scene_placements ~= true ) then
		return nil, string.format( "%s (enumerates_shop_scene_placements is not true)",
			M.GAPS.declaration_missing )
	end
	if ( type( caps.regions ) ~= "table" ) then
		return nil, string.format( "%s (no regions map)", M.GAPS.declaration_missing )
	end
	return {
		schema = caps.schema,
		enumerates_shop_scene_placements = true,
		regions = caps.regions,
	}, nil
end

-- Does a validated capability cover one biome key?
function M.capability_covers( capability, biome_key )
	if ( type( capability ) ~= "table" or type( capability.regions ) ~= "table" ) then
		return false
	end
	return capability.regions[ biome_key ] == true
end

-- discover( scan_result, opts ) -> {
--   shops, placements, rejected, unsupported, invalid, examined, reasons, complete,
--   evidence, enumeration_proven, gaps, capability
-- }
--
-- `scan_result` is a worldgen scan result table (files/isf/worldgen/scan.lua
-- scan_layer). It is read, never modified.
--
-- opts.region optionally restricts the accepted display names (a region filter);
-- a record from another R4 region is then reported as out_of_region rather than
-- silently accepted.
--
-- opts.allow_slots_only (default false) is a TEST-ONLY escape hatch that must
-- not be used to manufacture a coverage claim; it is documented so a reviewer
-- can see it exists rather than find it by accident. Even when set, `enumeration
-- _proven` stays false.
function M.discover( scan_result, opts )
	opts = opts or {}
	local out = {
		shops = {},
		placements = {},
		rejected = {},
		unsupported = {},
		invalid = {},
		out_of_region = {},
		examined = 0,
		reasons = {},
		complete = false,
		-- Enumeration evidence: is "no shop here" a proven answer, or merely
		-- "no slot record in the input"?
		evidence = M.EVIDENCE_MODES.NONE,
		enumeration_proven = false,
		gaps = {},
		capability = nil,
		placed_scene_ids = {},
	}

	if ( type( scan_result ) ~= "table" ) then
		out.reasons[ #out.reasons + 1 ] = "scan result is not a table"
		return out
	end

	local records = scan_result.records
	if ( type( records ) ~= "table" or #records == 0 ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.no_records
		return out
	end

	local allow = nil
	if ( type( opts.region ) == "string" ) then
		local region, name = shops_data.region( opts.region )
		if ( region ~= nil ) then
			allow = { [ name ] = true }
		end
	end

	local any_classified = false
	local any_unsupported = false
	local any_shop = false

	-- scene identity -> shop table, so five slots collapse into one scene.
	local by_scene = {}

	local function shop_for( verdict )
		local identity = validate.scene_identity( verdict.region, verdict.scene_name,
			verdict.scene_x, verdict.scene_y )
		local shop = by_scene[ identity ]
		if ( shop == nil ) then
			shop = {
				object_id = identity,
				region = verdict.region_name,
				biome_key = verdict.biome_key,
				scene_name = verdict.scene_name,
				scene_x = verdict.scene_x,
				scene_y = verdict.scene_y,
				scene_width = verdict.scene_width,
				scene_height = verdict.scene_height,
				level = verdict.region.level,
				origin = "discovered",
				slots = {},
				slot_ids = {},
				evidence = {},
			}
			by_scene[ identity ] = shop
			out.shops[ #out.shops + 1 ] = shop
		end
		return shop
	end

	for i = 1, #records do
		local record = records[ i ]
		out.examined = out.examined + 1
		local verdict = M.classify_record( record, opts )

		if ( verdict.status == "shop_slot" ) then
			if ( allow ~= nil and not allow[ verdict.region_name ] ) then
				out.out_of_region[ #out.out_of_region + 1 ] = {
					region = verdict.region_name,
					scene_name = verdict.scene_name,
					reason = string.format(
						"shop slot in %s is outside the requested region filter",
						tostring( verdict.region_name ) ),
				}
				any_classified = true
			else
				any_shop = true
				any_classified = true
				local shop = shop_for( verdict )
				local slot = verdict.slot
				local slot_id = validate.slot_identity( verdict.region, verdict.scene_name,
					verdict.scene_x, verdict.scene_y, slot.x, slot.y )
				if ( shop.slot_ids[ slot_id ] == nil ) then
					shop.slot_ids[ slot_id ] = true
					shop.slots[ #shop.slots + 1 ] = {
						x = slot.x,
						y = slot.y,
						marker_offset_x = slot.marker_offset_x,
						marker_offset_y = slot.marker_offset_y,
						source_id = slot.source_id,
						object_id = slot_id,
					}
				else
					-- A duplicate view of one physical slot. Not an error: the
					-- same marker can arrive as a nested record and a scene
					-- record. It must never add a second card.
					shop.evidence[ #shop.evidence + 1 ] = "duplicate slot view at ("
						.. tostring( slot.x ) .. ", " .. tostring( slot.y ) .. ")"
				end
			end
		elseif ( verdict.status == "shop_scene" ) then
			if ( allow ~= nil and not allow[ verdict.region_name ] ) then
				out.out_of_region[ #out.out_of_region + 1 ] = {
					region = verdict.region_name,
					scene_name = verdict.scene_name,
					reason = "shop scene is outside the requested region filter",
				}
				any_classified = true
			else
				any_classified = true
				local shop = shop_for( verdict )
				out.placements[ #out.placements + 1 ] = shop.object_id
				out.placed_scene_ids[ shop.object_id ] = true
				shop.evidence[ #shop.evidence + 1 ] = verdict.reason
			end
		elseif ( verdict.status == "not_shop" ) then
			-- A conclusive zero: the record is settled, so it counts as
			-- classified for coverage purposes.
			any_classified = true
			out.rejected[ #out.rejected + 1 ] = {
				source_id = record.source_id,
				spawn_kind = record.spawn_kind,
				spawn_function = record.spawn_function,
				reason = verdict.reason,
			}
		elseif ( verdict.status == "unsupported" ) then
			any_unsupported = true
			local key = record.spawn_kind or record.spawn_function or "<unnamed>"
			local seen = false
			for j = 1, #out.unsupported do
				if ( out.unsupported[ j ].key == key ) then
					seen = true
					break
				end
			end
			if ( not seen ) then
				out.unsupported[ #out.unsupported + 1 ] = {
					key = key,
					spawn_kind = record.spawn_kind,
					spawn_function = record.spawn_function,
					reason = verdict.reason,
				}
			end
		else
			out.invalid[ #out.invalid + 1 ] = {
				source_id = record.source_id,
				reason = verdict.reason,
			}
		end
	end

	-- Sort slots deterministically so two runs produce identical reports even if
	-- the scan visited markers in a different order.
	for i = 1, #out.shops do
		local slots = out.shops[ i ].slots
		table.sort( slots, function( a, b )
			if ( a.x ~= b.x ) then return a.x < b.x end
			return a.y < b.y
		end )
	end
	table.sort( out.shops, function( a, b )
		if ( a.scene_x ~= b.scene_x ) then return a.scene_x < b.scene_x end
		if ( a.scene_y ~= b.scene_y ) then return a.scene_y < b.scene_y end
		return a.object_id < b.object_id
	end )

	if ( not any_classified ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.unsupported_only
	end
	if ( not any_shop ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.no_shop_function
	end
	if ( any_unsupported ) then
		out.reasons[ #out.reasons + 1 ] = M.REASONS.partial_functions
	end
	if ( #out.invalid > 0 ) then
		out.reasons[ #out.reasons + 1 ] = string.format(
			"%d shop record(s) were malformed or mis-framed", #out.invalid )
	end

	-- `complete` here means ONLY "every record in this list was modelable". It is
	-- deliberately NOT a statement that the list is exhaustive; see
	-- `enumeration_proven` below, which is the claim a consumer actually needs.
	out.complete = any_classified and not any_unsupported
		and #out.invalid == 0 and #records > 0

	-- Placement records prove only the observed scenes. No audited producer
	-- currently proves absence of omitted shop scenes, including zero-slot scenes.
	-- A caller's capability-shaped table cannot supply that missing source audit.
	local capability, cap_reason = M.validate_capability(scan_result)
	out.capability = capability
	out.evidence = M.EVIDENCE_MODES.SLOTS_ONLY
	out.enumeration_proven = false
	out.gaps[#out.gaps + 1] = "producer shop-scene exhaustiveness is unverified; observed placements cannot prove no omitted scenes"
	if cap_reason then out.gaps[#out.gaps + 1] = cap_reason end

	return out
end

return M
