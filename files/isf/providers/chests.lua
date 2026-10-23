-- files/isf/providers/chests.lua
--
-- ISF-05 provider: predicts Mines / Collapsed Mines / Coal Pits / Fungal Caverns
-- chest loot and scores it under PRD R2.
--
-- TWO SEPARATE COVERAGE CLAIMS, deliberately (same discipline as wild_wands):
--
--   wild.chests.discovery
--       Was the region ENUMERATED from seed + profile? `complete` only when a
--       real worldgen scan result was consumed and the chest adapter could model
--       every record in it. `unsupported` whenever chests were supplied by the
--       caller, because then nothing about the seed was discovered.
--
--   wild.chests.known_chests
--       Was every known chest scored under R2? `complete` when every chest and
--       every one of its loot items was resolved.
--
-- The overall report is only `complete` when BOTH are complete. A report built
-- from supplied chests therefore stays `partial`: it proves R2 arithmetic on
-- known objects, NOT that those objects exist in the seed, and NOT that the seed
-- has no other chests.
--
-- Interface (WORKER_CONTRACT.md):
--   evaluate( seed, profile, options ) -> {
--     schema_version = 1, rule_version = "1.0", seed, profile_id,
--     coverage, entries, errors, totals, ...
--   }
--
-- options:
--   biome            "Mines" | "Collapsed Mines" | "Coal Pits" | "Fungal Caverns"
--                    (default "Mines"); may also be a generator key.
--   ng_plus          NG+ count (default 0; only 0 is supported/in scope).
--   chests           array of chest specs (see chests/score.lua validate_chest).
--                    Each may carry `loot` (supplied) or be loot-predicted.
--   predict_loot     boolean (default true): generate loot for supplied chests
--                    that do not carry an explicit `loot` table.
--   scan             a worldgen scan result table (read-only). When present the
--                    discovery adapter derives chests from its records.
--   scan_biome       region name for `scan` (default: options.biome).
--   scan_complete    boolean (default false). Asserts that `scan.records` is the
--                    region's EXHAUSTIVE spawn record set. Only with worldgen
--                    evidence for that claim; without it the report stays
--                    partial even when every record was modelable.
--   is_flag_set      function(flag) -> boolean override (tests).
--   wand_generator   optional table { generate = fn(seed, ng, wand_type, x, y) }
--                    replacing the built-in wand_gen path (tests / fixtures).
--   r5_records       optional output array: potion/pouch records are appended so
--                    a caller can feed them to the collectibles provider.
--   calendar        { month, day } frozen date. REQUIRED for a fully resolved
--                    `spawn_heart` classification: its threshold is 0.35 on 14
--                    February, so the (0.35, 0.7] band is a heart on that date and
--                    a chest otherwise. Without it that band is reported
--                    `unresolved` rather than guessed. Defaults to the profile's
--                    calendar when omitted.
--
-- Native-game parity is unverified for every claim here. Everything is offline.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process.

local prng = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
if ( type( prng ) ~= "table" ) then
	error( "chests provider: files/isf/random/prng.lua did not return a table" )
end

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
local chest_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/chests.lua" )
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
local report_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
local loot = dofile_once( "mods/interesting_seed_filter/files/isf/chests/loot.lua" )
local chest_score = dofile_once( "mods/interesting_seed_filter/files/isf/chests/score.lua" )
local discovery = dofile_once( "mods/interesting_seed_filter/files/isf/chests/discovery.lua" )

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.PROVIDER_ID = "chests"

M.CATEGORY_DISCOVERY = "wild.chests.discovery"
M.CATEGORY_KNOWN = "wild.chests.known_chests"
M.CATEGORIES = { M.CATEGORY_DISCOVERY, M.CATEGORY_KNOWN }

M.ERRORS = {
	bad_seed = "seed is not an integer in [0, 2^32-1]",	bad_profile = "profile is not a normalized snapshot table",
	unknown_biome = "biome is not a documented R2 region",
	ng_plus_unsupported = "NG+ chest prediction is not implemented (only NG0)",
	bad_chests = "options.chests is not an array",
	bad_scan = "options.scan is not a worldgen scan result table",
	chest_invalid = "one or more chest specs failed validation",
	chest_errors = "one or more chests could not be fully scored",
	scan_unavailable = "no worldgen scan result was supplied",
	discovery_partial = "the scan result contains records this adapter cannot model",
	recursive_chest_cycle = "a chest source chain contains a cycle",
	chest_depth_limit = "a chest source chain exceeded the depth limit",
	r5_records_bad = "options.r5_records is not a table",
}

