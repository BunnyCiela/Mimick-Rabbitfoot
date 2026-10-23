-- files/isf/data/puzzles.lua
--
-- PRD R3 puzzle whitelist, derived from the ACTUAL installed biome scripts and
-- pixel-scene bitmaps, not from scene file names.
--
-- PROVENANCE (all read out of D:/SteamLibrary/steamapps/common/Noita/data/data.wak
-- with the read-only development extractor tools/puzzles/extract_sources.py,
-- which records SHA-256 metadata in
-- .scratch/interesting-seed-filter/puzzles/source_metadata.json):
--
--   data/scripts/biomes/coalmine.lua
--       RegisterSpawnFunction( 0xff005cfd, "spawn_swing_puzzle_box" )
--       RegisterSpawnFunction( 0xff00b5fc, "spawn_swing_puzzle_target" )
--       RegisterSpawnFunction( 0xff93ca00, "spawn_oiltank_puzzle" )
--       RegisterSpawnFunction( 0xffb97300, "spawn_receptacle_oil" )
--       scene table g_pixel_scene_02 (reached through load_pixel_scene2 /
--       default marker 0xFF0080) contains physics_swing_puzzle.png at prob 0.5
--       and receptacle_oil.png at prob 0.5; scene table g_oiltank contains
--       oiltank_puzzle.png at prob 0.05.
--   data/scripts/biomes/excavationsite.lua
--       RegisterSpawnFunction( 0xff7868ff, "load_puzzleroom" )
--       RegisterSpawnFunction( 0xffb09016, "spawn_meditation_cube" )
--       RegisterSpawnFunction( 0xff00855c, "spawn_receptacle" )
--       scene table g_puzzleroom = puzzleroom_01/02/03 (prob 1.5 each)
--   data/scripts/biomes/snowcave.lua
--       RegisterSpawnFunction( 0xff4691c7, "load_puzzle_capsule" )
--       RegisterSpawnFunction( 0xff3691d7, "load_puzzle_capsule_b" )
--       RegisterSpawnFunction( 0xffaa42ff, "spawn_electricity_trap" )
--       RegisterSpawnFunction( 0xff366178, "spawn_buried_eye_teleporter" )
--       scene tables g_puzzle_capsule / g_puzzle_capsule_b (prob 9.0 empty,
--       1.0 capsule) and g_pixel_scene_03 (buried_eye.png, prob 0.2)
--   data/entities/buildings/oiltank_puzzle.xml + scripts/buildings/oiltank_puzzle_check.lua
--   data/entities/buildings/swing_puzzle_target.xml + scripts/buildings/swing_puzzle_target.lua
--   data/entities/buildings/receptacle_oil.xml + scripts/buildings/receptacle_oil.lua
--   data/entities/buildings/receptacle_steam.xml + scripts/buildings/receptacle_steam.lua
--   data/entities/buildings/teleport_meditation_cube.xml
--   data/entities/buildings/teleport_snowcave_buried_eye.xml
--   data/scripts/biomes/excavationsite_cube_chamber.lua
--   data/scripts/biomes/snowcave_secret_chamber.lua
--   data/biome/_pixel_scenes.xml, data/biome/_biomes_all.xml
--
-- MARKER-PIXEL EVIDENCE (tools/puzzles/scan_marker_positions.py). A puzzle scene
-- is recognised by the spawn-function marker pixels actually present in its
-- bitmap, not by its name:
--
--   physics_swing_puzzle.png 260x130   0x005cfd (1px) 0x00b5fc (1px)
--   receptacle_oil.png       260x130   0xb97300 (1px)
--   oiltank_puzzle.png       130x260   0x93ca00 (1px)
--   puzzleroom_01/02/03.png  90x70     NO registered puzzle marker
--   puzzle_capsule.png       200x120   0xaa42ff, 0x50a0f0
--   puzzle_capsule_b.png     170x350   0xaa42ff, 0x50a0f0
--   buried_eye.png           169x250   0x366178
--   secret_chamber.png       512x512   0x366178, 0x50a0f0 (x2), 0x55af8c (x7)
--   cube_chamber.png         512x512   0x366178, 0x50a0f0, 0x55af8c (x3)
--
-- Collapsed Mines (coalmine_alt.lua) registers NO puzzle marker and its scene
-- tables contain no puzzle bitmap. Fungal Caverns (fungicave.lua) likewise.
-- That matches PRD R3, which grants a puzzle base only to Mines, Coal Pits and
-- Snowy Depths.
--
-- Lua 5.1 / LuaJIT 2.0 compatible. Data only: no functions, no state, no I/O.
-- Nothing here is verified against a running game.
--
-- ATTRIBUTION (substantial reuse, MIT)
--   noita-telescope, MIT License, Copyright (c) 2026 Lymm:
--     js/spawn_function_config.js  DEFAULT_SPAWNS (engine-default marker mapping)
--     js/pixel_scene_config.js     scene weights (cross-check only)
--     js/misc_generation.js        reward-room positions (cross-check only)
--   noita-tools, MIT License, Copyright (c) 2022 Seva Maltsev:
--     InfoProviders/Map/impl/Excavationsite.ts, Snowcavetunnel.ts
--     (puzzleroom / capsule tables, cross-check only)
--   The entries below were read out of the INSTALLED game files; upstream is
--   corroboration, never the source of truth for a scoring rule.

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

