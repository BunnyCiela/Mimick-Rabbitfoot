-- files/isf/items/score.lua
--
-- ISF-09 / PRD R5: the exact scoring paths.
--
-- Three rules only, each gated on (container kind, exact material, region):
--
--   R5.1  potion whose initial material is magic_liquid_unstable_teleportation,
--         in Mines or Coal Pits                                   => +2 (8 units)
--   R5.2  powder pouch whose initial material is `gold` (gold powder),
--         in Mines, Coal Pits or Fungal Caverns                    => +5 (20 units)
--   R5.3  one independently generated natural unstable teleportatium pool,
--         in Mines or Coal Pits                                   => +2 (8 units)
--
-- Explicit non-awards, all covered by tests:
--   * stable teleportatium (`magic_liquid_teleportation`) is a different liquid
--     and scores nothing under R5.1;
--   * a gold *nugget*, coin, molten gold, or a pouch of any other powder is not
--     a gold pouch;
--   * an empty potion, a jar, a chest, or any other container is not a potion or
--     powder pouch;
--   * Collapsed Mines gets neither reward (PRD R5 lists only Mines / Coal Pits
--     and Mines / Coal Pits / Fungal Caverns);
--   * a mixture or player-poured liquid is rejected upstream in record.lua.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local containers = dofile_once( "mods/interesting_seed_filter/files/isf/data/containers.lua" )
if ( type( containers ) ~= "table" ) then
	error( "items/score: files/isf/data/containers.lua did not return a table" )
end

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "items/score: files/isf/core/units.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.UNITS = {
	R5_1 = containers.RULES.R5_1.score_units, -- 8
	R5_2 = containers.RULES.R5_2.score_units, -- 20
	R5_3 = containers.RULES.R5_3.score_units, -- 8
}

-- classify( normalized_record, material ) -> nil (no award) or
--   { rule_id, category, score_units, reason, category_reason }
--
-- `material` is the container's ACTUAL initial material: either the fixed
-- material carried by the record or the predictor's output. A nil material is
-- never scored (unknown is not "some material").
function M.classify( record, material )
	if ( type( record ) ~= "table" ) then
		return nil, "record is not a table"
	end
	if ( type( material ) ~= "string" or material == "" ) then
		return nil, "no resolved material"
	end

	local rule_key = nil
	local table_for_kind = containers.REWARD_BY_KIND_AND_MATERIAL[ record.kind ]
	if ( table_for_kind ~= nil ) then
		rule_key = table_for_kind[ material ]
	end
	if ( rule_key == nil ) then
		return nil, "container/material pair has no R5 reward"
	end

	local rule = containers.RULES[ rule_key ]
	local region = record.region
	if ( type( region ) ~= "table" ) then
		return nil, "record has no resolved region"
	end
	if ( region[ rule.region_flag ] ~= true ) then
		if ( region.in_scope == true ) then
			return nil, "region " .. tostring( record.biome ) .. " is not an R5 region for "
				.. rule.rule_id
		end
		return nil, "region " .. tostring( record.biome ) .. " is outside R5 scope"
	end

	-- A negative control belongs here: the score depends only on the three
	-- fields above, so anything else in the record cannot silently add points.
	return {
		rule_id = rule.rule_id,
		category = rule.category,
		score_units = rule.score_units,
		reason = rule.reason,
		material = material,
		kind = rule.kind,
		region = record.biome,
	}
end

-- Convenience for callers that only need the units.
function M.score_units( record, material )
	local award = M.classify( record, material )
	if ( award == nil ) then
		return 0
	end
	return award.score_units
end

-- Maximum a single object can add, used only for report sizing.
M.MAX_SINGLE_OBJECT_UNITS = M.UNITS.R5_2

-- Exact display strings, for docs and tests (4 units = 1 point).
M.DISPLAY = {
	R5_1 = units.to_string( M.UNITS.R5_1 ),
	R5_2 = units.to_string( M.UNITS.R5_2 ),
	R5_3 = units.to_string( M.UNITS.R5_3 ),
}

return M
