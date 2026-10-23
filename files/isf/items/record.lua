-- files/isf/items/record.lua
--
-- ISF-09 / PRD R5: the *object record contract*.
--
-- The provider cannot yet discover containers per seed (that needs the worldgen
-- pixel-scene/chest/puzzle ports owned by ISF-02/05/06). It therefore scores
-- explicit records supplied by a caller, and refuses to invent records. This
-- module defines exactly what such a record may contain, what is mandatory, and
-- which malformed or unscoreable shapes produce which error code.
--
-- Record contract (all keys are documented, nothing else is interpreted):
--
--   id            string, REQUIRED. Stable id of this record (log/dedup key).
--   object_id     string, optional. Stable identity of the REAL object. Two
--                 records that describe the same physical object from different
--                 traversal views (e.g. an entity scan and a puzzle-reward list)
--                 must share it; the provider then counts the object once.
--                 Coordinates or material are NOT used as identity.
--   kind          "potion" | "powder_pouch" | "natural_pool", REQUIRED.
--   biome         string, REQUIRED. An R5 region name or a documented alias
--                 (files/isf/data/containers.lua REGION_ALIASES).
--   entrance_biome string, REQUIRED when visit == "puzzle_reward": PRD R3/R5
--                 attribute a puzzle reward to the puzzle entrance's region.
--                 If both are supplied they must name the same region.
--   x, y          numbers, REQUIRED. For items: the EXACT entity transform the
--                 content generator seeds with (containers.SEED_FRAME), not a
--                 spawn-table anchor. For pools: the source position.
--   material      string, optional. When present the content is treated as
--                 already fixed (chest/puzzle contents are rolled once at
--                 generation) and is NEVER re-derived or rerolled.
--   generator     string, optional. Overrides the generator implied by
--                 entity_file. Needed when kind == "potion" and no entity_file
--                 says whether it is a normal or a secret potion.
--   entity_file   string, optional but recommended. Exact game entity path; if
--                 given it must be a documented container entity and agree with
--                 `kind`.
--   amount        number, optional. Must be > 0 when present ("positive amount").
--                 Omitted means the container was created with its full initial
--                 fill, which these generators guarantee.
--   visit         "entity_scan" | "chest_reward" | "puzzle_reward" | "shop" |
--                 "other", optional (default "entity_scan").
--   source_id     string, optional provenance id (chest id, puzzle id, ...).
--   source_kind   string, REQUIRED for natural_pool. Checked against the
--                 verified-source allowlist in containers.NATURAL_POOL_SUPPORT;
--                 an unverified source is never scored.
--   spawned_during "initial_generation" (default). Anything else is rejected:
--                 PRD R5 forbids scoring liquid poured or mixed after spawning.
--   mixed         boolean, optional. true => rejected (mixture, not initial fill).
--   poured_by_player boolean, optional. true => rejected.
--   contents      array of material ids, optional. A single-element list is
--                 accepted as the material; more than one is a mixture.
--   region_scope  "out_of_scope", optional. Permits a region this build's table
--                 does not name, and makes the record explicitly scoreless
--                 instead of an unknown-region error.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local containers = dofile_once( "mods/interesting_seed_filter/files/isf/data/containers.lua" )
if ( type( containers ) ~= "table" ) then
	error( "items/record: files/isf/data/containers.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.VISITS = {
	entity_scan = true,
	chest_reward = true,
	puzzle_reward = true,
	shop = true,
	other = true,
}

-- Error codes produced by validate(). Kept as data so tests can enumerate them.
M.ERRORS = {
	record_not_table = "record is not a table",
	missing_id = "record has no stable string id",
	duplicate_id = "two records share the same id",
	bad_kind = "kind must be one of potion / powder_pouch / natural_pool",
	bad_entity_file = "entity_file is not a documented container entity",
	entity_kind_mismatch = "entity_file does not produce the declared kind",
	unsupported_container = "container kind has no R5 scoring path",
	bad_biome = "biome must be a non-empty string",
	unknown_biome = "biome is not a documented region and region_scope is unset",
	missing_entrance_biome = "puzzle_reward records must name the puzzle entrance biome",
	entrance_biome_mismatch = "entrance_biome and biome name different regions",
	bad_visit = "visit is not a documented traversal view",
	bad_coordinates = "x and y must be finite numbers",
	bad_amount = "amount must be a number",
	non_positive_amount = "amount must be positive",
	bad_material = "material must be a non-empty string",
	unknown_material = "material id is not defined by this game build",
	mixed_contents = "record describes a mixture, not a single initial fill",
	player_poured = "record describes liquid poured/mutated after generation",
	not_initial_generation = "record is not from initial generation",
	ambiguous_generator = "kind potion needs a generator or entity_file to tell normal from secret",
	unresolved_generator = "no reproducible content generator for this record",
	natural_pool_unverified = "natural pool source is not a verified generator",
	bad_source_kind = "natural_pool records must name a source_kind",
}

