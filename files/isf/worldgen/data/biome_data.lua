-- files/isf/worldgen/data/biome_data.lua
--
-- Per-biome spawn tables, pixel-scene lists, altar gates, generator
-- metadata and PRD section 2 resource scope for the discovery path.
--
-- GENERATED FILE - do not edit by hand. Regenerate with:
--   node tools/worldgen/oracle/extract_biome_data.mjs
--
-- Derived from noita-telescope js/spawn_function_config.js,
-- js/pixel_scene_config.js, js/spawn_config.js, js/generator_config.js
-- MIT License, Copyright (c) 2026 Lymm
--
-- SCOPE: five biomes. Mines / Collapsed Mines / Coal Pits / Fungal
-- Caverns carry R1 scoring scope; Snowy Depths (snowcave) is DISCOVERY
-- ONLY and scores no wild-wand body, no in-wand spell share, no chest and
-- no R5 item (PRD section 2). Other fungal/Overgrown areas are absent.
--
-- ARRAY ORDER IS LOAD-BEARING: spawn-pixel RGB colours are looked up by
-- scanning the array, and the resulting INDEX is what the game dispatches on.

local M = {}

-- Scope version so a consumer can detect a stale snapshot.
M.SCOPE_VERSION = 1

M.biomes = {
  ["coalmine"] = {
    key = "coalmine",
    name = "Mines",
    region = "mines",
    scored = true,
    body_bonus = true,
    wand_spells = true,
    color = 13990167,
    wang_file = "coalmine.png",
    small_altar = false,
    scope = {
      wand_body = true,
      wand_inner_spells = true,
      chest = true,
      puzzle = true,
      shop = true,
      unstable_teleportatium = true,
      gold_pouch = true,
    },
    spawns = {
      { index = 0, color = 16711680, func = "spawn_small_enemies", active = true, is_pixel_scene = false },
      { index = 1, color = 8388608, func = "spawn_big_enemies", active = true, is_pixel_scene = false },
      { index = 2, color = 65280, func = "spawn_items", active = true, is_pixel_scene = true },
      { index = 3, color = 13143322, func = "spawn_props", active = true, is_pixel_scene = false },
      { index = 4, color = 13139968, func = "spawn_props2", active = true, is_pixel_scene = false },
      { index = 5, color = 13107264, func = "spawn_props3", active = true, is_pixel_scene = false },
      { index = 6, color = 16776960, func = "spawn_lamp", active = true, is_pixel_scene = false },
      { index = 7, color = 16714495, func = "load_pixel_scene", active = true, is_pixel_scene = true },
      { index = 8, color = 16711808, func = "load_pixel_scene2", active = true, is_pixel_scene = true },
      { index = 9, color = 16744448, func = "spawn_unique_enemy", active = true, is_pixel_scene = false },
      { index = 10, color = 13123648, func = "spawn_unique_enemy2", active = true, is_pixel_scene = false },
      { index = 11, color = 8405056, func = "spawn_unique_enemy3", active = true, is_pixel_scene = false },
      { index = 12, color = 9881680, func = "spawn_ghostlamp", active = true, is_pixel_scene = false },
      { index = 13, color = 6332516, func = "spawn_candles", active = true, is_pixel_scene = false },
      { index = 14, color = 5283840, func = "spawn_potion_altar", active = true, is_pixel_scene = true },
      { index = 15, color = 12361968, func = "spawn_potions", active = true, is_pixel_scene = false },
      { index = 16, color = 65370, func = "spawn_apparition", active = true, is_pixel_scene = false },
      { index = 17, color = 7929855, func = "spawn_heart", active = true, is_pixel_scene = false },
      { index = 18, color = 5284080, func = "spawn_wands", active = true, is_pixel_scene = false },
      { index = 19, color = 12527270, func = "spawn_portal", active = true, is_pixel_scene = false },
      { index = 20, color = 305527, func = "spawn_end_portal", active = true, is_pixel_scene = false },
      { index = 21, color = 16765297, func = "spawn_orb", active = true, is_pixel_scene = false },
      { index = 22, color = 16765313, func = "spawn_perk", active = true, is_pixel_scene = false },
      { index = 23, color = 16777089, func = "spawn_all_perks", active = true, is_pixel_scene = false },
      { index = 24, color = 13101864, func = "spawn_wand_trap", active = true, is_pixel_scene = false },
      { index = 25, color = 15269760, func = "spawn_wand_trap_ignite", active = true, is_pixel_scene = false },
      { index = 26, color = 2582750, func = "spawn_wand_trap_electricity_source", active = true, is_pixel_scene = false },
      { index = 27, color = 2582751, func = "spawn_wand_trap_electricity", active = true, is_pixel_scene = false },
      { index = 28, color = 7032731, func = "spawn_moon", active = true, is_pixel_scene = false },
      { index = 29, color = 14136296, func = "spawn_collapse", active = true, is_pixel_scene = false },
      { index = 30, color = 255, func = "spawn_nest", active = true, is_pixel_scene = false },
      { index = 31, color = 11796480, func = "spawn_fungi", active = true, is_pixel_scene = false },
      { index = 32, color = 9868920, func = "load_structures", active = true, is_pixel_scene = false },
      { index = 33, color = 9861240, func = "load_large_structures", active = true, is_pixel_scene = false },
      { index = 34, color = 9861270, func = "load_i_structures", active = true, is_pixel_scene = false },
      { index = 35, color = 8453978, func = "spawn_vines", active = true, is_pixel_scene = false },
      { index = 36, color = 12801792, func = "load_oiltank", active = true, is_pixel_scene = true },
      { index = 37, color = 5615435, func = "load_altar", active = true, is_pixel_scene = true },
      { index = 38, color = 2341315, func = "spawn_altar_torch", active = true, is_pixel_scene = false },
      { index = 39, color = 5615500, func = "spawn_skulls", active = true, is_pixel_scene = false },
      { index = 40, color = 5635980, func = "spawn_chest", active = true, is_pixel_scene = false },
      { index = 41, color = 5117790, func = "load_oiltank_alt", active = true, is_pixel_scene = true },
      { index = 42, color = 3380044, func = "spawn_shopitem", active = true, is_pixel_scene = false },
      { index = 43, color = 5307130, func = "spawn_trapwand", active = true, is_pixel_scene = false },
      { index = 44, color = 15805109, func = "spawn_bbqbox", active = true, is_pixel_scene = false },
      { index = 45, color = 23805, func = "spawn_swing_puzzle_box", active = true, is_pixel_scene = false },
      { index = 46, color = 46588, func = "spawn_swing_puzzle_target", active = true, is_pixel_scene = false },
      { index = 47, color = 9685504, func = "spawn_oiltank_puzzle", active = true, is_pixel_scene = false },
      { index = 48, color = 12153600, func = "spawn_receptacle_oil", active = true, is_pixel_scene = false },
    },
    scenes = {
      ["g_altar"] = {
        { prob = 1, name = "trailer_altar" },
      },
      ["g_oiltank"] = {
        { prob = 1, name = "oiltank_1", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "sand", "coal", "radioactive_liquid" } } },
        { prob = 0.0004, name = "oiltank_1", color_material = { ["f0bbee"] = { "magic_liquid_teleportation", "magic_liquid_polymorph", "magic_liquid_random_polymorph", "magic_liquid_berserk", "magic_liquid_charm", "magic_liquid_invisibility", "magic_liquid_hp_regeneration", "salt", "blood", "gold", "honey" } } },
        { prob = 0.01, name = "oiltank_2", color_material = { ["f0bbee"] = { "blood_fungi", "blood_cold", "lava", "poison", "slime", "gunpowder_explosive", "soil", "salt", "blood", "cement" } } },
        { prob = 1, name = "oiltank_2", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "oil", "coal", "radioactive_liquid" } } },
        { prob = 1, name = "oiltank_3", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "water", "coal", "radioactive_liquid", "magic_liquid_teleportation" } } },
        { prob = 1, name = "oiltank_4", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "sand", "coal", "radioactive_liquid", "magic_liquid_polymorph" } } },
        { prob = 1, name = "oiltank_5", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "radioactive_liquid", "coal", "radioactive_liquid" } } },
        { prob = 0.05, name = "oiltank_puzzle" },
      },
      ["g_oiltank_alt"] = {
        { prob = 1, name = "oiltank_alt", color_material = { ["f0bbee"] = { "water", "oil", "water", "oil", "alcohol", "sand", "radioactive_liquid", "radioactive_liquid", "magic_liquid_berserk" } } },
      },
      ["g_pixel_scene_01"] = {
        { prob = 0.5, name = "coalpit01" },
        { prob = 0.5, name = "coalpit02" },
        { prob = 0.5, name = "carthill" },
        { prob = 0.5, name = "coalpit03" },
        { prob = 0.5, name = "coalpit04" },
        { prob = 0.5, name = "coalpit05" },
      },
      ["g_pixel_scene_02"] = {
        { prob = 0.5, name = "shrine01" },
        { prob = 0.5, name = "shrine02" },
        { prob = 0.5, name = "slimepit" },
        { prob = 0.5, name = "laboratory" },
        { prob = 0.5, name = "swarm" },
        { prob = 0.5, name = "symbolroom" },
        { prob = 0.5, name = "physics_01" },
        { prob = 0.5, name = "physics_02" },
        { prob = 0.5, name = "physics_03" },
        { prob = 1.5, name = "shop" },
        { prob = 0.5, name = "radioactivecave" },
        { prob = 0.75, name = "wandtrap_h_02" },
        { prob = 0.75, name = "wandtrap_h_04", color_material = { ["f0bbee"] = { "oil", "alcohol", "gunpowder_explosive" } } },
        { prob = 0.75, name = "wandtrap_h_06", color_material = { ["f0bbee"] = { "magic_liquid_teleportation", "magic_liquid_polymorph", "magic_liquid_random_polymorph", "radioactive_liquid" } } },
        { prob = 0.75, name = "wandtrap_h_07", color_material = { ["f0bbee"] = { "water", "oil", "alcohol", "radioactive_liquid" } } },
        { prob = 0.5, name = "physics_swing_puzzle" },
        { prob = 0.5, name = "receptacle_oil" },
      },
    },
    altar = { r0 = 0.47, rl = 0.755, x = 5, y = -9, xoff = -11.431, yoff = 10.5257, rp = 0.65, px = 5, py = -4, gx = 0, gy = 0 },
    wand_lottery = { types = { "premade_1", "premade_2", "premade_3", "premade_4", "premade_5", "premade_6", "premade_7", "premade_8", "premade_9", "premade_10", "premade_11", "premade_12", "premade_13", "premade_14", "premade_15", "premade_16", "premade_17", "wand_level_01" }, weights = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.9 } },
  },
  ["coalmine_alt"] = {
    key = "coalmine_alt",
    name = "Collapsed Mines",
    region = "mines",
    scored = true,
    body_bonus = true,
    wand_spells = true,
    color = 13985047,
    wang_file = "coalmine_alt.png",
    small_altar = false,
    scope = {
      wand_body = true,
      wand_inner_spells = true,
      chest = true,
      puzzle = false,
      shop = false,
      unstable_teleportatium = false,
      gold_pouch = false,
    },
    spawns = {
      { index = 0, color = 16711680, func = "spawn_small_enemies", active = true, is_pixel_scene = false },
      { index = 1, color = 8388608, func = "spawn_big_enemies", active = true, is_pixel_scene = false },
      { index = 2, color = 65280, func = "spawn_items", active = true, is_pixel_scene = true },
      { index = 3, color = 13143322, func = "spawn_props", active = true, is_pixel_scene = false },
      { index = 4, color = 13139968, func = "spawn_props2", active = true, is_pixel_scene = false },
      { index = 5, color = 13107264, func = "spawn_props3", active = true, is_pixel_scene = false },
      { index = 6, color = 16776960, func = "spawn_lamp", active = true, is_pixel_scene = false },
      { index = 7, color = 16714495, func = "load_pixel_scene", active = true, is_pixel_scene = true },
      { index = 8, color = 16711808, func = "load_pixel_scene2", active = true, is_pixel_scene = true },
      { index = 9, color = 16744448, func = "spawn_unique_enemy", active = true, is_pixel_scene = false },
      { index = 10, color = 13123648, func = "spawn_unique_enemy2", active = true, is_pixel_scene = false },
      { index = 11, color = 8405056, func = "spawn_unique_enemy3", active = true, is_pixel_scene = false },
      { index = 12, color = 9881680, func = "spawn_ghostlamp", active = true, is_pixel_scene = false },
      { index = 13, color = 6332516, func = "spawn_candles", active = true, is_pixel_scene = false },
      { index = 14, color = 5283840, func = "spawn_potion_altar", active = true, is_pixel_scene = true },
      { index = 15, color = 12361968, func = "spawn_potions", active = true, is_pixel_scene = false },
      { index = 16, color = 65370, func = "spawn_apparition", active = true, is_pixel_scene = false },
      { index = 17, color = 7929855, func = "spawn_heart", active = true, is_pixel_scene = false },
      { index = 18, color = 5284080, func = "spawn_wands", active = true, is_pixel_scene = false },
      { index = 19, color = 12527270, func = "spawn_portal", active = true, is_pixel_scene = false },
      { index = 20, color = 305527, func = "spawn_end_portal", active = true, is_pixel_scene = false },
      { index = 21, color = 16765297, func = "spawn_orb", active = true, is_pixel_scene = false },
      { index = 22, color = 16765313, func = "spawn_perk", active = true, is_pixel_scene = false },
      { index = 23, color = 16777089, func = "spawn_all_perks", active = true, is_pixel_scene = false },
      { index = 24, color = 13101864, func = "spawn_wand_trap", active = true, is_pixel_scene = false },
      { index = 25, color = 15269760, func = "spawn_wand_trap_ignite", active = true, is_pixel_scene = false },
      { index = 26, color = 2582750, func = "spawn_wand_trap_electricity_source", active = true, is_pixel_scene = false },
      { index = 27, color = 2582751, func = "spawn_wand_trap_electricity", active = true, is_pixel_scene = false },
      { index = 28, color = 7032731, func = "spawn_moon", active = true, is_pixel_scene = false },
      { index = 29, color = 14136296, func = "spawn_collapse", active = true, is_pixel_scene = false },
      { index = 30, color = 255, func = "spawn_nest", active = true, is_pixel_scene = false },
      { index = 31, color = 11796480, func = "spawn_fungi", active = true, is_pixel_scene = false },
      { index = 32, color = 9868920, func = "load_structures", active = true, is_pixel_scene = false },
      { index = 33, color = 9861240, func = "load_large_structures", active = true, is_pixel_scene = false },
      { index = 34, color = 8453978, func = "spawn_vines", active = true, is_pixel_scene = false },
      { index = 35, color = 3380044, func = "spawn_shopitem", active = true, is_pixel_scene = false },
    },
    scenes = {
      ["g_pixel_scene_01"] = {
        { prob = 0.5, name = "coalpit01" },
        { prob = 0.5, name = "coalpit02" },
        { prob = 0.5, name = "carthill" },
        { prob = 0.5, name = "coalpit03" },
        { prob = 0.5, name = "coalpit04" },
        { prob = 0.5, name = "coalpit05" },
      },
      ["g_pixel_scene_02"] = {
        { prob = 0.5, name = "shrine01_alt", is_unique = true },
        { prob = 0.5, name = "shrine02_alt" },
        { prob = 0.5, name = "swarm_alt" },
        { prob = 1.2, name = "symbolroom_alt" },
        { prob = 1.2, name = "physics_01_alt" },
        { prob = 1.2, name = "physics_02_alt" },
        { prob = 1.2, name = "physics_03_alt" },
        { prob = 0.75, name = "shop_alt" },
        { prob = 0.5, name = "radioactivecave" },
      },
    },
    altar = { r0 = 0.47, rl = 0.725, x = 0, y = -14, xoff = -11.431, yoff = 10.5257, rp = 0.65, px = 5, py = -4 },
    wand_lottery = { types = { "premade_1", "premade_2", "premade_3", "premade_4", "premade_5", "premade_6", "premade_7", "premade_8", "premade_9" }, weights = { 1, 1, 1, 1, 1, 1, 1, 1, 1 } },
  },
  ["excavationsite"] = {
    key = "excavationsite",
    name = "Coal Pits",
    region = "mines",
    scored = true,
    body_bonus = true,
    wand_spells = true,
    color = 1197125,
    wang_file = "excavationsite.png",
    small_altar = false,
    scope = {
      wand_body = true,
      wand_inner_spells = true,
      chest = true,
      puzzle = true,
      shop = true,
      unstable_teleportatium = true,
      gold_pouch = true,
    },
    spawns = {
      { index = 0, color = 16711680, func = "spawn_small_enemies", active = true, is_pixel_scene = false },
      { index = 1, color = 8388608, func = "spawn_big_enemies", active = true, is_pixel_scene = false },
      { index = 2, color = 65280, func = "spawn_items", active = true, is_pixel_scene = true },
      { index = 3, color = 13143322, func = "spawn_props", active = true, is_pixel_scene = false },
      { index = 4, color = 13139968, func = "spawn_props2", active = true, is_pixel_scene = false },
      { index = 5, color = 13107264, func = "spawn_props3", active = true, is_pixel_scene = false },
      { index = 6, color = 16776960, func = "spawn_lamp", active = true, is_pixel_scene = false },
      { index = 7, color = 16714495, func = "load_pixel_scene", active = true, is_pixel_scene = true },
      { index = 8, color = 16711808, func = "load_pixel_scene2", active = true, is_pixel_scene = true },
      { index = 9, color = 16744448, func = "spawn_unique_enemy", active = true, is_pixel_scene = false },
      { index = 10, color = 13123648, func = "spawn_unique_enemy2", active = true, is_pixel_scene = false },
      { index = 11, color = 8405056, func = "spawn_unique_enemy3", active = true, is_pixel_scene = false },
      { index = 12, color = 9881680, func = "spawn_ghostlamp", active = true, is_pixel_scene = false },
      { index = 13, color = 6332516, func = "spawn_candles", active = true, is_pixel_scene = false },
      { index = 14, color = 5283840, func = "spawn_potion_altar", active = true, is_pixel_scene = true },
      { index = 15, color = 12361968, func = "spawn_potions", active = true, is_pixel_scene = false },
      { index = 16, color = 65370, func = "spawn_apparition", active = true, is_pixel_scene = false },
      { index = 17, color = 7929855, func = "spawn_heart", active = true, is_pixel_scene = false },
      { index = 18, color = 5284080, func = "spawn_wands", active = true, is_pixel_scene = false },
      { index = 19, color = 12527270, func = "spawn_portal", active = true, is_pixel_scene = false },
      { index = 20, color = 305527, func = "spawn_end_portal", active = true, is_pixel_scene = false },
      { index = 21, color = 16765297, func = "spawn_orb", active = true, is_pixel_scene = false },
      { index = 22, color = 16765313, func = "spawn_perk", active = true, is_pixel_scene = false },
      { index = 23, color = 16777089, func = "spawn_all_perks", active = true, is_pixel_scene = false },
      { index = 24, color = 13101864, func = "spawn_wand_trap", active = true, is_pixel_scene = false },
      { index = 25, color = 15269760, func = "spawn_wand_trap_ignite", active = true, is_pixel_scene = false },
      { index = 26, color = 2582750, func = "spawn_wand_trap_electricity_source", active = true, is_pixel_scene = false },
      { index = 27, color = 2582751, func = "spawn_wand_trap_electricity", active = true, is_pixel_scene = false },
      { index = 28, color = 7032731, func = "spawn_moon", active = true, is_pixel_scene = false },
      { index = 29, color = 14136296, func = "spawn_collapse", active = true, is_pixel_scene = false },
      { index = 30, color = 255, func = "spawn_nest", active = true, is_pixel_scene = false },
      { index = 31, color = 16732415, func = "spawn_hanger", active = true, is_pixel_scene = false },
      { index = 32, color = 44132, func = "load_pixel_scene4", active = true, is_pixel_scene = true },
      { index = 33, color = 44142, func = "load_pixel_scene4_alt", active = true, is_pixel_scene = true },
      { index = 34, color = 20735, func = "spawn_wheel", active = true, is_pixel_scene = false },
      { index = 35, color = 86271, func = "spawn_wheel_small", active = true, is_pixel_scene = false },
      { index = 36, color = 151807, func = "spawn_wheel_tiny", active = true, is_pixel_scene = false },
      { index = 37, color = 2961068, func = "spawn_rock", active = true, is_pixel_scene = false },
      { index = 38, color = 676095, func = "spawn_physicsstructure", active = true, is_pixel_scene = false },
      { index = 39, color = 13212159, func = "spawn_hanging_prop", active = true, is_pixel_scene = false },
      { index = 40, color = 7891199, func = "load_puzzleroom", active = true, is_pixel_scene = true },
      { index = 41, color = 7395230, func = "load_gunpowderpool_01", active = true, is_pixel_scene = true },
      { index = 42, color = 7395231, func = "load_gunpowderpool_02", active = true, is_pixel_scene = true },
      { index = 43, color = 7395232, func = "load_gunpowderpool_03", active = true, is_pixel_scene = true },
      { index = 44, color = 7395233, func = "load_gunpowderpool_04", active = true, is_pixel_scene = true },
      { index = 45, color = 3380044, func = "spawn_shopitem", active = true, is_pixel_scene = false },
      { index = 46, color = 11571222, func = "spawn_meditation_cube", active = true, is_pixel_scene = false },
      { index = 47, color = 34140, func = "spawn_receptacle", active = true, is_pixel_scene = false },
      { index = 48, color = 11665305, func = "spawn_tower_short", active = true, is_pixel_scene = false },
      { index = 49, color = 6063440, func = "spawn_tower_tall", active = true, is_pixel_scene = false },
      { index = 50, color = 2260991, func = "spawn_beam_low", active = true, is_pixel_scene = false },
      { index = 51, color = 8530175, func = "spawn_beam_low_flipped", active = true, is_pixel_scene = false },
      { index = 52, color = 39098, func = "spawn_beam_steep", active = true, is_pixel_scene = false },
      { index = 53, color = 7733417, func = "spawn_beam_steep_flipped", active = true, is_pixel_scene = false },
    },
    scenes = {
      ["extras"] = {
        { prob = 0, name = "meditation_cube_visual" },
      },
      ["g_gunpowderpool_01"] = {
        { prob = 1.5, name = "gunpowderpool_01" },
      },
      ["g_gunpowderpool_02"] = {
        { prob = 1.5, name = "gunpowderpool_02" },
      },
      ["g_gunpowderpool_03"] = {
        { prob = 1.5, name = "gunpowderpool_03" },
      },
      ["g_gunpowderpool_04"] = {
        { prob = 1.5, name = "gunpowderpool_04" },
      },
      ["g_pixel_scene_01"] = {
      },
      ["g_pixel_scene_02"] = {
      },
      ["g_pixel_scene_04"] = {
        { prob = 0.5, name = "machine_1" },
        { prob = 0.5, name = "machine_2" },
        { prob = 0.5, name = "machine_3b" },
        { prob = 0.5, name = "machine_4" },
        { prob = 0.5, name = "machine_5" },
        { prob = 0.5, name = "machine_6" },
        { prob = 0.3, name = "machine_7" },
        { prob = 3, name = "shop" },
        { prob = 0.8, name = "oiltank_1" },
        { prob = 0.8, name = "lake" },
      },
      ["g_pixel_scene_04_alt"] = {
        { prob = 0.5, name = "machine_1_alt" },
        { prob = 0.5, name = "machine_2_alt" },
        { prob = 0.5, name = "machine_3b_alt" },
        { prob = 0.5, name = "machine_4_alt" },
        { prob = 0.5, name = "machine_5_alt" },
        { prob = 0.5, name = "machine_6_alt" },
        { prob = 0.3, name = "machine_7_alt" },
        { prob = 3, name = "shop_alt" },
        { prob = 0.7, name = "receptacle_steam" },
        { prob = 0.8, name = "lake_alt" },
      },
      ["g_puzzleroom"] = {
        { prob = 1.5, name = "puzzleroom_01" },
        { prob = 1.5, name = "puzzleroom_02" },
        { prob = 1.5, name = "puzzleroom_03" },
      },
    },
    altar = { rl = 0.725, x = 0, y = -14, xoff = -11.431, yoff = 10.5257 },
    wand_lottery = { types = { "wand_unshuffle_01", "wand_level_02", "wand_level_02_better" }, weights = { 2, 2, 2 } },
  },
  ["fungicave"] = {
    key = "fungicave",
    name = "Fungal Caverns",
    region = "fungal",
    scored = true,
    body_bonus = false,
    wand_spells = true,
    color = 15229424,
    wang_file = "fungicave.png",
    small_altar = false,
    scope = {
      wand_body = false,
      wand_inner_spells = true,
      chest = true,
      puzzle = false,
      shop = false,
      unstable_teleportatium = false,
      gold_pouch = true,
    },
    spawns = {
      { index = 0, color = 16711680, func = "spawn_small_enemies", active = true, is_pixel_scene = false },
      { index = 1, color = 8388608, func = "spawn_big_enemies", active = true, is_pixel_scene = false },
      { index = 2, color = 65280, func = "spawn_items", active = true, is_pixel_scene = true },
      { index = 3, color = 13143322, func = "spawn_props", active = true, is_pixel_scene = false },
      { index = 4, color = 13139968, func = "spawn_props2", active = true, is_pixel_scene = false },
      { index = 5, color = 13107264, func = "spawn_props3", active = true, is_pixel_scene = false },
      { index = 6, color = 16776960, func = "spawn_lamp", active = true, is_pixel_scene = false },
      { index = 7, color = 16714495, func = "load_pixel_scene", active = true, is_pixel_scene = true },
      { index = 8, color = 16711808, func = "load_pixel_scene2", active = true, is_pixel_scene = true },
      { index = 9, color = 16744448, func = "spawn_unique_enemy", active = true, is_pixel_scene = false },
      { index = 10, color = 13123648, func = "spawn_unique_enemy2", active = true, is_pixel_scene = false },
      { index = 11, color = 8405056, func = "spawn_unique_enemy3", active = true, is_pixel_scene = false },
      { index = 12, color = 9881680, func = "spawn_ghostlamp", active = true, is_pixel_scene = false },
      { index = 13, color = 6332516, func = "spawn_candles", active = true, is_pixel_scene = false },
      { index = 14, color = 5283840, func = "spawn_potion_altar", active = true, is_pixel_scene = true },
      { index = 15, color = 12361968, func = "spawn_potions", active = true, is_pixel_scene = false },
      { index = 16, color = 65370, func = "spawn_apparition", active = true, is_pixel_scene = false },
      { index = 17, color = 7929855, func = "spawn_heart", active = true, is_pixel_scene = false },
      { index = 18, color = 5284080, func = "spawn_wands", active = true, is_pixel_scene = false },
      { index = 19, color = 12527270, func = "spawn_portal", active = true, is_pixel_scene = false },
      { index = 20, color = 305527, func = "spawn_end_portal", active = true, is_pixel_scene = false },
      { index = 21, color = 16765297, func = "spawn_orb", active = true, is_pixel_scene = false },
      { index = 22, color = 16765313, func = "spawn_perk", active = true, is_pixel_scene = false },
      { index = 23, color = 16777089, func = "spawn_all_perks", active = true, is_pixel_scene = false },
      { index = 24, color = 13101864, func = "spawn_wand_trap", active = true, is_pixel_scene = false },
      { index = 25, color = 15269760, func = "spawn_wand_trap_ignite", active = true, is_pixel_scene = false },
      { index = 26, color = 2582750, func = "spawn_wand_trap_electricity_source", active = true, is_pixel_scene = false },
      { index = 27, color = 2582751, func = "spawn_wand_trap_electricity", active = true, is_pixel_scene = false },
      { index = 28, color = 7032731, func = "spawn_moon", active = true, is_pixel_scene = false },
      { index = 29, color = 14136296, func = "spawn_collapse", active = true, is_pixel_scene = false },
      { index = 30, color = 16772829, func = "init", active = true, is_pixel_scene = false },
      { index = 31, color = 4194304, func = "spawn_robots", active = true, is_pixel_scene = false },
      { index = 32, color = 255, func = "spawn_nest", active = true, is_pixel_scene = false },
      { index = 33, color = 3191728, func = "spawn_physics_fungus", active = true, is_pixel_scene = false },
    },
    scenes = {
    },
    altar = { rl = 0.06, x = 0, y = -14, xoff = -11.631, yoff = 10.2257, rp = 0, px = 0, py = -6 },
    wand_lottery = { types = { "wand_unshuffle_02", "wand_unshuffle_01" }, weights = { 0.5, 0.5 } },
  },
  ["snowcave"] = {
    key = "snowcave",
    name = "Snowy Depths",
    region = "snow",
    scored = false,
    body_bonus = false,
    wand_spells = false,
    color = 1537493,
    wang_file = "snowcave.png",
    small_altar = false,
    scope = {
      wand_body = false,
      wand_inner_spells = false,
      chest = false,
      puzzle = true,
      shop = true,
      unstable_teleportatium = false,
      gold_pouch = false,
    },
    spawns = {
      { index = 0, color = 16711680, func = "spawn_small_enemies", active = true, is_pixel_scene = false },
      { index = 1, color = 8388608, func = "spawn_big_enemies", active = true, is_pixel_scene = false },
      { index = 2, color = 65280, func = "spawn_items", active = true, is_pixel_scene = true },
      { index = 3, color = 13143322, func = "spawn_props", active = true, is_pixel_scene = false },
      { index = 4, color = 13139968, func = "spawn_props2", active = true, is_pixel_scene = false },
      { index = 5, color = 13107264, func = "spawn_props3", active = true, is_pixel_scene = false },
      { index = 6, color = 16776960, func = "spawn_lamp", active = true, is_pixel_scene = false },
      { index = 7, color = 16714495, func = "load_pixel_scene", active = true, is_pixel_scene = true },
      { index = 8, color = 16711808, func = "load_pixel_scene2", active = true, is_pixel_scene = true },
      { index = 9, color = 16744448, func = "spawn_unique_enemy", active = true, is_pixel_scene = false },
      { index = 10, color = 13123648, func = "spawn_unique_enemy2", active = true, is_pixel_scene = false },
      { index = 11, color = 8405056, func = "spawn_unique_enemy3", active = true, is_pixel_scene = false },
      { index = 12, color = 9881680, func = "spawn_ghostlamp", active = true, is_pixel_scene = false },
      { index = 13, color = 6332516, func = "spawn_candles", active = true, is_pixel_scene = false },
      { index = 14, color = 5283840, func = "spawn_potion_altar", active = true, is_pixel_scene = true },
      { index = 15, color = 12361968, func = "spawn_potions", active = true, is_pixel_scene = false },
      { index = 16, color = 65370, func = "spawn_apparition", active = true, is_pixel_scene = false },
      { index = 17, color = 7929855, func = "spawn_heart", active = true, is_pixel_scene = false },
      { index = 18, color = 5284080, func = "spawn_wands", active = true, is_pixel_scene = false },
      { index = 19, color = 12527270, func = "spawn_portal", active = true, is_pixel_scene = false },
      { index = 20, color = 305527, func = "spawn_end_portal", active = true, is_pixel_scene = false },
      { index = 21, color = 16765297, func = "spawn_orb", active = true, is_pixel_scene = false },
      { index = 22, color = 16765313, func = "spawn_perk", active = true, is_pixel_scene = false },
      { index = 23, color = 16777089, func = "spawn_all_perks", active = true, is_pixel_scene = false },
      { index = 24, color = 13101864, func = "spawn_wand_trap", active = true, is_pixel_scene = false },
      { index = 25, color = 15269760, func = "spawn_wand_trap_ignite", active = true, is_pixel_scene = false },
      { index = 26, color = 2582750, func = "spawn_wand_trap_electricity_source", active = true, is_pixel_scene = false },
      { index = 27, color = 2582751, func = "spawn_wand_trap_electricity", active = true, is_pixel_scene = false },
      { index = 28, color = 7032731, func = "spawn_moon", active = true, is_pixel_scene = false },
      { index = 29, color = 14136296, func = "spawn_collapse", active = true, is_pixel_scene = false },
      { index = 30, color = 16772829, func = "init", active = true, is_pixel_scene = false },
      { index = 31, color = 44083, func = "load_pixel_scene3", active = true, is_pixel_scene = true },
      { index = 32, color = 44132, func = "load_pixel_scene4", active = true, is_pixel_scene = true },
      { index = 33, color = 4624839, func = "load_puzzle_capsule", active = true, is_pixel_scene = true },
      { index = 34, color = 3576279, func = "load_puzzle_capsule_b", active = true, is_pixel_scene = true },
      { index = 35, color = 5615435, func = "load_altar", active = true, is_pixel_scene = true },
      { index = 36, color = 2341315, func = "spawn_altar_torch", active = true, is_pixel_scene = false },
      { index = 37, color = 5615500, func = "spawn_skulls", active = true, is_pixel_scene = false },
      { index = 38, color = 16062179, func = "spawn_scavenger_party", active = true, is_pixel_scene = false },
      { index = 39, color = 16762958, func = "spawn_acid", active = true, is_pixel_scene = false },
      { index = 40, color = 7505348, func = "load_acidtank_right", active = true, is_pixel_scene = true },
      { index = 41, color = 9728708, func = "load_acidtank_left", active = true, is_pixel_scene = true },
      { index = 42, color = 5260800, func = "spawn_stones", active = true, is_pixel_scene = false },
      { index = 43, color = 13107455, func = "load_pixel_scene_alt", active = true, is_pixel_scene = true },
      { index = 44, color = 3380044, func = "spawn_shopitem", active = true, is_pixel_scene = false },
      { index = 45, color = 8453978, func = "spawn_vines", active = true, is_pixel_scene = false },
      { index = 46, color = 4407360, func = "spawn_burning_barrel", active = true, is_pixel_scene = false },
      { index = 47, color = 11837450, func = "spawn_fish", active = true, is_pixel_scene = false },
      { index = 48, color = 11158271, func = "spawn_electricity_trap", active = true, is_pixel_scene = false },
      { index = 49, color = 3563896, func = "spawn_buried_eye_teleporter", active = true, is_pixel_scene = false },
      { index = 50, color = 8873283, func = "spawn_statue_hand", active = true, is_pixel_scene = false },
      { index = 51, color = 34140, func = "spawn_receptacle", active = true, is_pixel_scene = false },
    },
    scenes = {
      ["extras"] = {
        { prob = 0, name = "altar_snowcave_capsule" },
      },
      ["g_acidtank_left"] = {
        { prob = 1.7, name = "" },
        { prob = 0.2, name = "acidtank" },
      },
      ["g_acidtank_right"] = {
        { prob = 1.7, name = "" },
        { prob = 0.2, name = "acidtank_2" },
      },
      ["g_altar"] = {
        { prob = 1, name = "trailer_altar" },
      },
      ["g_pixel_scene_01"] = {
        { prob = 0.5, name = "verticalobservatory" },
        { prob = 0.5, name = "verticalobservatory2" },
        { prob = 0.5, name = "icebridge2" },
        { prob = 0.5, name = "pipe" },
        { prob = 0.25, name = "receptacle_water" },
      },
      ["g_pixel_scene_01_alt"] = {
        { prob = 0.5, name = "verticalobservatory_alt" },
        { prob = 0.5, name = "verticalobservatory2_alt" },
        { prob = 0.5, name = "icebridge2_alt" },
        { prob = 0.5, name = "pipe_alt" },
      },
      ["g_pixel_scene_02"] = {
        { prob = 0.4, name = "crater" },
        { prob = 0.5, name = "horizontalobservatory" },
        { prob = 0.5, name = "horizontalobservatory2" },
        { prob = 0.3, name = "horizontalobservatory3" },
        { prob = 0.4, name = "icebridge" },
        { prob = 0.4, name = "snowcastle" },
        { prob = 0, name = "symbolroom" },
        { prob = 0.5, name = "icepillar" },
        { prob = 1.5, name = "shop" },
        { prob = 0.5, name = "camp" },
      },
      ["g_pixel_scene_03"] = {
        { prob = 0.9, name = "" },
        { prob = 0.5, name = "tinyobservatory" },
        { prob = 0.5, name = "tinyobservatory2" },
        { prob = 0.2, name = "buried_eye" },
      },
      ["g_pixel_scene_04"] = {
        { prob = 0.5, name = "" },
        { prob = 0.5, name = "icicles" },
        { prob = 0.5, name = "icicles2" },
        { prob = 0.5, name = "icicles3" },
        { prob = 0.5, name = "icicles4" },
      },
      ["g_puzzle_capsule"] = {
        { prob = 9, name = "" },
        { prob = 1, name = "puzzle_capsule" },
      },
      ["g_puzzle_capsule_b"] = {
        { prob = 9, name = "" },
        { prob = 1, name = "puzzle_capsule_b" },
      },
    },
    altar = { rg = 0.45, x = -5, y = -14, xoff = -11.631, yoff = 10.2257, rp = 0.65, px = 5, py = -4 },
    wand_lottery = { types = { "wand_level_02", "wand_level_02_better", "wand_unshuffle_02" }, weights = { 5, 5, 5 } },
  },
}