M.WARNINGS = {
	invalid_chest = "a chest spec failed validation (details attached)",
	duplicate_chest = "another chest spec already scored the same real chest object",
	duplicate_loot_object = "a loot object was already scored via another entry",
	loot_unknown = "a chest's contents were not determined",
	unknown_reward_entity = "a chest looted an entity this build cannot classify",
	non_target_card = "a loose card is not a PRD target",
	heal_only_not_maxhp = "a heal-only pickup never counts as a max-HP pickup",
	out_of_scope_region = "a chest is outside the R2 regions",
	unsupported_provenance = "a chest's provenance is excluded from R2 entirely",
	entrance_not_authorized = "a puzzle chest's entrance is not proven generated",
	converted_to_gold = "the reward loop converted the chest into gold",
	wand_generation_failed = "a dropped wand could not be generated",
	calendar_incomplete = "the calendar input is missing fields (R5 hand-off only)",
	scan_unavailable = "no worldgen scan result was supplied, so chest presence is unproven",
	discovery_partial = "the scan result contains records this adapter cannot model",
	scan_exhaustiveness_undeclared = "the scan set's exhaustiveness was not declared",
	discovery_known_omissions = "the source pipeline is known to omit a chest source, "
		.. "so exhaustiveness cannot be claimed",
}

-- Safety limits for nested chest-source chains.
M.MAX_CHEST_DEPTH = 8

