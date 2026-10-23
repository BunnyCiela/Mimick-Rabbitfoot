-- files/isf/data/chests.lua
--
-- ISF-05 / PRD R2 data: chest entity identities, chest-source kinds, reward
-- entity classification, region gates and reward units.
--
-- EVERY constant here is transcribed from the installed game build
-- (9dbd52ced019a643169a2db02f46c77f8766c6e5, branch master), read out of
-- data.wak read-only with tools/chests/extract_chest_sources.py:
--
--   data/scripts/items/chest_random.lua        reward loop of a normal chest
--   data/scripts/items/chest_random_super.lua  reward loop of a great chest
--   data/scripts/biomes/coalmine.lua           spawn_chest (chest type lottery)
--   data/scripts/biome_scripts.lua             spawn_heart (second chest source)
--   data/entities/items/pickup/chest_random*.xml   entity ids + Lua wiring
--   data/entities/items/pickup/heart*.xml      max-HP vs heal-only pickups
--   data/scripts/gun/procedural/gun_procedural.lua wand content seeding
--
-- Cross-checked against (MIT, not truth):
--   * noita-telescope js/chest_generation.js, js/heart_generation.js —
--     Copyright (c) 2026 Lymm, pin ca0282fbb2bcb86f040a8a39c148a65bf48d1cbc
--   * noita-tools InfoProviders/ChestRandom.ts —
--     Copyright (c) 2022 Seva Maltsev <me@seva.dev>,
--     pin 0c7f27cf9b28ffcf2d8e6a5e41b3a007fe8ad21f
-- Both are MIT; both disagree with the vanilla scripts in places that are
-- documented at each constant below. The vanilla Lua wins every time.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.GAME_VERSION_HASH = "9dbd52ced019a643169a2db02f46c77f8766c6e5"

-- Where each constant came from, so a report can point at evidence.
M.SOURCES = {
	chest_random_lua = {
		path = "data/scripts/items/chest_random.lua",
		sha256 = "2e1e4d0c981270bbe57e73b35301731481aed11ea0e888fdd2c51b9cd9e97fcf",
	},
	chest_random_super_lua = {
		path = "data/scripts/items/chest_random_super.lua",
		sha256 = "e972aa89228c4817f4caac24fcdf9e6be0d863a0f348f001e5dd9bee8a9baa31",
	},
	coalmine_lua = {
		path = "data/scripts/biomes/coalmine.lua",
		sha256 = "d0a01489a17798cd638b6d1a2636962e0a528f1d86fa3f2c255cb59306d67269",
	},
	biome_scripts_lua = {
		path = "data/scripts/biome_scripts.lua",
		sha256 = "8f9eb6966da9be87303fcf8dc4d43dd34b3907f8e421b04aa09b843b95f17793",
	},
	chest_random_xml = {
		path = "data/entities/items/pickup/chest_random.xml",
		sha256 = "18865bcb0f15133cbc3d4aa0db75e446531c2a9280f1206869cf01f9e584ac6b",
	},
	chest_random_super_xml = {
		path = "data/entities/items/pickup/chest_random_super.xml",
		sha256 = "b379b63d8a5897824888bc862e8576fc78c27ddc40e12a005dc6110d5b1d52c8",
	},
}

-------------------------------------------------------------------------------
-- Chest entity kinds
-------------------------------------------------------------------------------
--
-- Only these two entity paths are R2 "real chests". `chest_mimic.xml` and
-- `chest_leggy.xml` are ENEMIES (they live under data/entities/animals/ and
-- data/entities/items/pickup/chest_leggy.xml is a pickup that turns into an
-- enemy) — PRD R2 says a mimic is not a chest. `chest_dark/light/steel` are the
-- Holy Mountain / secret-chest family; the Holy Mountain pacifist chest is
-- explicitly out of R2 scope.
M.CHEST_KINDS = {
	normal = {
		kind = "normal",
		entity = "data/entities/items/pickup/chest_random.xml",
		script = "data/scripts/items/chest_random.lua",
		label = "random chest",
	},
	super = {
		kind = "super",
		entity = "data/entities/items/pickup/chest_random_super.xml",
		script = "data/scripts/items/chest_random_super.lua",
		label = "great chest",
	},
}

