-- files/isf/core/adapters.lua
--
-- Translate neutral worldgen discovery records into each provider's documented
-- input shapes (ISF-12).
--
-- Why a translation layer at all
-- ------------------------------
-- `files/isf/worldgen/discover.lua` emits *neutral* placement records. Each
-- provider was written against its own contract:
--
--   wild_wands   -> options.assets (does its own discovery), or options.placement
--   chests       -> options.scan (a discovery region), or options.chests
--   puzzles      -> options.entrances (records with scene_name/spawn_function)
--   collectibles -> options.records (the items/record.lua object contract)
--
-- Rather than edit those modules (they are other workflows' files), this module
-- performs the translation, and it is the ONLY place where the mapping between a
-- neutral record and a provider input is written down.
--
-- Everything here is a pure function of the region records. No discovery, no
-- scoring, no PRNG, no I/O.
--
-- Where the mapping is NOT source-justified, the record is passed through with
-- the uncertainty attached rather than being silently coerced. The clearest case
-- is the R5 container seed frame: `containers.SEED_FRAME` is "entity_transform",
-- but a discovery record carries the world *load point*. Those differ by half the
-- sprite (chests/COORDINATE_HANDOFF.md). So the collectible record keeps the load
-- point, states which frame it is, and carries the alternative transform as an
-- explicit candidate. The provider then scores it exactly as it scores any other
-- record, and the report says the frame is unproven.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local discovery_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/discovery.lua" )
if ( type( discovery_mod ) ~= "table" ) then
	error( "adapters: files/isf/core/discovery.lua did not return a table" )
end
local containers = dofile_once( "mods/interesting_seed_filter/files/isf/data/containers.lua" )
if ( type( containers ) ~= "table" ) then
	error( "adapters: files/isf/data/containers.lua did not return a table" )
end
local dedup_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/dedup.lua" )
if ( type( dedup_mod ) ~= "table" ) then
	error( "adapters: files/isf/core/dedup.lua did not return a table" )
end

-- Local alias so the claim call reads as a verb, not a module lookup.
local dedup_claim = dedup_mod.claim

local M = {}

M.SCHEMA_VERSION = 1

-- Regions where R5 scores a container. Mirrors containers.REGIONS; a region
-- outside R5 keeps the record but scores 0 with an explicit out-of-scope reason.
local function r5_region_in_scope( biome_name )
	local region = containers.REGIONS[ biome_name ]
	return region ~= nil and region.in_scope == true
end

-- R5 container records (PRD R5: potions and gold pouches in Mines / Coal Pits /
-- Fungal Caverns).
--
-- WORLDGEN CONTRACT (2026-10-22 arbitration, DISCOVERY_CONTRACT.md section 7):
-- the scan already resolves the SOURCE and the proven LOAD POINT for containers.
-- A `potion` record carries `outcome`, `container_kind`, `entity_file`,
-- `load_x/load_y`, `coordinate_frame = "entity_load_point"`,
-- `init_seed_frame = "unresolved"` and `container_owner = "collectibles"`.
--
-- So this adapter must NOT re-derive any of that. It maps the record onto the
-- collectibles object-record contract and preserves the provenance verbatim:
--   * `outcome == "container"` with a known `container_kind` is an object;
--   * every other outcome (`other`, `potion_mimic`, `flag_blocked`, `unresolved`,
--     `no_band`, or a missing outcome) is NOT silently dropped -- each is counted
--     under its own cause so the report can distinguish "no container here" from
--     "this build could not tell".
--
-- The scan supplies the load point. For the two exact standard entity paths,
-- native evidence now proves the transform conversion used below. Unknown
-- shapes keep the candidate labelled and remain unresolved.
M.R5_SPAWN_KINDS = {
	potion = true,
}

-- Container kinds this build can score, keyed by the scan's `container_kind`.
M.R5_CONTAINER_KINDS = {
	potion = { kind = "potion", generator = "potion",
		entity_file = "data/entities/items/pickup/potion.xml" },
	powder_pouch = { kind = "powder_pouch", generator = "powder_stash",
		entity_file = "data/entities/items/pickup/powder_stash.xml" },
}

-- Classify one scan record for R5.
-- Returns kind, generator, reason, cause where cause names the drop-out reason.
function M.container_candidate( rec )
	if ( type( rec ) ~= "table" ) then
		return nil, nil, "not a record", "invalid"
	end
	local spawn_kind = rec.spawn_kind
	if ( not M.R5_SPAWN_KINDS[ spawn_kind ] ) then
		return nil, nil, "spawn kind '" .. tostring( spawn_kind ) .. "' is not an R5 container source",
			"not_container_source"
	end

	-- The worldgen contract resolves the dispatch outcome. Trust it verbatim.
	local outcome = rec.outcome
	if ( outcome == "container" ) then
		local ck = rec.container_kind
		local info = M.R5_CONTAINER_KINDS[ ck ]
		if ( info == nil ) then
			return nil, nil, "container kind '" .. tostring( ck )
				.. "' is not an R5 container this build scores", "unsupported_container_kind"
		end
		if ( rec.not_a_container == true ) then
			return nil, nil, "record is explicitly not an R5 container", "not_a_container"
		end
		return info.kind, info.generator, nil, nil
	end

	-- Every non-container outcome is a DISTINCT, source-specific cause. Unknown is
	-- never reported as "absent": `unresolved` in particular means this build could
	-- not decide, which must stay visible.
	if ( outcome == "other" ) then
		return nil, nil, "the list band rolled a non-R5 object", "other_object"
	elseif ( outcome == "potion_mimic" ) then
		return nil, nil, "the band rolled a potion mimic, not a container", "mimic"
	elseif ( outcome == "flag_blocked" ) then
		return nil, nil, "a persistent flag blocked the band, so nothing was loaded", "flag_blocked"
	elseif ( outcome == "no_band" ) then
		return nil, nil, "the list roll landed outside every band", "no_band"
	elseif ( outcome == "unresolved" ) then
		return nil, nil, "the dispatch could not be resolved by this build", "unresolved"
	end
	return nil, nil, "outcome '" .. tostring( outcome ) .. "' is unknown to this adapter", "unknown_outcome"
end

-- Convert one scan container record to an items/record.lua record.
--
-- Provenance is preserved verbatim from the scan:
--   x/y                 = the proven EntityLoad argument
--   coordinate_frame    = "entity_load_point"
--   init_seed_frame     = "unresolved"   (NEVER "load_point")
--   init_seed_candidate = containers.seed_position_from_load(), a labelled hypothesis
--
-- Exact native-proven standard shapes are promoted below; variants stay unknown.
local function container_record( rec, index, biome_name, kind, generator )
	local x = rec.load_x
	local y = rec.load_y
	if ( type( x ) ~= "number" or type( y ) ~= "number" ) then
		return nil, "record " .. tostring( index ) .. " has no proven load point"
	end
	local object_id = rec.object_id or rec.source_id
	if ( type( object_id ) ~= "string" or object_id == "" ) then
		return nil, "record " .. tostring( index ) .. " has no stable identity"
	end

	local candidate_x, candidate_y = containers.seed_position_from_load( kind, x, y )
	local init_x,init_y,init_proof = containers.native_init_position(kind,rec.entity_file,x,y)

	local out = {
		id = object_id,
		object_id = object_id,
		kind = kind,
		biome = biome_name,
		x = x,
		y = y,
		generator = generator or "potion",
		visit = "entity_scan",
		spawned_during = "initial_generation",
		source_id = rec.source_id,
		source_kind = rec.spawn_kind,
		entity_file = rec.entity_file,
		coordinate_frame = rec.coordinate_frame or "entity_load_point",
		init_seed_frame = "unresolved",
		coordinate_confidence = rec.coordinate_confidence
			or "load_point_proven_init_seed_unresolved",
		entrance_object_id = rec.entrance_object_id,
		entrance_source_id = rec.entrance_source_id,
	}
	if init_proof then
		out.load_x,out.load_y=x,y
		out.x,out.y=init_x,init_y
		out.coordinate_frame="init_entity_transform"
		out.init_seed_frame="entity_transform"
		out.coordinate_confidence=init_proof
	end
	if ( candidate_x ~= nil ) then
		out.init_seed_candidate_x = candidate_x
		out.init_seed_candidate_y = candidate_y
		out.init_seed_candidate_source =
			"containers.seed_position_from_load (hypothesis, not engine-confirmed)"
	end
	return out
end

-- Collect R5 candidate records from one region.
--
-- Returns records, info. Every non-container outcome is counted under its own
-- cause, so the report can say WHY nothing scored instead of assuming absence.
function M.collectible_records( region )
	local out = {}
	local info = {
		examined = 0,
		converted = 0,
		dropped = {},
		missing_position = 0,
		missing_identity = 0,
		region_in_scope = nil,
	}
	local function drop( cause )
		info.dropped[ cause ] = ( info.dropped[ cause ] or 0 ) + 1
	end

	if ( type( region ) ~= "table" ) then
		info.reason = "no region"
		return out, info
	end
	local biome_name = region.biome_name or discovery_mod.NAME_BY_KEY[ region.biome_key ]
	info.biome_name = biome_name
	info.region_in_scope = r5_region_in_scope( biome_name )

	for i = 1, #( region.records or {} ) do
		local rec = region.records[ i ]
		info.examined = info.examined + 1
		if ( type( rec ) == "table" and M.R5_SPAWN_KINDS[ rec.spawn_kind ] ) then
			local kind, generator, why, cause = M.container_candidate( rec )
			if ( kind == nil ) then
				drop( cause or "unknown_outcome" )
			else
				local record, err = container_record( rec, i, biome_name, kind, generator )
				if ( record ~= nil ) then
					out[ #out + 1 ] = record
					info.converted = info.converted + 1
				elseif ( err:find( "load point", 1, true ) ) then
					info.missing_position = info.missing_position + 1
					drop( "missing_load_point" )
				else
					info.missing_identity = info.missing_identity + 1
					drop( "missing_identity" )
				end
			end
		end
	end
	return out, info
end

-- Collect R5 records across every discovered region, de-duplicating by real
-- object identity through the shared registry.
--
-- `registry` is a dedup registry (dedup.new_registry()), NOT the dedup module:
-- the claim call needs the registry's own seen/duplicates tables.
function M.collectible_records_all( results, registry, claim_owner )
	local out = {}
	local infos = {}
	local dropped_duplicates = 0
	local keys = discovery_mod.region_keys()
	for i = 1, #keys do
		local region = results[ keys[ i ] ]
		if ( region ~= nil ) then
			local records, info = M.collectible_records( region )
			infos[ keys[ i ] ] = info
			for j = 1, #records do
				local rec = records[ j ]
				if ( registry == nil ) then
					out[ #out + 1 ] = rec
				else
					local accepted, why = dedup_claim( registry, {
						object_id = rec.object_id,
						kind = rec.kind,
						biome_key = info.biome_name,
						x = rec.x,
						y = rec.y,
						source_id = rec.source_id,
					}, {
						owner = claim_owner or "collectibles",
						id = rec.id,
						traversal = "entity_scan",
					} )
					if ( accepted ) then
						out[ #out + 1 ] = rec
					else
						dropped_duplicates = dropped_duplicates + 1
						rec.dedup_reason = why
					end
				end
			end
		end
	end
	return out, infos, dropped_duplicates
end

--------------------------------------------------------------------------------
-- puzzles: entrance records
--------------------------------------------------------------------------------

-- Neutral discovery records already carry what `puzzles.recognize` expects:
-- biome, spawn_function, scene_name, world_x/world_y, scene_x/scene_y and
-- `generated`. The translation is a copy that drops nothing and adds only a
-- provenance marker.
--
-- Records where `generated` is not true are passed through unchanged: the
-- recognizer itself rejects them with a precise reason ("an opportunity is not an
-- object"), and pre-filtering them here would hide that reasoning from the report.
function M.puzzle_entrances( region )
	if ( type( region ) ~= "table" or type( region.records ) ~= "table" ) then
		return {}, { reason = "no region records", supplied = 0, verified = 0, unverified = 0 }
	end
	local out = {}
	local verified = 0
	for i = 1, #region.records do
		local rec = region.records[ i ]
		if ( type( rec ) == "table" and rec.spawn_kind ~= nil ) then
			out[ #out + 1 ] = {
				biome = rec.biome,
				biome_key = rec.biome,
				spawn_function = rec.spawn_function,
				spawn_kind = rec.spawn_kind,
				scene_name = rec.scene_name,
				scene_x = rec.scene_x,
				scene_y = rec.scene_y,
				world_x = rec.world_x,
				world_y = rec.world_y,
				marker_offset_x = rec.marker_offset_x,
				marker_offset_y = rec.marker_offset_y,
				generated = rec.generated,
				source_id = rec.source_id,
				object_id = rec.object_id,
			}
			if ( rec.generated == true ) then
				verified = verified + 1
			end
		end
	end
	return out, {
		supplied = #out,
		verified = verified,
		unverified = #out - verified,
	}
end

-- Concatenate entrance records from several regions, in report order.
function M.puzzle_entrances_all( results )
	local out = {}
	local stats = { supplied = 0, verified = 0, unverified = 0, regions = 0 }
	local keys = discovery_mod.region_keys()
	for i = 1, #keys do
		local region = results[ keys[ i ] ]
		if ( region ~= nil ) then
			local records, info = M.puzzle_entrances( region )
			stats.regions = stats.regions + 1
			for j = 1, #records do
				out[ #out + 1 ] = records[ j ]
			end
			stats.supplied = stats.supplied + ( info.supplied or 0 )
			stats.verified = stats.verified + ( info.verified or 0 )
			stats.unverified = stats.unverified + ( info.unverified or 0 )
		end
	end
	return out, stats
end

--------------------------------------------------------------------------------
-- chests: discovery regions
--------------------------------------------------------------------------------

-- The chests provider consumes a discovery region directly (options.scan). This
-- wrapper exists so the aggregate passes ONE region object per region and so the
-- mapping is documented in one place.
--
-- `scan_complete` is deliberately NOT set true by the aggregate: exhaustiveness of
-- the scan set is a worldgen claim, and the chests provider caps it anyway when
-- the pipeline has known source omissions.
function M.chest_scan( region )
	if ( type( region ) ~= "table" or type( region.records ) ~= "table" ) then
		return nil, "no discovery region"
	end
	return region, nil
end

-- R2 applies only to Mines / Collapsed Mines / Coal Pits / Fungal Caverns.
M.CHEST_REGION_KEYS = {
	coalmine = true,
	coalmine_alt = true,
	excavationsite = true,
	fungicave = true,
}

M.CHEST_BIOME_NAMES = {
	coalmine = "Mines",
	coalmine_alt = "Collapsed Mines",
	excavationsite = "Coal Pits",
	fungicave = "Fungal Caverns",
}

--------------------------------------------------------------------------------
-- wild wands: discovery regions
--------------------------------------------------------------------------------

-- R1 body/inner-spell scope. Snowy Depths is discovery-capable but outside R1, so
-- the aggregate must not ask the wild-wand provider about it.
M.WAND_REGION_KEYS = {
	coalmine = true,
	coalmine_alt = true,
	excavationsite = true,
	fungicave = true,
}

M.WAND_BIOME_NAMES = {
	coalmine = "Mines",
	coalmine_alt = "Collapsed Mines",
	excavationsite = "Coal Pits",
	fungicave = "Fungal Caverns",
}

--------------------------------------------------------------------------------
-- wild spell shops: R4 region scope
--------------------------------------------------------------------------------

-- PRD section 2: wild spell shops exist only in Mines, Coal Pits and Snowy
-- Depths. Collapsed Mines, Fungal Caverns and Holy Mountain are explicitly
-- excluded, so the aggregate must not even ask the provider about them (asking
-- would invite a "0 shops" reading for a region that cannot have any).
M.SHOP_REGION_NAMES = {
	coalmine = "Mines",
	excavationsite = "Coal Pits",
	snowcave = "Snowy Depths",
}

--------------------------------------------------------------------------------
-- puzzle rewards → owning providers
--------------------------------------------------------------------------------

-- Split puzzle reward records into the owning providers' input shapes.
--
-- The puzzles provider emits linked reward records and does NOT score R1/R2/R5.
-- The aggregate must route them (PRD R3: "rewards are scored under the applicable
-- rules"), so this function partitions them:
--
--   chest      -> the chests provider needs a *chest* object; a puzzle reward that
--                 is a chest carries entrance authorization and is handled by the
--                 chests owner's own contract. We only forward the ones the owner
--                 can authorize (see chest_reward_inputs).
--   potion /
--   powder_pouch -> items/record.lua records (collectibles).
--   wand       -> NOT routed: a fixed wand reward needs R1 generation at a proven
--                 position, and the reward record's frame is the reward room's.
--                 Reported as `unrouted` with the reason, never silently dropped.
--
-- Returns { collectibles = {...}, chests = {...}, unrouted = {...}, stats = {...} }
function M.route_puzzle_rewards( reward_records, biome_name_by_key )
	local out = {
		collectibles = {},
		chests = {},
		wands = {},
		excluded = {},
		unrouted = {},
		stats = {
			examined = 0,
			collectibles = 0,
			chests = 0,
			unrouted = 0,
		},
	}
	for i = 1, #( reward_records or {} ) do
		local rec = reward_records[ i ]
		out.stats.examined = out.stats.examined + 1

		if rec.content_status == "empty" then
			out.excluded[#out.excluded+1]={id=rec.id,reason="empty flask is outside R5"}
		elseif rec.region_scope_allowed == false then
			out.excluded[#out.excluded+1]={id=rec.id,reason="entrance region excludes this resource"}
		elseif ( rec.resolved ~= true ) then
			-- An unresolved reward keeps its identity and reason. It is not routed
			-- to a scorer, because scoring an unresolved object would fabricate a
			-- material/position.
			out.unrouted[ #out.unrouted + 1 ] = {
				id = rec.id,
				kind = rec.kind,
				reason = "reward is source-justified but unresolved ("
					.. tostring( rec.unresolved_reason or "no reason recorded" ) .. ")",
			}
			out.stats.unrouted = out.stats.unrouted + 1
		elseif rec.entrance_generated == false then
			out.unrouted[#out.unrouted+1] = {id=rec.id, kind=rec.kind, reason="puzzle entrance is unverified"}
			out.stats.unrouted = out.stats.unrouted + 1
		elseif ( rec.record_kind == "potion" or rec.kind == "potion"
			or rec.kind == "powder_pouch" ) then
			local view = rec.collectibles_record or rec
			out.collectibles[ #out.collectibles + 1 ] = view
			out.stats.collectibles = out.stats.collectibles + 1
		elseif ( rec.kind == "chest" or rec.resource == "chest" ) then
			out.chests[ #out.chests + 1 ] = {
				id=rec.id, object_id=rec.object_id or rec.id, kind="normal",
				entity=rec.entity, biome=rec.entrance_biome or rec.biome,
				entrance_biome=rec.entrance_biome or rec.biome,
				entrance_generated=rec.entrance_generated == true,
				puzzle_id=rec.puzzle_id, provenance="puzzle_reward",
				x=rec.x,y=rec.y,loot=rec.loot,supplied_loot=rec.loot ~= nil,
			}
			out.stats.chests = out.stats.chests + 1
		elseif rec.kind == "wand" and type(rec.wand) == "table" then
			out.wands[#out.wands+1] = rec
		else
			out.unrouted[ #out.unrouted + 1 ] = {
				id = rec.id,
				kind = rec.kind,
				reason = "no owning provider accepts this reward kind in this build "
					.. "(fixed wand / direct spell rewards need a proven reward frame)",
			}
			out.stats.unrouted = out.stats.unrouted + 1
		end
	end
	return out
end

return M
