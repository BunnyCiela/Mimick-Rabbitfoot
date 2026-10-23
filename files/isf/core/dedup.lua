-- files/isf/core/dedup.lua
--
-- Central de-duplication of REAL OBJECTS across every resource path (ISF-12).
--
-- The problem this solves
-- ----------------------
-- One physical object can be reached through more than one traversal:
--
--   * a worldgen scan record for a chest inside a region;
--   * the same chest reached again through nested-scene recursion;
--   * a puzzle reward chest, which the puzzle provider links to an entrance and
--     the chests provider then scores under R2;
--   * a potion that appears both as a scan record and as a puzzle reward.
--
-- PRD section 5 requires each real object to contribute at most once, while
-- distinct objects of the same kind each count. So identity must be based on the
-- OBJECT, not on the provider, the entry id, or the traversal path.
--
-- Identity model
-- --------------
-- An object's identity is its `object_id` when the producer supplies one (the
-- providers already use a stable object id). When it does not, identity is
-- derived from the fields that describe the physical thing: region, kind, and
-- its placement. Two records that describe the same thing must produce the same
-- key; two different things must not.
--
-- Deliberately NOT deduped here:
--   * perk opportunities -- PRD R8 dedups by perk TYPE, which is a different rule
--     owned by the perks provider. Mixing them would silently drop opportunities.
--   * spell cards inside a wand -- PRD accumulates per card. Identity is the
--     deck slot, not the card id.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local M = {}

M.SCHEMA_VERSION = 1

-- Round a coordinate to a stable, comparable representation.
--
-- A placement that arrives via two paths can differ in the last float bit (one
-- path may narrow to binary32). Rounding to 1e-3 is far tighter than any real
-- distinction between two objects (the smallest PRD-relevant spacing is a scene
-- offset of many pixels) and far looser than float noise.
local function coord( value )
	if ( type( value ) ~= "number" ) then
		return tostring( value )
	end
	return string.format( "%.3f", value )
end

-- Build the identity key for one object record.
--
-- fields (all optional except kind):
--   object_id   stable producer-supplied identity; wins when present
--   kind        "chest" | "potion" | "powder_pouch" | "wand" | "natural_pool" | ...
--   biome_key   region the object physically belongs to
--   x, y        placement
--   source_id   the scan/marker that produced it
function M.object_key( fields )
	if ( type( fields ) ~= "table" ) then
		return nil, "object fields must be a table"
	end
	local object_id = fields.object_id
	if ( type( object_id ) == "string" and object_id ~= "" ) then
		return "obj:" .. object_id, nil
	end

	local kind = fields.kind
	if ( type( kind ) ~= "string" or kind == "" ) then
		return nil, "object record needs a kind to be identifiable"
	end

	-- Placement-based identity. `source_id` participates because two distinct
	-- objects can legitimately share a coordinate in different scenes.
	local parts = {
		"gen",
		tostring( fields.biome_key or fields.biome or "?" ),
		kind,
		coord( fields.x ),
		coord( fields.y ),
	}
	if ( fields.source_id ~= nil ) then
		parts[ #parts + 1 ] = tostring( fields.source_id )
	end
	return table.concat( parts, "|" ), nil
end

-- new_registry() -> registry
function M.new_registry()
	return {
		schema_version = M.SCHEMA_VERSION,
		seen = {},          -- key -> { owner, id, traversal }
		duplicates = {},    -- list of { key, first, duplicate }
		order = {},         -- keys in first-seen order (deterministic reports)
	}
end

-- claim( registry, fields, claim_info ) -> accepted, reason
--
-- claim_info: { owner = "chests" | "puzzles" | ..., id = entry id, traversal = label }
--
-- Returns true when this is the first claim on the object. On a repeat it records
-- the duplicate and returns false plus an explanation naming the first owner, so
-- a report can show WHY an award was suppressed instead of dropping it silently.
function M.claim( registry, fields, claim_info )
	if ( type( registry ) ~= "table" or registry.seen == nil ) then
		return false, "dedup registry is not initialised"
	end
	local key, err = M.object_key( fields )
	if ( key == nil ) then
		-- An unidentifiable object must not be silently admitted: that would let
		-- the same thing be counted twice under two anonymous keys.
		return false, "cannot identify object: " .. tostring( err )
	end

	local existing = registry.seen[ key ]
	if ( existing == nil ) then
		registry.seen[ key ] = {
			owner = claim_info and claim_info.owner or "?",
			id = claim_info and claim_info.id or nil,
			traversal = claim_info and claim_info.traversal or nil,
		}
		registry.order[ #registry.order + 1 ] = key
		return true, nil
	end

	registry.duplicates[ #registry.duplicates + 1 ] = {
		key = key,
		first = existing,
		duplicate = {
			owner = claim_info and claim_info.owner or "?",
			id = claim_info and claim_info.id or nil,
			traversal = claim_info and claim_info.traversal or nil,
		},
	}
	return false, string.format(
		"already counted by %s%s%s",
		tostring( existing.owner ),
		existing.id and (" entry " .. tostring( existing.id )) or "",
		existing.traversal and (" via " .. tostring( existing.traversal )) or ""
	)
end

-- has( registry, fields ) -> boolean
function M.has( registry, fields )
	if ( type( registry ) ~= "table" or registry.seen == nil ) then
		return false
	end
	local key = M.object_key( fields )
	return key ~= nil and registry.seen[ key ] ~= nil
end

function M.duplicate_count( registry )
	if ( type( registry ) ~= "table" or registry.duplicates == nil ) then
		return 0
	end
	return #registry.duplicates
end

-- A deterministic summary for the report: how many duplicates were suppressed,
-- and one line per duplicate naming both claimants.
function M.summary( registry )
	local lines = {}
	local dupes = ( type( registry ) == "table" and registry.duplicates ) or {}
	for i = 1, #dupes do
		local d = dupes[ i ]
		lines[ i ] = string.format(
			"%s: kept %s%s, suppressed %s%s",
			d.key,
			tostring( d.first.owner ),
			d.first.id and ("/" .. tostring( d.first.id )) or "",
			tostring( d.duplicate.owner ),
			d.duplicate.id and ("/" .. tostring( d.duplicate.id )) or ""
		)
	end
	return {
		unique_objects = ( type( registry ) == "table" and registry.order ) and #registry.order or 0,
		duplicates = #dupes,
		duplicate_lines = lines,
	}
end

-- Identity helper for a spell card inside a wand.
--
-- Cards accumulate per card (PRD), so the identity is the wand plus the deck
-- slot, never the card id: two Chainsaws are two awards.
function M.wand_card_key( wand_id, deck_index )
	if ( wand_id == nil or deck_index == nil ) then
		return nil, "wand card identity needs wand_id and deck_index"
	end
	return "wandcard:" .. tostring( wand_id ) .. "#" .. tostring( deck_index ), nil
end

-- Identity helper for a perk opportunity.
--
-- PRD R8 dedups by perk TYPE across the whole opportunity set, which the perks
-- provider already does. This helper exists so the aggregate can state the rule
-- explicitly rather than accidentally applying object identity to perks.
function M.perk_type_key( perk_id )
	if ( type( perk_id ) ~= "string" or perk_id == "" ) then
		return nil, "perk identity needs a perk id"
	end
	return "perktype:" .. perk_id, nil
end

return M