M.CHEST_ENTITY_TO_KIND = {
	[ "data/entities/items/pickup/chest_random.xml" ] = "normal",
	[ "data/entities/items/pickup/chest_random_super.xml" ] = "super",
}

-- Creature / other entities that must never be scored as chests. Kept as data
-- so a discovery adapter can reject them by name instead of by a heuristic.
M.NON_CHEST_ENTITIES = {
	[ "data/entities/animals/chest_mimic.xml" ] = "chest mimic is an enemy (PRD R2)",
	[ "data/entities/items/pickup/chest_leggy.xml" ] = "leggy chest is an enemy (PRD R2)",
	[ "data/entities/items/pickup/potion_mimic.xml" ] = "potion mimic is an enemy",
	[ "data/entities/buildings/chest_dark.xml" ] = "Holy Mountain / secret chest, out of R2",
	[ "data/entities/buildings/chest_light.xml" ] = "Holy Mountain / secret chest, out of R2",
	[ "data/entities/buildings/chest_steel.xml" ] = "Holy Mountain / secret chest, out of R2",
	[ "data/entities/misc/chest_random_dummy.xml" ] = "visual dummy, has no Lua reward script",
}

-- Chest provenance.
--
-- Two things are separate here and must never be conflated:
--
--   in_r2                          -- does this KIND of chest earn R2 at all?
--   requires_entrance_authorization -- is an R3 entrance gate a precondition?
--
-- PRD R2 says "谜题生成的宝箱按 R3 的入口条件与区域归属判断" and PRD R3 says
-- "需要解谜才出现的宝箱...也按对应资源规则计分" / "奖励区域以入口归属确定". So a
-- puzzle-generated chest IS an R2 chest — the R3 provider owns the ENTRANCE, not
-- the chest score. Owning a different half of the rule is not exclusion.
--
-- `blocks_derived_scores` is the stronger statement: when it is true the chest
-- contributes NOTHING chest-derived (no base, no loose-card bonus, no card, no
-- wand, no max-HP, no R5 forwarding). Pacifist and Holy Mountain chests are
-- excluded by PRD R2 outright, so they must not leak partial credit.
M.SOURCES_BY_PROVENANCE = {
	biome_spawn = {
		label = "biome spawn_chest marker",
		in_r2 = true,
		blocks_derived_scores = false,
		note = "data/scripts/biomes/<biome>.lua spawn_chest",
	},
	heart_spawn = {
		label = "spawn_heart chest branch",
		in_r2 = true,
		blocks_derived_scores = false,
		note = "data/scripts/biome_scripts.lua spawn_heart, r in (0.3, 0.7]",
	},
	puzzle_reward = {
		label = "puzzle-generated chest",
		in_r2 = true,
		blocks_derived_scores = false,
		requires_entrance_authorization = true,
		note = "PRD R2 defers the ENTRANCE to R3 and still scores the chest; the "
			.. "entrance must be proven generated and its region gates the reward",
	},
	pacifist = {
		label = "Holy Mountain pacifist chest",
		in_r2 = false,
		blocks_derived_scores = true,
		note = "PRD R2 excludes the pacifist chest entirely",
	},
	holy_mountain = {
		label = "Holy Mountain chest",
		in_r2 = false,
		blocks_derived_scores = true,
		note = "PRD R2 has no Holy Mountain chest reward",
	},
	unknown = {
		label = "unattributed chest",
		in_r2 = false,
		blocks_derived_scores = true,
		note = "provenance not established; presence alone proves no R2 award",
	},
}