-- PRD R3, in exact score_units (4 units = 1 point).
M.UNITS = {
	PUZZLE_SCENE = 8, -- each real puzzle scene: +2
	CUBE_EXTRA = 20,  -- Meditation Cube, additionally: +5
	EYE_EXTRA = 20,   -- Buried Eye, additionally: +5
}

M.CATEGORY_EXISTENCE = "puzzles"
M.CATEGORY_BONUS = "puzzle_bonus"

-- Coverage is split so an entrance-only report can never look like a complete
-- seed enumeration, and so a delegated reward can never look like a scored one.
M.COVERAGE = {
	EXISTENCE = "puzzles.existence",
	REWARDS = "puzzles.rewards",
	REWARD_SCORING = "puzzles.reward_scoring",
	DISCOVERY = "puzzles.discovery",
}

-- ---------------------------------------------------------------------------
-- Regions
-- ---------------------------------------------------------------------------
--
-- `key` is the generator key that appears in worldgen discovery records and in
-- vanilla file tables. `name` is the PRD display name used on report entries.
--
-- `in_scope` is PRD section 2's "谜题及特殊谜题奖励" column: Mines yes,
-- Collapsed Mines no, Coal Pits yes, Fungal Caverns no, Snowy Depths yes.
--
-- `resource_scope` is the per-resource column that must STILL apply afterwards.
-- A Snowy Depths puzzle inherits the Snowy Depths resource scope, which grants
-- no wild-wand body, no in-wand spell share, no chest score and no R5 item
-- score. That is deliberately expressed here, once, instead of being re-derived
-- per call site.
M.REGIONS = {
	coalmine = {
		key = "coalmine",
		name = "Mines",
		in_scope = true,
		resource_scope = {
			wand_body = true,      -- R1 +1 per natural wand body
			wand_inner_spells = true, -- R1 in-wand target spells at 1/4
			chest = true,          -- R2
			r5_items = true,       -- R5 unstable teleportatium / gold pouch
		},
	},
	coalmine_alt = {
		key = "coalmine_alt",
		name = "Collapsed Mines",
		in_scope = false,
		out_of_scope_reason = "PRD R3 grants no puzzle base to Collapsed Mines",
		resource_scope = {
			wand_body = true, wand_inner_spells = true, chest = true, r5_items = false,
		},
	},
	excavationsite = {
		key = "excavationsite",
		name = "Coal Pits",
		in_scope = true,
		resource_scope = {
			wand_body = true, wand_inner_spells = true, chest = true, r5_items = true,
		},
	},
	fungicave = {
		key = "fungicave",
		name = "Fungal Caverns",
		in_scope = false,
		out_of_scope_reason = "PRD R3 grants no puzzle base to Fungal Caverns",
		resource_scope = {
			wand_body = false, wand_inner_spells = true, chest = true, r5_items = true,
		},
	},
	snowcave = {
		key = "snowcave",
		name = "Snowy Depths",
		in_scope = true,
		resource_scope = {
			-- PRD section 2: Snowy Depths gets NO wild-wand body, NO in-wand
			-- spell share, NO chest score and NO R5 item score. Its puzzles
			-- still earn their R3 existence score.
			wand_body = false, wand_inner_spells = false, chest = false, r5_items = false,
		},
	},
	-- Reward-room biomes. These are places, not scoring regions: a reward found
	-- in one of them is attributed to the ENTRANCE's region (PRD R3: 入口归属),
	-- never re-classified by the hidden room's own coordinates.
	excavationsite_cube_chamber = {
		key = "excavationsite_cube_chamber",
		name = "Meditation Cube chamber",
		in_scope = false,
		reward_room_of = "excavationsite",
		out_of_scope_reason = "hidden reward room; region is inherited from its entrance",
	},
	snowcave_secret_chamber = {
		key = "snowcave_secret_chamber",
		name = "Buried Eye chamber",
		in_scope = false,
		reward_room_of = "snowcave",
		out_of_scope_reason = "hidden reward room; region is inherited from its entrance",
	},
}

