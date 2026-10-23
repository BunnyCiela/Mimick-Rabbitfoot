-- files/isf/data/spells.lua
--
-- Generated file. Do not hand-edit; regenerate with
--   python tools/foundation/gen_spell_pool.py
--
-- Source of the spell pool: Noita's installed
--   data/scripts/gun/gun_actions.lua
-- read out of data/data.wak read-only by the development extractor
-- (tools/foundation/wak_extract.py). Pool order is the game's action-table
-- order, which is the order GetRandomAction walks when accumulating spawn
-- weights, so it must not be sorted.
--
-- The pool keeps only actions whose card sprite exists in the installation,
-- matching the observable filter used by the upstream data extractors.
--
-- Scoring data (G10 / G20 / G50 / H2) is transcribed from PRD section 3; the
-- PRD is the only source of scoring semantics.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local M = {}

M.SCHEMA_VERSION = 1
M.UNITS_PER_POINT = 4

-- Game build the pool was extracted from (Noita branch master).
M.GAME_VERSION_HASH = "9dbd52ced019a643169a2db02f46c77f8766c6e5"
M.SOURCE = "data/scripts/gun/gun_actions.lua"

-- Number of actions in the pool.
M.POOL_COUNT = 422

-- Per-entity spell spawning: GetRandomAction(x, y, level, offset) seeds with
-- world_seed + offset and walks the pool in order. Weights are the 11
-- spawn_level -> spawn_probability values (levels 0..10) as the game stores
-- them; absent levels are 0.
--
-- Each entry: "ID|w0,w1,...,w10|spawn_requires_flag-or-empty"
M.RAW_POOL = {
    "BOMB|1,1,1,1,0.5,0.5,0.1,0,0,0,0|",
    "LIGHT_BULLET|2,1,0.5,0,0,0,0,0,0,0,0|",
    "LIGHT_BULLET_TRIGGER|1,0.5,0.5,0.5,0,0,0,0,0,0,0|",
    "LIGHT_BULLET_TRIGGER_2|0,0,1,0.5,0,1,1,0,0,0,0.2|",
    "LIGHT_BULLET_TIMER|0,0.5,0.5,0.75,0,0,0,0,0,0,0|",
    "BULLET|0,1,1,1,0.8,0.5,0,0,0,0,0|",
    "BULLET_TRIGGER|0,0.5,0.5,0.5,0.6,0.5,0,0,0,0,0|",
    "BULLET_TIMER|0,0,0.5,0.5,0.5,0.5,0.6,0,0,0,0|",
    "HEAVY_BULLET|0,0.5,1,1,1,1,1,0,0,0,0|",
    "HEAVY_BULLET_TRIGGER|0,0,0.5,0.5,0.5,0.7,0.5,0,0,0,0|",
    "HEAVY_BULLET_TIMER|0,0,0.5,0.5,0.5,0.5,0.7,0,0,0,0|",
    "AIR_BULLET|0,1,1,0,0,0,0,0,0,0,0|",
    "SLOW_BULLET|0,1,1,1,1,0,0,0,0,0,0|",
    "SLOW_BULLET_TRIGGER|0,0.5,0.5,0.5,0.5,1,0,0,0,0,0|",
    "SLOW_BULLET_TIMER|0,0.5,0.5,0.5,0.5,1,1,0,0,0,0|",
    "HOOK|0,0.1,0.3,0.4,0.2,0.1,0,0,0,0,0|",
    "BLACK_HOLE|0.8,0,0.8,0,0.8,0.8,0,0,0,0,0|",
    "BLACK_HOLE_DEATH_TRIGGER|0,0,0.5,0,0.5,0.5,0.5,0,0,0,0|",
    "WHITE_HOLE|0.05,0,0.05,0,0.1,0,0.2,0,0,0,0.5|",
    "BLACK_HOLE_BIG|0,0.8,0,0.8,0,0.8,0.8,0,0,0,0.5|",
    "WHITE_HOLE_BIG|0,0.05,0,0.05,0,0.1,0.4,0,0,0,0.2|",
    "BLACK_HOLE_GIGA|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_black_hole",
    "WHITE_HOLE_GIGA|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_black_hole",
    "TENTACLE_PORTAL|0,0.4,0.4,0.4,0.5,0,0,0,0,0,0.2|",
    "SPITTER|1,1,1,0.5,0,0,0,0,0,0,0|",
    "SPITTER_TIMER|0.5,0.5,0.5,1,0,0,0,0,0,0,0|",
    "SPITTER_TIER_2|0,0,1,1,1,0.5,0,0,0,0,0|",
    "SPITTER_TIER_2_TIMER|0,0,0.5,0.5,0.5,1,0,0,0,0,0|",
    "SPITTER_TIER_3|0,0,0,0.8,0.8,1,1,0,0,0,0|",
    "SPITTER_TIER_3_TIMER|0,0,0,0,0.5,0.65,0.5,0,0,0,0|",
    "BUBBLESHOT|1,0.6,1,0.5,0,0,0,0,0,0,0|",
    "BUBBLESHOT_TRIGGER|0,0.5,0.5,1,0,0,0,0,0,0,0|",
    "DISC_BULLET|1,0,1,0,0.6,0,0,0,0,0,0|",
    "DISC_BULLET_BIG|0.6,0,0.7,0,0.8,0,0,0,0,0,0|",
    "DISC_BULLET_BIGGER|0,0,0.1,0.6,0,1,0,0,0,0,0.4|card_unlocked_everything",
    "BOUNCY_ORB|1,0,1,0,1,0,0,0,0,0,0|",
    "BOUNCY_ORB_TIMER|0.5,0,0.5,0,0.5,0,0,0,0,0,0|",
    "RUBBER_BALL|1,1,0,0,0,0,0.2,0,0,0,0|",
    "ARROW|0,1,1,0,0.6,0.3,0,0,0,0,0|",
    "POLLEN|0.6,1,0,1,0.6,0,0,0,0,0,0|",
    "LANCE|0,0.9,1,0,0,0.8,1,0,0,0,0|",
    "LANCE_HOLY|0,0,0,0.5,0,0.8,1,0,0,0,0|",
    "ROCKET|0,1,1,1,0.5,0.3,0,0,0,0,0|",
    "ROCKET_TIER_2|0,0,0.5,1,1,0.8,0.5,0,0,0,0|",
    "ROCKET_TIER_3|0,0,0.25,0.5,1,1,1,0,0,0,0|",
    "GRENADE|1,1,0.5,0.25,0.2,0,0,0,0,0,0|",
    "GRENADE_TRIGGER|0.5,0.5,0.2,0.5,0.5,1,0,0,0,0,0|",
    "GRENADE_TIER_2|0,0.5,1,1,1,0.5,0,0,0,0,0|",
    "GRENADE_TIER_3|0,0.25,0.5,0.75,1,1,0,0,0,0,0|",
    "GRENADE_ANTI|0.4,0.4,0.7,0.4,0.4,0.4,0,0,0,0,0|",
    "GRENADE_LARGE|0.4,0.4,0.4,0.4,0.4,0.4,0,0,0,0,0|",
    "MINE|0,1,0,0.75,1,0,0.5,0,0,0,0|",
    "MINE_DEATH_TRIGGER|0,0,1,0,0,0,1,0,0,0,0|",
    "PIPE_BOMB|0,0,1,1,0.6,0,0,0,0,0,0|",
    "PIPE_BOMB_DEATH_TRIGGER|0,0,0.6,0.8,1,0.8,0,0,0,0,0|",
    "FISH|0,0,0,0.01,0.01,0.01,0,0,0,0,0|card_unlocked_fish",
    "EXPLODING_DEER|0,0,0,0.6,0.6,0.6,0,0,0,0,0|card_unlocked_exploding_deer",
    "EXPLODING_DUCKS|0,0,0,0.8,0.5,0.6,0,0,0,0,0|card_unlocked_exploding_deer",
    "WORM_SHOT|0,0,0,0.6,0.8,0.6,0.4,0,0,0,0.6|card_unlocked_exploding_deer",
    "BOMB_DETONATOR|0,0,0.5,1,0.4,0.5,1,0,0,0,0|",
    "LASER|0,1,1,0,1,0,0,0,0,0,0|",
    "MEGALASER|0,0,0,0.6,0.6,0.8,0.6,0,0,0,0.3|",
    "LIGHTNING|0,1,0.9,0,0,0.7,1,0,0,0,0|",
    "BALL_LIGHTNING|0,0.2,0.4,0,1,1,0,0,0,0,0|",
    "LASER_EMITTER|0,0.2,0.8,1,0.5,0,0,0,0,0,0|",
    "LASER_EMITTER_FOUR|0,0.2,0.9,0.3,0.5,1,0,0,0,0,0|",
    "LASER_EMITTER_CUTTER|0.2,0.3,1,0.5,0.1,0,0,0,0,0,0|",
    "DIGGER|0,1,0.5,0,0,0,0,0,0,0,0|",
    "POWERDIGGER|0,0,0.5,1,0.8,0,0,0,0,0,0|",
    "CHAINSAW|1,0,1,0,0,0,0,0,0,0,0|",
    "LUMINOUS_DRILL|1,0,1,0,0,0,0,0,0,0,0.1|",
    "LASER_LUMINOUS_DRILL|1,0,1,0,0,0,0.2,0,0,0,0.1|",
    "TENTACLE|0,0,0,1,0.5,1,0.8,0,0,0,0|card_unlocked_tentacle",
    "TENTACLE_TIMER|0,0,0,0.6,0.8,0.6,0.7,0,0,0,0|card_unlocked_tentacle",
    "HEAL_BULLET|0,0,1,1,0.6,0,0,0,0,0,0|",
    "ANTIHEAL|0,0,0.4,0.3,0.3,0.3,0,0,0,0,0|",
    "SPIRAL_SHOT|0,0,0,0,0.7,0.8,0.7,0,0,0,0|card_unlocked_spiral_shot",
    "MAGIC_SHIELD|0,0,0.5,0,0.6,0.7,1,0,0,0,0|",
    "BIG_MAGIC_SHIELD|0,0,0.2,0,0.4,0.5,0.6,0,0,0,0.2|",
    "CHAIN_BOLT|0.75,0,0,0,1,0.8,0.6,0,0,0,0|",
    "FIREBALL|1,0,0,0.7,1,0,0.5,0,0,0,0|",
    "METEOR|0,0,0,0,0.6,0.6,0.7,0,0,0,0.5|",
    "FLAMETHROWER|0,0,0.8,0.9,0.9,0,0.6,0,0,0,0|",
    "ICEBALL|0,0,0.8,0.9,0.9,0,0.6,0,0,0,0|",
    "SLIMEBALL|1,0,0,1,0.7,0,0,0,0,0,0|",
    "DARKFLAME|0,0,0,1,0,0.9,0.8,0,0,0,0|",
    "MISSILE|0,0.5,0.5,1,0,1,0,0,0,0,0|",
    "FUNKY_SPELL|0,0,0,0,0,0,0.1,0,0,0,0.1|card_unlocked_funky",
    "PEBBLE|0,0.9,1,0,0.9,0,0.6,0,0,0,0|",
    "DYNAMITE|1,0.9,0.8,0.7,0.6,0,0,0,0,0,0|",
    "GLITTER_BOMB|0.8,0.9,0.8,0.7,0.6,0,0,0,0,0,0|",
    "BUCKSHOT|1,1,0.9,0.9,0.6,0,0,0,0,0,0|",
    "FREEZING_GAZE|0,0,0.9,1,1,0,0,0,0,0,0|",
    "GLOWING_BOLT|0,0,0,0.8,0.9,1,0,0,0,0,0.1|",
    "SPORE_POD|0,0.7,0.8,0.9,0.8,0.6,0,0,0,0,0|",
    "GLUE_SHOT|0,0,0.7,0.4,0.2,0.5,0,0,0,0,0|",
    "BOMB_HOLY|0,0,0.2,0.2,0.2,0.2,0.2,0,0,0,0.5|card_unlocked_bomb_holy",
    "BOMB_HOLY_GIGA|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_bomb_holy_giga",
    "PROPANE_TANK|0,0,1,1,0.8,0.8,0.7,0,0,0,0|",
    "BOMB_CART|0,0,0.6,0.6,0.5,0.8,0.6,0,0,0,0|",
    "CURSED_ORB|0,0.3,0.2,0.1,0,0,0,0,0,0,0|",
    "EXPANDING_ORB|0,0,0.5,0.5,1,1,0.5,0,0,0,0|",
    "CRUMBLING_EARTH|0,0,0.4,0.3,0.5,0.6,0.9,0,0,0,0|card_unlocked_crumbling_earth",
    "SUMMON_ROCK|0.8,0.8,0.6,0.6,0.3,0.7,0.7,0,0,0,0|",
    "SUMMON_EGG|0.7,0.8,0.8,0.7,0.6,0.6,0.5,0,0,0,0|",
    "SUMMON_HOLLOW_EGG|0.6,0.8,0.7,0,0,0.8,0.3,0,0,0,0|",
    "TNTBOX|0,0.8,0.9,0.5,0,0.4,0,0,0,0,0|",
    "TNTBOX_BIG|0,0,0.8,0,1,0.7,0,0,0,0,0|",
    "SWARM_FLY|0,0,0.3,0,0.4,0.5,0,0,0,0,0|",
    "SWARM_FIREBUG|0,0,0.2,0,0,0.4,0.5,0,0,0,0|",
    "SWARM_WASP|0,0,0,0,0.2,0.5,0.6,0,0,0,0|",
    "FRIEND_FLY|0,0,0,0,0.2,0.6,0.5,0,0,0,0|",
    "ACIDSHOT|0,1,1,0.9,0.6,0,0,0,0,0,0|",
    "THUNDERBALL|0,0,0.9,0,1,0,0.7,0,0,0,0.2|",
    "FIREBOMB|0,1,0.9,0.7,0,0,0,0,0,0,0|",
    "SOILBALL|0,0.8,0.8,1,0,0.75,0,0,0,0,0|",
    "DEATH_CROSS|0,1,0.8,0.6,0.5,0.5,0.3,0,0,0,0|",
    "DEATH_CROSS_BIG|0,0,0.4,0.5,0.55,0.3,0.4,0,0,0,0.2|",
    "INFESTATION|0,0,0.1,0.3,0.4,0,0,0,0,0,0|",
    "WALL_HORIZONTAL|0.4,0.4,0.6,0,0.5,0.2,0,0,0,0,0|",
    "WALL_VERTICAL|0.4,0.4,0.6,0,0.5,0.2,0,0,0,0,0|",
    "WALL_SQUARE|0.3,0.2,0.6,0,0.5,0.4,0.4,0,0,0,0|",
    "TEMPORARY_WALL|0.1,0.1,0.3,0,0.4,0.2,0,0,0,0,0|",
    "TEMPORARY_PLATFORM|0.1,0.1,0.3,0,0.4,0.2,0,0,0,0,0|",
    "PURPLE_EXPLOSION_FIELD|0.7,1,0.7,0,0.5,0.5,0.3,0,0,0,0|",
    "DELAYED_SPELL|0.8,0.8,1,0,0.7,0.5,0.4,0,0,0,0|",
    "LONG_DISTANCE_CAST|0.6,0.7,0.8,0,0.6,0.3,0.4,0,0,0,0|",
    "TELEPORT_CAST|0,0.6,0.6,0,0.6,0.8,1,0,0,0,0|",
    "SUPER_TELEPORT_CAST|0,0,0.2,0,0.6,0.8,0.8,0,0,0,0|",
    "CASTER_CAST|0,0,0.2,0,0.2,0.4,0.4,0,0,0,0.2|",
    "MIST_RADIOACTIVE|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "MIST_ALCOHOL|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "MIST_SLIME|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "MIST_BLOOD|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "CIRCLE_FIRE|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "CIRCLE_ACID|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "CIRCLE_OIL|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "CIRCLE_WATER|0,0.4,0.4,0.4,0.4,0,0,0,0,0,0|",
    "MATERIAL_WATER|0,0.4,0.4,0.4,0.4,0.4,0,0,0,0,0|",
    "MATERIAL_OIL|0,0.4,0.4,0.4,0.4,0.4,0,0,0,0,0|",
    "MATERIAL_BLOOD|0,0.4,0.4,0.4,0.4,0.4,0,0,0,0,0|",
    "MATERIAL_ACID|0,0,0.4,0.4,0.4,0.4,0.4,0,0,0,0|",
    "MATERIAL_CEMENT|0,0,0.4,0.4,0.4,0.4,0.4,0,0,0,0|card_unlocked_material_cement",
    "TELEPORT_PROJECTILE|0.6,0.6,0.6,0,0.4,0.4,0.4,0,0,0,0|",
    "TELEPORT_PROJECTILE_SHORT|0.6,0.6,0.6,0,0.4,0.4,0.4,0,0,0,0|",
    "TELEPORT_PROJECTILE_STATIC|0.6,0.6,0.6,0,0.4,0.4,0.4,0,0,0,0|",
    "SWAPPER_PROJECTILE|0.05,0.05,0.1,0,0.4,0.4,0.1,0,0,0,0|",
    "TELEPORT_PROJECTILE_CLOSER|0.4,0.6,0.6,0,0.7,0.4,0.4,0,0,0,0|",
    "NUKE|0,0.3,0,0,0,1,1,0,0,0,0.2|card_unlocked_nuke",
    "NUKE_GIGA|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_nukegiga",
    "FIREWORK|0,1,0.8,1,1,0.5,0.3,0,0,0,0|card_unlocked_firework",
    "SUMMON_WANDGHOST|0,0,0.08,0,0.1,0.3,0.3,0,0,0,0.1|",
    "TOUCH_GOLD|0,0,0,0,0,0.1,0.1,0.1,0,0,0.5|",
    "TOUCH_WATER|0,0,0,0,0,0.1,0.1,0.1,0,0,0.4|",
    "TOUCH_OIL|0,0,0,0,0,0.1,0.1,0.1,0,0,0.4|",
    "TOUCH_ALCOHOL|0,0,0,0,0,0.1,0.1,0.1,0,0,0.4|",
    "TOUCH_PISS|0,0,0,0,0,0.035,0.035,0.035,0,0,0.1|card_unlocked_piss",
    "TOUCH_GRASS|0,0,0,0,0,0.1,0.1,0.1,0,0,0.2|card_unlocked_touch_grass",
    "TOUCH_BLOOD|0,0,0,0,0,0.1,0.1,0.1,0,0,0.5|",
    "TOUCH_SMOKE|0,0,0,0,0,0.1,0.1,0.1,0,0,0.4|",
    "DESTRUCTION|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_destruction",
    "MASS_POLYMORPH|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_polymorph",
    "BURST_2|0.8,0.8,0.8,0.8,0.8,0.8,0.8,0,0,0,0|",
    "BURST_3|0,0.7,0.7,0.7,0.7,0.7,0.7,0,0,0,0|",
    "BURST_4|0,0,0.4,0.5,0.6,0.6,0.6,0,0,0,0|",
    "BURST_8|0,0,0,0,0,0.1,0.1,0,0,0,0.5|card_unlocked_musicbox",
    "BURST_X|0,0,0,0,0,0.1,0.1,0,0,0,0.5|card_unlocked_musicbox",
    "SCATTER_2|0.8,0.8,0.7,0,0,0,0,0,0,0,0|",
    "SCATTER_3|0.6,0.7,0.7,0.8,0,0,0,0,0,0,0|",
    "SCATTER_4|0,0.5,0.6,0.7,0.8,0.8,0.6,0,0,0,0|",
    "I_SHAPE|0,0.4,0.5,0.3,0,0,0,0,0,0,0|",
    "Y_SHAPE|0.8,0.5,0.4,0.3,0,0,0,0,0,0,0|",
    "T_SHAPE|0,0.4,0.5,0.4,0.3,0,0,0,0,0,0|",
    "W_SHAPE|0,0,0.4,0.3,0.5,0.3,0.3,0,0,0,0|",
    "CIRCLE_SHAPE|0,0.1,0.2,0.3,0.3,0.3,0.3,0,0,0,0|",
    "PENTAGRAM_SHAPE|0,0.4,0.4,0.3,0.2,0.1,0,0,0,0,0|",
    "I_SHOT|0,0.1,0.2,0.5,0,0,0,0,0,0,0|",
    "Y_SHOT|0,0.1,0.2,0.5,0,0,0,0,0,0,0|",
    "T_SHOT|0,0,0.1,0.2,0,0.5,0,0,0,0,0|",
    "W_SHOT|0,0,0.1,0.2,0,0.5,0.4,0,0,0,0|",
    "QUAD_SHOT|0,0.1,0.2,0,0.5,0,0,0,0,0,0|",
    "PENTA_SHOT|0,0,0,0.1,0.2,0.5,0.5,0,0,0,0.2|",
    "HEXA_SHOT|0,0,0,0.1,0.2,0.5,0.5,0,0,0,0.2|",
    "SPREAD_REDUCE|0,0.8,0.8,0.8,0.8,0.7,0.6,0,0,0,0|",
    "HEAVY_SPREAD|0.6,0.7,0.8,0,0.8,0.8,0.6,0,0,0,0|",
    "RECHARGE|0,0.8,0.9,1,0.8,0.9,1,0,0,0,0|",
    "LIFETIME|0,0,0,0.5,0.5,0.5,0.75,0,0,0,0.1|",
    "LIFETIME_DOWN|0,0,0,0.5,0.5,0.75,0.5,0,0,0,0.1|",
    "NOLLA|0,0,0.2,0,0.2,0.5,0.5,0,0,0,1|card_unlocked_pyramid",
    "SLOW_BUT_STEADY|0,0,0,0.1,0.2,0.6,0.6,0,0,0,0.4|card_unlocked_maths",
    "EXPLOSION_REMOVE|0,0,0.2,0,0.6,0.7,0.2,0,0,0,0|",
    "EXPLOSION_TINY|0,0,0.2,0,0.6,0.7,0.2,0,0,0,0|",
    "LASER_EMITTER_WIDER|0,0,0.3,0.3,0.4,0,0,0,0,0,0|",
    "MANA_REDUCE|0,0.7,0.9,1,1,1,1,0,0,0,0|",
    "BLOOD_MAGIC|0,0,0,0,0,0.3,0.7,0,0,0,0.5|",
    "MONEY_MAGIC|0,0,0,0.2,0,0.8,0.3,0,0,0,0.5|",
    "BLOOD_TO_POWER|0,0,0.2,0,0,0.8,0.2,0,0,0,0.5|",
    "DUPLICATE|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_mestari",
    "QUANTUM_SPLIT|0,0,0.5,0.6,0.5,0.5,1,0,0,0,0|",
    "GRAVITY|0,0,0.5,0.4,0.4,0.3,0.3,0,0,0,0|",
    "GRAVITY_ANTI|0,0,0.5,0.4,0.4,0.3,0.3,0,0,0,0|",
    "SINEWAVE|0,0,0.4,0,0.55,0,0.4,0,0,0,0|",
    "CHAOTIC_ARC|0,0.4,0,0.55,0,0.4,0,0,0,0,0|",
    "PINGPONG_PATH|0,0.4,0,0.5,0,0.4,0,0,0,0,0|",
    "AVOIDING_ARC|0,0,0.5,0,0.4,0,0.4,0,0,0,0|",
    "FLOATING_ARC|0,0.4,0,0.4,0,0.5,0,0,0,0,0|",
    "FLY_DOWNWARDS|0,0.3,0,0.45,0,0.3,0,0,0,0,0|",
    "FLY_UPWARDS|0,0,0.3,0,0.45,0,0.3,0,0,0,0|",
    "HORIZONTAL_ARC|0,0.4,0,0.4,0,0.4,0,0,0,0,0|",
    "LINE_ARC|0,0.3,0,0.4,0,0.5,0,0,0,0,0|",
    "ORBIT_SHOT|0,0.2,0.4,0.4,0.3,0,0,0,0,0,0|",
    "SPIRALING_SHOT|0,0.2,0.3,0.4,0.5,0,0,0,0,0,0|",
    "PHASING_ARC|0,0,0.2,0.3,0.6,0.1,0,0,0,0,0|",
    "TRUE_ORBIT|0,0,0.2,0.3,0.4,0,0,0,0,0,0|",
    "BOUNCE|0,0,1,1,0.4,0,0.2,0,0,0,0|",
    "REMOVE_BOUNCE|0,0,0.2,0.2,1,1,0,0,0,0,0|",
    "HOMING|0,0.1,0.4,0.4,0.4,0.4,0.4,0,0,0,0|",
    "ANTI_HOMING|0,0.05,0.3,0.3,0.1,0.1,0.01,0,0,0,0|",
    "HOMING_WAND|0,1e-05,0.08,0,0.08,0.25,0.25,0,0,0,0.2|card_unlocked_homing_wand",
    "HOMING_SHORT|0,0.4,0.8,1,0.4,0.3,0.1,0,0,0,0|",
    "HOMING_ROTATE|0,0,0.2,0.4,0.6,0.4,0.4,0,0,0,0|",
    "HOMING_SHOOTER|0,0,0.2,0.3,0.2,0,0.2,0,0,0,0|",
    "AUTOAIM|0,0,0.4,0.4,0.4,0.4,0.4,0,0,0,0|",
    "HOMING_ACCELERATING|0,0.1,0.3,0.3,0.5,0,0,0,0,0,0|",
    "HOMING_CURSOR|0,0,0.7,0.7,0.4,0.4,1,0,0,0,0|",
    "HOMING_AREA|0,0,0.2,0.4,0.6,0.7,0.4,0,0,0,0|",
    "PIERCING_SHOT|0,0,0.4,0.5,0.6,0.6,0.4,0,0,0,0|",
    "CLIPPING_SHOT|0,0,0.2,0.3,0.6,0.4,0.6,0,0,0,0|",
    "DAMAGE|0,0.6,0.6,0.8,0.6,0.6,0,0,0,0,0|",
    "DAMAGE_RANDOM|0,0,0,0.7,0.6,0.6,0,0,0,0,0|card_unlocked_pyramid",
    "BLOODLUST|0,0.2,0,0.3,0.6,0.7,0.3,0,0,0,0|",
    "DAMAGE_FOREVER|0,0,0.2,0.3,0.6,0.5,0.2,0,0,0,0.2|",
    "CRITICAL_HIT|0,0.5,0.6,0.6,0.7,0.6,0,0,0,0,0|",
    "AREA_DAMAGE|0,0,0.4,0.5,0.5,0.5,0.6,0,0,0,0|",
    "SPELLS_TO_POWER|0,0,0.3,0.3,0.5,0.5,0.5,0,0,0,0.1|",
    "ESSENCE_TO_POWER|0,0.2,0.5,0.5,0,0,0.5,0,0,0,0.1|",
    "ZERO_DAMAGE|0,0,0,0.3,0.3,0.6,0,0,0,0,0.3|",
    "HEAVY_SHOT|0,0,0.4,0.4,0.5,0,0,0,0,0,0|",
    "LIGHT_SHOT|0,0,0.3,0.5,0.4,0,0,0,0,0,0|",
    "KNOCKBACK|0,0,0,0.7,0,0.6,0,0,0,0,0|",
    "RECOIL|0,0,0.6,0,0.7,0,0,0,0,0,0|",
    "RECOIL_DAMPER|0,0,0,0.6,0,0,0.7,0,0,0,0|",
    "SPEED|0,1,0.5,0.5,0,0,0,0,0,0,0|",
    "ACCELERATING_SHOT|0,0,0.5,0.4,1,0,0,0,0,0,0|",
    "DECELERATING_SHOT|0,0,0.4,0.1,0.7,0,0,0,0,0,0|",
    "EXPLOSIVE_PROJECTILE|0,0,1,1,0.8,0,0,0,0,0,0|",
    "CLUSTERMOD|0,0.5,1,0.6,0,0,0,0,0,0,0|",
    "WATER_TO_POISON|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "BLOOD_TO_ACID|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "LAVA_TO_BLOOD|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "LIQUID_TO_EXPLOSION|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "TOXIC_TO_ACID|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "STATIC_TO_SAND|0,0,0.3,0.3,0.3,0,0,0,0,0,0.2|",
    "TRANSMUTATION|0,0,0.3,0.3,0.3,0.3,0.3,0,0,0,0.2|",
    "RANDOM_EXPLOSION|0,0,0,0.3,0,0.6,1,0,0,0,0|",
    "NECROMANCY|0,0,0.4,0.6,0.6,0.3,0,0,0,0,0|card_unlocked_necromancy",
    "LIGHT|1,0.8,0.6,0.4,0.2,0,0,0,0,0,0|",
    "EXPLOSION|0.5,0,1,0,1,0.7,0,0,0,0,0|",
    "EXPLOSION_LIGHT|0,0,0.5,1,0,0.7,0.5,0,0,0,0|",
    "FIRE_BLAST|0.5,0.7,0,0.6,0,0.4,0,0,0,0,0|",
    "POISON_BLAST|0,0.5,0.8,0,0.4,0,0.3,0,0,0,0|",
    "ALCOHOL_BLAST|0,0.5,0.6,0,0.65,0,0.3,0,0,0,0|",
    "THUNDER_BLAST|0,0.5,0,0.6,0,0.7,0.5,0,0,0,0.1|",
    "BERSERK_FIELD|0,0,0.3,0.6,0.3,0,0,0,0,0,0|",
    "POLYMORPH_FIELD|0.3,0.3,0.3,0.8,0.8,0.3,0.3,0,0,0,0|",
    "CHAOS_POLYMORPH_FIELD|0,0.3,0.3,0.5,0.6,0.3,0.3,0,0,0,0|",
    "ELECTROCUTION_FIELD|0,0.3,0,0.6,0,0.8,0.3,0,0,0,0|",
    "FREEZE_FIELD|0.3,0,0.6,0,0.7,0.3,0,0,0,0,0|",
    "REGENERATION_FIELD|0,0.3,0.3,0.4,0.3,0,0,0,0,0,0|",
    "TELEPORTATION_FIELD|0.3,0.6,0.3,0.3,0.6,0.3,0,0,0,0,0|",
    "LEVITATION_FIELD|0,0.3,0.6,0.6,0.3,0,0,0,0,0,0|",
    "SHIELD_FIELD|0,0,0.3,0.3,0.4,0.5,0.3,0,0,0,0|",
    "PROJECTILE_TRANSMUTATION_FIELD|0,0,0.3,0.4,0.4,0.3,0.3,0,0,0,0|",
    "PROJECTILE_THUNDER_FIELD|0,0,0,0.3,0.3,0.5,0.3,0,0,0,0|",
    "PROJECTILE_GRAVITY_FIELD|0,0,0.6,0,0,0.3,0.3,0,0,0,0|",
    "VACUUM_POWDER|0,0,0.3,0.7,0,0.3,0.4,0,0,0,0|",
    "VACUUM_LIQUID|0,0,0.3,0,0.7,0.4,0.3,0,0,0,0|",
    "VACUUM_ENTITIES|0,0,0.3,0.7,0,0.3,0.4,0,0,0,0|",
    "SEA_LAVA|0.2,0,0,0,0.2,0.5,0.6,0,0,0,0|card_unlocked_sea_lava",
    "SEA_ALCOHOL|0.3,0,0,0,0.5,0.6,0.3,0,0,0,0|",
    "SEA_OIL|0.3,0,0,0,0.5,0.6,0.3,0,0,0,0|",
    "SEA_WATER|0.5,0,0,0,0.4,0.3,0.2,0,0,0,0|",
    "SEA_SWAMP|0,0,0,0,0,0,0,0,0,0,0|",
    "SEA_ACID|0.2,0,0,0,0.2,0.4,0.5,0,0,0,0|",
    "SEA_ACID_GAS|0.3,0,0,0,0.4,0.4,0.3,0,0,0,0|",
    "SEA_MIMIC|0.05,0,0,0,0.05,0.1,0.1,0,0,0,0.2|card_unlocked_sea_mimic",
    "CLOUD_WATER|0.2,0.3,0.4,0.4,0.3,0.2,0,0,0,0,0|",
    "CLOUD_OIL|0.2,0.3,0.4,0.4,0.3,0.2,0,0,0,0,0|",
    "CLOUD_BLOOD|0.2,0.3,0.3,0.4,0.3,0.2,0,0,0,0,0|",
    "CLOUD_ACID|0.2,0.2,0.4,0.2,0.2,0.5,0,0,0,0,0|",
    "CLOUD_THUNDER|0.3,0.3,0.2,0.3,0.4,0.5,0,0,0,0,0|card_unlocked_cloud_thunder",
    "ELECTRIC_CHARGE|0,1,1,0,0.8,0.7,0,0,0,0,0|",
    "MATTER_EATER|0,0.1,0.9,0,0.1,0.2,0,0,0,0,0.2|",
    "FREEZE|0,1,0,1,0.9,0.8,0,0,0,0,0|",
    "HITFX_BURNING_CRITICAL_HIT|0,0.2,0,0.4,0.2,0.2,0,0,0,0,0|",
    "HITFX_CRITICAL_WATER|0,0.2,0,0.2,0.4,0.2,0,0,0,0,0|",
    "HITFX_CRITICAL_OIL|0,0.2,0,0.4,0.2,0.2,0,0,0,0,0|",
    "HITFX_CRITICAL_BLOOD|0,0.2,0,0.2,0.2,0.4,0,0,0,0,0|",
    "HITFX_TOXIC_CHARM|0,0.2,0,0.2,0.3,0.2,0,0,0,0,0|",
    "HITFX_EXPLOSION_SLIME|0,0.2,0,0.3,0.2,0.2,0,0,0,0,0|",
    "HITFX_EXPLOSION_SLIME_GIGA|0,0.1,0,0.1,0.3,0.1,0,0,0,0,0|",
    "HITFX_EXPLOSION_ALCOHOL|0,0.3,0,0.2,0.2,0.2,0,0,0,0,0|",
    "HITFX_EXPLOSION_ALCOHOL_GIGA|0,0.1,0,0.1,0.1,0.3,0,0,0,0,0|",
    "HITFX_PETRIFY|0,0,0.2,0.3,0,0.2,0.3,0,0,0,0|",
    "ROCKET_DOWNWARDS|0,0.2,0.5,0.7,0.7,0,0,0,0,0,0|",
    "ROCKET_OCTAGON|0,0,0.5,0.6,0.3,0,0,0,0,0,0|",
    "FIZZLE|0,0,0,0.4,0.3,0.1,0,0,0,0,0|",
    "BOUNCE_EXPLOSION|0,0,0.2,0.6,0.8,0.8,0,0,0,0,0|",
    "BOUNCE_SPARK|0,0.2,0.6,0.6,0.6,0,0,0,0,0,0|",
    "BOUNCE_LASER|0,0,0,0.4,0.8,0.4,0,0,0,0,0|",
    "BOUNCE_LASER_EMITTER|0,0,0,0.4,0.8,0.4,0,0,0,0,0|",
    "BOUNCE_LARPA|0,0,0,0,0.4,0.6,0.4,0,0,0,0|",
    "BOUNCE_SMALL_EXPLOSION|0.5,0.3,0.3,0,0,0,0,0,0,0,0|",
    "BOUNCE_LIGHTNING|0,0.1,0,0.3,0,0.6,0,0,0,0,0|",
    "BOUNCE_HOLE|0,0,0.1,0,0.4,0,0.4,0,0,0,0.1|",
    "FIREBALL_RAY|0,0.6,0.6,0,0.4,0.4,0,0,0,0,0|",
    "LIGHTNING_RAY|0,0,0.2,0.4,0.4,0.4,0,0,0,0,0|",
    "TENTACLE_RAY|0,0.1,0,0.4,0.4,0.4,0,0,0,0,0|",
    "LASER_EMITTER_RAY|0,0,0.1,0.4,0.4,0.4,0,0,0,0,0|",
    "FIREBALL_RAY_LINE|0,0,0.6,0.4,0.4,0.4,1,0,0,0,0|",
    "FIREBALL_RAY_ENEMY|0,0.5,0.6,0,0.4,0.3,0,0,0,0,0|",
    "LIGHTNING_RAY_ENEMY|0,0,0.2,0.4,0.4,0.5,0,0,0,0,0|",
    "TENTACLE_RAY_ENEMY|0,0,0.1,0.4,0.5,0.4,0,0,0,0,0|",
    "GRAVITY_FIELD_ENEMY|0,0.5,0.6,0,0.4,0.4,0,0,0,0,0|",
    "CURSE|0,0,0.6,0.7,0,0.4,0,0,0,0,0.1|",
    "CURSE_WITHER_PROJECTILE|0,0,0,0.2,0.4,0.7,0.7,0,0,0,0.1|",
    "CURSE_WITHER_EXPLOSION|0,0,0.2,0.4,0.7,0.7,0,0,0,0,0.1|",
    "CURSE_WITHER_MELEE|0,0,0,0.2,0.4,0.7,0.7,0,0,0,0.1|",
    "CURSE_WITHER_ELECTRICITY|0,0.2,0,0,0.4,0.7,0.7,0,0,0,0.1|",
    "ORBIT_DISCS|0,0.3,0.65,0,0.4,0.3,0,0,0,0,0|card_unlocked_dragon",
    "ORBIT_FIREBALLS|0.2,0.3,0.7,0,0.4,0.2,0,0,0,0,0|card_unlocked_dragon",
    "ORBIT_NUKES|0,0,0.1,0,0.2,0.1,0.2,0,0,0,1|card_unlocked_dragon",
    "ORBIT_LASERS|0,0.2,0.7,0,0.4,0.3,0,0,0,0,0.2|card_unlocked_dragon",
    "ORBIT_LARPA|0,0,0,0.2,0.2,0,0.8,0,0,0,0.2|card_unlocked_dragon",
    "CHAIN_SHOT|0,0,0.4,0,0.6,0.8,0,0,0,0,0|",
    "ARC_ELECTRIC|0,0,0.4,0.4,0.4,0.4,0.8,0,0,0,0|",
    "ARC_FIRE|0,0.4,0.2,0.2,0.5,0.2,0,0,0,0,0|",
    "ARC_GUNPOWDER|0,0.4,0.4,0.2,0.4,0.2,0,0,0,0,0|",
    "ARC_POISON|0,0.4,0.2,0.4,0.2,0.4,0,0,0,0,0|",
    "CRUMBLING_EARTH_PROJECTILE|0,0.2,0.3,0.4,0.4,0.3,0,0,0,0,0|",
    "X_RAY|0.8,1,1,0.7,0.5,0.3,0.2,0,0,0,0|",
    "UNSTABLE_GUNPOWDER|0,0,0.3,0.4,0.4,0,0,0,0,0,0|",
    "ACID_TRAIL|0,0.3,0.2,0.3,0.3,0.4,0,0,0,0,0|",
    "POISON_TRAIL|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "OIL_TRAIL|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "WATER_TRAIL|0,0.3,0.3,0.3,0.3,0,0,0,0,0,0|",
    "GUNPOWDER_TRAIL|0,0,0.3,0.3,0.3,0,0,0,0,0,0|",
    "FIRE_TRAIL|0.4,0.5,0.3,0.3,0.2,0,0,0,0,0,0|",
    "BURN_TRAIL|0.4,0.3,0.3,0,0,0,0,0,0,0,0|",
    "TORCH|1,0.6,0.5,0,0,0,0,0,0,0,0|",
    "TORCH_ELECTRIC|0.8,0.6,0.4,0,0,0,0,0,0,0,0|",
    "ENERGY_SHIELD|0,0.05,0.4,0.8,0.4,0.4,0.6,0,0,0,0|",
    "ENERGY_SHIELD_SECTOR|0.1,0.5,0.6,0.8,0.5,0.4,0,0,0,0,0|",
    "ENERGY_SHIELD_SHOT|0,0,0.3,0.3,0.5,0.4,0.3,0,0,0,0|",
    "TINY_GHOST|0,0.1,0.5,1,0.8,0.7,0.5,0,0,0,0|",
    "OCARINA_A|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_B|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_C|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_D|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_E|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_F|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_GSHARP|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "OCARINA_A2|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_ocarina",
    "KANTELE_A|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_kantele",
    "KANTELE_D|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_kantele",
    "KANTELE_DIS|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_kantele",
    "KANTELE_E|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_kantele",
    "KANTELE_G|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_kantele",
    "RANDOM_SPELL|0,0,0,0.2,0.3,0.2,0.1,0,0,0,0.5|card_unlocked_pyramid",
    "RANDOM_PROJECTILE|0,0,0.2,0,0.4,0.1,0.2,0,0,0,0.5|card_unlocked_pyramid",
    "RANDOM_MODIFIER|0,0,0,0,0.3,0.2,0.1,0,0,0,0.5|card_unlocked_pyramid",
    "RANDOM_STATIC_PROJECTILE|0,0,0,0.2,0,0.1,0.2,0,0,0,0.5|card_unlocked_pyramid",
    "DRAW_RANDOM|0,0,0.3,0.2,0.2,0.1,0.1,0,0,0,1|card_unlocked_pyramid",
    "DRAW_RANDOM_X3|0,0,0,0.1,0.3,0.1,0.1,0,0,0,1|card_unlocked_pyramid",
    "DRAW_3_RANDOM|0,0,0.1,0.2,0,0.1,0.1,0,0,0,1|card_unlocked_pyramid",
    "ALL_NUKES|0,0,0,0,0,0,0.1,0,0,0,1|card_unlocked_alchemy",
    "ALL_DISCS|0.1,0,0,0,0,0,0.05,0,0,0,1|card_unlocked_alchemy",
    "ALL_ROCKETS|0,0.1,0,0,0,0,0.05,0,0,0,1|card_unlocked_alchemy",
    "ALL_DEATHCROSSES|0,0,0.1,0,0,0,0.05,0,0,0,1|card_unlocked_alchemy",
    "ALL_BLACKHOLES|0,0,0,0.1,0,0,0.05,0,0,0,1|card_unlocked_alchemy",
    "ALL_ACID|0,0,0,0,0.1,0,0.05,0,0,0,1|card_unlocked_alchemy",
    "ALL_SPELLS|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_everything",
    "SUMMON_PORTAL|0,0,0,0,0,0,0,0,0,0,0|",
    "ADD_TRIGGER|0,0,0,0.3,0.6,0.6,0,0,0,0,1|card_unlocked_mestari",
    "ADD_TIMER|0,0,0,0.3,0.6,0.6,0,0,0,0,1|card_unlocked_mestari",
    "ADD_DEATH_TRIGGER|0,0,0,0.3,0.6,0.6,0,0,0,0,1|card_unlocked_mestari",
    "LARPA_CHAOS|0,0,0.1,0.2,0.3,0.4,0,0,0,0,0.2|",
    "LARPA_DOWNWARDS|0,0,0.1,0.3,0.4,0.2,0,0,0,0,0.2|",
    "LARPA_UPWARDS|0,0,0.1,0.1,0.2,0.4,0,0,0,0,0.2|",
    "LARPA_CHAOS_2|0,0,0,0.1,0,0.4,0,0,0,0,0.1|card_unlocked_alchemy",
    "LARPA_DEATH|0,0,0.1,0.1,0.3,0.4,0,0,0,0,0.2|",
    "ALPHA|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_duplicate",
    "GAMMA|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_duplicate",
    "TAU|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_duplicate",
    "OMEGA|0,0,0,0,0,0.1,0.1,0,0,0,1|card_unlocked_duplicate",
    "MU|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_duplicate",
    "PHI|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_duplicate",
    "SIGMA|0,0,0,0,0.1,0.2,0,0,0,0,1|card_unlocked_duplicate",
    "ZETA|0,0,0.2,0,0,0.4,0,0,0,0,0.5|card_unlocked_duplicate",
    "DIVIDE_2|0,0,0,0.2,0,0.3,0.2,0,0,0,1|card_unlocked_musicbox",
    "DIVIDE_3|0,0,0,0,0.1,0.1,0.2,0,0,0,1|card_unlocked_musicbox",
    "DIVIDE_4|0,0,0,0,0,0.1,0.1,0,0,0,1|card_unlocked_musicbox",
    "DIVIDE_10|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_divide",
    "METEOR_RAIN|0,0,0,0,0,0,0.1,0,0,0,1|card_unlocked_rain",
    "WORM_RAIN|0,0,0,0,0,0,0.1,0,0,0,1|card_unlocked_rain",
    "RESET|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_mestari",
    "IF_ENEMY|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "IF_PROJECTILE|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "IF_HP|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "IF_HALF|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "IF_END|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "IF_ELSE|0,0,0,0,0,0,0,0,0,0,1|card_unlocked_maths",
    "COLOUR_RED|0,0.2,0.2,0.4,0.2,0.2,0.2,0,0,0,0|card_unlocked_paint",
    "COLOUR_ORANGE|0,0,0.1,0.1,0.4,0,0,0,0,0,0|card_unlocked_paint",
    "COLOUR_GREEN|0,0,0.4,0.1,0.1,0,0,0,0,0,0|card_unlocked_paint",
    "COLOUR_YELLOW|0,0,0.1,0.4,0.1,0,0,0,0,0,0|card_unlocked_paint",
    "COLOUR_PURPLE|0,0,0.1,0.1,0.4,0,0,0,0,0,0|card_unlocked_paint",
    "COLOUR_BLUE|0,0,0.4,0.1,0.1,0,0,0,0,0,0|card_unlocked_paint",
    "COLOUR_RAINBOW|0,0,0.1,0.1,0.1,0,0,0,0,0,0.2|card_unlocked_paint",
    "COLOUR_INVIS|0,0,0.1,0.1,0.1,0,0,0,0,0,0.1|card_unlocked_paint",
    "RAINBOW_TRAIL|0,0,0,0,0,0,0,0,0,0,0|card_unlocked_rainbow_trail",
    "CESSATION|0,0,0,0,0,0.1,0.2,0,0,0,1|card_unlocked_cessation",
}