-- Entrance-authorization statuses for a puzzle_reward chest.
M.ENTRANCE_STATUS = {
	authorized = "authorized",
	missing = "missing",
	not_generated = "not_generated",
	region_mismatch = "region_mismatch",
	region_blocks_chest = "region_blocks_chest",
}

-------------------------------------------------------------------------------
-- Seed frames (THE critical detail)
-------------------------------------------------------------------------------
--
-- chest_random.lua on_open():
--     rand_x, rand_y = PositionSeedComponent.pos_x/pos_y  (if the component
--                     exists; chest_random.xml DOES have an empty one, so the
--                     values come from the component, defaulting to the
--                     transform the engine wrote into it at spawn)
--     rand_x = rand_x + 509.7
--     rand_y = rand_y + 683.1
--     SetRandomSeed(rand_x, rand_y)
--
-- chest_random_super.lua on_open() does the same WITHOUT the two offsets.
--
-- The 509.7 / 683.1 pair is also the potion/pouch content offset used by the
-- reward loop (`createPotion(x + 510, y + 683)` upstream), which is why it is
-- easy to mistake for a potion-only constant. It is not.
M.SEED_FRAME = {
	normal = { offset_x = 509.7, offset_y = 683.1, reload_on_open = true },
	super = { offset_x = 0, offset_y = 0, reload_on_open = true },
}

-- Reward items that are loaded at (rand_x, rand_y) with NO explicit position.
--
-- The PROVEN fact is the EntityLoad argument; see COORDINATE_HANDOFF.md. Whether
-- the engine makes the container's own transform equal to that argument or to
-- `argument - sprite/2` is NOT proven by the shipped Lua. `frame_x/frame_y` is
-- therefore documented as the LOAD POINT (`entity_load_point`), which is the
-- only claim this module makes.
M.CONTENT_SEEDED_AT_CHEST_FRAME = {
	[ "data/entities/items/pickup/potion.xml" ] = true,
	[ "data/entities/items/pickup/potion_secret.xml" ] = true,
	[ "data/entities/items/pickup/potion_random_material.xml" ] = true,
	[ "data/entities/items/pickup/powder_stash.xml" ] = true,
}

-- The coordinate frame this module's `frame_x/frame_y` denote.
M.FRAME_LOAD_POINT = "entity_load_point"

-- The engine boundary this module cannot settle offline.
M.INIT_SEED_STATUS = {
	unresolved = "unresolved",
	proven_load_point = "proven_load_point",
}

