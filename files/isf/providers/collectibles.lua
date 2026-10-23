-- files/isf/providers/collectibles.lua
--
-- ISF-09 / PRD R5 provider: unstable teleportatium potions, gold-powder pouches
-- and (unsupported) natural unstable teleportatium pools.
--
-- SCOPE / HONESTY STATEMENT
--
--   This provider knows how to *score* R5 objects exactly, and it can predict a
--   container's initial material from its seeded transform. It does NOT know how
--   to find those containers in a seed: enumerating them needs the worldgen
--   pixel-scene / wang spawn scan (ISF-02), the regional chest port (ISF-05) and
--   the puzzle ports (ISF-06/07).
--
--   Therefore:
--     * without options.records the report is `unsupported` for every category
--       and says why - it never reports "no teleport potions in this seed";
--     * with options.records the report scores exactly the supplied records,
--       and every category is claimed `partial`, because per-seed discovery is
--       still missing. A partial report can never pass as a complete filter
--       result (PRD section 5);
--     * natural-pool coverage is `unsupported` with a concrete, sourced reason;
--       a pool record from an unverified source is an error, not a zero score.
--
-- The provider never mutates its inputs, never touches game globals, and uses
-- one PRNG instance per evaluation (the shared files/isf/random/prng.lua).
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process.

local containers = dofile_once( "mods/interesting_seed_filter/files/isf/data/containers.lua" )
if ( type( containers ) ~= "table" ) then
	error( "collectibles: files/isf/data/containers.lua did not return a table" )
end

local record_lib = dofile_once( "mods/interesting_seed_filter/files/isf/items/record.lua" )
local content = dofile_once( "mods/interesting_seed_filter/files/isf/items/content.lua" )
local score = dofile_once( "mods/interesting_seed_filter/files/isf/items/score.lua" )
local report_lib = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.PROVIDER_ID = "collectibles"

M.CATEGORY_TELEPORT = containers.RULES.R5_1.category
M.CATEGORY_GOLD = containers.RULES.R5_2.category
M.CATEGORY_POOLS = containers.RULES.R5_3.category

M.CATEGORIES = { M.CATEGORY_TELEPORT, M.CATEGORY_GOLD, M.CATEGORY_POOLS }

-- The aggregate evaluator (files/isf/core/evaluate.lua, foundation-owned) has a
-- single placeholder category for all of R5. This provider deliberately reports
-- the three rules separately so a per-rule gap stays visible; `rollup` gives the
-- aggregate the one status it needs, without this module editing shared files.
M.AGGREGATE_CATEGORY = "wild.liquids_and_pouches"

-- Report diagnostics this provider can emit. Kept as data so a caller (and the
-- tests) can enumerate them instead of pattern-matching message text.
M.ERRORS = {
	bad_seed = "seed is not an integer in [0, 2^32-1]",
	bad_profile = "profile is not a normalized snapshot table",
	bad_records = "options.records is not an array",
	bad_enumeration = "options.enumeration is not absent/supplied/complete",
	rng_unavailable = "the shared PRNG module could not be loaded",
	rng_bad_instance = "the shared PRNG instance does not expose the contract",
	rng_factory_failed = "the PRNG factory raised for this seed",
	discovery_unimplemented = "no container records were supplied, so nothing was examined",
	unresolved_records = "at least one record could not be resolved to an initial material",
	invalid_records = "at least one record failed the object-record contract",
}

M.WARNINGS = {
	invalid_record = "one record failed the contract (details attached)",
	duplicate_object = "another record already scored the same real object",
	unresolved_content = "a record's initial material could not be determined",
	calendar_assumed = "engine-only calendar flags were not supplied for a potion",
	out_of_scope = "a record's region is outside R5, so it earns nothing",
	natural_pool_unverified = "a natural-pool source is not verified, so it is not scored",
	calendar_incomplete = "the calendar input is missing fields",
}

local DEFAULT_OPTIONS = {
	records = nil,
	enumeration = nil, -- "absent" | "supplied" | "complete" (documented below)
}

local function merge_options( options )
	local resolved = {}
	for k, v in pairs( DEFAULT_OPTIONS ) do
		resolved[ k ] = v
	end
	if ( type( options ) == "table" ) then
		for k, v in pairs( options ) do
			resolved[ k ] = v
		end
	end
	return resolved
