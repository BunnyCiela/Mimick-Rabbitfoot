-- files/isf/core/spell_score.lua
--
-- The single shared normal-spell scoring module (WORKER_CONTRACT.md):
-- These are BASE values. Rule2 global duplicate decay runs once in evaluate,
-- after every provider and resource deduplication; this module holds no counts.
--
--   score_spell( spell_id, context ) -> integer score_units
--
-- `context` is exactly one of:
--   "wild_direct"    -- a wild spell shop slot or a chest's direct card drop
--                       (PRD R2 / R4): G10 +10, G20 +20, G50 +50, per card.
--   "wild_wand"      -- a normal (non-Always-Cast) card inside a wild wand
--                       (PRD R1): one quarter of the wild_direct value, i.e.
--                       G10 +2.5 (10 units), G20 +5 (20 units), G50 +12.5
--                       (50 units).
--   "holy_mountain"  -- a card in the first three Holy Mountains, whether sold
--                       as an independent card or inside a sold wand (PRD R6 /
--                       R7): H2 +2, G20 +20, G50 +50, no discount.
--
-- Everything outside the PRD section 3 whitelist scores 0 units. Matching is on
-- the exact card ID; no name prefixes, suffixes or "similar" variants are ever
-- folded in (Giga/Omega black and white holes, Triplicate Bolt, Divide by
-- spells and similar must stay out).
--
-- Always Cast is a wand property, not a normal spell: callers must never route
-- an Always Cast ID through this module. `is_always_cast=false` is therefore
-- required to be explicit in higher-level call sites; see
-- providers/holy_mountains.lua.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" ) then
	error( "spell_score: files/isf/data/spells.lua did not return a table" )
end

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "spell_score: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.CONTEXT_WILD_DIRECT = "wild_direct"
M.CONTEXT_WILD_WAND = "wild_wand"
M.CONTEXT_HOLY_MOUNTAIN = "holy_mountain"

local VALID_CONTEXT = {
	[ M.CONTEXT_WILD_DIRECT ] = true,
	[ M.CONTEXT_WILD_WAND ] = true,
	[ M.CONTEXT_HOLY_MOUNTAIN ] = true,
}

-- Wild-wand cards score one quarter of the wild-direct value. Expressed in
-- units that is exactly a division by four; the constants below are precomputed
-- so no float arithmetic ever reaches the accumulator.
local WILD_DIRECT_UNITS = {
	G10 = units.points( 10 ), -- 40
	G20 = units.points( 20 ), -- 80
	G50 = units.points( 50 ), -- 200
}

local HOLY_MOUNTAIN_UNITS = {
	H2 = units.points( 2 ), -- 8
	G20 = units.points( 20 ), -- 80
	G50 = units.points( 50 ), -- 200
}

-- Return the PRD group a card belongs to, or nil when it is not a target.
-- A card can only be in one group; the whitelists are disjoint and this is
-- asserted at load time below.
function M.group_of( spell_id )
	if ( spells.G50[ spell_id ] == true ) then
		return "G50"
	end
	if ( spells.G20[ spell_id ] == true ) then
		return "G20"
	end
	if ( spells.G10[ spell_id ] == true ) then
		return "G10"
	end
	if ( spells.H2_EXTRA[ spell_id ] == true ) then
		return "H2_EXTRA"
	end
	return nil
end

-- Assert the whitelists are pairwise disjoint, so no card could be scored
-- twice through two groups.
do
	local seen = {}
	local function claim( group, list )
		for id in pairs( list ) do
			if ( seen[ id ] ~= nil ) then
				error( "spell_score: " .. id .. " appears in both " .. seen[ id ] .. " and " .. group )
			end
			seen[ id ] = group
		end
	end
	claim( "G10", spells.G10 )
	claim( "G20", spells.G20 )
	claim( "G50", spells.G50 )
	claim( "H2_EXTRA", spells.H2_EXTRA )
	-- H2 is defined as G10 plus H2_EXTRA, so H2 membership is derived, never a
	-- separate list that could drift.
end

-- Detailed classification, used by providers and by the report.
-- Returns nil when the card scores nothing in this context, otherwise
--   { group = "G10"|"G20"|"G50"|"H2_EXTRA", score_units = <int>, reason = <string> }
function M.classify( spell_id, context )
	if ( type( spell_id ) ~= "string" or spell_id == "" ) then
		return nil
	end
	if ( not VALID_CONTEXT[ context ] ) then
		error( "spell_score.classify: unknown context " .. tostring( context ) )
	end

	local group = M.group_of( spell_id )
	if ( group == nil ) then
		return nil -- not on the PRD whitelist: 0 units, by design
	end

	local score_units
	local reason

	if ( context == M.CONTEXT_HOLY_MOUNTAIN ) then
		if ( group == "H2_EXTRA" ) then
			score_units = HOLY_MOUNTAIN_UNITS.H2
			reason = "H2 normal target card sold in a Holy Mountain (+2)"
		elseif ( group == "G10" ) then
			score_units = HOLY_MOUNTAIN_UNITS.H2
			reason = "H2 normal target card sold in a Holy Mountain, G10 member (+2)"
		else
			score_units = HOLY_MOUNTAIN_UNITS[ group ]
			reason = group .. " normal target card sold in a Holy Mountain (+"
				.. units.to_string( score_units ) .. ")"
		end
	elseif ( context == M.CONTEXT_WILD_DIRECT ) then
		if ( group == "H2_EXTRA" ) then
			-- Luminous Drill / Digging Bolt / Healing Bolt are Holy Mountain
			-- only; the PRD does not award them as wild direct drops.
			return nil
		end
		score_units = WILD_DIRECT_UNITS[ group ]
		reason = group .. " normal target card, wild direct drop (+"
			.. units.to_string( score_units ) .. ")"
	else -- wild_wand
		if ( group == "H2_EXTRA" ) then
			return nil
		end
		score_units = WILD_DIRECT_UNITS[ group ] / 4 -- exact: 40/4, 80/4, 200/4
		reason = group .. " normal target card inside a wild wand (1/4 => +"
			.. units.to_string( score_units ) .. ")"
	end

	return {
		group = group,
		score_units = score_units,
		reason = reason,
	}
end

-- Public contract entry point: integer score_units, 0 for anything that is not
-- a whitelisted normal target card in this context.
function M.score_spell( spell_id, context )
	local info = M.classify( spell_id, context )
	if ( info == nil ) then
		return 0
	end
	return info.score_units
end

-- Convenience for callers that want the maximum a single card can add; used to
-- size report sections, never to score.
M.MAX_SINGLE_CARD_UNITS = WILD_DIRECT_UNITS.G50

return M
