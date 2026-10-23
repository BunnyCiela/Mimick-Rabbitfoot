-- tests/foundation/spell_score_spec.lua
--
-- PRD section 3/4 whitelist and reward-tier conformance for the shared
-- score_spell( spell_id, context ) module (WORKER_CONTRACT.md).
--
-- These assertions test external scoring behaviour, not internals: given a card
-- ID and a context, the public function must return the PRD's units.

local spell_score = __isf_load("mods/interesting_seed_filter/files/isf/core/spell_score.lua")

local WILD_DIRECT = "wild_direct"
local WILD_WAND = "wild_wand"
local HOLY = "holy_mountain"

T.describe("score_spell: exact-ID whitelist matching")
do
	-- Every PRD whitelist member must score, and must score its documented tier.
	local function expect( id, context, points )
		local got = spell_score.score_spell( id, context )
		T.equal_int( got, points * 4, id .. " in " .. context .. " => " .. points .. " points" )
	end

	-- G10 (9 members), wild direct +10 / wild wand +2.5 / holy mountain +2 (H2)
	T.describe("G10 group")
	local g10 = {
		"TELEPORT_PROJECTILE",
		"TELEPORT_PROJECTILE_SHORT",
		"CHAINSAW",
		"LIGHT_BULLET_TRIGGER",
		"BLACK_HOLE",
		"WHITE_HOLE",
		"BLACK_HOLE_DEATH_TRIGGER",
		"MANA_REDUCE",
		"POLYMORPH_FIELD",
	}
	T.equal_int( #g10, 9, "G10 has exactly 9 members in the PRD" )
	for _, id in ipairs( g10 ) do
		expect( id, WILD_DIRECT, 10 )
		expect( id, HOLY, 2 )
		T.equal_int( spell_score.score_spell( id, WILD_WAND ), 10, id .. " wild wand => 2.5 points (10 units)" )
	end

	-- G20, wild direct +20 / holy mountain +20 / wild wand +5
	T.describe("G20 group")
	local g20 = {
		"ALPHA", "GAMMA", "TAU", "OMEGA", "MU", "PHI", "SIGMA", "ZETA",
		"ADD_TRIGGER", "ADD_TIMER", "ADD_DEATH_TRIGGER",
		"I_SHOT", "Y_SHOT", "T_SHOT", "W_SHOT", "QUAD_SHOT", "PENTA_SHOT", "HEXA_SHOT",
		"RESET",
	}
	T.equal_int( #g20, 19, "G20 has exactly 19 members in the PRD" )
	for _, id in ipairs( g20 ) do
		expect( id, WILD_DIRECT, 20 )
		expect( id, HOLY, 20 )
		expect( id, WILD_WAND, 5 )
	end

	-- G50 healing, wild direct +50 / holy mountain +50 / wild wand +12.5
	T.describe("G50 group")
	expect( "REGENERATION_FIELD", WILD_DIRECT, 50 )
	expect( "REGENERATION_FIELD", HOLY, 50 )
	T.equal_int( spell_score.score_spell( "REGENERATION_FIELD", WILD_WAND ), 50,
		"Circle of Vigour wild wand => 12.5 points (50 units)" )

	-- H2 extras: Holy Mountain only, +2. No wild reward in the PRD.
	T.describe("H2 extras")
	for _, id in ipairs( { "LUMINOUS_DRILL", "DIGGER", "HEAL_BULLET" } ) do
		expect( id, HOLY, 2 )
		T.equal_int( spell_score.score_spell( id, WILD_DIRECT ), 0,
			id .. " is Holy-Mountain-only and scores 0 as a wild direct drop" )
		T.equal_int( spell_score.score_spell( id, WILD_WAND ), 0,
			id .. " is Holy-Mountain-only and scores 0 inside a wild wand" )
	end
end

T.describe("score_spell: near-miss variants must NOT score")
do
	-- PRD section 3 explicitly excludes these; each must stay at zero.
	local excluded = {
		"BLACK_HOLE_GIGA",          -- Giga black hole is not G10
		"WHITE_HOLE_GIGA",          -- Giga white hole is not G10
		"BLACK_HOLE_BIG",           -- "Big" variant is not G10
		"OMEGA_DISC_BULLET",        -- not a Greek spell
		"BURST_3",                  -- Triplicate-ish name, not a Plicate
		"SPELLS_TO_POWER",          -- Divide-by family is not included
		"DIVIDE_2",
		"DIVIDE_3",
		"DIVIDE_4",
		"DIVIDE_10",
		"DUPLICATE",
		"LUMINOUS_DRILL_TIMER",     -- timed variant is not H2
		"DIGGER_TIMER",
		"HEAL_BULLET_TIMER",
		"TELEPORT_PROJECTILE_CLOSER",
		"TELEPORT_PROJECTILE_STATIC",
		"MANA_REDUCE_DOWN",
		"POLYMORPH_FIELD_BIG",
		"ELECTRICITY",              -- PRD: does not score
		"FREEZE_FIELD",             -- PRD: does not score
		"BOMB",
		"LIGHT_BULLET",
	}
	for _, id in ipairs( excluded ) do
		T.equal_int( spell_score.score_spell( id, WILD_DIRECT ), 0, id .. " wild direct => 0" )
		T.equal_int( spell_score.score_spell( id, HOLY ), 0, id .. " holy mountain => 0" )
		T.equal_int( spell_score.score_spell( id, WILD_WAND ), 0, id .. " wild wand => 0" )
	end

	-- Unknown / malformed ids must be inert rather than raise.
	T.equal_int( spell_score.score_spell( "NOT_A_REAL_SPELL", WILD_DIRECT ), 0, "unknown id => 0" )
	T.equal_int( spell_score.score_spell( "", WILD_DIRECT ), 0, "empty id => 0" )
	T.equal_int( spell_score.score_spell( nil, WILD_DIRECT ), 0, "nil id => 0" )
	T.equal_int( spell_score.score_spell( 12345, WILD_DIRECT ), 0, "numeric id => 0" )
end

T.describe("score_spell: context validation")
do
	local ok = pcall( function()
		return spell_score.score_spell( "CHAINSAW", "not_a_context" )
	end )
	T.check( not ok, "an unknown context raises instead of silently scoring" )
end

T.describe("score_spell: PRD section 4 representative totals")
do
	-- "Mines normal wand with two Chainsaws => wand body + spells = 6 points"
	-- (the wand body is R1, owned by worldgen; here we pin the spell part)
	T.equal_int( spell_score.score_spell( "CHAINSAW", WILD_WAND ) * 2, 20,
		"two Chainsaws inside a wild wand => 5 points (20 units)" )

	-- "Fungal Caverns normal wand with two Chainsaws => 5 points"
	T.equal_int( spell_score.score_spell( "CHAINSAW", WILD_WAND ) * 2, 20,
		"two Chainsaws in a Fungal Caverns wand => 5 points (20 units)" )

	-- "Holy Mountain wand with two Chainsaws => normal spell subtotal 4 points"
	T.equal_int( spell_score.score_spell( "CHAINSAW", HOLY ) * 2, 16,
		"two Chainsaws in a Holy Mountain wand => 4 points (16 units)" )

	-- "Chest directly drops two Chainsaws => 27 points": 2 chest + 5 card-drop
	-- bonus + 20 target cards. Only the 20 is a spell_score concern here.
	T.equal_int( spell_score.score_spell( "CHAINSAW", WILD_DIRECT ) * 2, 80,
		"two Chainsaws dropped from a chest => 20 points of card score" )
end

T.describe("score_spell: whitelist integrity")
do
	-- Group membership must be derivable and disjoint, so one card can never be
	-- counted under two tiers.
	local seen = {}
	local function claim( group, list )
		for id in pairs( list ) do
			T.check( seen[ id ] == nil, id .. " appears only once across whitelist groups" )
			seen[ id ] = group
		end
	end
	local spells = __isf_load("mods/interesting_seed_filter/files/isf/data/spells.lua")
	claim( "G10", spells.G10 )
	claim( "G20", spells.G20 )
	claim( "G50", spells.G50 )
	claim( "H2_EXTRA", spells.H2_EXTRA )

	-- Every whitelist id must exist in the real pool (otherwise the tier could
	-- never be reached and the whitelist would silently be dead data).
	for id, group in pairs( seen ) do
		T.check( spells.by_id[ id ] ~= nil, id .. " (" .. group .. ") exists in the generated spell pool" )
	end
end