end

local function is_integer_seed( seed )
	return type( seed ) == "number" and seed == math.floor( seed )
		and seed >= 0 and seed <= 4294967295
end

-- Entry ids are the record ids (already validated unique by record.validate and
-- by the seen_ids check). The report layer additionally rejects duplicate ids, so
-- a double traversal cannot be counted twice unnoticed.

--------------------------------------------------------------------------------
-- Per-record resolution
--------------------------------------------------------------------------------

-- Resolve the initial material of one normalized record.
--   * a record that already carries a material (chest/puzzle fixed content) is
--     taken as-is and is NEVER rerolled;
--   * otherwise the exact content generator is run at the recorded transform;
--   * an unsupported generator yields nil + a reason, which the caller turns
--     into a coverage statement / error, never into a zero.
local function resolve_material( rng, rec, calendar )
	if ( rec.material ~= nil ) then
		return rec.material, {
			source = "recorded",
			note = "fixed content supplied by the caller; not regenerated",
		}
	end
	if ( rec.init_seed_frame == "unresolved" or rec.coordinate_frame == "entity_load_point" ) then
		return nil, {source="unresolved", reason="container load point is known but init transform is unverified"}
	end
	if ( rec.kind == "natural_pool" ) then
		return nil, { source = "pool", reason = "natural pool material is set by the pool record" }
	end
	local problem = content.check_rng_instance( rng )
	if ( problem ~= nil ) then
		return nil, { source = "error", reason = problem }
	end
	local material, details = content.predict( rng, rec.kind, rec.generator, rec.x, rec.y, calendar )
	if ( material == nil ) then
		return nil, { source = "unresolved", reason = details }
	end
	if details.calendar_complete == false then
		return nil, {source="unresolved", reason="potion calendar flags are unknown; candidate material is not a determined result"}
	end
	details.source = "predicted"
	return material, details
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