-------------------------------------------------------------------------------
-- Reward classification
-------------------------------------------------------------------------------
--
-- `category` drives the R2 rules; `entity` is the exact game path.
--
--   maxhp      -- a pickup that raises MAX hp
--   heal_only  -- a pickup that only refills hp (PRD R2: never max-HP)
--   card_direct-- a loose spell card (triggers the once-per-chest +5)
--   wand       -- a dropped wand (never triggers the +5)
--   none       -- scored nothing; still a real object for R5 forwarding
--
-- Only the entity paths that the two vanilla reward loops can actually produce
-- are listed. A path that is missing is treated as `unknown`, which is reported,
-- not silently scored.
M.REWARD_KIND_BY_ENTITY = {
	-- max-HP pickups (heart.lua +1, heart_better.lua +2)
	[ "data/entities/items/pickup/heart.xml" ] = "maxhp",
	[ "data/entities/items/pickup/heart_better.xml" ] = "maxhp",
	-- heal-only: heart_fullhp.lua sets hp = max_hp and never touches max_hp
	[ "data/entities/items/pickup/heart_fullhp.xml" ] = "heal_only",

	-- direct loose cards (CreateItemActionEntity, not a wand)
	Spell = "card_direct",
	[ "data/entities/items/pickup/random_card.xml" ] = "card_direct",

	-- wands
	[ "data/entities/items/wand_level_01.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_01.xml" ] = "wand",
	[ "data/entities/items/wand_level_02.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_02.xml" ] = "wand",
	[ "data/entities/items/wand_level_03.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_03.xml" ] = "wand",
	[ "data/entities/items/wand_level_04.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_04.xml" ] = "wand",
	[ "data/entities/items/wand_level_05.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_05.xml" ] = "wand",
	[ "data/entities/items/wand_level_06.xml" ] = "wand",
	[ "data/entities/items/wand_unshuffle_06.xml" ] = "wand",
	[ "data/entities/items/wand_level_10.xml" ] = "wand",

	-- everything else the loops can emit
	[ "data/entities/projectiles/bomb_small.xml" ] = "none",
	[ "data/entities/projectiles/rain_gold.xml" ] = "none",
	[ "data/entities/items/pickup/spell_refresh.xml" ] = "none",
	[ "data/entities/animals/illusions/shaman_wind.xml" ] = "none",
	[ "data/entities/animals/illusions/dark_alchemist.xml" ] = "none",
	[ "data/entities/items/pickup/safe_haven.xml" ] = "none",
	[ "data/entities/items/pickup/moon.xml" ] = "none",
	[ "data/entities/items/pickup/thunderstone.xml" ] = "none",
	[ "data/entities/items/pickup/evil_eye.xml" ] = "none",
	[ "data/entities/items/pickup/brimstone.xml" ] = "none",
	[ "data/entities/items/pickup/physics_die.xml" ] = "none",
	[ "data/entities/items/pickup/physics_greed_die.xml" ] = "none",
	[ "data/entities/items/pickup/physics_gold_orb.xml" ] = "none",
	[ "data/entities/items/pickup/physics_gold_orb_greed.xml" ] = "none",
	[ "data/entities/items/pickup/waterstone.xml" ] = "none",
	[ "data/entities/items/pickup/poopstone.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_laser.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_fireball.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_lava.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_slow.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_null.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_disc.xml" ] = "none",
	[ "data/entities/items/pickup/runestones/runestone_metal.xml" ] = "none",
	[ "data/entities/items/pickup/chest_leggy.xml" ] = "none",
	[ "data/entities/animals/chest_mimic.xml" ] = "none",
	[ "data/entities/animals/boss_centipede/sampo.xml" ] = "none",
	[ "data/entities/items/pickup/true_orb.xml" ] = "none",
	-- gold nuggets are tracked as `gold`, handled separately (never a maxHP
	-- pickup and never a card), see REWARD_KIND_BY_ENTITY below + gold entities
}

-- Gold entities the loops emit. Tracked so the loot list is complete (and so a
-- caller can tell an empty chest from one that dropped only gold), but they
-- earn nothing under R2.
M.GOLD_ENTITIES = {
	[ "data/entities/items/pickup/goldnugget.xml" ] = true,
	[ "data/entities/items/pickup/goldnugget_50.xml" ] = true,
	[ "data/entities/items/pickup/goldnugget_200.xml" ] = true,
	[ "data/entities/items/pickup/goldnugget_1000.xml" ] = true,
}

M.ENTITY_BY_REWARD_KIND = {
	maxhp = {
		[ "data/entities/items/pickup/heart.xml" ] = true,
		[ "data/entities/items/pickup/heart_better.xml" ] = true,
	},
	heal_only = {
		[ "data/entities/items/pickup/heart_fullhp.xml" ] = true,
	},
}

