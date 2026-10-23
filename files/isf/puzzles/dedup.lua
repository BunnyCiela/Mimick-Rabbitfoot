-- files/isf/puzzles/dedup.lua
--
-- Physical-object de-duplication across traversal paths.
--
-- PRD section 5: "同一个资源的容器、场景和实体视图不得重复贡献同一奖励". The puzzle
-- provider can reach the same object three ways:
--   1. a puzzle reward (the chest the rope puzzle creates),
--   2. a region scan of the same area (worldgen chest marker),
--   3. a second scan of the same puzzle (duplicate entrance records).
--
-- Paths 1 and 3 are handled here. Path 2 is handled by KEYING on a real object
-- identity: this module exports an identity function that any provider can use,
-- and the puzzle provider registers every reward it emits so a later region scan
-- that presents the same object cannot add a second score.
--
-- Identity is deliberately NOT the report id: two different views of one object
-- (the puzzle's own reward record and a region-scan record at the same position
-- with the same entity) must collide, while two genuinely distinct objects at
-- the same position (a chest and a wand dropped on top of it) must not.
--
-- Lua 5.1 / LuaJIT 2.0 compatible. No I/O, no RNG, no globals.

local M = {}

M.SCHEMA_VERSION = 1

-- Identity of a physical object.
--
-- object_identity( { entity=, x=, y=, kind= } ) -> string
--
-- The coordinate is quantised to whole world units: the game places content on
-- integer or half-integer positions, and float noise from a different code path
-- must not create a second identity for one object.
--
-- `kind` keeps a chest and a wand at the same coordinates apart, which matters
-- because the rope puzzle loads a chest at (x-75, y-70) and a scene marker could
-- theoretically sit there too.
function M.object_identity( entity, x, y, kind )
	local ex = "?"
	if ( type( entity ) == "string" and entity ~= "" ) then
		ex = entity
	end
	local qx = 0
	local qy = 0
	if ( type( x ) == "number" ) then
		qx = math.floor( x + ( x >= 0 and 0.5 or -0.5 ) )
	end
	if ( type( y ) == "number" ) then
		qy = math.floor( y + ( y >= 0 and 0.5 or -0.5 ) )
	end
	return string.format( "%s@%d,%d#%s", ex, qx, qy, tostring( kind or "object" ) )
end

-- A registry of already-claimed object identities, so the same physical object
-- can only be scored once across providers.
local Registry = {}
Registry.__index = Registry

function M.new_registry()
	return setmetatable( { claimed = {}, order = {} }, Registry )
end

-- claim( identity, provenance ) -> true when this caller now owns the object,
-- false when somebody already claimed it. A rejected claim carries the original
-- provenance so the reason can be reported.
function Registry:claim( identity, provenance )
	if ( type( identity ) ~= "string" or identity == "" ) then
		error( "dedup: claim needs a non-empty identity string" )
	end
	if ( self.claimed[ identity ] ~= nil ) then
		return false, self.claimed[ identity ]
	end
	self.claimed[ identity ] = provenance or true
	self.order[ #self.order + 1 ] = identity
	return true
end

function Registry:is_claimed( identity )
	return self.claimed[ identity ] ~= nil
end

function Registry:count()
	return #self.order
end

function Registry:identities()
	return self.order
end

-- ---------------------------------------------------------------------------
-- Puzzle instance de-duplication
-- ---------------------------------------------------------------------------

-- Distinct physical puzzle instances, keyed by recognize.instance_id.
--
-- Puzzle EXISTENCE is once per physical scene. A second view of the same scene
-- (a repeated scan, or the second marker of a two-marker bitmap) must not add a
-- second +2. This function returns the deduplicated list plus the count of
-- folds, and it never merges two instances with different ids.
function M.dedup_instances( instances )
	if ( type( instances ) ~= "table" ) then
		error( "dedup.dedup_instances expects an array" )
	end
	local seen = {}
	local out = {}
	local folded = 0
	for i = 1, #instances do
		local inst = instances[ i ]
		local id = inst.id
		if ( type( id ) ~= "string" or id == "" ) then
			error( "dedup: instance " .. i .. " has no stable id" )
		end
		if ( seen[ id ] == nil ) then
			seen[ id ] = true
			out[ #out + 1 ] = inst
		else
			folded = folded + 1
		end
	end
	return out, folded
end

return M