local DEFAULT_OPTIONS = {
	biome = "Mines",
	ng_plus = 0,
	predict_loot = true,
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


-------------------------------------------------------------------------------
-- Container sprite sizes (read-only, for the R5 coordinate labelling)
-------------------------------------------------------------------------------

-- The collectibles contract converts a load point to a hypothesised seed
-- transform by subtracting half the shipped sprite. Those sizes live in
-- files/isf/data/containers.lua, which is owned by the collectibles workflow.
-- This function only READS them so a forwarded record can label the candidate;
-- it never performs the conversion and never asserts the result is the proven
-- seed transform.
function container_sprite_offsets()
	if ( __container_sprite_offsets_cached ~= nil ) then
		return __container_sprite_offsets_cached
	end
	local ok, containers = pcall( dofile_once,
		"mods/interesting_seed_filter/files/isf/data/containers.lua" )
	if ( not ok or type( containers ) ~= "table"
		or type( containers.SPRITE_SIZE ) ~= "table" ) then
		__container_sprite_offsets_cached = false
		return false
	end
	local out = {}
	for kind, size in pairs( containers.SPRITE_SIZE ) do
		if ( type( size ) == "table" ) then
			out[ kind ] = { width = size.width, height = size.height }
		end
	end
	__container_sprite_offsets_cached = out
	return out
end

-------------------------------------------------------------------------------
-- Generation conditions
-------------------------------------------------------------------------------

-- HasFlagPersistent() looks at persistent flags, which on this build include the
-- spell-unlock flags. The profile keeps two maps, so both are consulted.
--
-- profile.flags(profile.unlocked_flags) copies the flag MAP; passing the profile
-- itself would copy its top-level keys (see wild_wands for the same bug class).
local function make_flag_fn( profile )
	local flags = {}
	if ( type( profile ) == "table" ) then
		local ok, copy = pcall( function()
			return profile_lib.flags( profile.unlocked_flags )
		end )
		if ( ok and type( copy ) == "table" ) then
			flags = copy
		end
		local ok2, copy2 = pcall( function()
			return profile_lib.flags( profile.persistent_flags )
		end )
		if ( ok2 and type( copy2 ) == "table" ) then
			for k, v in pairs( copy2 ) do
				if ( flags[ k ] == nil ) then
					flags[ k ] = v
				end
			end
		end
	end
	local all_unlocked = flags.ALL_UNLOCKED == true
	return function( flag )
		if ( type( flag ) ~= "string" ) then
			return false
		end
		if ( all_unlocked ) then
			return true
		end
		return flags[ flag ] == true
	end
end

-------------------------------------------------------------------------------
-- Wand support (reuses wild_wands.score_wand; never re-implements R1)
-------------------------------------------------------------------------------

-- The chest rolls its reward table at its exact fractional seed frame. A wand
-- loaded there initializes at the engine's integer entity transform, just like
-- sold wands. Native seed2355: load(728.7,1634.1), generate_gun(729,1634).
-- Do not round the chest RNG frame or apply this wand-specific bridge to bottles.
function M.wand_init_transform(frame)
	local gen=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/wand_gen.lua")
	return gen.round_half_even(frame.x),gen.round_half_even(frame.y)
end

local function build_wand_provider( resolved, profile, flag_fn )
	-- Explicit injection (tests / fixtures): both halves must be supplied.
	if ( type( resolved.wand_provider ) == "table" ) then
		return resolved.wand_provider
	end

	local wand_gen = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/wand_gen.lua" )
	local wild_wands = dofile_once( "mods/interesting_seed_filter/files/isf/providers/wild_wands.lua" )
	if ( type( wand_gen ) ~= "table" or type( wild_wands ) ~= "table" ) then
		return nil, "wand generator or wild_wands scorer unavailable"
	end
	-- wild_wands.configure() wires the shared PRNG, the spell pool and the
	-- unlock predicate into spell_select / wand_gen. Reusing it keeps exactly one
	-- wand implementation in the project.
	wild_wands.configure( profile )

	local generate_override = resolved.wand_generator

	return {
		generate = function( chest, item )
			local wand_type = item.wand_type
			if ( wand_type == nil ) then
				return nil, "loot item has no wand_type"
			end
			local frame = item.content_frame
				or { x = chest.frame_x, y = chest.frame_y }
			local gen_x,gen_y=M.wand_init_transform(frame)
			if ( type( generate_override ) == "table"
				and type( generate_override.generate ) == "function" ) then
				return generate_override.generate( resolved.seed_for_wands, 0,
					wand_type, gen_x, gen_y )
			end
			local wand, err = wand_gen.generate( resolved.seed_for_wands, 0, wand_type,
				gen_x, gen_y, { no_more_shuffle = false } )
			if ( wand == nil ) then
				return nil, err
			end
			return wand
		end,
		score = function( wand, biome, source_id, wand_index )
			return wild_wands.score_wand( wand, biome, source_id, wand_index )
		end,
	}
end

-------------------------------------------------------------------------------
-- Chat: chest source chain checks
-------------------------------------------------------------------------------

-- `chain` documents where a chest came from. A cyclic or over-deep chain means
-- the caller's data is inconsistent, and the chest must not be scored silently.
local function check_chain( chest, report )
	local chain = chest.chain
	if ( type( chain ) ~= "table" ) then
		return true
	end
	if ( #chain > M.MAX_CHEST_DEPTH ) then
		report:error( "chest_depth_limit",
			string.format( "chest %s chain has %d steps (limit %d)",
				chest.id, #chain, M.MAX_CHEST_DEPTH ) )
		return false
	end
	local seen = {}
	for i = 1, #chain do
		local step = chain[ i ]
		local key = type( step ) == "table" and step.source_id or tostring( step )
		if ( key ~= nil and seen[ key ] ) then
			report:error( "recursive_chest_cycle",
				string.format( "chest %s chain repeats source '%s' at step %d",
					chest.id, tostring( key ), i ) )
			return false
		end
		if ( key ~= nil ) then
			seen[ key ] = true
		end
	end
	return true
end

-------------------------------------------------------------------------------
-- evaluate
-------------------------------------------------------------------------------

function M.evaluate( seed, profile, options )
	local resolved = merge_options( options )
	resolved.seed_for_wands = seed

	local report = report_mod.new( {
		seed = seed,
		profile_id = ( type( profile ) == "table" and profile.id ) or "invalid",
		profile_identity = ( type( profile ) == "table" and profile_lib.identity( profile ) )
			or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, no perks picked (PRD section 2)",
			"R2.1 real chest +2; R2.2 one loose card +5 once; R2.3 full wild-direct card value; "
				.. "R2.4 max-HP pickup +2",
			"a dropped wand never triggers the loose-card bonus (R2.5)",
			"chest type and contents come from the vanilla Lua scripts, not from upstream ports",
			"discovery coverage is separate from R2 arithmetic coverage",
			"native/game parity is NOT verified for any result here",
		},
		meta = {
			provider = M.PROVIDER_ID,
			schema_version = M.SCHEMA_VERSION,
			data = {
				game_version_hash = chest_data.GAME_VERSION_HASH,
				seed_frame = chest_data.SEED_FRAME,
				baseline = chest_data.BASELINE,
				action_count = loot.ACTION_COUNT,
			},
			generation_inputs = chest_data.generation_inputs(),
			options = {
				biome = resolved.biome,
				ng_plus = resolved.ng_plus,
				predict_loot = resolved.predict_loot == true,
				chests_supplied = type( resolved.chests ) == "table" and #resolved.chests or 0,
				scan_supplied = type( resolved.scan ) == "table",
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

	local biome, biome_info = chest_data.region( resolved.biome )
	if ( biome == nil ) then
		report:error( "unknown_biome",
			M.ERRORS.unknown_biome .. ": " .. tostring( resolved.biome ) )
		input_ok = false
	end
	if ( resolved.ng_plus ~= nil and resolved.ng_plus ~= 0 ) then
		report:error( "ng_plus_unsupported",
			M.ERRORS.ng_plus_unsupported .. " (got " .. tostring( resolved.ng_plus ) .. ")" )
		input_ok = false
	end
	if ( resolved.chests ~= nil and type( resolved.chests ) ~= "table" ) then
		report:error( "bad_chests", M.ERRORS.bad_chests )
		input_ok = false
	end
	if ( resolved.scan ~= nil and type( resolved.scan ) ~= "table" ) then
		report:error( "bad_scan", M.ERRORS.bad_scan )
		input_ok = false
	end
	if ( resolved.r5_records ~= nil and type( resolved.r5_records ) ~= "table" ) then
		report:error( "r5_records_bad", M.ERRORS.r5_records_bad )
		input_ok = false
	end

	if ( not input_ok ) then
		for _, category in ipairs( M.CATEGORIES ) do
			report:claim( category, report_mod.COVERAGE_UNSUPPORTED, "invalid input" )
		end
		local failed = report:finish()
		failed.details = M.empty_details( "invalid input" )
		return failed
	end

	local flag_fn = resolved.is_flag_set or make_flag_fn( profile )
	-- A frozen calendar is an INPUT to the heart dispatch, so it is resolved once
	-- here and never read from the live clock.
	if ( resolved.calendar == nil and type( profile ) == "table" ) then
		local cal = profile.calendar
		if ( type( cal ) == "table" and type( cal.month ) == "number"
			and type( cal.day ) == "number" ) then
			resolved.calendar = { month = cal.month, day = cal.day }
		end
	end

	-- ---- discovery ---------------------------------------------------------
	local discovery_status, discovery_reason
	local discovered = {}

	if ( type( resolved.scan ) == "table" ) then
		local scan_biome = resolved.scan_biome or biome
		local result = discovery.discover( seed, resolved.scan, scan_biome, {
			is_flag_set = flag_fn,
			calendar = resolved.calendar,
		} )
		discovered = result.chests
		report.meta.discovery = "worldgen scan records"
		report.meta.scan_examined = result.examined
		report.meta.scan_rejected = #result.rejected
		report.meta.scan_unsupported = #result.unsupported
		report.meta.scan_unresolved_detail = result.unresolved
		report.meta.scan_unresolved = result.unresolved_count or 0
		report.meta.scan_declared_complete = resolved.scan_complete == true

		-- EXHAUSTIVENESS PROOF, in three independent parts. A caller's assertion
		-- alone is never sufficient:
		--
		--   1. the records must be fully modelable (`result.complete`);
		--   2. the records must actually ACCOUNT FOR every chest source the
		--      vanilla biome script registers (`result.source_capability`), which
		--      is what stops a hand-built two-record "scan" from claiming a whole
		--      region;
		--   3. the caller must declare the record set exhaustive (`scan_complete`),
		--      because only worldgen can vouch for the enumeration itself.
		--
		-- Additionally a region-specific known-omission list can veto the claim
		-- outright (currently empty: the spawn_bbqbox omission is fixed and
		-- verified, see files/isf/chests/discovery.lua).
		local omissions = result.known_source_omissions or {}
		local has_omissions = #omissions > 0
		local declared = resolved.scan_complete == true
		local capability = result.source_capability or {}
		-- Is this a REAL region enumeration, or a hand-built record list? Only a
		-- real pipeline result may ever claim exhaustiveness.
		local pipeline_ok = false
		local pipeline_reason = nil
		if ( scan_biome ~= nil ) then
			pipeline_ok, pipeline_reason = discovery.is_pipeline_result( resolved.scan )
		else
			pipeline_reason = "no biome for the scan result"
		end
		report.meta.scan_known_omissions = omissions
		report.meta.scan_pipeline_result = pipeline_ok
		report.meta.scan_pipeline_reason = pipeline_reason
		report.meta.scan_source_capability = {
			expected = capability.expected,
			observed = capability.observed,
			unmodeled_expected = capability.unmodeled_expected,
			unknown_observed = capability.unknown_observed,
			sufficient = capability.sufficient == true,
		}

		-- State EVERY blocker that applies, so a caller is never told only the
		-- less important half of why coverage is partial.
		local blockers = {}
		if ( has_omissions ) then
			blockers[ #blockers + 1 ] = "the source pipeline has known chest-source "
				.. "omissions: " .. table.concat( omissions, "; " )
		end
		if ( not pipeline_ok ) then
			blockers[ #blockers + 1 ] = "the scan result is not a real region "
				.. "enumeration (" .. tostring( pipeline_reason or "unproven" ) .. "); a "
				.. "hand-built record list cannot prove a seed was exhausted"
		end
		if ( capability.sufficient ~= true ) then
			local parts = {}
			if ( type( capability.unmodeled_expected ) == "table"
				and #capability.unmodeled_expected > 0 ) then
				parts[ #parts + 1 ] = "unresolvable source(s) "
					.. table.concat( capability.unmodeled_expected, ", " )
			end
			if ( type( capability.unknown_observed ) == "table"
				and #capability.unknown_observed > 0 ) then
				parts[ #parts + 1 ] = "unmodelled source(s) "
					.. table.concat( capability.unknown_observed, ", " )
			end
			if ( #parts == 0 ) then
				parts[ #parts + 1 ] = tostring( capability.reason
					or "no expected chest-source set is recorded for this region" )
			end
			blockers[ #blockers + 1 ] = "this build cannot resolve every chest source "
				.. "the vanilla script registers here (" .. table.concat( parts, "; " ) .. ")"
		end
		if ( not declared ) then
			blockers[ #blockers + 1 ] = "the scan set's exhaustiveness was not declared "
				.. "(pass scan_complete = true only with worldgen evidence)"
		end

		if ( result.complete and #blockers == 0 ) then
			discovery_status = report_mod.COVERAGE_COMPLETE
			discovery_reason = string.format(
				"all %d scan records were verified chest sources (%d confirmed chest(s)), "
					.. "they account for every vanilla chest source in this region, and the "
					.. "caller declared the scan set exhaustive",
				result.examined, #result.chests )
		elseif ( result.complete ) then
			discovery_status = report_mod.COVERAGE_PARTIAL
			discovery_reason = string.format(
				"all %d scan records were modelable (%d confirmed chest(s)) but "
					.. "exhaustiveness cannot be claimed: %s",
				result.examined, #result.chests, table.concat( blockers, "; " ) )
			report:warning( has_omissions and "discovery_known_omissions"
				or "scan_exhaustiveness_undeclared", discovery_reason )
		else
			discovery_status = report_mod.COVERAGE_PARTIAL
			discovery_reason = string.format(
				"scan result is not fully modelable: %s",
				table.concat( result.reasons, "; " ) )
			report:warning( "discovery_partial", discovery_reason )
		end
		report.meta.scan_rejected_reasons = {}
		for i = 1, #result.rejected do
			report.meta.scan_rejected_reasons[ i ] = result.rejected[ i ].reason
		end
	else
		discovery_status = report_mod.COVERAGE_UNSUPPORTED
		discovery_reason = M.ERRORS.scan_unavailable
			.. "; chest presence is unproven for this seed/region"
		report:warning( "scan_unavailable", discovery_reason )
	end

	-- ---- chest set ---------------------------------------------------------
	local normalized = {}
	local invalid_count = 0
	local seen_chests = {}
	local seen_loot_objects = {}

	local function add_chest( raw, origin )
		local chest, errors = chest_score.validate_chest( raw )
		if ( chest == nil ) then
			invalid_count = invalid_count + 1
			local who = type( raw ) == "table" and tostring( raw.id ) or origin
			for _, err in ipairs( errors ) do
				report:warning( "invalid_chest", who .. ": " .. err.code .. " (" .. err.message .. ")" )
			end
			return
		end
		local identity = chest_score.chest_identity( chest )
		if ( seen_chests[ identity ] ) then
			report:warning( "duplicate_chest",
				string.format( "chest %s resolves to %s, already scored; not counted again",
					chest.id, identity ) )
			return
		end
		if ( not check_chain( chest, report ) ) then
			invalid_count = invalid_count + 1
			return
		end
		seen_chests[ identity ] = chest.id
		if resolved.object_registry ~= nil then
			local dedup = dofile_once("mods/interesting_seed_filter/files/isf/core/dedup.lua")
			local accepted, why = dedup.claim(resolved.object_registry,
				{object_id=chest.object_id or chest.id,kind="chest"}, {owner="chests",id=chest.id})
			if not accepted then report:warning("duplicate_chest",why); return end
		end
		chest.origin = origin
		normalized[ #normalized + 1 ] = chest
	end

	for i = 1, #( resolved.chests or {} ) do
		add_chest( resolved.chests[ i ], "supplied" )
	end
	for i = 1, #discovered do
		add_chest( discovered[ i ], "discovered" )
	end

	if ( invalid_count > 0 ) then
		report:error( "chest_invalid",
			string.format( "%d chest spec(s) failed validation", invalid_count ) )
	end

	-- ---- scoring -----------------------------------------------------------
	local wand_provider, wand_err = build_wand_provider( resolved, profile, flag_fn )
	if ( wand_provider == nil ) then
		report:warning( "wand_generation_failed",
			"wand scoring unavailable: " .. tostring( wand_err )
				.. "; chests that drop wands will be reported as unresolved" )
	end

	local counts = {
		chests = 0,
		scored_chests = 0,
		loose_cards = 0,
		loose_target_cards = 0,
		maxhp_pickups = 0,
		heal_only_pickups = 0,
		wands = 0,
		predicted_loot = 0,
		supplied_loot = 0,
		unknown_items = 0,
		out_of_scope = 0,
		chest_errors = 0,
		deduplicated_loot = 0,
	}
	local unresolved = {}
	local r5_records = {}
	local unknown_entries = {}

	for index = 1, #normalized do
		local chest = normalized[ index ]
		counts.chests = counts.chests + 1

		-- Loot acquisition. An explicit `loot` table is used as-is (never
		-- rerolled). Otherwise loot is predicted from the seed, which is the only
		-- path that can be called a prediction. `skip` marks a chest whose loot
		-- could not be established at all; it still gets its R2.1 chest award.
		local loot_table = chest.loot
		local loot_source = "supplied"
		local skip = false
		if ( loot_table == nil ) then
			if ( chest.kind == nil ) then
				report:error( "chest_errors",
					string.format( "chest %s has no kind and no loot", chest.id ) )
				counts.chest_errors = counts.chest_errors + 1
				unresolved[ #unresolved + 1 ] = chest.id
				skip = true
				loot_table = nil
			elseif ( resolved.predict_loot ~= true ) then
				loot_table = nil
				loot_source = "unknown"
			else
				local generated, code, detail = loot.generate( seed, chest.kind,
					chest.x, chest.y, { is_flag_set = flag_fn } )
				if ( generated == nil ) then
					report:error( code or "chest_errors",
						string.format( "chest %s loot generation failed: %s",
							chest.id, tostring( detail ) ) )
					counts.chest_errors = counts.chest_errors + 1
					unresolved[ #unresolved + 1 ] = chest.id
					loot_table = nil
					loot_source = "failed"
				else
					loot_table = generated
					loot_source = "predicted"
					counts.predicted_loot = counts.predicted_loot + 1
				end
			end
		else
			-- Normalise a supplied loot table through the same contract.
			local items = loot_table.items
			if ( items == nil and #loot_table > 0 ) then
				items = loot_table -- a bare array of items is accepted
			end
			loot_table = {
				items = loot.normalize_items( items or {} ),
				outcome = loot_table.outcome or loot.OUTCOME_ITEMS,
			}
			counts.supplied_loot = counts.supplied_loot + 1
		end

		-- Cross-entry loot dedup: one real loose object reachable through two
		-- chest entries is counted once (PRD section 5). The item is NOT removed:
		-- a duplicated card still proves that its chest dropped a loose card, so
		-- R2.2 must still fire. It is only marked so R2.3/R2.4 award no points
		-- for it a second time.
		if ( loot_table ~= nil and loot_table.items ~= nil ) then
			for i = 1, #loot_table.items do
				local item = loot_table.items[ i ]
				local identity = type( item.object_id ) == "string"
					and item.object_id ~= "" and ( "object:" .. item.object_id ) or nil
				if identity and resolved.object_registry and item.reward_kind == "wand" then
					local dedup=dofile_once("mods/interesting_seed_filter/files/isf/core/dedup.lua")
					if not dedup.claim(resolved.object_registry,{object_id=item.object_id,kind="wand"},{owner="chest_wand"}) then
						item.deduplicated=true
					end
				end
				if ( identity ~= nil and seen_loot_objects[ identity ] ) then
					item.deduplicated = true
					counts.deduplicated_loot = counts.deduplicated_loot + 1
					report:warning( "duplicate_loot_object",
						string.format( "chest %s loot item %d resolves to %s, already "
							.. "scored; not counted again", chest.id, i, identity ) )
				elseif ( identity ~= nil ) then
					seen_loot_objects[ identity ] = true
				end
			end
		end

		if ( not skip ) then
			local scored = chest_score.score_chest( chest, loot_table, {
				wand_provider = wand_provider,
				is_flag_set = flag_fn,
				-- Read-only sprite sizes, used ONLY to label the collectibles
				-- convention as a candidate. This module never performs the
				-- collectibles conversion itself (see COORDINATE_HANDOFF.md).
				sprite_offsets = container_sprite_offsets(),
			} )

			for _, entry in ipairs( scored.entries ) do
				entry.chest_origin = chest.origin
				entry.loot_source = loot_source
				report:add( entry )
			end

			for _, err in ipairs( scored.errors ) do
				report:error( err.code, err.message )
				counts.chest_errors = counts.chest_errors + 1
				unresolved[ #unresolved + 1 ] = chest.id
			end
			for _, warn in ipairs( scored.warnings ) do
				report:warning( warn.code, warn.message )
			end

			for _, record in ipairs( scored.r5_records ) do
				if ( record ~= nil ) then
					r5_records[ #r5_records + 1 ] = record
				end
			end
			for _, entity in ipairs( scored.unknown_entities ) do
				unknown_entries[ #unknown_entries + 1 ] = {
					chest_id = chest.id, entity = entity,
				}
			end

			local c = scored.counts
			counts.loose_cards = counts.loose_cards + c.loose_cards
			counts.loose_target_cards = counts.loose_target_cards + c.loose_target_cards
			counts.maxhp_pickups = counts.maxhp_pickups + c.maxhp_pickups
			counts.heal_only_pickups = counts.heal_only_pickups + c.heal_only_pickups
			counts.wands = counts.wands + c.wands
			counts.unknown_items = counts.unknown_items + c.unknown_items
			if ( c.chest == 0 ) then
				counts.out_of_scope = counts.out_of_scope + 1
			else
				counts.scored_chests = counts.scored_chests + 1
			end
		end
	end

	-- ---- coverage ----------------------------------------------------------
	--
	-- `known_chests` is complete only when every chest the report was given was
	-- fully scored AND every spec was valid. An invalid spec is a gap in what
	-- was examined, so it must bias the claim downward, not be papered over with
	-- a "0 chest(s) could not be scored" message.
	local known_complete = ( counts.chest_errors == 0 ) and ( invalid_count == 0 )
	if ( known_complete ) then
		report:claim( M.CATEGORY_KNOWN, report_mod.COVERAGE_COMPLETE,
			string.format( "scored all %d known chest(s) under R2", #normalized ) )
	else
		local reasons = {}
		if ( #unresolved > 0 ) then
			reasons[ #reasons + 1 ] = string.format( "%d chest(s) could not be fully scored",
				#unresolved )
		end
		if ( invalid_count > 0 ) then
			reasons[ #reasons + 1 ] = string.format(
				"%d chest spec(s) failed validation and were not examined", invalid_count )
		end
		local reason = table.concat( reasons, "; " )
		report:claim( M.CATEGORY_KNOWN, report_mod.COVERAGE_PARTIAL, reason )
		report:error( "chest_errors", reason )
	end

	-- A supplied-chest run never proves discovery, even when the adapter is
	-- available; only a consumed scan result can claim anything about the seed.
	local supplied_only = ( type( resolved.chests ) == "table" and #resolved.chests > 0 )
	if ( supplied_only and type( resolved.scan ) ~= "table" ) then
		discovery_status = report_mod.COVERAGE_UNSUPPORTED
		discovery_reason = "chests were supplied by the caller; the seed/region was not "
			.. "enumerated, so chest PRESENCE and ABSENCE are both unproven"
	end
	report:claim( M.CATEGORY_DISCOVERY, discovery_status, discovery_reason )

	report.meta.chests_scored = counts.scored_chests
	report.meta.chests_found = counts.chests

	local finished = report:finish()

	-- Overall completeness requires BOTH sub-claims AND no errors.
	local cats = finished.coverage.categories
	local discovery_cat = cats[ M.CATEGORY_DISCOVERY ]
	local known_cat = cats[ M.CATEGORY_KNOWN ]
	local all_complete = discovery_cat ~= nil and known_cat ~= nil
		and discovery_cat.status == report_mod.COVERAGE_COMPLETE
		and known_cat.status == report_mod.COVERAGE_COMPLETE
		and #finished.errors == 0
	if ( all_complete ) then
		finished.coverage.complete = true
		finished.coverage.status = report_mod.COVERAGE_COMPLETE
	end

	-- ---- details (never affects totals) -----------------------------------
	finished.details = {
		summary = counts,
		discovery = {
			implemented = ( type( resolved.scan ) == "table" ),
			status = discovery_status,
			reason = discovery_reason,
			missing = {
				"worldgen region pipelines beyond Mines (Collapsed Mines, Coal Pits, Fungal Caverns)",
				"chest-bearing pixel-scene marker coverage for every biome",
			},
		},
		unresolved_chests = unresolved,
		unknown_entities = unknown_entries,
		r5_records = r5_records,
	}

	-- Expose forwarded records directly for callers that want them without
	-- digging through details; the array is shared with options.r5_records.
	if ( type( resolved.r5_records ) == "table" ) then
		for i = 1, #r5_records do
			resolved.r5_records[ #resolved.r5_records + 1 ] = r5_records[ i ]
		end
	end
	finished.r5_records = r5_records

	return finished
end

function M.empty_details( reason )
	return {
		summary = {
			chests = 0, scored_chests = 0, loose_cards = 0, loose_target_cards = 0,
			maxhp_pickups = 0, heal_only_pickups = 0, wands = 0, predicted_loot = 0,
			supplied_loot = 0, unknown_items = 0, out_of_scope = 0, chest_errors = 0,
			deduplicated_loot = 0,
		},
		discovery = {
			implemented = false,
			status = report_mod.COVERAGE_UNSUPPORTED,
			reason = reason,
			missing = {},
		},
		unresolved_chests = {},
		unknown_entities = {},
		r5_records = {},
	}
end

-------------------------------------------------------------------------------
-- Pure helpers for tests and for callers that already hold a chest
-------------------------------------------------------------------------------

-- Predict one chest's loot without building a report.
function M.predict_loot( seed, kind, x, y, is_flag_set )
	return loot.generate( seed, kind, x, y, { is_flag_set = is_flag_set } )
end

-- Classify one scan record without running a whole discovery pass.
function M.classify_scan_record( seed, record, region, opts )
	return discovery.classify_record( seed, record, region, opts )
end

-- Roll the two sub-claims up into the aggregate evaluator's single
-- `wild.chests` category, without editing the foundation-owned aggregator.
--
-- Same pattern (and justification) as collectibles.rollup:
--   * any sub-claim unsupported -> "unsupported" + that reason
--   * any sub-claim partial     -> "partial" + the first reason
--   * both complete             -> "complete"
--
-- Because a supplied-chest run always leaves discovery unsupported, and a scan
-- run stays partial until the caller declares exhaustiveness, this currently
-- returns "complete" only for a declared-exhaustive, fully-scored scan.
function M.rollup( report )
	if ( type( report ) ~= "table" or type( report.coverage ) ~= "table" ) then
		return report_mod.COVERAGE_UNSUPPORTED, "no coverage information"
	end
	local categories = report.coverage.categories or {}
	local statuses = {}
	local reason = nil
	for _, name in ipairs( M.CATEGORIES ) do
		local info = categories[ name ]
		local status = info and info.status or report_mod.COVERAGE_UNSUPPORTED
		statuses[ #statuses + 1 ] = status
		if ( reason == nil and status ~= report_mod.COVERAGE_COMPLETE ) then
			reason = name .. ": " .. tostring( info and info.reason or "no claim" )
		end
	end
	for i = 1, #statuses do
		if ( statuses[ i ] == report_mod.COVERAGE_UNSUPPORTED ) then
			return report_mod.COVERAGE_UNSUPPORTED, reason
		end
	end
	for i = 1, #statuses do
		if ( statuses[ i ] == report_mod.COVERAGE_PARTIAL ) then
			return report_mod.COVERAGE_PARTIAL, reason
		end
	end
	return report_mod.COVERAGE_COMPLETE, "every chest sub-claim resolved"
end

M.CHEST_DATA = chest_data
M.LOOT = loot
M.SCORE = chest_score
M.DISCOVERY = discovery

return M
