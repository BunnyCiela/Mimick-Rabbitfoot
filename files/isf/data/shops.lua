-- files/isf/data/shops.lua
--
-- ISF-08 / PRD R4 data: which vanilla pixel scenes are REAL wild spell shops in
-- the three R4 regions, which slot positions those scenes contain, and which
-- spell level their generator uses.
--
-- EVERY constant here is transcribed from the installed game build
-- (9dbd52ced019a643169a2db02f46c77f8766c6e5, branch master), read out of
-- data.wak read-only with tools/foundation/wak_extract.py and
-- tools/shops/extract_shop_sources.py:
--
--   data/scripts/items/generate_shop_item.lua   card generator + biome levels
--   data/scripts/biomes/coalmine.lua            spawn_shopitem(..., 1)
--   data/scripts/biomes/excavationsite.lua      spawn_shopitem(..., 2)
--   data/scripts/biomes/snowcave.lua            spawn_shopitem(..., 3)
--   data/scripts/biomes/coalmine_alt.lua        spawn_shopitem(..., 1) [R4-excluded]
--   data/scripts/biomes/shop_room.lua           Holy Mountain shop [R7, not R4]
--   data/biome_impl/{coalmine,excavationsite,snowcave}/shop*.png
--                                               the scene bitmaps themselves
--
-- Cross-checked against (MIT, not truth):
--   * noita-telescope js/spawn_functions.js (BIOME_TIERS) and
--     js/spell_generator.js (generateShopItem / GetRandomAction)
--     Copyright (c) 2026 Lymm, local pinned clone
-- The vanilla scripts win wherever the two differ. In particular upstream's
-- `pixelScene.name.includes("shop")` heuristic is NOT copied: a scene is a wild
-- spell shop here only when its exact name is on the region's allowlist.
--
-- The slot layouts below are the `spawn_shopitem` marker pixels found inside each
-- scene bitmap, in scene-local pixel coordinates. The game places a pixel scene
-- at (scene_x, scene_y) and runs each marker at (scene_x + marker_x,
-- scene_y + marker_y), which is the position `generate_shop_item` seeds content
-- with. tools/shops/extract_shop_sources.py re-derives these lists from data.wak
-- and asserts they match this file, so a layout change cannot go unnoticed.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "data/shops: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.GAME_VERSION_HASH = "9dbd52ced019a643169a2db02f46c77f8766c6e5"

-- Where each constant came from, so a report can point at evidence. Hashes are
-- sha256 over the exact bytes data.wak holds.
M.SOURCES = {
	generate_shop_item_lua = {
		path = "data/scripts/items/generate_shop_item.lua",
		sha256 = "9ff53564b6a3e953a2f0bb66d34cdd5e1b004bea8556f8d315a0e8108cedb70c",
	},
	coalmine_lua = {
		path = "data/scripts/biomes/coalmine.lua",
		sha256 = "d0a01489a17798cd638b6d1a2636962e0a528f1d86fa3f2c255cb59306d67269",
	},
	excavationsite_lua = {
		path = "data/scripts/biomes/excavationsite.lua",
		sha256 = "45e8dfc6e3f5cf23ba83dc8c970dacd22538e369e563b5f1b07ee0a2381810ea",
	},
	snowcave_lua = {
		path = "data/scripts/biomes/snowcave.lua",
		sha256 = "efd7b821af7c9784430ad2e7dd011e4a52578246c7750f8251a1c8310b801b66",
	},
	coalmine_alt_lua = {
		path = "data/scripts/biomes/coalmine_alt.lua",
		sha256 = "b8775ac16adba2fd5f5ec8bd686c59a4b85d47ed80237edcf832ea7219e2a3a1",
	},
	shop_room_lua = {
		path = "data/scripts/biomes/shop_room.lua",
		sha256 = "9157580151e33da373d430e5af50c4fec6997ddf1052d2a56a8ab19c6ff1d666",
	},
	gun_actions_lua = {
		path = "data/scripts/gun/gun_actions.lua",
		sha256 = "09a034b16fbacbe330b76f47bf66a05919d8d3301c1030263851ab95b5c8c532",
	},
}