-- Accepted aliases -> generator key. Display names come from the PRD table; the
-- lower-case generator keys come from worldgen discovery records.
M.REGION_ALIASES = {
	["Mines"] = "coalmine",
	["mines"] = "coalmine",
	["Coal Pits"] = "excavationsite",
	["coal pits"] = "excavationsite",
	["CoalPits"] = "excavationsite",
	["Snowy Depths"] = "snowcave",
	["snowy depths"] = "snowcave",
	["Collapsed Mines"] = "coalmine_alt",
	["collapsed mines"] = "coalmine_alt",
	["Fungal Caverns"] = "fungicave",
	["fungal caverns"] = "fungicave",
	["excavationsite_cube_chamber"] = "excavationsite_cube_chamber",
	["snowcave_secret_chamber"] = "snowcave_secret_chamber",
}

-- ---------------------------------------------------------------------------
-- Marker colours (source citation, not a lookup mechanism)
-- ---------------------------------------------------------------------------
--
-- `rgb` is the 24-bit colour that a pixel-scene bitmap must contain for the
-- engine to dispatch the function. Each value is copied from the
-- RegisterSpawnFunction call listed above; `evidence` names the exact call.
M.MARKER_COLORS = {
	["0x005cfd"] = { rgb = 0x005cfd, func = "spawn_swing_puzzle_box", biome = "coalmine" },
	["0x00b5fc"] = { rgb = 0x00b5fc, func = "spawn_swing_puzzle_target", biome = "coalmine" },
	["0x93ca00"] = { rgb = 0x93ca00, func = "spawn_oiltank_puzzle", biome = "coalmine" },
	["0xb97300"] = { rgb = 0xb97300, func = "spawn_receptacle_oil", biome = "coalmine" },
	["0x7868ff"] = { rgb = 0x7868ff, func = "load_puzzleroom", biome = "excavationsite" },
	["0xb09016"] = { rgb = 0xb09016, func = "spawn_meditation_cube", biome = "excavationsite" },
	["0x00855c"] = { rgb = 0x00855c, func = "spawn_receptacle", biome = "excavationsite" },
	["0x4691c7"] = { rgb = 0x4691c7, func = "load_puzzle_capsule", biome = "snowcave" },
	["0x3691d7"] = { rgb = 0x3691d7, func = "load_puzzle_capsule_b", biome = "snowcave" },
	["0xaa42ff"] = { rgb = 0xaa42ff, func = "spawn_electricity_trap", biome = "snowcave" },
	["0x366178"] = { rgb = 0x366178, func = "spawn_buried_eye_teleporter", biome = "snowcave" },
}