-- evaluate( seed, profile, options ) -> report table (WORKER_CONTRACT schema)
--
-- options.records     : array of object records (files/isf/items/record.lua)
-- options.calendar    : explicit calendar input. Defaults to the profile's
--                       calendar snapshot; missing engine-only fields make the
--                       normal-potion result assume jussi=false, mammi=false and
--                       are reported as an unresolved condition.
-- options.enumeration : "absent" (default) | "supplied" | "complete".
--                       "complete" additionally asserts that the supplied
--                       records are the full per-seed enumeration; it still
--                       cannot make the report complete while natural-pool
--                       coverage is unsupported.
-- options.rng_module / rng_factory / rng_path : shared PRNG selection.
function M.evaluate( seed, profile, options )
	local resolved = merge_options( options )

	local report = report_lib.new( {
		seed = seed,
		profile_id = ( type( profile ) == "table" and profile.id ) or "invalid",
		profile_identity = ( type( profile ) == "table" and profile_lib.identity( profile ) ) or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, baseline with no perks picked",
			"R5.1 unstable teleportatium potions: Mines, Coal Pits (+2 each)",
			"R5.2 gold-powder pouches: Mines, Coal Pits, Fungal Caverns (+5 each)",
			"R5.3 natural unstable teleportatium pools: UNSUPPORTED in this build",
			"per-seed container discovery is not implemented; supplied records are scored, "
				.. "and every category stays partial",
		},
		meta = {
			provider = M.PROVIDER_ID,
			provider_version = M.RULE_VERSION,
			schema_version = M.SCHEMA_VERSION,
			data = {
				game_version_hash = containers.GAME_VERSION_HASH,
				materials_source = containers.MATERIALS_SOURCE,
				seed_frame = containers.SEED_FRAME,
			},
			generation_inputs = containers.generation_inputs(),
			baseline = containers.BASELINE,
			options = {
				enumeration = resolved.enumeration or "absent",
				records_supplied = type( resolved.records ) == "table" and #resolved.records or 0,
			},
		},
	} )

	-- ---- input validation ---------------------------------------------------
	local input_ok = true
	if ( not is_integer_seed( seed ) ) then
		report:error( "bad_seed",
			"seed must be an integer in [0, 2^32-1]; got " .. tostring( seed ) )
		input_ok = false
	end
	if ( type( profile ) ~= "table" ) then
		report:error( "bad_profile",
			"profile must be a normalized profile table (see files/isf/adapters/profile.lua)" )
		input_ok = false
	end
	if ( resolved.records ~= nil and type( resolved.records ) ~= "table" ) then
		report:error( "bad_records", "options.records must be an array of object records" )
		input_ok = false
	end
	local enumeration = resolved.enumeration or "absent"
	if ( enumeration ~= "absent" and enumeration ~= "supplied" and enumeration ~= "complete" ) then
		report:error( "bad_enumeration",
			"options.enumeration must be absent / supplied / complete; got " .. tostring( enumeration ) )
		input_ok = false
	end

	if ( not input_ok ) then
		for _, category in ipairs( M.CATEGORIES ) do
			report:claim( category, report_lib.COVERAGE_UNSUPPORTED, "invalid input" )
		end
		local failed = report:finish()
		failed.details = {
			summary = {
				records_supplied = 0, records_valid = 0, records_invalid = 0,
				records_scored = 0, teleport_potions = 0, gold_pouches = 0,
				natural_pools = 0, recorded_materials = 0, predicted_materials = 0,
				out_of_scope = 0, unresolved = 0, deduplicated = 0,
			},
			discovery = { implemented = false, capability = "absent", missing = {} },
			natural_pools = containers.NATURAL_POOL_SUPPORT,
			calendar = { input = nil, problem = "invalid input" },
			aggregate = {
				category = M.AGGREGATE_CATEGORY,
				status = report_lib.COVERAGE_UNSUPPORTED,
				reason = "invalid input",
			},
		}
		return failed
	end

	-- ---- explicit, immutable generation inputs ------------------------------
	local calendar = resolved.calendar or profile.calendar or {}
	local calendar_view, calendar_problem = content.normalize_calendar( calendar )
	if ( calendar_problem ~= nil ) then
		-- Only an actual unresolved condition is surfaced; a fully pinned
		-- calendar produces no warning at all.
		report:warning( "calendar_incomplete", calendar_problem )
	end

	local factory, rng_err = content.resolve_rng_factory( resolved )
	local rng = nil
	if ( factory ~= nil ) then
		local ok, instance = pcall( factory, seed )
		if ( ok ) then
			local problem = content.check_rng_instance( instance )
			if ( problem == nil ) then
				rng = instance
			else
				report:error( "rng_bad_instance", problem )
			end
		else
			report:error( "rng_factory_failed", tostring( instance ) )
		end
	else
		report:error( "rng_unavailable", rng_err )
	end

	-- ---- discovery capability ----------------------------------------------
	local records = resolved.records
	if ( records == nil ) then
		report:error( "discovery_unimplemented",
			"no container records were supplied: per-seed container discovery needs the "
				.. "worldgen pixel-scene/wang spawn scan (ISF-02), the regional chest port "
				.. "(ISF-05) and the puzzle ports (ISF-06/07). No object was examined, so "
				.. "this is NOT a report that the seed contains none." )
		report:claim( M.CATEGORY_TELEPORT, report_lib.COVERAGE_UNSUPPORTED,
			"container discovery not implemented; supply options.records" )
		report:claim( M.CATEGORY_GOLD, report_lib.COVERAGE_UNSUPPORTED,
			"container discovery not implemented; supply options.records" )
		report:claim( M.CATEGORY_POOLS, report_lib.COVERAGE_UNSUPPORTED,
			containers.NATURAL_POOL_SUPPORT.reason )
		local undiscovered = report:finish()
		undiscovered.details = {
			summary = {
				records_supplied = 0, records_valid = 0, records_invalid = 0,
				records_scored = 0, teleport_potions = 0, gold_pouches = 0,
				natural_pools = 0, recorded_materials = 0, predicted_materials = 0,
				out_of_scope = 0, unresolved = 0, deduplicated = 0,
			},
			discovery = {
				implemented = false,
				capability = "absent",
				missing = {
					"worldgen pixel-scene / wang container spawn scan (ISF-02)",
					"regional chest enumeration and chest reward port (ISF-05)",
					"puzzle entrance + reward enumeration (ISF-06/07)",
				},
			},
			natural_pools = containers.NATURAL_POOL_SUPPORT,
			calendar = { input = calendar_view, problem = calendar_problem },
			aggregate = {
				category = M.AGGREGATE_CATEGORY,
				status = report_lib.COVERAGE_UNSUPPORTED,
				reason = "container discovery is not implemented, so R5 is unknown for this seed",
			},
		}
		return undiscovered
	end

	-- ---- record validation --------------------------------------------------
	local normalized = {}
	local seen_ids = {}
	local seen_objects = {}
	local invalid = 0

	for index = 1, #records do
		local raw = records[ index ]
		local rec, errors = record_lib.validate( raw )
		if ( rec == nil ) then
			invalid = invalid + 1
			local label = type( raw ) == "table" and tostring( raw.id ) or tostring( index )
			for _, err in ipairs( errors ) do
				report:warning( "invalid_record", label .. ": " .. err.code .. " (" .. err.message .. ")" )
			end
		else
			if ( seen_ids[ rec.id ] ) then
				invalid = invalid + 1
				report:warning( "invalid_record", rec.id .. ": duplicate_id" )
			else
				seen_ids[ rec.id ] = true
				normalized[ #normalized + 1 ] = rec
			end
		end
	end

	-- ---- scoring ------------------------------------------------------------
	local counts = {
		teleport_potions = 0,
		gold_pouches = 0,
		pools = 0,
		recorded_materials = 0,
		predicted_materials = 0,
		out_of_scope = 0,
		unresolved = 0,
		deduplicated = 0,
	}
	local unresolved_reasons = {}
	-- Prefer an observed fixed material to an unresolved traversal of the same
	-- object. Traversal order must not turn known contents into an unknown zero.
	local best = {}
	local function rank(rec)
		if rec.material ~= nil then return 3 end
		if rec.init_seed_frame == "unresolved" or rec.coordinate_frame == "entity_load_point" then return 0 end
		return 1
	end
	for _, rec in ipairs(normalized) do
		local key=record_lib.identity(rec)
		if best[key] == nil or rank(rec) > rank(best[key]) then best[key] = rec end
	end

	for index = 1, #normalized do
		local rec = normalized[ index ]
		local identity = record_lib.identity( rec )

		if ( seen_objects[ identity ] or best[identity] ~= rec ) then
			-- Same real object seen again through another traversal view: the
			-- first award already covers it, and PRD section 5 forbids counting
			-- "the container, the scene and the entity" separately.
			counts.deduplicated = counts.deduplicated + 1
			report:warning( "duplicate_object",
				string.format( "record %s resolves to %s, already scored; not counted again",
					tostring( rec.id ), identity ) )
		else
			seen_objects[ identity ] = rec.id

			if ( rec.kind == "natural_pool" ) then
				local verified = containers.NATURAL_POOL_SUPPORT.verified_sources[ rec.source_kind ]
				if ( containers.NATURAL_POOL_SUPPORT.status ~= "supported" or verified == nil ) then
					counts.unresolved = counts.unresolved + 1
					unresolved_reasons[ #unresolved_reasons + 1 ] = rec.id
					report:warning( "natural_pool_unverified",
						string.format( "record %s: natural pool source '%s' is not a verified "
							.. "per-seed generator; not scored (pools stay unsupported)",
							tostring( rec.id ), tostring( rec.source_kind ) ) )
				else
					local material = rec.material
					local award = score.classify( rec, material )
					if ( award ~= nil ) then
						report:add( {
							id = rec.id,
							rule_id = award.rule_id,
							category = award.category,
							biome = rec.biome,
							source_id = rec.source_id or rec.id,
							x = rec.x,
							y = rec.y,
							score_units = award.score_units,
							reason = award.reason,
							kind = rec.kind,
							material = material,
							source_kind = rec.source_kind,
							visit = rec.visit,
							object_id = rec.object_id,
						} )
						counts.pools = counts.pools + 1
					end
				end
			else
				local material, details = resolve_material( rng, rec, calendar )
				if ( material == nil ) then
					counts.unresolved = counts.unresolved + 1
					unresolved_reasons[ #unresolved_reasons + 1 ] = rec.id
					report:warning( "unresolved_content",
						string.format( "record %s (%s at %s, %s): %s",
							tostring( rec.id ), tostring( rec.kind ),
							units.to_string( rec.x or 0 ), tostring( rec.y ),
							tostring( details and details.reason or "no material") ) )
				else
					if ( details.source == "recorded" ) then
						counts.recorded_materials = counts.recorded_materials + 1
					elseif ( details.source == "predicted" ) then
						counts.predicted_materials = counts.predicted_materials + 1
						if ( details.calendar_complete == false ) then
							report:warning( "calendar_assumed",
								string.format( "record %s: engine-only calendar flags were not "
									.. "supplied; assumed jussi=false, mammi=false", tostring( rec.id ) ) )
						end
					end

					local award, why = score.classify( rec, material )
					if ( award == nil ) then
						-- No award. Out-of-scope regions and non-reward materials
						-- are legitimate zeros; they must not be silently folded
						-- into "unresolved", and they must not add points.
						if ( rec.region and rec.region.in_scope == false ) then
							counts.out_of_scope = counts.out_of_scope + 1
							report:warning( "out_of_scope",
								string.format( "record %s in %s earns nothing: %s",
									tostring( rec.id ), tostring( rec.biome ), tostring( why ) ) )
						end
					else
						report:add( {
							id = rec.id,
							rule_id = award.rule_id,
							category = award.category,
							biome = rec.biome,
							source_id = rec.source_id or rec.id,
							x = rec.x,
							y = rec.y,
							score_units = award.score_units,
							reason = award.reason,
							kind = rec.kind,
							material = material,
							generator = rec.generator,
							entity_file = rec.entity_file,
							visit = rec.visit,
							entrance_biome = rec.entrance_biome,
							material_source = details.source,
							object_id = rec.object_id,
							amount = rec.amount,
							filled = rec.filled,
						} )
						if ( award.rule_id == "R5.1" ) then
							counts.teleport_potions = counts.teleport_potions + 1
						elseif ( award.rule_id == "R5.2" ) then
							counts.gold_pouches = counts.gold_pouches + 1
						end
					end
				end
			end
		end
	end

	-- ---- coverage -----------------------------------------------------------
	--
	-- With supplied records the provider scored every record it was given, but
	-- it cannot claim the enumeration is the seed's full set unless the caller
	-- says so AND nothing failed. Natural-pool coverage is independent of that
	-- and is unsupported in this build, so the overall report stays partial:
	-- `claim(UNSUPPORTED)` clears coverage.complete by design.
	local pool_supported = containers.NATURAL_POOL_SUPPORT.status == "supported"
	local enumeration_complete = ( enumeration == "complete" )
	local partial_reason = "per-seed container discovery is not implemented (ISF-02/05/06/07); "
		.. "only supplied records were examined"

	if ( enumeration_complete and invalid == 0 and #unresolved_reasons == 0 ) then
		report:claim( M.CATEGORY_TELEPORT, report_lib.COVERAGE_COMPLETE,
			"every supplied record resolved and the caller declared the enumeration complete" )
		report:claim( M.CATEGORY_GOLD, report_lib.COVERAGE_COMPLETE,
			"every supplied record resolved and the caller declared the enumeration complete" )
	else
		report:claim( M.CATEGORY_TELEPORT, report_lib.COVERAGE_PARTIAL, partial_reason )
		report:claim( M.CATEGORY_GOLD, report_lib.COVERAGE_PARTIAL, partial_reason )
	end
	if ( pool_supported ) then
		report:claim( M.CATEGORY_POOLS, report_lib.COVERAGE_PARTIAL,
			"pool sources verified but per-seed discovery still depends on worldgen" )
	else
		report:claim( M.CATEGORY_POOLS, report_lib.COVERAGE_UNSUPPORTED,
			containers.NATURAL_POOL_SUPPORT.reason )
	end

	if ( #unresolved_reasons > 0 ) then
		report:error( "unresolved_records",
			string.format( "%d record(s) could not be resolved to a material: %s",
				#unresolved_reasons, table.concat( unresolved_reasons, ", " ) ) )
	end
	if ( invalid > 0 ) then
		report:error( "invalid_records",
			string.format( "%d record(s) failed the object contract", invalid ) )
	end

	local finished = report:finish()

	-- Post-scoring detail payload: never influences the total.
	finished.details = {
		summary = {
			records_supplied = #records,
			records_valid = #normalized,
			records_invalid = invalid,
			records_scored = #finished.entries,
			teleport_potions = counts.teleport_potions,
			gold_pouches = counts.gold_pouches,
			natural_pools = counts.pools,
			recorded_materials = counts.recorded_materials,
			predicted_materials = counts.predicted_materials,
			out_of_scope = counts.out_of_scope,
			unresolved = counts.unresolved,
			deduplicated = counts.deduplicated,
		},
		discovery = {
			implemented = false,
			capability = enumeration,
			missing = {
				"worldgen pixel-scene / wang container spawn scan (ISF-02)",
				"regional chest enumeration and chest reward port (ISF-05)",
				"puzzle entrance + reward enumeration (ISF-06/07)",
			},
		},
		natural_pools = containers.NATURAL_POOL_SUPPORT,
		calendar = {
			input = calendar_view,
			problem = calendar_problem,
		},
	}
	local rolled, roll_reason = M.rollup( finished )
	finished.details.aggregate = {
		category = M.AGGREGATE_CATEGORY,
		status = rolled,
		reason = roll_reason,
	}

	return finished
end

--------------------------------------------------------------------------------
-- Pure helpers exposed for tests and for callers that already hold content
--------------------------------------------------------------------------------

-- Predict a container's initial material without building a report.
--   kind      "potion" | "powder_pouch"
--   generator "potion" | "potion_secret" | "powder_stash"
--   x, y      exact entity transform
function M.predict_material( seed, kind, generator, x, y, calendar, rng_module )
	local factory, err = content.resolve_rng_factory( rng_module or {} )
	if ( factory == nil ) then
		return nil, err
	end
	local instance = factory( seed )
	local problem = content.check_rng_instance( instance )
	if ( problem ~= nil ) then
		return nil, problem
	end
	local cal = content.normalize_calendar( calendar or {} )
	return content.predict( instance, kind, generator, x, y, cal )
end

-- Roll the three R5 categories up into the aggregate evaluator's single
-- placeholder category (`wild.liquids_and_pouches`), without touching the
-- foundation-owned aggregator. Returns the status a caller should claim and the
-- reason it must carry:
--
--   * any category unsupported            -> "unsupported" + that reason
--   * any category partial                -> "partial" + the first reason
--   * all complete                        -> "complete"
--
-- The natural-pool category is unsupported in this build, so this function
-- currently always returns "unsupported": that is the correct aggregate for a
-- rule whose pool half is unknown, and it keeps a partial R5 score from ever
-- looking complete.
function M.rollup( report, options )
	if ( type( report ) ~= "table" or type( report.coverage ) ~= "table" ) then
		return report_lib.COVERAGE_UNSUPPORTED, "no coverage information"
	end
	local categories = report.coverage.categories or {}
	local statuses = {}
	local reason = nil
	for _, name in ipairs( M.CATEGORIES ) do
		local info = categories[ name ]
		local status = info and info.status or report_lib.COVERAGE_UNSUPPORTED
		if options and options.exclude_natural_pools and name==M.CATEGORY_POOLS then
			status=report_lib.COVERAGE_COMPLETE -- explicitly outside this scoring scope
		end
		statuses[ #statuses + 1 ] = status
		if ( reason == nil and status ~= report_lib.COVERAGE_COMPLETE ) then
			reason = ( name .. ": " .. tostring( info and info.reason or "no claim" ) )
		end
	end
	for i = 1, #statuses do
		if ( statuses[ i ] == report_lib.COVERAGE_UNSUPPORTED ) then
			return report_lib.COVERAGE_UNSUPPORTED, reason
		end
	end
	for i = 1, #statuses do
		if ( statuses[ i ] == report_lib.COVERAGE_PARTIAL ) then
			return report_lib.COVERAGE_PARTIAL, reason
		end
	end
	return report_lib.COVERAGE_COMPLETE, "every R5 sub-rule resolved"
end

M.CONTAINERS = containers

return M