-------------------------------------------------------------------------------
-- The one spawn function that makes a wild spell shop slot
-------------------------------------------------------------------------------
--
-- coalmine.lua / excavationsite.lua / snowcave.lua all register
--   RegisterSpawnFunction( 0xff33934c, "spawn_shopitem" )
-- and their bodies call generate_shop_item(x, y, false, <biome level>).
-- `spawn_cheap_shopitem` and `spawn_workshop*` exist only in the Holy Mountain
-- shop_room.lua, and are R7 territory; they are deliberately absent here.
M.SHOP_SPAWN_FUNCTION = "spawn_shopitem"
M.SHOP_MARKER_COLOR = 0x33934c

-------------------------------------------------------------------------------
-- The three R4 regions
-------------------------------------------------------------------------------
--
-- `level` is the `biomeid_` argument each biome passes to generate_shop_item,
-- which becomes the GetRandomAction tier. It is NOT the squared price tier
-- (`biomeid * biomeid`), which only affects the displayed cost.
--
-- `scenes` is the exact allowlist of scene names that are wild spell shops in
-- that biome. coalmine_alt (Collapsed Mines) really does contain shop_alt
-- upstream, but PRD section 2 gives Collapsed Mines no wild shop scope, so it is
-- listed under EXCLUDED_REGIONS and never scores.
M.REGIONS = {
	Mines = {
		biome = "Mines",
		biome_key = "coalmine",
		level = 1,
		-- coalmine.lua's g_pixel_scene_02 lists ONLY "shop" (material_file
		-- data/biome_impl/coalmine/shop.png). coalmine/shop_alt.png exists in the
		-- data.wak but is referenced by coalmine_alt.lua (Collapsed Mines), not by
		-- coalmine.lua, so it is NOT a Mines scene.
		scenes = {
			shop = {
				scene_width = 260,
				scene_height = 130,
				slots = { { 84, 93 }, { 108, 93 }, { 132, 93 }, { 156, 93 }, { 180, 93 } },
			},
		},
	},
	["Coal Pits"] = {
		biome = "Coal Pits",
		biome_key = "excavationsite",
		level = 2,
		scenes = {
			shop = {
				scene_width = 400,
				scene_height = 200,
				slots = { { 168, 107 }, { 192, 107 }, { 216, 107 }, { 240, 107 }, { 264, 107 } },
			},
			shop_alt = {
				scene_width = 400,
				scene_height = 200,
				slots = { { 168, 107 }, { 192, 107 }, { 216, 107 }, { 240, 107 }, { 264, 107 } },
			},
		},
	},
	["Snowy Depths"] = {
		biome = "Snowy Depths",
		biome_key = "snowcave",
		level = 3,
		scenes = {
			shop = {
				scene_width = 520,
				scene_height = 260,
				slots = { { 313, 115 }, { 337, 115 }, { 361, 115 }, { 385, 115 }, { 409, 115 } },
			},
		},
	},
}

-- Deterministic iteration order for reports and for the provider's region loop.
M.REGION_ORDER = { "Mines", "Coal Pits", "Snowy Depths" }

M.KEY_BY_DISPLAY = {
	Mines = "coalmine",
	["Coal Pits"] = "excavationsite",
	["Snowy Depths"] = "snowcave",
}

M.DISPLAY_BY_KEY = {
	coalmine = "Mines",
	excavationsite = "Coal Pits",
	snowcave = "Snowy Depths",
}

-- Regions that DO have a vanilla shop mechanism but are outside PRD R4. They are
-- reported as explicit exclusions, never silently dropped and never scored.
M.EXCLUDED_REGIONS = {
	["Collapsed Mines"] = {
		biome_key = "coalmine_alt",
		reason = "PRD section 2 gives Collapsed Mines no wild spell shop scope, "
			.. "although data/scripts/biomes/coalmine_alt.lua does register "
			.. "spawn_shopitem and its g_pixel_scene_02 list contains shop_alt",
	},
	["Fungal Caverns"] = {
		biome_key = "fungicave",
		reason = "data/scripts/biomes/fungicave.lua registers no spawn_shopitem and "
			.. "has no shop scene, and PRD section 2 gives Fungal Caverns no shop scope",
	},
	["Holy Mountain"] = {
		biome_key = "temple",
		reason = "the Holy Mountain shop is data/scripts/biomes/shop_room.lua and is "
			.. "scored by PRD R7 (holy mountain provider), never by R4",
	},
}