M.blocked_colors = {
  [44142] = true,
  [7395230] = true,
  [7395231] = true,
  [7395232] = true,
  [7395233] = true,
  [7891199] = true,
  [12801792] = true,
  [16711808] = true,
  [16711935] = true,
  [16714495] = true,
  [44132] = true,
}

-- Wand altar placement offsets (default -10, -17 when absent).
M.wand_altar_offsets = {
  ["coalmine"] = { x = -5, y = -12 },
  ["snowcave"] = { x = -15, y = -17 },
  ["snowcastle"] = { x = -5, y = -9 },
  ["vault"] = { x = -5, y = -10 },
  ["vault_frozen"] = { x = -5, y = -10 },
  ["robobase"] = { x = -5, y = -10 },
  ["meat"] = { x = -15, y = -17 },
  ["solid_wall_tower_1"] = { x = -5, y = -12 },
  ["solid_wall_tower_2"] = { x = -5, y = -12 },
  ["solid_wall_tower_3"] = { x = -5, y = -12 },
  ["solid_wall_tower_4"] = { x = -5, y = -12 },
  ["solid_wall_tower_5"] = { x = -5, y = -12 },
  ["solid_wall_tower_6"] = { x = -5, y = -12 },
  ["solid_wall_tower_7"] = { x = -5, y = -12 },
  ["solid_wall_tower_8"] = { x = -5, y = -12 },
  ["solid_wall_tower_9"] = { x = -5, y = -12 },
}