-- ---------------------------------------------------------------------------
-- ENGINE-DEFAULT SPAWN MARKERS (used by reward-room bitmaps)
-- ---------------------------------------------------------------------------
--
-- Reward-room bitmaps carry marker pixels whose function is NOT registered by
-- their own biome script; it comes from the engine's built-in default spawn
-- table that is prepended to every biome list.
--
--   0x50a0f0 -> spawn_wands        (a free-standing wand drop)
--   0x55af8c -> spawn_skulls       (decoration)
--
-- The mapping is supported by two independent pieces of evidence:
--   * upstream noita-telescope js/spawn_function_config.js DEFAULT_SPAWNS lists
--     {color: 0x50A0F0, funcName: "spawn_wands"} in the default block that is
--     prepended to every biome (BIOME_SPAWN_FUNCTION_MAP);
--   * the project's own generated worldgen table
--     files/isf/worldgen/data/biome_data.lua contains the same 30 default
--     entries (indices 0..29) in every biome, including spawn_wands.
--
-- It is NOT confirmed against the engine's built-in registration in this build:
-- no string in data.wak registers 0x50a0f0, because that table lives in the
-- executable. Any reward that depends on it is therefore reported with
-- `marker_mapping = "unresolved_engine_default"` and is not scored, even though
-- the presence itself is source-justified. See WORKLOG/RESULT.
M.ENGINE_DEFAULT_MARKERS = {
	["0x50a0f0"] = {
		rgb = 0x50a0f0,
		func = "spawn_wands",
		confidence = "upstream_default_table",
		evidence = {
			"noita-telescope js/spawn_function_config.js DEFAULT_SPAWNS[{color:0x50A0F0}]",
			"files/isf/worldgen/data/biome_data.lua default spawn block (indices 0..29)",
		},
		unresolved = "not confirmed against the engine built-in registration in this build",
	},
	["0x55af8c"] = {
		rgb = 0x55af8c,
		func = "spawn_skulls",
		confidence = "upstream_default_table",
		evidence = {
			"noita-telescope js/spawn_function_config.js DEFAULT_SPAWNS[{color:0x55AF8C}]",
		},
		unresolved = "decoration only; never scored",
	},
}