local function is_finite_number( v )
	return type( v ) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function fail( errors, code, detail )
	errors[ #errors + 1 ] = {
		code = code,
		message = ( M.ERRORS[ code ] or code ) .. ( detail and ( ": " .. detail ) or "" ),
	}
end

-- Resolve a region, honouring the explicit out-of-scope escape hatch.
local function resolve_region( rec, errors )
	local region, info = containers.region( rec.biome )
	if ( region == nil ) then
		if ( rec.region_scope == "out_of_scope" and type( rec.biome ) == "string" and rec.biome ~= "" ) then
			return rec.biome, { in_scope = false, reason = "caller declared region_scope = out_of_scope" }, false
		end
		fail( errors, "unknown_biome", tostring( info ) )
		return nil, nil, false
	end
	return region, info, true
end

-- validate( record ) -> normalized | nil, errors[]
--
-- A normalized record has all defaults resolved and both region spellings
-- canonicalized. It is still not scored: content resolution happens in the
-- provider because it needs the seed and the PRNG.
function M.validate( record )
	local errors = {}
	if ( type( record ) ~= "table" ) then
		fail( errors, "record_not_table" )
		return nil, errors
	end

	if ( type( record.id ) ~= "string" or record.id == "" ) then
		fail( errors, "missing_id" )
	end
	if ( record.object_id ~= nil and ( type( record.object_id ) ~= "string" or record.object_id == "" ) ) then
		fail( errors, "missing_id", "object_id must be a non-empty string when present" )
	end

	local kind_info = containers.KINDS[ record.kind ]
	if ( kind_info == nil ) then
		fail( errors, "bad_kind", tostring( record.kind ) )
	end

	if ( not is_finite_number( record.x ) or not is_finite_number( record.y ) ) then
		fail( errors, "bad_coordinates" )
	end

	local visit = record.visit or "entity_scan"
	if ( not M.VISITS[ visit ] ) then
		fail( errors, "bad_visit", tostring( visit ) )
		visit = "entity_scan"
	end

	-- Mutation guards (PRD R5: no player pouring, no mixtures).
	if ( record.poured_by_player == true ) then
		fail( errors, "player_poured" )
	end
	if ( record.mixed == true ) then
		fail( errors, "mixed_contents" )
	end
	if ( record.spawned_during ~= nil and record.spawned_during ~= "initial_generation" ) then
		fail( errors, "not_initial_generation", tostring( record.spawned_during ) )
	end

	local material = record.material
	if ( record.contents ~= nil ) then
		if ( type( record.contents ) ~= "table" ) then
			fail( errors, "mixed_contents", "contents must be a list of material ids" )
		elseif ( #record.contents > 1 ) then
			fail( errors, "mixed_contents", tostring( #record.contents ) .. " materials listed" )
		elseif ( #record.contents == 1 ) then
			if ( material ~= nil and material ~= record.contents[ 1 ] ) then
				fail( errors, "mixed_contents", "contents[1] disagrees with material" )
			end
			material = record.contents[ 1 ]
		end
	end

	if ( material ~= nil ) then
		if ( type( material ) ~= "string" or material == "" ) then
			fail( errors, "bad_material" )
			material = nil
		elseif ( not containers.is_known_material( material ) ) then
			fail( errors, "unknown_material", material )
		end
	end

	local amount = record.amount
	if ( amount ~= nil ) then
		if ( not is_finite_number( amount ) ) then
			fail( errors, "bad_amount", tostring( amount ) )
			amount = nil
		elseif ( amount <= 0 ) then
			fail( errors, "non_positive_amount", tostring( amount ) )
		end
	end

	-- Container kind / entity file / generator resolution.
	local entity = nil
	if ( record.entity_file ~= nil ) then
		entity = containers.ENTITY_FILES[ record.entity_file ]
		if ( entity == nil ) then
			fail( errors, "bad_entity_file", tostring( record.entity_file ) )
		elseif ( record.kind ~= nil and entity.kind ~= record.kind ) then
			-- A known entity whose kind differs from the declared kind is either a
			-- real-but-unscoreable container (empty flask, jar) or a caller bug
			-- (a pouch declared as a potion). Distinguish the two so the error is
			-- actionable instead of a blanket type mismatch.
			if ( entity.supported == false ) then
				fail( errors, "unsupported_container",
					string.format( "%s is a %s (%s)", record.entity_file, entity.kind,
						tostring( entity.reason or "no R5 scoring path" ) ) )
			else
				fail( errors, "entity_kind_mismatch",
					string.format( "%s is a %s, not a %s", record.entity_file, entity.kind,
						tostring( record.kind ) ) )
			end
		end
	end

	local generator = record.generator or ( entity and entity.generator ) or nil
	local supported = true
	if ( record.kind == "natural_pool" ) then
		if ( record.source_kind == nil or record.source_kind == "" ) then
			fail( errors, "bad_source_kind" )
		end
		generator = record.source_kind
		supported = ( containers.NATURAL_POOL_SUPPORT.status == "supported" )
	elseif ( entity ~= nil and entity.supported == false ) then
		supported = false
	elseif ( generator ~= nil ) then
		local info = containers.GENERATORS[ generator ]
		if ( info == nil ) then
			fail( errors, "unresolved_generator", "unknown generator '" .. tostring( generator ) .. "'" )
			generator = nil
			supported = false
		elseif ( info.supported == false ) then
			supported = false
		end
	elseif ( record.material == nil ) then
		-- No entity file, no generator, no fixed material: the kind alone cannot
		-- say whether this is a normal or a secret potion, so guessing would be
		-- exactly the silent approximation the contract forbids.
		if ( record.kind == "potion" ) then
			fail( errors, "ambiguous_generator" )
		else
			fail( errors, "unresolved_generator" )
		end
		supported = false
	end

	local biome, region_info, known_region = resolve_region( record, errors )

	local entrance_biome = nil
	if ( visit == "puzzle_reward" ) then
		if ( record.entrance_biome == nil or record.entrance_biome == "" ) then
			fail( errors, "missing_entrance_biome" )
		else
			local entrance_region = containers.region( record.entrance_biome )
			if ( entrance_region == nil and record.region_scope ~= "out_of_scope" ) then
				fail( errors, "unknown_biome", "entrance_biome " .. tostring( record.entrance_biome ) )
			elseif ( entrance_region ~= nil and known_region and biome ~= nil and entrance_region ~= biome ) then
				fail( errors, "entrance_biome_mismatch",
					string.format( "entrance_biome %s vs biome %s", entrance_region, tostring( biome ) ) )
			else
				entrance_biome = entrance_region or record.entrance_biome
			end
		end
	end

	if ( #errors > 0 ) then
		return nil, errors
	end

	return {
		id = record.id,
		object_id = record.object_id,
		kind = record.kind,
		biome = biome,
		region = region_info,
		entrance_biome = entrance_biome,
		x = record.x,
		y = record.y,
		material = material,
		generator = generator,
		entity_file = record.entity_file,
		amount = amount,
		filled = ( amount == nil ),
		visit = visit,
		source_id = record.source_id,
		source_kind = record.source_kind,
		region_scope = record.region_scope,
		container_supported = supported,
		coordinate_frame = record.coordinate_frame,
		init_seed_frame = record.init_seed_frame,
		coordinate_confidence = record.coordinate_confidence,
	}, nil
end

-- Stable identity of the real object a record describes.
-- Two views of one object must therefore share `object_id`; nothing else is
-- allowed to collapse records, because equal coordinates or equal materials do
-- not prove "same object".
function M.identity( record )
	if ( type( record.object_id ) == "string" and record.object_id ~= "" ) then
		return "object:" .. record.object_id
	end
	return "record:" .. tostring( record.id )
end

return M