-------------------------------------------------------------------------------
-- Action slots with `spawn_probability == "0"`
-------------------------------------------------------------------------------
--
-- chest_random.lua make_random_card() reads:
--
--     if ( thisitem.spawn_requires_flag ~= nil ) then
--         valid = HasFlagPersistent( flag_name )
--         if ( thisitem.spawn_probability == "0" ) then valid = false end
--     else
--         valid = true
--     end
--
-- so the "0" test ONLY applies to flagged slots. The two unflagged zero-
-- probability slots (SEA_SWAMP, SUMMON_PORTAL) are therefore droppable, which
-- contradicts both upstream libraries (they treat every zero-probability slot
-- as invalid). Transcribed from data/scripts/gun/gun_actions.lua; the
-- independent extraction `tests/chests/fixtures/action_table.json` records all
-- 16, and tests/chests/data_spec.lua asserts this table matches the flagged 14.
M.CARD_PROBABILITY_ZERO = {
	SEA_SWAMP = true,        -- index 283, no flag: DROPPABLE
	OCARINA_A = true,
	OCARINA_B = true,
	OCARINA_C = true,
	OCARINA_D = true,
	OCARINA_E = true,
	OCARINA_F = true,
	OCARINA_GSHARP = true,
	OCARINA_A2 = true,
	KANTELE_A = true,
	KANTELE_D = true,
	KANTELE_DIS = true,
	KANTELE_E = true,
	KANTELE_G = true,
	SUMMON_PORTAL = true,    -- index 383, no flag: DROPPABLE
	RAINBOW_TRAIL = true,
}

-- Slots the vanilla validity rule actually rejects: flagged AND probability 0.
-- Kept explicit so a test can prove the unflagged pair stays accepted.
M.CARD_PROBABILITY_ZERO_FLAGGED = {
	OCARINA_A = true, OCARINA_B = true, OCARINA_C = true, OCARINA_D = true,
	OCARINA_E = true, OCARINA_F = true, OCARINA_GSHARP = true, OCARINA_A2 = true,
	KANTELE_A = true, KANTELE_D = true, KANTELE_DIS = true, KANTELE_E = true,
	KANTELE_G = true, RAINBOW_TRAIL = true,
}

-- Human-readable labels for report reasons.
M.REWARD_LABEL = {
	maxhp = "max-HP pickup",
	heal_only = "heal-only pickup",
	card_direct = "loose spell card",
	wand = "dropped wand",
	none = "unscored item",
	gold = "gold",
	unknown = "unclassified item",
}

-------------------------------------------------------------------------------
-- R2 reward units (4 units = 1 point; PRD R2)
-------------------------------------------------------------------------------

local UNITS_PER_POINT = 4

M.RULES = {
	R2_1 = {
		rule_id = "R2.1",
		category = "wild.chests",
		score_units = 2 * UNITS_PER_POINT,
		reason = "real chest in an R2 region (+2)",
	},
	R2_2 = {
		rule_id = "R2.2",
		category = "wild.chests",
		score_units = 5 * UNITS_PER_POINT,
		reason = "chest dropped at least one loose spell card, once per chest (+5)",
	},
	R2_3 = {
		rule_id = "R2.3",
		category = "wild.chests",
		-- Per-card value comes from the shared spell_score module
		-- (context "wild_direct"); this entry documents the rule only.
		score_units = 0,
		reason = "loose target card in a chest, full G10/G20/G50 value",
	},
	R2_4 = {
		rule_id = "R2.4",
		category = "wild.chests",
		score_units = 2 * UNITS_PER_POINT,
		reason = "max-HP pickup inside a chest (+2)",
	},
}

M.RULE_ORDER = { "R2_1", "R2_2", "R2_3", "R2_4" }

