-- files/isf/core/units.lua
--
-- score_units convention (WORKER_CONTRACT.md): 4 units = 1 point. Every reward
-- is accumulated as an exact integer number of units so that the 1/4 wild-wand
-- discount (2.5 points = 10 units) never introduces rounding error.
--
-- Lua 5.1 / LuaJIT compatible; no external dependencies.

local M = {}

M.UNITS_PER_POINT = 4
-- Final rule2 settlement uses binary fixed precision within quarter units.
-- Providers still produce integer base units. A tick is 1/4194304 point.
M.DECAY_PRECISION = 1048576
function M.is_score_units(n)
  if type(n)~="number" or n~=n or n<0 or n==math.huge then return false end
  local ticks=n*M.DECAY_PRECISION
  return ticks<=9007199254740991 and ticks==math.floor(ticks)
end

-- Points -> exact integer units. Any value that is not a whole number of
-- quarter-points is a programming error, not data to be rounded away.
function M.points( points )
	local units = points * M.UNITS_PER_POINT
	local rounded = math.floor( units + 0.5 )
	if ( math.abs( units - rounded ) > 1e-9 ) then
		error( "score is not a whole number of quarter-points: " .. tostring( points ) )
	end
	return rounded
end

-- Quarter units map exactly onto .00/.25/.50/.75. The half case is rendered as
-- ".5" (not ".50") to match how the PRD writes 2.5 / 5.5 / 12.5.
local QUARTERS = { [ 0 ] = "", [ 1 ] = ".25", [ 2 ] = ".5", [ 3 ] = ".75" }

-- Units -> exact decimal string, e.g. 22 -> "5.5", 27 -> "6.75", 106*4 -> "106".
-- Never rounds; the caller is expected to hold exact quarter-unit values.
function M.to_string( units )
	if ( type( units ) ~= "number" ) then
		return tostring( units )
	end
	if units~=math.floor(units) then
		-- Display only; comparisons and totals retain exact binary ticks.
		local rendered=string.format("%.8f",units/M.UNITS_PER_POINT):gsub("0+$",""):gsub("%.$","")
		return rendered
	end
	local sign = ""
	if ( units < 0 ) then
		sign = "-"
		units = -units
	end
	local whole = math.floor( units / M.UNITS_PER_POINT )
	local rem = units - whole * M.UNITS_PER_POINT
	if ( rem == 0 ) then
		return sign .. tostring( whole )
	end
	return sign .. tostring( whole ) .. ( QUARTERS[ rem ] or "" )
end

function M.to_number( units )
	return units / M.UNITS_PER_POINT
end

return M
