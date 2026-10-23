-- Vanilla perk pool data and PRD R8 scoring targets.
--
-- GENERATED FILE - do not edit by hand.
--   source : Noita data/scripts/perks/perk_list.lua (game version hash 9dbd52ce...)
--   tool   : tools/perks/extract_perk_list.py -> tools/perks/gen_perk_data.py
--
-- Only fields that affect perk deck ordering are retained, plus `id` for scoring.
-- Fields absent in perk_list.lua are omitted (nil), matching native behaviour where
-- the absence vs. false distinction matters.
--
-- Scoring model: R8 of .scratch/interesting-seed-filter/PRD.md.
-- score_units convention: 4 units = 1 point, so all values here are integers.
--
-- Upstream reference for the deck/refresh algorithm this data feeds:
--   noita-tools (MIT, Copyright (c) 2022 Seva Maltsev),
--     upstream pin 0c7f27cf9b28ffcf2d8e6a5e41b3a007fe8ad21f
--   noita-telescope (MIT, Copyright (c) 2026 Lymm)
-- see files/isf/providers/perks.lua for the ported code and attribution.
-- Agreement with those upstreams is oracle parity, NOT game validation.

local M = {}

-- 4 score units = 1 displayed point (WORKER_CONTRACT.md score_units convention).
M.UNITS_PER_POINT = 4