-- Potion altar placement offsets (default -5, -15 when absent).
M.potion_altar_offsets = {
  ["snowcastle"] = { x = -3, y = -9 },
  ["vault"] = { x = -3, y = -10 },
  ["vault_frozen"] = { x = -3, y = -10 },
  ["robobase"] = { x = -3, y = -10 },
  ["fungicave"] = { x = -10, y = -17 },
  ["fungiforest"] = { x = -10, y = -17 },
}

-- Spawn functions whose vanilla body UNCONDITIONALLY loads the named
-- entity (no probability gate, no flag). A marker for one of these
-- proves the object exists with no further resolution.
--
-- Keyed by "biome/function": the same function name loads different
-- entities in different biomes (spawn_receptacle is steam in Coal Pits
-- and water in Snowy Depths), so it is not a name-only table.
M.existence_proven_functions = {
  ["coalmine/spawn_swing_puzzle_box"] = {
    entity = "data/entities/props/physics/trap_electricity_suspended.xml",
    source = "coalmine.lua spawn_swing_puzzle_box",
  },
  ["coalmine/spawn_swing_puzzle_target"] = {
    entity = "data/entities/buildings/swing_puzzle_target.xml",
    source = "coalmine.lua spawn_swing_puzzle_target",
  },
  ["coalmine/spawn_oiltank_puzzle"] = {
    entity = "data/entities/buildings/oiltank_puzzle.xml",
    source = "coalmine.lua spawn_oiltank_puzzle",
  },
  ["coalmine/spawn_receptacle_oil"] = {
    entity = "data/entities/buildings/receptacle_oil.xml",
    source = "coalmine.lua spawn_receptacle_oil",
    extra = {
      { entity = "data/entities/items/pickup/potion_empty.xml", dx = 72, dy = -17, source = "coalmine.lua spawn_receptacle_oil second EntityLoad" },
    },
  },
  ["excavationsite/spawn_receptacle"] = {
    entity = "data/entities/buildings/receptacle_steam.xml",
    source = "excavationsite.lua spawn_receptacle",
  },
  ["snowcave/spawn_receptacle"] = {
    entity = "data/entities/buildings/receptacle_water.xml",
    source = "snowcave.lua spawn_receptacle",
  },
  ["snowcave/spawn_electricity_trap"] = {
    entity = "data/entities/props/physics_trap_electricity_enabled.xml",
    source = "snowcave.lua spawn_electricity_trap",
  },
  ["snowcave/spawn_buried_eye_teleporter"] = {
    entity = "data/entities/buildings/teleport_snowcave_buried_eye.xml",
    source = "snowcave.lua spawn_buried_eye_teleporter",
  },
}