-- PRD section 3: normal target group G10 (wild shop / chest direct drop: +10).
M.G10 = {
	TELEPORT_PROJECTILE = true,
	TELEPORT_PROJECTILE_SHORT = true,
	CHAINSAW = true,
	LIGHT_BULLET_TRIGGER = true,
	BLACK_HOLE = true,
	WHITE_HOLE = true,
	BLACK_HOLE_DEATH_TRIGGER = true,
	MANA_REDUCE = true,
	POLYMORPH_FIELD = true,
}

-- PRD section 3: advanced target group G20 (+20 wild direct / +20 Holy Mountain).
M.G20 = {
	ALPHA = true,
	GAMMA = true,
	TAU = true,
	OMEGA = true,
	MU = true,
	PHI = true,
	SIGMA = true,
	ZETA = true,
	ADD_TRIGGER = true,
	ADD_TIMER = true,
	ADD_DEATH_TRIGGER = true,
	I_SHOT = true,
	Y_SHOT = true,
	T_SHOT = true,
	W_SHOT = true,
	QUAD_SHOT = true,
	PENTA_SHOT = true,
	HEXA_SHOT = true,
	RESET = true,
}

-- PRD section 3: healing target G50 (Circle of Vigour, +50).
M.G50 = {
	REGENERATION_FIELD = true,
}