-------------------------------------------------------------------------------
-- R4 reward units
-------------------------------------------------------------------------------
--
-- PRD R4: each shop SCENE +5 (once, regardless of slot count), and each target
-- card sold at its full G10/G20/G50 wild-direct value. The per-card value is
-- NEVER computed here: it comes from files/isf/core/spell_score.lua with
-- context "wild_direct" (G10 10 units, G20 20 units, G50 50 units).
M.RULES = {
	R4_1 = {
		rule_id = "R4.1",
		category = "wild.spell_shops",
		score_units = units.points( 5 ),
		reason = "real wild spell shop scene in an R4 region (+5, once per scene)",
	},
	R4_2 = {
		rule_id = "R4.2",
		category = "wild.spell_shops",
		-- Per-card units come from the shared spell scorer; this entry only
		-- documents the rule so a reader does not look for a table here.
		score_units = 0,
		reason = "target card sold in the shop, full G10/G20/G50 wild-direct value",
	},
}

-------------------------------------------------------------------------------
-- Report categories
-------------------------------------------------------------------------------
--
-- Three SEPARATE claims, because they answer three different questions:
--   discovery       -- was the region enumerated from seed+profile at all?
--   shop_existence  -- was every candidate shop scene/probe resolved into a real
--                      shop scene or a conclusive non-shop?
--   shop_contents   -- was every slot's card determined?
-- The aggregate evaluator only sees `wild.spell_shops`; M.rollup() combines the
-- three for it without editing the foundation-owned aggregator.
M.CATEGORIES = {
	DISCOVERY = "wild.spell_shops.discovery",
	EXISTENCE = "wild.spell_shops.shop_existence",
	CONTENTS = "wild.spell_shops.shop_contents",
	AGGREGATE = "wild.spell_shops",
}

-- Resolve a region by display name, generator key or lower-case alias.
function M.region( value )
	if ( type( value ) ~= "string" or value == "" ) then
		return nil
	end
	local by_name = M.REGIONS[ value ]
	if ( by_name ~= nil ) then
		return by_name, value
	end
	local display = M.DISPLAY_BY_KEY[ value ]
	if ( display ~= nil ) then
		return M.REGIONS[ display ], display
	end
	local lower = string.lower( value )
	for _, name in ipairs( M.REGION_ORDER ) do
		if ( string.lower( name ) == lower ) then
			return M.REGIONS[ name ], name
		end
	end
	return nil
end

-- Is this (region, scene name) pair a real wild spell shop?
function M.is_wild_shop_scene( region, scene_name )
	if ( region == nil or type( scene_name ) ~= "string" ) then
		return false
	end
	return region.scenes[ scene_name ] ~= nil
end

-- The exact slot layout of one shop scene, or nil.
function M.scene_layout( region, scene_name )
	if ( not M.is_wild_shop_scene( region, scene_name ) ) then
		return nil
	end
	return region.scenes[ scene_name ]
end

-- Offset string used in identities and reasons, so "84,93" is unambiguous.
function M.offset_key( dx, dy )
	return string.format( "%d,%d", dx, dy )
end

-- Human-readable description of a region's scope, used in coverage reasons.
function M.region_scope_note( region_name )
	local region = M.region( region_name )
	if ( region == nil ) then
		return "region is not an R4 wild spell shop region"
	end
	local names = {}
	for name in pairs( region.scenes ) do
		names[ #names + 1 ] = name
	end
	table.sort( names )
	return string.format( "%s (biome %s, card level %d, scenes %s)",
		region.biome, region.biome_key, region.level, table.concat( names, "/" ) )
end

return M