-- Deterministic probability gates, transcribed from the vanilla body.
-- The gate is evaluable from (world_seed, x, y) with the shared PRNG, so
-- a failed gate means the object does NOT exist (not "cannot resolve").
M.gated_functions = {
  ["excavationsite/spawn_meditation_cube"] = {
    gate = "random_gt",
    seed_from = "position",
    random_min = 1,
    random_max = 100,
    threshold = 96,
    entity = "data/entities/buildings/teleport_meditation_cube.xml",
    entity_dx = 0, entity_dy = -70,
    scene_name = "meditation_cube",
    scene_dx = -20, scene_dy = -29,
    source = "excavationsite.lua spawn_meditation_cube",
  },
}

-- Functions whose vanilla body places its pixel scene at marker + offset.
M.scene_placement_offsets = {
  ["load_puzzle_capsule_b"] = { x = -50, y = -230 },
  ["load_acidtank_right"] = { x = -12, y = -12 },
  ["load_acidtank_left"] = { x = -252, y = -12 },
  ["load_gunpowderpool_03"] = { x = -3, y = 3 },
}

-- Scene bitmaps whose PLACEMENT must be reported even when the bitmap
-- itself carries no registered spawn-marker pixel. Puzzle instances are
-- identified by scene placement, not by an inner marker.
M.tracked_scene_names = {
  ["shop"] = true,
  ["shop_alt"] = true,
  ["physics_swing_puzzle"] = true,
  ["receptacle_oil"] = true,
  ["oiltank_puzzle"] = true,
  ["puzzleroom_01"] = true,
  ["puzzleroom_02"] = true,
  ["puzzleroom_03"] = true,
  ["meditation_cube"] = true,
  ["puzzle_capsule"] = true,
  ["puzzle_capsule_b"] = true,
  ["buried_eye"] = true,
  ["potion_altar"] = true,
  ["potion_altar_vault"] = true,
}