-- Regions where R2 applies at all (PRD section 2 + R2).
--
-- `puzzle_chest` is the PRD section 2 "宝箱及对应掉落" column as seen by a chest
-- whose ENTRANCE lives in this region. It is the same column as `in_scope` today
-- (the four R2 regions grant it; Snowy Depths' puzzles exist but the chest column
-- is "no"), but it is spelled separately because PRD R3 makes the reward follow
-- the entrance, and that must stay independently checkable.
M.REGIONS = {
	[ "Mines" ] = { in_scope = true, key = "coalmine", puzzle_chest = true },
	[ "Collapsed Mines" ] = { in_scope = true, key = "coalmine_alt", puzzle_chest = true },
	[ "Coal Pits" ] = { in_scope = true, key = "excavationsite", puzzle_chest = true },
	[ "Fungal Caverns" ] = { in_scope = true, key = "fungicave", puzzle_chest = true },
	[ "Snowy Depths" ] = { in_scope = false, key = "snowcave", puzzle_chest = false,
		reason = "PRD section 2 gives Snowy Depths no chest reward (its puzzles still "
			.. "score R3 existence, but no chest is derived through them)" },
	[ "Holy Mountain" ] = { in_scope = false, key = "temple_altar", puzzle_chest = false,
		reason = "PRD R2 excludes Holy Mountain chests (incl. the pacifist chest)" },
	[ "Hiisi Base" ] = { in_scope = false, key = "robobase",
		reason = "outside the R2 regions" },
	[ "Underground Jungle" ] = { in_scope = false, key = "rainforest",
		reason = "outside the R2 regions" },
	[ "The Vault" ] = { in_scope = false, key = "vault",
		reason = "outside the R2 regions" },
	[ "Temple of the Art" ] = { in_scope = false, key = "temple_of_the_art",
		reason = "outside the R2 regions" },
	[ "The Laboratory" ] = { in_scope = false, key = "laboratory",
		reason = "outside the R2 regions" },
	[ "Lake" ] = { in_scope = false, key = "lake",
		reason = "outside the R2 regions" },
}

-- Generator keys accepted as aliases, matching data/containers.lua's spelling so
-- a worldgen record can be passed through without re-spelling.
M.REGION_ALIASES = {
	coalmine = "Mines",
	mines = "Mines",
	coalmine_alt = "Collapsed Mines",
	[ "collapsed mines" ] = "Collapsed Mines",
	excavationsite = "Coal Pits",
	[ "coal pits" ] = "Coal Pits",
	fungicave = "Fungal Caverns",
	[ "fungal caverns" ] = "Fungal Caverns",
	snowcave = "Snowy Depths",
	snowy_depths = "Snowy Depths",
	temple_altar = "Holy Mountain",
	holy_mountain = "Holy Mountain",
	robobase = "Hiisi Base",
	hiisi_base = "Hiisi Base",
	rainforest = "Underground Jungle",
	underground_jungle = "Underground Jungle",
	vault = "The Vault",
	the_vault = "The Vault",
	temple_of_the_art = "Temple of the Art",
	laboratory = "The Laboratory",
	the_laboratory = "The Laboratory",
	lake = "Lake",
}

-- Resolve a region spelling -> name, info. nil + reason when unknown.
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
	return nil, "unknown region '" .. tostring( name ) .. "'"
end

function M.reward_kind( entity )
	if ( entity == nil ) then
		return "unknown"
	end
	if ( M.GOLD_ENTITIES[ entity ] ) then
		return "gold"
	end
	local kind = M.REWARD_KIND_BY_ENTITY[ entity ]
	if ( kind == nil ) then
		return "unknown"
	end
	return kind
end