-- ---------------------------------------------------------------------------
-- Puzzle kinds
-- ---------------------------------------------------------------------------
--
-- `scene_names`   variant scene bitmap names (no directory, no .png)
-- `markers`       marker functions that can announce this puzzle
-- `scene_markers` marker functions that appear INSIDE the scene bitmap and are
--                 part of the same physical puzzle (never a second instance)
-- `shared_scene`  true when several markers belong to one physical placement
-- `gate`          nil | "meditation" (deterministic per-position probability)
-- `bonus`         nil | "cube" | "eye"
-- `rewards`       deterministic reward predictions; see rewards.lua
M.KINDS = {
	{
		id = "mines_swing_rope",
		-- Actual trigger pixel in physics_swing_puzzle.png, not scene origin.
		anchor_scene_offset = { x = 199, y = 89 },
		puzzle_type = "swinging_rope",
		biome_key = "coalmine",
		label = "Mines swinging-rope puzzle",
		scene_names = { "physics_swing_puzzle" },
		markers = { "spawn_swing_puzzle_box", "spawn_swing_puzzle_target" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "spawn_swing_puzzle_target",
		provenance = {
			"coalmine.lua: RegisterSpawnFunction(0xff005cfd, spawn_swing_puzzle_box)",
			"coalmine.lua: RegisterSpawnFunction(0xff00b5fc, spawn_swing_puzzle_target)",
			"coalmine.lua: g_pixel_scene_02 contains physics_swing_puzzle.png (prob 0.5)",
			"scan: physics_swing_puzzle.png carries 0x005cfd and 0x00b5fc",
		},
		rewards = {
			{
				resource = "chest",
				kind = "chest",
				entity = "data/entities/items/pickup/chest_random.xml",
				anchor_marker = "spawn_swing_puzzle_target",
				dx = -75,
				dy = -70,
				presence = "conditional_on_solution",
				content = "delegated",
				delegated_to = "chests",
				scoring_rule = "R2",
				provenance = "scripts/buildings/swing_puzzle_target.lua: EntityLoad(chest_random.xml, x-75, y-70)",
			},
		},
	},
	{
		id = "mines_oil_receptacle",
		anchor_scene_offset = { x = 40, y = 55 },
		puzzle_type = "empty_flask_oil_receptacle",
		biome_key = "coalmine",
		label = "Mines empty-flask oil receptacle puzzle",
		scene_names = { "receptacle_oil" },
		markers = { "spawn_receptacle_oil" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "spawn_receptacle_oil",
		provenance = {
			"coalmine.lua: RegisterSpawnFunction(0xffb97300, spawn_receptacle_oil)",
			"coalmine.lua: g_pixel_scene_02 contains receptacle_oil.png (prob 0.5)",
			"coalmine.lua: spawn_receptacle_oil loads receptacle_oil.xml and potion_empty at x+72,y-17",
			"scan: receptacle_oil.png carries 0xb97300",
		},
		rewards = {
			{
				resource = "wand",
				kind = "wand",
				entity = "data/entities/items/wand_ruusu.xml",
				anchor_marker = "spawn_receptacle_oil",
				dx = 72,
				dy = -22,
				presence = "conditional_on_solution",
				content = "fixed_entity_procedural_cards",
				delegated_to = "wild_wands",
				scoring_rule = "R1",
				provenance = "scripts/buildings/receptacle_oil.lua: EntityLoad(wand_ruusu.xml, x+72, y-22)",
			},
			{
				resource = "potion",
				kind = "potion",
				entity = "data/entities/items/pickup/potion_empty.xml",
				anchor_marker = "spawn_receptacle_oil",
				dx = 72,
				dy = -17,
				presence = "deterministic_on_load",
				content = "empty",
				delegated_to = nil,
				scoring_rule = nil,
				not_scored_reason = "empty flask; R5 scores unstable-teleportatium flasks and gold pouches only",
				provenance = "coalmine.lua: spawn_receptacle_oil EntityLoad(potion_empty.xml, x+72, y-17)",
			},
		},
	},
	{
		id = "mines_oiltank_material",
		anchor_scene_offset = { x = 55, y = 234 },
		puzzle_type = "empty_receptacle_material",
		biome_key = "coalmine",
		label = "Mines empty-receptacle material puzzle",
		scene_names = { "oiltank_puzzle" },
		markers = { "spawn_oiltank_puzzle" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "spawn_oiltank_puzzle",
		provenance = {
			"coalmine.lua: RegisterSpawnFunction(0xff93ca00, spawn_oiltank_puzzle)",
			"coalmine.lua: g_oiltank contains oiltank_puzzle.png (prob 0.05)",
			"entities/buildings/oiltank_puzzle.xml: MaterialAreaCheckerComponent + oiltank_puzzle_check.lua",
			"scan: oiltank_puzzle.png carries 0x93ca00",
		},
		rewards = {
			{
				resource = "chest",
				kind = "chest",
				entity = "data/entities/items/pickup/chest_random.xml",
				anchor_marker = "spawn_oiltank_puzzle",
				dx = 0,
				dy = -25,
				presence = "conditional_on_solution",
				content = "delegated",
				delegated_to = "chests",
				scoring_rule = "R2",
				provenance = "scripts/buildings/oiltank_puzzle_check.lua: EntityLoad(chest_random.xml, x, y-25)",
			},
		},
	},
	{
		id = "coal_puzzleroom",
		puzzle_type = "capsule_puzzleroom",
		biome_key = "excavationsite",
		label = "Coal Pits capsule puzzle room",
		scene_names = { "puzzleroom_01", "puzzleroom_02", "puzzleroom_03" },
		markers = { "load_puzzleroom" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "load_puzzleroom",
		provenance = {
			"excavationsite.lua: RegisterSpawnFunction(0xff7868ff, load_puzzleroom)",
			"excavationsite.lua: g_puzzleroom = puzzleroom_01/02/03 (prob 1.5 each)",
			"puzzleroom_01 carries enemy markers only; rooms 02/03 carry one/two spawn_potion_altar markers",
			"nested altar containers are emitted by the region scanner, not created by solving the room",
		},
		rewards = {},
		reward_status = "delegated_to_region_scan",
		scene_resources = {
			puzzleroom_01 = { potion_altars = {} },
			puzzleroom_02 = { potion_altars = { {49,62} } },
			puzzleroom_03 = { potion_altars = { {36,60}, {58,61} } },
		},
		reward_reason = "on-load potion altars are enumerated recursively by the region scanner "
			.. "and their containers go to R5 through normal resource identities; "
			.. "R3 must not emit a duplicate reward or treat those objects as absent",
	},
	{
		id = "coal_meditation_cube",
		puzzle_type = "meditation_cube",
		biome_key = "excavationsite",
		label = "Coal Pits Meditation Cube",
		scene_names = { "meditation_cube" },
		markers = { "spawn_meditation_cube" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "spawn_meditation_cube",
		gate = "meditation",
		bonus = "cube",
		provenance = {
			"excavationsite.lua: RegisterSpawnFunction(0xffb09016, spawn_meditation_cube)",
			"excavationsite.lua: SetRandomSeed(x,y); if Random(1,100) > 96 then load cube + teleporter",
			"entities/buildings/teleport_meditation_cube.xml: TeleportComponent target (-4345, 2365)",
			"biomes/excavationsite_cube_chamber.lua: init loads cube_chamber.png",
			"scan: cube_chamber.png carries 0x50a0f0 (spawn_wands) and 0x366178 (return teleporter)",
		},
		rewards = {
			{
				resource = "wand",
				kind = "wand",
				entity = "data/entities/items/wand_level_03.xml",
				anchor = "reward_room",
				room_biome_key = "excavationsite_cube_chamber",
				room_target_x = -4345,
				room_target_y = 2365,
				room_marker_rgb = "0x50a0f0",
				room_marker_offset_x = 350,
				room_marker_offset_y = 303,
				presence = "deterministic_if_entrance",
				content = "delegated",
				delegated_to = "wild_wands",
				scoring_rule = "R1",
				provenance = "excavationsite_cube_chamber.lua loads cube_chamber.png; "
					.. "cube_chamber.png carries 0x50a0f0 at (350,303); "
					.. "teleport_meditation_cube.xml targets (-4345, 2365)",
			},
		},
	},
	{
		id = "snow_capsule_a",
		puzzle_type = "capsule",
		mechanism = "electric_box",
		biome_key = "snowcave",
		label = "Snowy Depths capsule puzzle (variant A)",
		scene_names = { "puzzle_capsule" },
		markers = { "load_puzzle_capsule" },
		scene_markers = { "spawn_electricity_trap" },
		shared_scene = true,
		anchor_marker = "spawn_electricity_trap",
		provenance = {
			"snowcave.lua: RegisterSpawnFunction(0xff4691c7, load_puzzle_capsule)",
			"snowcave.lua: g_puzzle_capsule = 9.0 empty / 1.0 puzzle_capsule",
			"scan: puzzle_capsule.png carries 0xaa42ff (spawn_electricity_trap) and 0x50a0f0",
		},
		rewards = {
			{
				resource = "wand",
				kind = "wand",
				entity = "data/entities/items/wand_level_02.xml",
				anchor = "scene_marker",
				scene_marker_rgb = "0x50a0f0",
				scene_marker_offset_x = 160,
				scene_marker_offset_y = 67,
				presence = "source_justified_engine_default_marker",
				marker_mapping = "unresolved_engine_default",
				content = "delegated",
				delegated_to = "wild_wands",
				scoring_rule = "R1",
				provenance = "puzzle_capsule.png carries 0x50a0f0 at (160,67)",
			},
		},
	},
	{
		id = "snow_capsule_b",
		puzzle_type = "capsule",
		mechanism = "electric_box",
		biome_key = "snowcave",
		label = "Snowy Depths capsule puzzle (variant B)",
		scene_names = { "puzzle_capsule_b" },
		markers = { "load_puzzle_capsule_b" },
		scene_markers = { "spawn_electricity_trap" },
		shared_scene = true,
		anchor_marker = "spawn_electricity_trap",
		provenance = {
			"snowcave.lua: RegisterSpawnFunction(0xff3691d7, load_puzzle_capsule_b)",
			"snowcave.lua: g_puzzle_capsule_b = 9.0 empty / 1.0 puzzle_capsule_b, placed at x-50, y-230",
			"scan: puzzle_capsule_b.png carries 0xaa42ff (spawn_electricity_trap) and 0x50a0f0",
		},
		rewards = {
			{
				resource = "wand",
				kind = "wand",
				entity = "data/entities/items/wand_level_02.xml",
				anchor = "scene_marker",
				scene_marker_rgb = "0x50a0f0",
				scene_marker_offset_x = 135,
				scene_marker_offset_y = 297,
				presence = "source_justified_engine_default_marker",
				marker_mapping = "unresolved_engine_default",
				content = "delegated",
				delegated_to = "wild_wands",
				scoring_rule = "R1",
				provenance = "puzzle_capsule_b.png carries 0x50a0f0 at (135,297)",
			},
		},
	},
	{
		id = "snow_buried_eye",
		puzzle_type = "buried_eye",
		biome_key = "snowcave",
		label = "Snowy Depths buried eye",
		scene_names = { "buried_eye" },
		markers = { "spawn_buried_eye_teleporter" },
		scene_markers = {},
		shared_scene = true,
		anchor_marker = "spawn_buried_eye_teleporter",
		bonus = "eye",
		provenance = {
			"snowcave.lua: RegisterSpawnFunction(0xff366178, spawn_buried_eye_teleporter)",
			"snowcave.lua: g_pixel_scene_03 contains buried_eye.png (prob 0.2)",
			"scan: buried_eye.png carries 0x366178",
			"entities/buildings/teleport_snowcave_buried_eye.xml: target (3895, 4510)",
			"biomes/snowcave_secret_chamber.lua: init loads secret_chamber.png",
			"scan: secret_chamber.png carries 0x366178 + 0x50a0f0 x2",
		},
		rewards = {
			{
				resource = "wand",
				kind = "wand",
				entity = "data/entities/items/wand_level_03.xml",
				anchor = "reward_room",
				room_biome_key = "snowcave_secret_chamber",
				room_target_x = 3895,
				room_target_y = 4510,
				room_marker_rgb = "0x50a0f0",
				room_marker_count = 2,
				-- secret_chamber.png carries 0x50a0f0 at (333,297) and (439,324);
				-- room origin is (3584, 4096). Two wands, two coordinates: keep
				-- both so no consumer silently picks one.
				room_marker_offsets = { { 333, 297 }, { 439, 324 } },
				presence = "deterministic_if_entrance",
				content = "delegated",
				delegated_to = "wild_wands",
				scoring_rule = "R1",
				provenance = "secret_chamber.png carries 0x50a0f0 twice; "
					.. "teleport_snowcave_buried_eye.xml targets (3895, 4510)",
			},
		},
	},
}

M.KIND_BY_ID = {}
for i = 1, #M.KINDS do
	local kind = M.KINDS[ i ]
	M.KIND_BY_ID[ kind.id ] = kind
end

-- Index: spawn function name -> kind definition list (a function can only
-- announce one puzzle kind, except the shared electric-trap marker which is
-- handled by scene context in recognize.lua).
M.KIND_BY_FUNCTION = {}
M.KIND_BY_SCENE = {}
for i = 1, #M.KINDS do
	local kind = M.KINDS[ i ]
	for _, fn in ipairs( kind.markers ) do
		M.KIND_BY_FUNCTION[ fn ] = M.KIND_BY_FUNCTION[ fn ] or {}
		table.insert( M.KIND_BY_FUNCTION[ fn ], kind )
	end
	for _, scene in ipairs( kind.scene_names ) do
		M.KIND_BY_SCENE[ scene ] = kind
	end
end

-- Marker function -> true when it is only a *mechanism inside* a scene and must
-- never create an instance on its own. `spawn_electricity_trap` is also a plain
-- prop in snowcave's g_props (prob 0.05) and in other biomes, so an isolated
-- electric-trap marker is NOT a puzzle.
M.SCENE_ONLY_FUNCTIONS = {
	spawn_electricity_trap = true,
}

-- Puzzles that get the PRD R3 "extra" bonus.
M.BONUS_KIND = {
	cube = "coal_meditation_cube",
	eye = "snow_buried_eye",
}

-- Reward-room biomes: a reward is always attributed to `reward_room_of`.
M.ROOM_TO_ENTRANCE = {
	excavationsite_cube_chamber = "excavationsite",
	snowcave_secret_chamber = "snowcave",
}

-- Every biome key that can host a puzzle entrance in this build.
M.SUPPORTED_ENTRANCE_BIOMES = {
	coalmine = true,
	excavationsite = true,
	snowcave = true,
}

return M