-- Container-bearing scenes: their placement proves an R5 entrance exists.
M.container_scene_names = {
  ["potion_altar"] = true,
  ["potion_altar_vault"] = true,
}

-- spawn_heart is a DISPATCH, not an entity. Transcribed from
-- data/scripts/biome_scripts.lua (see the extractor for the full body).
-- The scanner resolves the outcome; it never reports "a heart exists"
-- from the marker alone.
M.heart_source = {
  source = "data/scripts/biome_scripts.lua spawn_heart",
  heart_threshold = 0.7,
  heart_rand = "procedural",
  calendar_override_month = 2,
  calendar_override_day = 14,
  calendar_override_threshold = 0.35,
  chest_branch_requires_r_gt = 0.3,
  chest_reseed_dx = 45,
  chest_reseed_dy = -2123,
  branch_rand_min = 1,
  branch_rand_max = 100,
  branch_deep_le = 90,
  deep_y_threshold = 1536,
  mimic_sign_rand_min = 1,
  mimic_sign_rand_max = 300,
  mimic_sign_on = 1,
  deep_rand_min = 1,
  deep_rand_max = 1000,
  deep_super_from = 1000,
  shallow_rand_min = 1,
  shallow_rand_max = 100,
  shallow_mimic_le = 95,
  shallow_mimic_sign_rand_max = 30,
  entities = {
    heart = "data/entities/items/pickup/heart.xml",
    chest_normal = "data/entities/items/pickup/chest_random.xml",
    chest_super = "data/entities/items/pickup/chest_random_super.xml",
    chest_mimic = "data/entities/animals/chest_mimic.xml",
    chest_leggy = "data/entities/items/pickup/chest_leggy.xml",
  },
}