-------------------------------------------------------------------------------
-- Entrance authorization for puzzle-generated chests
-------------------------------------------------------------------------------
--
-- PRD R2 + R3, jointly:
--   * a chest that only appears because a puzzle was solved follows the R3
--     ENTRANCE condition ("只有对应谜题入口实际生成时，才计入其奖励");
--   * its region for every resource gate is the ENTRANCE's region, never the
--     hidden room's own coordinates ("奖励区域以入口归属确定").
--
-- So a puzzle chest needs three facts, and a caller that omits any of them gets
-- a rejection rather than an assumed pass:
--
--   entrance_generated == true   the entrance really generated in this seed
--   entrance_biome               the entrance's region (falling back to biome)
--   entrance_biome == biome      the record must not re-label the region
--
-- Nothing here can VERIFY the entrance itself; it checks that the caller supplied
-- a coherent, affirmative authorization. Verifying entrances is the R3
-- provider's job (files/isf/puzzles/recognize.lua).
--
-- Returns status, reason. Status is one of M.ENTRANCE_STATUS.
function M.check_entrance( chest )
	local generated = chest.entrance_generated
	local entrance_biome = chest.entrance_biome

	if ( generated == nil ) then
		return M.ENTRANCE_STATUS.missing,
			"puzzle chest has no entrance_generated authorization; an unproven "
				.. "entrance must not earn R2 (PRD R3)"
	end
	if ( generated ~= true ) then
		return M.ENTRANCE_STATUS.not_generated,
			"puzzle chest entrance_generated is not true (got " .. tostring( generated )
				.. "); a fixed hidden room must not contribute when its entrance is absent"
	end

	if ( entrance_biome == nil or entrance_biome == "" ) then
		return M.ENTRANCE_STATUS.missing,
			"puzzle chest has no entrance_biome; PRD R3 requires the entrance region "
				.. "to control the reward's resource gates"
	end

	local entrance_region = M.region( entrance_biome )
	if ( entrance_region == nil ) then
		return M.ENTRANCE_STATUS.region_mismatch,
			"puzzle chest entrance_biome '" .. tostring( entrance_biome )
				.. "' is not a documented region"
	end

	local biome_region = M.region( chest.biome )
	if ( biome_region ~= nil and biome_region ~= entrance_region ) then
		return M.ENTRANCE_STATUS.region_mismatch,
			string.format( "puzzle chest biome '%s' disagrees with entrance_biome '%s'; "
				.. "a reward room's physical location must not re-label the entrance region",
				tostring( chest.biome ), tostring( entrance_biome ) )
	end

	local info = M.REGIONS[ entrance_region ]
	if ( info == nil or info.in_scope ~= true or info.puzzle_chest ~= true ) then
		return M.ENTRANCE_STATUS.region_blocks_chest,
			string.format( "entrance region %s grants no R2 chest resource for a puzzle "
				.. "reward (PRD section 2 column)", tostring( entrance_region ) )
	end

	return M.ENTRANCE_STATUS.authorized,
		string.format( "entrance in %s is declared generated; reward inherits that region",
			entrance_region )
end

-------------------------------------------------------------------------------
-- Generation inputs
-------------------------------------------------------------------------------
--
-- Stated explicitly so a caller cannot assume more (or less) dependence:
--   * chest TYPE   : depends on the seed + the marker position only.
--   * chest CONTENT: depends on the seed + the seed frame, plus the
--     unlocked_flags / persistent_flags that gate spell-card slots
--     (`spawn_requires_flag` -> HasFlagPersistent) and the spell pool.
--   * perks        : the greed curse changes the super-chest rate (2000 -> 100)
--     and swaps die/orb entities. The PRD baseline is "no perks picked", so the
--     baseline path is used and the curse is explicitly unsupported.
--   * calendar     : NO effect on chest contents. potion.lua inside a chest
--     still applies its date rules, and those are handled by the collectibles
--     provider when the potion record is forwarded; the chest predictor passes
--     the calendar through untouched.
M.BASELINE = {
	perks_picked = false,
	greed_curse = false,
	super_chest_rate = 2000,
	content_depends_on_seed = true,
	content_depends_on_flags = true,
	content_depends_on_calendar = false,
	content_depends_on_perks = false,
}

function M.generation_inputs()
	return {
		chest_type = "seed + marker position",
		chest_content = "seed + seed frame (509.7/683.1 for normal chests)",
		unlocked_flags = "spell-card slots gated by spawn_requires_flag",
		persistent_flags = "same as unlocked_flags (HasFlagPersistent)",
		perks = "no-perk baseline; the greed curse is not modelled",
		calendar = "no effect on chest loot; forwarded to potion records",
	}
end

return M