-- PRD section 3: Holy Mountain H2 = G10 plus these three; +2 each.
M.H2_EXTRA = {
	LUMINOUS_DRILL = true,
	DIGGER = true,
	HEAL_BULLET = true,
}

-- ---------------------------------------------------------------------------
-- Derived structures (built once at load)
-- ---------------------------------------------------------------------------

M.pool = {}
M.by_id = {}
M.gated_flags = {}

local function split( value )
	local out = {}
	if ( value == nil or value == "" ) then
		return out
	end
	for part in string.gmatch( value, "([^,]+)" ) do
		out[ #out + 1 ] = part
	end
	return out
end

for i = 1, #M.RAW_POOL do
	local raw = M.RAW_POOL[ i ]
	local id, weights, flag = string.match( raw, "^([A-Z0-9_]+)|([^|]*)|(.*)$" )
	if ( id == nil ) then
		error( "files/isf/data/spells.lua: malformed pool row " .. tostring( i ) )
	end
	local w = {}
	local parts = split( weights )
	for level = 0, 10 do
		w[ level + 1 ] = tonumber( parts[ level + 1 ] or "0" ) or 0
	end
	if ( flag == "" ) then
		flag = nil
	end
	local entry = {
		index = i,
		id = id,
		weights = w,
		requires_flag = flag,
	}
	M.pool[ i ] = entry
	if ( M.by_id[ id ] ~= nil ) then
		error( "files/isf/data/spells.lua: duplicate spell id " .. tostring( id ) )
	end
	M.by_id[ id ] = entry
	if ( flag ~= nil ) then
		M.gated_flags[ flag ] = true
	end
end

-- Flags that gate pool membership, sorted for stable reporting.
M.gated_flag_list = {}
for flag in pairs( M.gated_flags ) do
	M.gated_flag_list[ #M.gated_flag_list + 1 ] = flag
end
table.sort( M.gated_flag_list )

-- True when the slot is a normal target-group member that gets a score.
function M.is_target( spell_id )
	return M.G10[ spell_id ] == true
		or M.G20[ spell_id ] == true
		or M.G50[ spell_id ] == true
		or M.H2_EXTRA[ spell_id ] == true
end

return M