-- spawn_bbqbox (Mines only) nests spawn_heart at (+10,+10). Enemies are
-- context, never resources.
M.bbqbox_sources = {
  ["coalmine/spawn_bbqbox"] = {
    source = "data/scripts/biomes/coalmine.lua spawn_bbqbox",
    gate_min = 1, gate_max = 100,
    gate_le = 99,
    nested_heart_dx = 10,
    nested_heart_dy = 10,
    enemy_offsets = {
      { dx = 0, dy = 0 },
      { dx = 20, dy = 0 },
      { dx = 20, dy = 10 },
    },
    else_entities = {
      { entity = "data/entities/items/pickup/jar_of_urine.xml", dx = 0, dy = 0 },
      { entity = "data/entities/animals/shotgunner_weak.xml", dx = 10, dy = 0 },
    },
  },
}

-- spawn_from_list lists that produce containers. RNG contract:
--   SetRandomSeed( x + seed_dx, y + seed_dy ) then Random(rnd_min, rnd_max)
-- and the matching band loads its entity at (x + offset_x, y + offset_y).
-- `spawn_requires_flag` entries consult the CALLER's frozen profile.
M.container_lists = {
  ["potion_spawnlist"] = {
    source = "data/scripts/item_spawnlists.lua potion_spawnlist",
    rnd_min = 1, rnd_max = 91,
    seed_dx = 425, seed_dy = -243,
    entries = {
      { value_min = 90, value_max = 91, entity = "data/entities/items/pickup/physics_gold_orb.xml", offset_x = 0, offset_y = -2, kind = "gold_orb" },
      { value_min = 86, value_max = 89, entity = "data/entities/items/pickup/broken_wand.xml", offset_x = 0, offset_y = -2, kind = "broken_wand" },
      { value_min = 84, value_max = 85, entity = "data/entities/items/pickup/thunderstone.xml", offset_x = 0, offset_y = -2, kind = "thunderstone" },
      { value_min = 80, value_max = 83, entity = "data/entities/items/pickup/brimstone.xml", offset_x = 0, offset_y = -2, kind = "brimstone" },
      { value_min = 78, value_max = 79, entity = "data/entities/items/pickup/egg_monster.xml", offset_x = 0, offset_y = -2, kind = "egg_monster" },
      { value_min = 74, value_max = 77, entity = "data/entities/items/pickup/egg_slime.xml", offset_x = 0, offset_y = -2, kind = "egg_slime" },
      { value_min = 73, value_max = 73, entity = "data/entities/items/pickup/egg_purple.xml", offset_x = 0, offset_y = -2, kind = "egg_purple" },
      { value_min = 72, value_max = 72, entity = "data/entities/items/pickup/runestones/runestone_<opt>.xml", offset_x = 0, offset_y = -10, kind = "runestone" },
      { value_min = 71, value_max = 71, entity = "data/entities/items/pickup/physics_die.xml", offset_x = 0, offset_y = -12, kind = "die", spawn_requires_flag = "card_unlocked_duplicate" },
      { value_min = 66, value_max = 70, entity = "data/entities/items/pickup/powder_stash.xml", offset_x = 0, offset_y = -2, kind = "powder_pouch" },
      { value_min = 1, value_max = 65, entity = "data/entities/items/pickup/potion.xml", offset_x = 0, offset_y = -2, kind = "potion" },
    },
  },
}