-- Ordered exactly as in perk_list.lua: deck ordering depends on it.
M.perk_list = {
	{ id = "CRITICAL_HIT", stackable = true },
	{ id = "BREATH_UNDERWATER", stackable = true, stackable_is_rare = true },
	{ id = "EXTRA_MONEY", stackable = true },
	{ id = "EXTRA_MONEY_TRICK_KILL", stackable = true },
	{ id = "GOLD_IS_FOREVER", stackable = false },
	{ id = "TRICK_BLOOD_MONEY", stackable = false },
	{ id = "EXPLODING_GOLD", stackable = true, stackable_maximum = 6, stackable_is_rare = true, max_in_perk_pool = 1 },
	{ id = "HOVER_BOOST", stackable = true, max_in_perk_pool = 1 },
	{ id = "FASTER_LEVITATION", stackable = true, max_in_perk_pool = 1 },
	{ id = "MOVEMENT_FASTER", stackable = true, max_in_perk_pool = 2 },
	{ id = "STRONG_KICK", stackable = true, max_in_perk_pool = 1 },
	{ id = "TELEKINESIS", stackable = false },
	{ id = "REPELLING_CAPE", stackable = true, stackable_maximum = 8, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "EXPLODING_CORPSES", stackable = false, remove_other_perks = { "PROTECTION_EXPLOSION" } },
	{ id = "SAVING_GRACE", stackable = false },
	{ id = "INVISIBILITY", stackable = false },
	{ id = "GLOBAL_GORE", stackable = true, max_in_perk_pool = 1 },
	{ id = "REMOVE_FOG_OF_WAR", stackable = false },
	{ id = "LEVITATION_TRAIL", stackable = true, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "VAMPIRISM", stackable = false },
	{ id = "EXTRA_HP", stackable = true, max_in_perk_pool = 3 },
	{ id = "HEARTS_MORE_EXTRA_HP", stackable = true, stackable_maximum = 9, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "GLASS_CANNON", stackable = true, stackable_maximum = 2, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "LOW_HP_DAMAGE_BOOST", stackable = true, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "RESPAWN", stackable = true, stackable_is_rare = true },
	{ id = "WORM_ATTRACTOR", stackable = true, stackable_is_rare = true },
	{ id = "RADAR_ENEMY", stackable = false },
	{ id = "FOOD_CLOCK", stackable = false },
	{ id = "IRON_STOMACH", stackable = false },
	{ id = "WAND_RADAR", stackable = false },
	{ id = "ITEM_RADAR", stackable = false },
	{ id = "MOON_RADAR", stackable = false, not_in_default_perk_pool = true },
	{ id = "MAP", stackable = false, not_in_default_perk_pool = true },
	{ id = "PROTECTION_FIRE", stackable = false },
	{ id = "PROTECTION_RADIOACTIVITY", stackable = false },
	{ id = "PROTECTION_EXPLOSION", stackable = false },
	{ id = "PROTECTION_MELEE", stackable = false },
	{ id = "PROTECTION_ELECTRICITY", stackable = false },
	{ id = "TELEPORTITIS", stackable = false },
	{ id = "TELEPORTITIS_DODGE", stackable = false },
	{ id = "STAINLESS_ARMOUR", stackable = true, stackable_is_rare = true },
	{ id = "EDIT_WANDS_EVERYWHERE", stackable = false },
	{ id = "NO_WAND_EDITING", stackable = false },
	{ id = "WAND_EXPERIMENTER", stackable = true, stackable_is_rare = true },
	{ id = "ADVENTURER", stackable = false },
	{ id = "ABILITY_ACTIONS_MATERIALIZED", stackable = false },
	{ id = "PROJECTILE_HOMING", stackable = false },
	{ id = "PROJECTILE_HOMING_SHOOTER", stackable = false },
	{ id = "UNLIMITED_SPELLS", stackable = false },
	{ id = "FREEZE_FIELD", stackable = false },
	{ id = "FIRE_GAS", stackable = false },
	{ id = "DISSOLVE_POWDERS", stackable = false },
	{ id = "BLEED_SLIME", stackable = true, stackable_is_rare = true },
	{ id = "BLEED_OIL", stackable = false, remove_other_perks = { "PROTECTION_FIRE" } },
	{ id = "BLEED_GAS", stackable = false, remove_other_perks = { "PROTECTION_RADIOACTIVITY" } },
	{ id = "SHIELD", stackable = true, stackable_maximum = 5, stackable_how_often_reappears = 10, max_in_perk_pool = 2 },
	{ id = "REVENGE_EXPLOSION", stackable = true, stackable_is_rare = true },
	{ id = "REVENGE_TENTACLE", stackable = true, stackable_is_rare = true },
	{ id = "REVENGE_RATS", stackable = false },
	{ id = "REVENGE_BULLET", stackable = true, stackable_is_rare = true },
	{ id = "ATTACK_FOOT", stackable = true, stackable_maximum = 3, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "LEGGY_FEET", stackable = true, stackable_is_rare = true, not_in_default_perk_pool = true },
	{ id = "PLAGUE_RATS", stackable = true, stackable_maximum = 5, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "VOMIT_RATS", stackable = false },
	{ id = "CORDYCEPS", stackable = false },
	{ id = "MOLD", stackable = false },
	{ id = "WORM_SMALLER_HOLES", stackable = false },
	{ id = "PROJECTILE_REPULSION", stackable = true, stackable_is_rare = true },
	{ id = "RISKY_CRITICAL", stackable = true, stackable_maximum = 3, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "FUNGAL_DISEASE", stackable = true, stackable_maximum = 3, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "PROJECTILE_SLOW_FIELD", stackable = true, stackable_is_rare = true },
	{ id = "PROJECTILE_REPULSION_SECTOR", stackable = true, stackable_is_rare = true },
	{ id = "PROJECTILE_EATER_SECTOR", stackable = false },
	{ id = "ORBIT", stackable = true, stackable_how_often_reappears = 10, max_in_perk_pool = 2 },
	{ id = "ANGRY_GHOST", stackable = true },
	{ id = "HUNGRY_GHOST", stackable = true, stackable_maximum = 5, max_in_perk_pool = 2 },
	{ id = "DEATH_GHOST", stackable = true, stackable_is_rare = true },
	{ id = "HOMUNCULUS", stackable = true, stackable_maximum = 10, max_in_perk_pool = 2 },
	{ id = "LUKKI_MINION", stackable = false },
	{ id = "ELECTRICITY", stackable = false, remove_other_perks = { "PROTECTION_ELECTRICITY" } },
	{ id = "ATTRACT_ITEMS", stackable = true, stackable_maximum = 6, max_in_perk_pool = 1 },
	{ id = "EXTRA_KNOCKBACK", stackable = true, stackable_is_rare = true },
	{ id = "LOWER_SPREAD", stackable = true, stackable_is_rare = true },
	{ id = "LOW_RECOIL", stackable = false },
	{ id = "BOUNCE", stackable = false },
	{ id = "FAST_PROJECTILES", stackable = false },
	{ id = "ALWAYS_CAST", stackable = true },
	{ id = "EXTRA_MANA", stackable = true },
	{ id = "NO_MORE_SHUFFLE", stackable = false },
	{ id = "NO_MORE_KNOCKBACK", stackable = false },
	{ id = "DUPLICATE_PROJECTILE", stackable = true },
	{ id = "FASTER_WANDS", stackable = true },
	{ id = "EXTRA_SLOTS", stackable = true },
	{ id = "CONTACT_DAMAGE", stackable = false },
	{ id = "EXTRA_PERK", stackable = true, stackable_maximum = 5, max_in_perk_pool = 3 },
	{ id = "PERKS_LOTTERY", stackable = true, stackable_maximum = 6, stackable_is_rare = true, max_in_perk_pool = 3 },
	{ id = "GAMBLE", stackable = true },
	{ id = "EXTRA_SHOP_ITEM", stackable = true, stackable_maximum = 5, max_in_perk_pool = 2 },
	{ id = "GENOME_MORE_HATRED", stackable = true },
	{ id = "GENOME_MORE_LOVE", stackable = true },
	{ id = "PEACE_WITH_GODS", stackable = false },
	{ id = "MANA_FROM_KILLS", stackable = false },
	{ id = "ANGRY_LEVITATION", stackable = false },
	{ id = "LASER_AIM", stackable = true, stackable_is_rare = true },
	{ id = "PERSONAL_LASER", stackable = true, stackable_maximum = 5, stackable_is_rare = true, max_in_perk_pool = 2 },
	{ id = "MEGA_BEAM_STONE", stackable = true },
}

