-- files/isf/data/containers.lua
--
-- ISF-09 / PRD R5 data: liquid containers (potions) and powder containers
-- (pouches), their exact content generators, the region table, and the
-- container-kind contract used by providers/collectibles.lua.
--
-- Every constant here was derived from the *installed* game data (read-only)
-- and, where the installed data is silent, from the pinned upstream sources:
--
--   data/scripts/items/potion.lua              (normal potion material chain)
--   data/scripts/items/potion_secret.lua       (fixed secret-potion list)
--   data/scripts/items/potion_random_material.lua
--   data/scripts/items/powder_stash.lua        (pouch material chain)
--   data/scripts/lib/utilities.lua             (random_from_array = Random(1,#t))
--   data/entities/items/pickup/*.xml           (which entity is which container)
--   data/items_gfx/potion.png, material_pouch.png (sprite sizes -> seed offset)
--   data/materials.xml                         (material names, wang colours)
--
-- Game build: 9dbd52ced019a643169a2db02f46c77f8766c6e5 (branch master).
-- The generated registry at the bottom is refreshed by
--   python tools/collectibles/gen_containers_materials.py
-- from data.wak; it is not hand-edited.
--
-- Lua 5.1 / LuaJIT compatible. No FFI, no external process, no game globals.
--
-- Licensing / provenance of reused material (MIT):
--   * noita-tools, Copyright (c) 2022 Seva Maltsev <me@seva.dev>
--     pin 0c7f27cf9b28ffcf2d8e6a5e41b3a007fe8ad21f
--     (InfoProviders/Potion.ts, PotionSecret.ts, PotionRandomMaterial.ts,
--      PowderStash.ts, chest/potion providers, Map/Base.ts)
--   * noita-telescope, Copyright (c) 2026 Lymm
--     pin ca0282fbb2bcb86f040a8a39c148a65bf48d1cbc
--     (js/potion_generation.js, js/potion_config.js, js/chest_generation.js)
-- The pools are taken from the game's own scripts; the upstream projects were
-- used to cross-check them and to obtain oracle vectors. No game asset is
-- redistributed by this module.

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.GAME_VERSION_HASH = "9dbd52ced019a643169a2db02f46c77f8766c6e5"

--------------------------------------------------------------------------------
-- Material IDs (exact, never substring-matched; PRD section 3 / R5 wording)
--------------------------------------------------------------------------------

-- "不稳定传送液" / unstable teleportatium. The game's material id.
M.MATERIAL_UNSTABLE_TELEPORTATIUM = "magic_liquid_unstable_teleportation"

-- The stable variant exists and is a *different* material; it must never be
-- accepted in place of the unstable one (PRD R5 names only the unstable liquid).
M.MATERIAL_TELEPORTATIUM = "magic_liquid_teleportation"

-- "金粉" / gold powder: the sand material `gold`, which is what a gold pouch is
-- initially filled with. Molten gold / gold nuggets / coins are different things.
M.MATERIAL_GOLD = "gold"

--------------------------------------------------------------------------------
-- Content generators (exact branch chains from the installed scripts)
--------------------------------------------------------------------------------

-- potion.lua `materials_standard` / `materials_magic`, in file order. The order
-- is load-bearing: `random_from_array` is `Random(1, #t)` and picks by index.
-- The upstream `cost` field is never read by the game; it is deliberately not
-- copied here so nobody mistakes it for a weight.
M.POTION_STANDARD = {
	"lava",
	"water",
	"blood",
	"alcohol",
	"oil",
	"slime",
	"acid",
	"radioactive_liquid",
	"gunpowder_unstable",
	"liquid_fire",
	"blood_cold",
}

M.POTION_MAGIC = {
	"magic_liquid_unstable_teleportation",
	"magic_liquid_polymorph",
	"magic_liquid_random_polymorph",
	"magic_liquid_berserk",
	"magic_liquid_charm",
	"magic_liquid_invisibility",
	"material_confusion",
	"magic_liquid_movement_faster",
	"magic_liquid_faster_levitation",
	"magic_liquid_worm_attractor",
	"magic_liquid_protection_all",
	"magic_liquid_mana_regeneration",
}

-- potion_secret.lua `potions` list, in file order (13 entries; the commented-out
-- `creepy_liquid` entry is not part of the list in this build).
M.POTION_SECRET = {
	"magic_liquid_hp_regeneration_unstable",
	"blood_worm",
	"gold",
	"snow",
	"glowshroom",
	"bush_seed",
	"cement",
	"salt",
	"sodium",
	"mushroom_seed",
	"plant_seed",
	"urine",
	"purifying_powder",
}

-- powder_stash.lua `materials_magic` / `materials_standard`, in file order.
M.POUCH_MAGIC = {
	"copper",
	"silver",
	"gold",
	"brass",
	"bone",
	"purifying_powder",
	"fungi",
}

M.POUCH_STANDARD = {
	"sand",
	"soil",
	"snow",
	"salt",
	"coal",
	"gunpowder",
	"fungisoil",
}

-- Content generators this module can reproduce exactly.
--   supported = false  -> the container is a real container but its content is
--   NOT predictable from (seed, transform) alone; callers must supply the fixed
--   material or the record is rejected. Never guessed, never defaulted.
M.GENERATORS = {
	potion = {
		supported = true,
		uses_calendar = true,
		source = "data/scripts/items/potion.lua init()",
	},
	potion_secret = {
		supported = true,
		uses_calendar = false,
		source = "data/scripts/items/potion_secret.lua init()",
	},
	powder_stash = {
		supported = true,
		uses_calendar = false,
		source = "data/scripts/items/powder_stash.lua init()",
	},
	random_material = {
		supported = false,
		reason = "potion_random_material.lua draws from the engine's live "
			.. "CellFactory_GetAllLiquids/GetAllSands lists, whose contents and "
			.. "order cannot be reconstructed offline: deriving them from this "
			.. "build's materials.xml gives 97 liquids / 86 sands while both "
			.. "pinned upstream libraries hardcode 98 / 87 (they include `peat` "
			.. "and `moss_rust`, which have no matching cell_type here).",
		source = "data/scripts/items/potion_random_material.lua init()",
	},
	potion_starting = {
		supported = false,
		reason = "potion_starting.lua branches on StatsGlobalGetValue("
			.. "\"death_count\") as well as the calendar; the starting flask is "
			.. "outside PRD R5 scope and is not reconstructed here.",
		source = "data/scripts/items/potion_starting.lua init()",
	},
	none = {
		supported = false,
		reason = "container has no content generator (empty / fixed material)",
		source = "data/entities/items/pickup/*.xml",
	},
}

--------------------------------------------------------------------------------
-- Container kinds and entity files
--------------------------------------------------------------------------------
--
-- The PRD rewards are tied to *actual container kinds*: a potion (glass flask)
-- and a powder pouch. A jar, an empty potion, a gold nugget, a coin or a chest
-- is not either of them, so those records are rejected instead of being folded
-- into the nearest-looking rule.
--
-- `entity_file` is the exact game path. `kind` is the canonical R5 container
-- kind. `supported=false` means "real object, but no R5 scoring path".
M.ENTITY_FILES = {
	[ "data/entities/items/pickup/potion.xml" ] = {
		kind = "potion", generator = "potion", supported = true,
	},
	[ "data/entities/items/pickup/potion_secret.xml" ] = {
		kind = "potion", generator = "potion_secret", supported = true,
	},
	[ "data/entities/items/pickup/potion_random_material.xml" ] = {
		kind = "potion", generator = "random_material", supported = false,
	},
	[ "data/entities/items/pickup/powder_stash.xml" ] = {
		kind = "powder_pouch", generator = "powder_stash", supported = true,
	},
	[ "data/entities/items/shop_potion.xml" ] = {
		kind = "potion", generator = "potion", supported = true,
	},
	[ "data/entities/items/pickup/potion_empty.xml" ] = {
		kind = "potion_empty", generator = "none", supported = false,
		reason = "empty flask: potion.xml with its LuaComponent disabled",
	},
	[ "data/entities/items/pickup/potion_starting.xml" ] = {
		kind = "starting_flask", generator = "potion_starting", supported = false,
	},
	[ "data/entities/items/pickup/jar.xml" ] = {
		kind = "jar", generator = "none", supported = false,
		reason = "jar is not a potion and not a powder pouch",
	},
	[ "data/entities/items/pickup/jar_of_urine.xml" ] = {
		kind = "jar", generator = "none", supported = false,
		reason = "jar with a VariableStorageComponent material; not R5",
	},
	[ "data/entities/items/pickup/potion_aggressive.xml" ] = {
		kind = "potion", generator = "none", supported = false,
		reason = "aggressive potion variant: no init() generator, material comes "
			.. "from elsewhere",
	},
}

-- Canonical container kinds accepted in an object record.
--   natural_pool is a *generated liquid source*, not an item; it is listed so
--   the unsupported path can be explicit instead of silently ignored.
M.KINDS = {
	potion = { label = "potion", reward = "R5.1" },
	powder_pouch = { label = "powder pouch", reward = "R5.2" },
	natural_pool = { label = "natural liquid pool", reward = "R5.3" },
}

--------------------------------------------------------------------------------
-- Regions (PRD section 2 + R5)
--------------------------------------------------------------------------------
--
-- `teleport_potion` / `gold_pouch` are exactly PRD R5's region gates:
--   unstable teleportatium potion : Mines, Coal Pits
--   gold powder pouch            : Mines, Coal Pits, Fungal Caverns
-- Collapsed Mines is deliberately excluded from both, even though it shares the
-- coalmine_alt spawn table with Mines.
M.REGIONS = {
	[ "Mines" ] = { in_scope = true, teleport_potion = true, gold_pouch = true },
	[ "Coal Pits" ] = { in_scope = true, teleport_potion = true, gold_pouch = true },
	[ "Fungal Caverns" ] = { in_scope = true, teleport_potion = false, gold_pouch = true },
	[ "Collapsed Mines" ] = {
		in_scope = false,
		reason = "PRD R5 does not extend either reward to Collapsed Mines",
	},
	-- Documented out-of-scope main-world regions. A record from one of these is
	-- valid but earns nothing; it is not an error.
	[ "Snowy Depths" ] = { in_scope = false, reason = "R5 does not extend to Snowy Depths" },
	[ "Holy Mountain" ] = { in_scope = false, reason = "R5 has no Holy Mountain reward" },
	[ "Hiisi Base" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "Underground Jungle" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "The Vault" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "Temple of the Art" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "The Laboratory" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "Lake" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
	[ "Ancient Laboratory" ] = { in_scope = false, reason = "outside the R5 scoring regions" },
}

-- Upstream/biome-script spellings of the same region, so a caller can pass the
-- generator key it already has. Only these aliases are accepted; anything else
-- is an unknown region and is rejected rather than silently treated as
-- out-of-scope.
M.REGION_ALIASES = {
	coalmine = "Mines",
	mines = "Mines",
	coalmine_alt = "Collapsed Mines",
	["collapsed mines"] = "Collapsed Mines",
	excavationsite = "Coal Pits",
	["coal pits"] = "Coal Pits",
	fungicave = "Fungal Caverns",
	["fungal caverns"] = "Fungal Caverns",
	snowy_depths = "Snowy Depths",
	snowcave = "Snowy Depths",
	holy_mountain = "Holy Mountain",
	temple_altar = "Holy Mountain",
	hiisi_base = "Hiisi Base",
	excavationsite_hiisi = "Hiisi Base",
	underground_jungle = "Underground Jungle",
	rainforest = "Underground Jungle",
	the_vault = "The Vault",
	vault = "The Vault",
	temple_of_the_art = "Temple of the Art",
	the_laboratory = "The Laboratory",
	laboratory = "The Laboratory",
	lake = "Lake",
	ancient_laboratory = "Ancient Laboratory",
}

-- Resolve a region spelling to { name, info } or nil + reason.
-- `region_scope = "out_of_scope"` on a record is the documented escape hatch
-- for a region this table does not name; the caller then states the fact
-- instead of the provider guessing it.
function M.region( name )
	if ( type( name ) ~= "string" or name == "" ) then
		return nil, "region must be a non-empty string"
	end
	local info = M.REGIONS[ name ]
	if ( info ~= nil ) then
		return name, info
	end
	local alias = M.REGION_ALIASES[ string.lower( name ) ]
	if ( alias ~= nil ) then
		return alias, M.REGIONS[ alias ]
	end
	return nil, "unknown region '" .. name .. "' (pass a documented region name or "
		.. "set region_scope = \"out_of_scope\")"
end

--------------------------------------------------------------------------------
-- Reward rules (PRD R5), in score_units (4 units = 1 point, WORKER_CONTRACT)
--------------------------------------------------------------------------------

local UNITS_PER_POINT = 4

M.RULES = {
	R5_1 = {
		rule_id = "R5.1",
		category = "wild.unstable_teleport_potions",
		kind = "potion",
		material = M.MATERIAL_UNSTABLE_TELEPORTATIUM,
		score_units = 2 * UNITS_PER_POINT, -- +2
		region_flag = "teleport_potion",
		reason = "unstable teleportatium potion in an R5 region (+2)",
	},
	R5_2 = {
		rule_id = "R5.2",
		category = "wild.gold_pouches",
		kind = "powder_pouch",
		material = M.MATERIAL_GOLD,
		score_units = 5 * UNITS_PER_POINT, -- +5
		region_flag = "gold_pouch",
		reason = "powder pouch initially filled with gold powder (+5)",
	},
	R5_3 = {
		rule_id = "R5.3",
		category = "wild.natural_teleport_pools",
		kind = "natural_pool",
		material = M.MATERIAL_UNSTABLE_TELEPORTATIUM,
		score_units = 2 * UNITS_PER_POINT, -- +2 per independent source
		region_flag = "teleport_potion",
		reason = "independently generated natural unstable teleportatium pool (+2)",
	},
}

M.RULE_ORDER = { "R5_1", "R5_2", "R5_3" }

M.REWARD_BY_KIND_AND_MATERIAL = {
	[ "potion" ] = { [ M.MATERIAL_UNSTABLE_TELEPORTATIUM ] = "R5_1" },
	[ "powder_pouch" ] = { [ M.MATERIAL_GOLD ] = "R5_2" },
	[ "natural_pool" ] = { [ M.MATERIAL_UNSTABLE_TELEPORTATIUM ] = "R5_3" },
}

--------------------------------------------------------------------------------
-- Natural liquid pools: explicit capability statement
--------------------------------------------------------------------------------
--
-- PRD R5 allows +2 per independent *initially generated* natural pool, but only
-- when the count can be predicted accurately. This build provides no such
-- source, so the capability is declared unsupported with the evidence below.
-- Reporting "0 pools" for a seed is forbidden: unknown is not absence.
--
-- Evidence gathered with tools/collectibles:
--   * `magic_liquid_unstable_teleportation` has wang_color 8000BEE4 in
--     data/materials.xml.
--   * scanning all 2117 `data/biome_impl/**` and `data/wang_tiles/**` PNGs in
--     data.wak finds that colour (and its red/blue-swapped uint form) in none
--     of them, while the same scanner does find the pixel-scene placeholder
--     FFF0BBEE in 13 scenes - so the scan itself works.
--   * every `color_material` pool in coalmine.lua / coalmine_alt.lua /
--     fungicave.lua / liquidcave.lua / vault.lua that mentions teleportatium
--     lists the *stable* `magic_liquid_teleportation`, never the unstable one.
--   * the unstable material appears in this build only as a potion/alchemy
--     ingredient and inside MaterialAreaCheckerComponent definitions of
--     pre-placed vault/lab teleporters.
--
-- A per-seed prediction would additionally need the pixel-scene placement port
-- (ISF-02) plus a verified material-recolour draw for the scene. Neither exists.
M.NATURAL_POOL_SUPPORT = {
	status = "unsupported",
	reason = "no verified source-level generator for natural unstable "
		.. "teleportatium pools exists in this build or in the local ports: "
		.. "no generated pixel scene or wang tile contains its wang colour "
		.. "8000BEE4, and every biome color_material pool that mentions "
		.. "teleportatium lists the stable magic_liquid_teleportation instead. "
		.. "Pool coverage is therefore unknown, not zero.",
	-- Empty by construction. A pool record is only scored when its
	-- `source_kind` appears here; adding an entry requires a verified
	-- per-seed generator, which is a separate, evidence-backed change.
	verified_sources = {},
	evidence = {
		material = M.MATERIAL_UNSTABLE_TELEPORTATIUM,
		wang_color = "8000BEE4",
		png_scanned = 2117,
		png_matches = 0,
		placeholder_color = "FFF0BBEE",
		placeholder_matches = 13,
	},
}

--------------------------------------------------------------------------------
-- Generation inputs (which of the profile's fields can change the content)
--------------------------------------------------------------------------------
--
-- Stated explicitly so a caller cannot assume more (or less) dependence than
-- exists:
--
--   * calendar  : YES for normal potions (potion.lua applies four date-based
--                 overrides). The two fixed-date rules only need month/day; the
--                 two other rules read the engine's undocumented 7th/8th values,
--                 which the caller must pass as `jussi` / `mammi`.
--                 NO for secret potions and for powder pouches.
--   * unlocked_flags / persistent_flags : NO. None of the three supported
--                 content generators reads an unlock or persistent flag, so a
--                 snapshot difference in flags cannot change an R5 material.
--                 (The spell/wand pools elsewhere do depend on flags; that is
--                 not this provider's data.)
--   * perks     : NO for the baseline. The only perk hook in these generators is
--                 `EXTRA_POTION_CAPACITY_LEVEL`, which raises the fill *amount*
--                 and never changes which material is chosen. PRD R5 scores the
--                 no-perk baseline, so the amount is recorded, not derived.
M.BASELINE = {
	perks_picked = false,
	extra_potion_capacity_level = 1000, -- default in potion.lua / powder_stash.lua
	content_depends_on_calendar = { potion = true, potion_secret = false, powder_stash = false },
	content_depends_on_flags = false,
	content_depends_on_perks = false,
}

-- Human-readable summary for reports/logs.
function M.generation_inputs()
	return {
		calendar = "explicit; required for normal potions (jussi/mammi must be supplied)",
		unlocked_flags = "not used by R5 content generators",
		persistent_flags = "not used by R5 content generators",
		perks = "no-perk baseline; capacity perk only changes fill amount, not material",
	}
end

--------------------------------------------------------------------------------
-- Coordinate frames
--------------------------------------------------------------------------------
--
-- The game seeds container content with the *entity transform*:
--   potion.lua: local x, y = EntityGetTransform(entity_id); SetRandomSeed(x, y)
--   powder_stash.lua: identical
-- so a predictor must be given that transform, never a spawn-table anchor.
--
-- The transform is not the position a spawn table writes: it is offset by half
-- the sprite, and the two offsets differ per container. Both upstream libraries
-- agree on the load-point -> transform relation:
--   seeds used = load + (-sprite_width/2, -sprite_height/2)
-- which is exactly what the shipped sprites give:
--   data/items_gfx/potion.png         9 x 8  -> (-4.5, -4.0)
--   data/items_gfx/material_pouch.png 9 x 11 -> (-4.5, -5.5)
-- and matches every published upstream vector when fed the same load point.
-- (noita-tools' pouch fixtures address the load point directly, its potion
-- fixtures address the spawnlist anchor, two pixels above the load point; that
-- bookkeeping difference is why this module refuses anchor coordinates.)
M.SPRITE_SIZE = {
	potion = { width = 9, height = 8 },
	powder_pouch = { width = 9, height = 11 },
}

M.SEED_FRAME = "entity_transform"

-- load point -> seeded transform, per container kind.
function M.seed_position_from_load( kind, load_x, load_y )
	local size = M.SPRITE_SIZE[ kind ]
	if ( size == nil ) then
		return nil, "no sprite size recorded for container kind " .. tostring( kind )
	end
	if ( type( load_x ) ~= "number" or type( load_y ) ~= "number" ) then
		return nil, "load position must be numeric"
	end
	return load_x - size.width / 2, load_y - size.height / 2
end

-- Only the two exact standard entities were observed at native init entry in
-- the installed build (seed49 potions/pouches and seed7482 gold pouch). Other
-- inherited/custom shapes keep their unresolved frame rather than borrowing it.
function M.native_init_position( kind, entity_file, load_x, load_y )
	local expected = kind == "potion" and "data/entities/items/pickup/potion.xml"
		or (kind == "powder_pouch" and "data/entities/items/pickup/powder_stash.xml")
	if not expected or entity_file ~= expected then return nil end
	local x,y = M.seed_position_from_load(kind,load_x,load_y)
	if type(x) ~= "number" then return nil end
	return x,y,"native-standard-centered-shape:"..M.GAME_VERSION_HASH
end

--------------------------------------------------------------------------------
-- Generated material registry (see tools/collectibles/gen_containers_materials.py)
--------------------------------------------------------------------------------
--
-- Used only to reject typo'd / non-existent material ids in supplied records.
-- A record naming a material this build does not define is a data error, not
-- "some other material": guessing would hide a broken caller.
M.MATERIALS_SOURCE = {
	wak_entry = "data/materials.xml",
	sha256 = "122df34514edaf312e1a15a619b3d6a44d49ce605c929d5950c9051a57429d04",
	game_version_hash = M.GAME_VERSION_HASH,
	generated_by = "tools/collectibles/gen_containers_materials.py",
}

M.KNOWN_MATERIALS = {
	-- BEGIN GENERATED MATERIALS
	["acid"] = true, ["acid_gas"] = true, ["acid_gas_static"] = true, ["air"] = true,
	["alcohol"] = true, ["alcohol_gas"] = true, ["aluminium"] = true, ["aluminium_molten"] = true,
	["aluminium_oxide"] = true, ["aluminium_oxide_molten"] = true, ["aluminium_robot"] = true,
	["aluminium_robot_molten"] = true, ["beer"] = true, ["blood"] = true, ["blood_cold"] = true,
	["blood_cold_vapour"] = true, ["blood_fading"] = true, ["blood_fading_slow"] = true,
	["blood_fungi"] = true, ["blood_thick"] = true, ["blood_worm"] = true, ["bloodgold_box2d"] = true,
	["bluefungi_static"] = true, ["bone"] = true, ["bone_box2d"] = true, ["bone_static"] = true,
	["brass"] = true, ["brass_molten"] = true, ["brick"] = true, ["burning_powder"] = true,
	["bush_seed"] = true, ["cactus"] = true, ["ceiling_plant_material"] = true, ["cement"] = true,
	["cheese_static"] = true, ["cloth_box2d"] = true, ["cloud"] = true, ["cloud_blood"] = true,
	["cloud_lighter"] = true, ["cloud_radioactive"] = true, ["cloud_slime"] = true, ["coal"] = true,
	["coal_static"] = true, ["cocoon_box2d"] = true, ["concrete_collapsed"] = true,
	["concrete_sand"] = true, ["concrete_static"] = true, ["copper"] = true, ["copper_molten"] = true,
	["corruption_static"] = true, ["creepy_liquid"] = true, ["creepy_liquid_emitter"] = true,
	["crystal"] = true, ["crystal_magic"] = true, ["crystal_purple"] = true, ["crystal_solid"] = true,
	["cursed_liquid"] = true, ["diamond"] = true, ["endslime"] = true, ["endslime_blood"] = true,
	["endslime_static"] = true, ["explosion_dirt"] = true, ["fire"] = true, ["fire_blue"] = true,
	["flame"] = true, ["fungal_gas"] = true, ["fungal_shift_particle_fx"] = true, ["fungi"] = true,
	["fungi_creeping"] = true, ["fungi_creeping_secret"] = true, ["fungi_green"] = true,
	["fungi_yellow"] = true, ["fungisoil"] = true, ["fungus_loose"] = true,
	["fungus_loose_green"] = true, ["fungus_loose_trippy"] = true, ["fungus_powder"] = true,
	["fungus_powder_bad"] = true, ["fuse"] = true, ["fuse_bright"] = true, ["fuse_holy"] = true,
	["fuse_tnt"] = true, ["gem_box2d"] = true, ["gem_box2d_darksun"] = true,
	["gem_box2d_green"] = true, ["gem_box2d_opal"] = true, ["gem_box2d_orange"] = true,
	["gem_box2d_pink"] = true, ["gem_box2d_red"] = true, ["gem_box2d_red_float"] = true,
	["gem_box2d_turquoise"] = true, ["gem_box2d_white"] = true, ["gem_box2d_yellow_sun"] = true,
	["gem_box2d_yellow_sun_gravity"] = true, ["glass"] = true, ["glass_box2d"] = true,
	["glass_brittle"] = true, ["glass_broken"] = true, ["glass_broken_molten"] = true,
	["glass_liquidcave"] = true, ["glass_molten"] = true, ["glass_static"] = true,
	["glowshroom"] = true, ["glowstone"] = true, ["glowstone_altar"] = true,
	["glowstone_altar_hdr"] = true, ["glowstone_potion"] = true, ["glue"] = true, ["gold"] = true,
	["gold_b2"] = true, ["gold_box2d"] = true, ["gold_molten"] = true, ["gold_radioactive"] = true,
	["gold_static"] = true, ["gold_static_dark"] = true, ["gold_static_radioactive"] = true,
	["grass"] = true, ["grass_dark"] = true, ["grass_darker"] = true, ["grass_dry"] = true,
	["grass_holy"] = true, ["grass_ice"] = true, ["grass_loose"] = true, ["gunpowder"] = true,
	["gunpowder_explosive"] = true, ["gunpowder_tnt"] = true, ["gunpowder_unstable"] = true,
	["gunpowder_unstable_big"] = true, ["gunpowder_unstable_boss_limbs"] = true, ["honey"] = true,
	["ice"] = true, ["ice_acid_glass"] = true, ["ice_acid_static"] = true, ["ice_b2"] = true,
	["ice_blood_glass"] = true, ["ice_blood_static"] = true, ["ice_ceiling"] = true,
	["ice_cold_glass"] = true, ["ice_cold_static"] = true, ["ice_glass"] = true,
	["ice_glass_b2"] = true, ["ice_melting_perf_killer"] = true, ["ice_meteor_static"] = true,
	["ice_poison_glass"] = true, ["ice_poison_static"] = true, ["ice_radioactive_glass"] = true,
	["ice_radioactive_static"] = true, ["ice_slime_glass"] = true, ["ice_slime_static"] = true,
	["ice_static"] = true, ["item_box2d"] = true, ["item_box2d_glass"] = true,
	["item_box2d_meat"] = true, ["juhannussima"] = true, ["just_death"] = true, ["lava"] = true,
	["lavarock_static"] = true, ["lavasand"] = true, ["liquid_fire"] = true,
	["liquid_fire_weak"] = true, ["magic_crystal"] = true, ["magic_crystal_green"] = true,
	["magic_gas_fungus"] = true, ["magic_gas_hp_regeneration"] = true, ["magic_gas_midas"] = true,
	["magic_gas_polymorph"] = true, ["magic_gas_teleport"] = true, ["magic_gas_weakness"] = true,
	["magic_gas_worm_blood"] = true, ["magic_liquid"] = true, ["magic_liquid_berserk"] = true,
	["magic_liquid_charm"] = true, ["magic_liquid_faster_levitation"] = true,
	["magic_liquid_faster_levitation_and_movement"] = true, ["magic_liquid_hp_regeneration"] = true,
	["magic_liquid_hp_regeneration_unstable"] = true, ["magic_liquid_invisibility"] = true,
	["magic_liquid_mana_regeneration"] = true, ["magic_liquid_movement_faster"] = true,
	["magic_liquid_polymorph"] = true, ["magic_liquid_protection_all"] = true,
	["magic_liquid_random_polymorph"] = true, ["magic_liquid_teleportation"] = true,
	["magic_liquid_unstable_polymorph"] = true, ["magic_liquid_unstable_teleportation"] = true,
	["magic_liquid_weakness"] = true, ["magic_liquid_worm_attractor"] = true, ["mammi"] = true,
	["material_confusion"] = true, ["material_darkness"] = true, ["material_rainbow"] = true,
	["meat"] = true, ["meat_burned"] = true, ["meat_confusion"] = true, ["meat_cursed"] = true,
	["meat_cursed_dry"] = true, ["meat_done"] = true, ["meat_fast"] = true, ["meat_frog"] = true,
	["meat_fruit"] = true, ["meat_helpless"] = true, ["meat_hot"] = true, ["meat_polymorph"] = true,
	["meat_polymorph_protection"] = true, ["meat_pumpkin"] = true, ["meat_slime"] = true,
	["meat_slime_cursed"] = true, ["meat_slime_green"] = true, ["meat_slime_orange"] = true,
	["meat_slime_sand"] = true, ["meat_static"] = true, ["meat_teleport"] = true,
	["meat_trippy"] = true, ["meat_warm"] = true, ["meat_worm"] = true, ["metal"] = true,
	["metal_chain_nohit"] = true, ["metal_hard"] = true, ["metal_molten"] = true,
	["metal_nohit"] = true, ["metal_nohit_molten"] = true, ["metal_prop"] = true,
	["metal_prop_loose"] = true, ["metal_prop_low_restitution"] = true, ["metal_prop_molten"] = true,
	["metal_rust"] = true, ["metal_rust_barrel"] = true, ["metal_rust_barrel_rust"] = true,
	["metal_rust_molten"] = true, ["metal_rust_rust"] = true, ["metal_sand"] = true,
	["metal_sand_molten"] = true, ["metal_wire_nohit"] = true, ["meteorite"] = true,
	["meteorite_crackable"] = true, ["meteorite_green"] = true, ["meteorite_static"] = true,
	["meteorite_test"] = true, ["midas"] = true, ["midas_precursor"] = true, ["milk"] = true,
	["mimic_liquid"] = true, ["molut"] = true, ["monster_powder_test"] = true, ["moss"] = true,
	["moss_rust"] = true, ["mud"] = true, ["mushroom"] = true, ["mushroom_giant_blue"] = true,
	["mushroom_giant_red"] = true, ["mushroom_seed"] = true, ["neon_tube_blood_red"] = true,
	["neon_tube_cyan"] = true, ["neon_tube_purple"] = true, ["nest_box2d"] = true,
	["nest_firebug_box2d"] = true, ["nest_static"] = true, ["oil"] = true, ["orb_powder"] = true,
	["pea_soup"] = true, ["peat"] = true, ["physics_throw_material_part2"] = true,
	["plant_material"] = true, ["plant_material_dark"] = true, ["plant_material_red"] = true,
	["plant_seed"] = true, ["plasma_fading"] = true, ["plasma_fading_bright"] = true,
	["plasma_fading_green"] = true, ["plasma_fading_pink"] = true, ["plastic"] = true,
	["plastic_grey"] = true, ["plastic_grey_molten"] = true, ["plastic_molten"] = true,
	["plastic_prop"] = true, ["plastic_prop_molten"] = true, ["plastic_red"] = true,
	["plastic_red_molten"] = true, ["poison"] = true, ["poison_gas"] = true, ["poo"] = true,
	["poo_gas"] = true, ["poop_box2d_hard"] = true, ["porridge"] = true,
	["potion_glass_box2d"] = true, ["purifying_powder"] = true, ["pus"] = true,
	["radioactive_gas"] = true, ["radioactive_gas_static"] = true, ["radioactive_liquid"] = true,
	["radioactive_liquid_fading"] = true, ["radioactive_liquid_yellow"] = true,
	["rainbow_gas"] = true, ["rat_powder"] = true, ["rock_box2d"] = true, ["rock_box2d_hard"] = true,
	["rock_box2d_nohit"] = true, ["rock_box2d_nohit_hard"] = true, ["rock_box2d_nohit_heavy"] = true,
	["rock_eroding"] = true, ["rock_hard"] = true, ["rock_hard_border"] = true, ["rock_loose"] = true,
	["rock_magic_bottom"] = true, ["rock_magic_gate"] = true, ["rock_static"] = true,
	["rock_static_box2d"] = true, ["rock_static_cursed"] = true, ["rock_static_cursed_green"] = true,
	["rock_static_fungal"] = true, ["rock_static_glow"] = true, ["rock_static_grey"] = true,
	["rock_static_intro"] = true, ["rock_static_intro_breakable"] = true,
	["rock_static_noedge"] = true, ["rock_static_poison"] = true, ["rock_static_purple"] = true,
	["rock_static_radioactive"] = true, ["rock_static_trip_secret"] = true,
	["rock_static_trip_secret2"] = true, ["rock_static_wet"] = true, ["rock_vault"] = true,
	["rocket_particles"] = true, ["root"] = true, ["root_growth"] = true, ["rotten_meat"] = true,
	["rotten_meat_radioactive"] = true, ["rust_static"] = true, ["salt"] = true, ["sand"] = true,
	["sand_blue"] = true, ["sand_herb"] = true, ["sand_herb_vapour"] = true, ["sand_petrify"] = true,
	["sand_static"] = true, ["sand_static_bright"] = true, ["sand_static_rainforest"] = true,
	["sand_static_rainforest_dark"] = true, ["sand_static_red"] = true, ["sand_surface"] = true,
	["sandstone"] = true, ["sandstone_surface"] = true, ["shock_powder"] = true, ["silver"] = true,
	["silver_molten"] = true, ["sima"] = true, ["skullrock"] = true, ["slime"] = true,
	["slime_green"] = true, ["slime_static"] = true, ["slime_yellow"] = true, ["slush"] = true,
	["smoke"] = true, ["smoke_explosion"] = true, ["smoke_magic"] = true, ["smoke_static"] = true,
	["snow"] = true, ["snow_b2"] = true, ["snow_static"] = true, ["snow_sticky"] = true,
	["snowrock_static"] = true, ["sodium"] = true, ["sodium_unstable"] = true, ["soil"] = true,
	["soil_dark"] = true, ["soil_dead"] = true, ["soil_lush"] = true, ["soil_lush_dark"] = true,
	["spark"] = true, ["spark_blue"] = true, ["spark_blue_dark"] = true, ["spark_electric"] = true,
	["spark_green"] = true, ["spark_green_bright"] = true, ["spark_player"] = true,
	["spark_purple"] = true, ["spark_purple_bright"] = true, ["spark_red"] = true,
	["spark_red_bright"] = true, ["spark_teal"] = true, ["spark_white"] = true,
	["spark_white_bright"] = true, ["spark_yellow"] = true, ["spore"] = true,
	["spore_pod_stalk"] = true, ["static_magic_material"] = true, ["steam"] = true,
	["steam_trailer"] = true, ["steel"] = true, ["steel_grey_static"] = true, ["steel_molten"] = true,
	["steel_rust"] = true, ["steel_rust_molten"] = true, ["steel_rusted_no_holes"] = true,
	["steel_sand"] = true, ["steel_static"] = true, ["steel_static_molten"] = true,
	["steel_static_strong"] = true, ["steel_static_unmeltable"] = true, ["steelfrost_static"] = true,
	["steelmoss_slanted"] = true, ["steelmoss_slanted_molten"] = true, ["steelmoss_static"] = true,
	["steelmoss_static_molten"] = true, ["steelpipe_static"] = true, ["steelsmoke_static"] = true,
	["steelsmoke_static_molten"] = true, ["sulphur"] = true, ["sulphur_box2d"] = true,
	["swamp"] = true, ["templebrick_box2d"] = true, ["templebrick_box2d_edgetiles"] = true,
	["templebrick_diamond_static"] = true, ["templebrick_golden_static"] = true,
	["templebrick_moss_static"] = true, ["templebrick_noedge_static"] = true,
	["templebrick_red"] = true, ["templebrick_static"] = true, ["templebrick_static_broken"] = true,
	["templebrick_static_ruined"] = true, ["templebrick_static_soft"] = true,
	["templebrick_thick_static"] = true, ["templebrick_thick_static_noedge"] = true,
	["templebrickdark_static"] = true, ["templerock_soft"] = true, ["templerock_static"] = true,
	["templeslab_crumbling_static"] = true, ["templeslab_static"] = true, ["the_end"] = true,
	["tnt"] = true, ["tnt_static"] = true, ["trailer_text"] = true, ["tube_physics"] = true,
	["tubematerial"] = true, ["urine"] = true, ["vine"] = true, ["void_liquid"] = true,
	["vomit"] = true, ["water"] = true, ["water_fading"] = true, ["water_ice"] = true,
	["water_salt"] = true, ["water_static"] = true, ["water_swamp"] = true, ["water_temp"] = true,
	["waterrock"] = true, ["wax"] = true, ["wax_b2"] = true, ["wax_molten"] = true,
	["wizardstone"] = true, ["wood"] = true, ["wood_burns_forever"] = true, ["wood_loose"] = true,
	["wood_player"] = true, ["wood_player_b2"] = true, ["wood_player_b2_vertical"] = true,
	["wood_prop"] = true, ["wood_prop_durable"] = true, ["wood_prop_noplayerhit"] = true,
	["wood_static"] = true, ["wood_static_gas"] = true, ["wood_static_vertical"] = true,
	["wood_static_wet"] = true, ["wood_trailer"] = true, ["wood_tree"] = true, ["wood_wall"] = true,
	-- END GENERATED MATERIALS
}

function M.is_known_material( material )
	return type( material ) == "string" and M.KNOWN_MATERIALS[ material ] == true
end

return M