-- spawn_potions wrapper: mimic branch + spawn_from_list call.
M.potion_sources = {
  ["general/spawn_potions"] = {
    source = "data/scripts/biome_scripts.lua spawn_potions",
    map_rand_min = 1,
    map_rand_max = 1000,
    map_list_le = 995,
    deep_y_threshold = 1536,
    list_name = "potion_spawnlist",
    mimic_entity = "data/entities/items/pickup/potion_mimic.xml",
  },
}

-- spawn_potion_altar: a gated pixel scene with a per-biome placement
-- offset. fungicave OVERRIDES the generic body (no gate, (-10,-17)).
M.potion_altar_sources = {
  ["general/spawn_potion_altar"] = {
    source = "data/scripts/biome_scripts.lua spawn_potion_altar",
    gate_op = "gt",
    gate_threshold = 0.65,
    scene_name = "potion_altar",
    scene_dx = -5, scene_dy = -15,
    inner_function = "spawn_potions",
    inner_marker_dx = 10,
    inner_marker_dy = 11,
  },
  ["fungicave/spawn_potion_altar"] = {
    source = "data/scripts/biomes/fungicave.lua spawn_potion_altar (override)",
    gate = nil,
    scene_name = "potion_altar",
    scene_dx = -10, scene_dy = -17,
    inner_function = "spawn_potions",
    inner_marker_dx = 10,
    inner_marker_dy = 11,
  },
}

return M