-- PRD R8 targets: id -> score in integer score_units (4 units = 1 point).
M.targets = {
	["REMOVE_FOG_OF_WAR"] = 20, -- All-Seeing Eye (5 points)
	["NO_MORE_SHUFFLE"] = 20, -- No More Shuffle (5 points)
	["PERKS_LOTTERY"] = 40, -- Perk Lottery (10 points)
	["PEACE_WITH_GODS"] = 12, -- Peace with Gods (3 points)
	["UNLIMITED_SPELLS"] = 20, -- Unlimited Spells (5 points)
	["EDIT_WANDS_EVERYWHERE"] = 80, -- Tinker with Wands Everywhere (20 points)
	["PROTECTION_FIRE"] = 12, -- Fire Immunity (3 points)
	["PROTECTION_RADIOACTIVITY"] = 12, -- Toxic Immunity (3 points)
	["PROTECTION_EXPLOSION"] = 12, -- Explosion Immunity (3 points)
	["PROTECTION_MELEE"] = 12, -- Melee Immunity (3 points)
	["PROTECTION_ELECTRICITY"] = 12, -- Electricity Immunity (3 points)
	["BLEED_OIL"] = 12, -- Oil Blood (3 points)
	["BLEED_GAS"] = 12, -- Gas Blood (3 points)
	["EXPLODING_CORPSES"] = 12, -- Exploding Corpses (3 points)
}

-- Display metadata for reports (name and points, never used for scoring).
M.target_meta = {
	["REMOVE_FOG_OF_WAR"] = { name = "All-Seeing Eye", points = 5 },
	["NO_MORE_SHUFFLE"] = { name = "No More Shuffle", points = 5 },
	["PERKS_LOTTERY"] = { name = "Perk Lottery", points = 10 },
	["PEACE_WITH_GODS"] = { name = "Peace with Gods", points = 3 },
	["UNLIMITED_SPELLS"] = { name = "Unlimited Spells", points = 5 },
	["EDIT_WANDS_EVERYWHERE"] = { name = "Tinker with Wands Everywhere", points = 20 },
	["PROTECTION_FIRE"] = { name = "Fire Immunity", points = 3 },
	["PROTECTION_RADIOACTIVITY"] = { name = "Toxic Immunity", points = 3 },
	["PROTECTION_EXPLOSION"] = { name = "Explosion Immunity", points = 3 },
	["PROTECTION_MELEE"] = { name = "Melee Immunity", points = 3 },
	["PROTECTION_ELECTRICITY"] = { name = "Electricity Immunity", points = 3 },
	["BLEED_OIL"] = { name = "Oil Blood", points = 3 },
	["BLEED_GAS"] = { name = "Gas Blood", points = 3 },
	["EXPLODING_CORPSES"] = { name = "Exploding Corpses", points = 3 },
}

-- Canonical order used when reporting deduplicated entries.
M.target_order = {
	"REMOVE_FOG_OF_WAR",
	"NO_MORE_SHUFFLE",
	"PERKS_LOTTERY",
	"PEACE_WITH_GODS",
	"UNLIMITED_SPELLS",
	"EDIT_WANDS_EVERYWHERE",
	"PROTECTION_FIRE",
	"PROTECTION_RADIOACTIVITY",
	"PROTECTION_EXPLOSION",
	"PROTECTION_MELEE",
	"PROTECTION_ELECTRICITY",
	"BLEED_OIL",
	"BLEED_GAS",
	"EXPLODING_CORPSES",
}

-- Maximum score obtainable when every distinct target appears once.
M.max_score_units = 288 -- 72 points


-- Perks that appear in the pool but must score 0 under R8.
M.excluded = {
	{ id = "ELECTRICITY", name = "Electricity", points = 0 },
	{ id = "FREEZE_FIELD", name = "Freeze Field", points = 0 },
}

return M
