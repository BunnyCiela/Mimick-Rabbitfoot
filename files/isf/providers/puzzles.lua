-- files/isf/providers/puzzles.lua
--
-- PRD R3 puzzle provider (ISF-06 Mines + Coal Pits, ISF-07 Snowy Depths + eye).
--
-- WHAT THIS DOES
--   1. Recognises puzzle INSTANCES from explicit, source-justified entrance
--      records (files/isf/puzzles/recognize.lua), one instance per physical
--      puzzle scene.
--   2. Scores PRD R3 exactly: +2 (8 units) per real puzzle scene, +5 more
--      (20 units) for the Meditation Cube and for the Buried Eye.
--   3. Emits LINKED REWARD RECORDS with a stable identity, entrance-inherited
--      region and a precise coordinate frame, for downstream R1/R2/R5 owners.
--      It does NOT port R1/R2/R5 and does not invent a universal bonus.
--
-- WHAT THIS DOES NOT DO
--   * It cannot discover puzzles from a seed by itself. There is no Snowy Depths
--     worldgen pipeline and the Mines/Coal Pits discovery path does not emit
--     puzzle records. Without supplied entrances, coverage is `unsupported` and
--     the report says so instead of claiming "this seed has none".
--   * Supplying entrances never implies the seed's puzzle set is complete. The
--     overall report therefore stays `partial` with an explicit reason.
--   * It does not treat the reward room as a region. A reward inherits the
--     entrance's region, then the per-resource scope is applied; a Snowy Depths
--     puzzle reward therefore does not enable Snowy Depths wand/chest/R5 score.
--
-- Lua 5.1 / LuaJIT 2.0 compatible. No FFI, no external process, no file access.
-- Nothing here is verified against a running game.

local data = dofile_once( "mods/interesting_seed_filter/files/isf/data/puzzles.lua" )
if ( type( data ) ~= "table" ) then
	error( "puzzles: files/isf/data/puzzles.lua did not return a table" )
end

local recognize = dofile_once( "mods/interesting_seed_filter/files/isf/puzzles/recognize.lua" )
if ( type( recognize ) ~= "table" ) then
	error( "puzzles: files/isf/puzzles/recognize.lua did not return a table" )
end

local rewards = dofile_once( "mods/interesting_seed_filter/files/isf/puzzles/rewards.lua" )
if ( type( rewards ) ~= "table" ) then
	error( "puzzles: files/isf/puzzles/rewards.lua did not return a table" )
end

local dedup = dofile_once( "mods/interesting_seed_filter/files/isf/puzzles/dedup.lua" )
if ( type( dedup ) ~= "table" ) then
	error( "puzzles: files/isf/puzzles/dedup.lua did not return a table" )
end

local report_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
if ( type( report_mod ) ~= "table" ) then
	error( "puzzles: files/isf/core/report.lua did not return a table" )
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.CATEGORY_EXISTENCE = data.CATEGORY_EXISTENCE
M.CATEGORY_BONUS = data.CATEGORY_BONUS

M.ENTRY_SCENE_REASON = "puzzle scene instance"
M.ENTRY_CUBE_REASON = "Meditation Cube extra reward"
M.ENTRY_EYE_REASON = "Buried Eye extra reward"

local prng_module = nil

-- Inject the shared PRNG used by the deterministic meditation gate. Production
-- callers pass files/isf/random/prng.lua. Tests pass the real module or a
-- deterministic stand-in. The provider never keeps a seeded instance: the gate
-- creates one per evaluation.
function M.configure( options )
	options = options or {}
	if ( options.prng ~= nil ) then
		if ( type( options.prng.new ) ~= "function" ) then
			error( "puzzles.configure: prng must expose .new(world_seed)" )
		end
		prng_module = options.prng
		recognize.set_prng( prng_module )
	end
	return M
end

-- Lazily attach the real PRNG the first time a gate needs it, so a caller that
-- only ever supplies already-gated records does not pay for the module load.
local function ensure_prng()
	if ( prng_module == nil ) then
		local ok, module = pcall( dofile_once,
			"mods/interesting_seed_filter/files/isf/random/prng.lua" )
		if ( ok and type( module ) == "table" and type( module.new ) == "function" ) then
			prng_module = module
			recognize.set_prng( prng_module )
		end
	end
	return prng_module
end
M.ensure_prng = ensure_prng

-- True when a discovered/known region can be enumerated by this provider alone.
-- Always false in this build: puzzle discovery depends on a worldgen adapter that
-- does not emit puzzle records yet.
function M.can_discover()
	return false
end

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------

-- Score the PRD R3 existence component of one instance. Returns entries.
function M.score_instance( instance, ordinal, claimed )
	local entries = {}
	local region = data.REGIONS[ instance.biome_key ]
	if ( region == nil or region.in_scope ~= true ) then
		return entries
	end

	-- Existence: one per physical puzzle scene.
	local base_id = string.format( "%s/existence", instance.id )
	local identity = dedup.object_identity( "puzzle_scene", instance.x, instance.y,
		instance.kind_id )
	local owns, previous = claimed:claim( identity, {
		provider = "puzzles",
		entry_id = base_id,
		puzzle_id = instance.id,
	} )
	if ( owns ) then
		entries[ #entries + 1 ] = {
			id = base_id,
			rule_id = "R3",
			category = M.CATEGORY_EXISTENCE,
			biome = region.name,
			biome_key = instance.biome_key,
			puzzle_id = instance.id,
			puzzle_type = instance.puzzle_type,
			mechanism = instance.mechanism,
			source_id = instance.source_ids[ 1 ] or instance.id,
			x = instance.x,
			y = instance.y,
			score_units = data.UNITS.PUZZLE_SCENE,
			reason = string.format( "%s: %s (+%s)", M.ENTRY_SCENE_REASON, instance.label,
				"2" ),
			trigger_count = instance.trigger_count,
			object_identity = identity,
			verified = instance.verified,
			resource_scope = region.resource_scope,
		}
	else
		-- Already counted through another view. Do not add; record why.
		entries[ #entries + 1 ] = {
			id = base_id .. "/duplicate",
			rule_id = "R3",
			category = M.CATEGORY_EXISTENCE,
			biome = region.name,
			biome_key = instance.biome_key,
			puzzle_id = instance.id,
			source_id = instance.source_ids[ 1 ] or instance.id,
			x = instance.x,
			y = instance.y,
			score_units = 0,
			duplicate_of = previous and previous.entry_id or nil,
			reason = "same physical puzzle scene already scored once; a repeated "
				.. "trigger or scan must not add a second existence score",
			object_identity = identity,
		}
	end

	-- Bonus: cube (+5) and eye (+5) are separate PRD R3 bonuses.
	if ( instance.bonus == "cube" ) then
		entries[ #entries + 1 ] = {
			id = instance.id .. "/bonus/cube",
			rule_id = "R3",
			category = M.CATEGORY_BONUS,
			biome = region.name,
			biome_key = instance.biome_key,
			puzzle_id = instance.id,
			source_id = instance.source_ids[ 1 ] or instance.id,
			x = instance.x,
			y = instance.y,
			score_units = data.UNITS.CUBE_EXTRA,
			reason = M.ENTRY_CUBE_REASON .. " (+5)",
			reward = "meditation_cube",
			verified = instance.verified,
		}
	elseif ( instance.bonus == "eye" ) then
		entries[ #entries + 1 ] = {
			id = instance.id .. "/bonus/eye",
			rule_id = "R3",
			category = M.CATEGORY_BONUS,
			biome = region.name,
			biome_key = instance.biome_key,
			puzzle_id = instance.id,
			source_id = instance.source_ids[ 1 ] or instance.id,
			x = instance.x,
			y = instance.y,
			score_units = data.UNITS.EYE_EXTRA,
			reason = M.ENTRY_EYE_REASON .. " (+5)",
			reward = "buried_eye",
			verified = instance.verified,
		}
	end

	return entries
end

-- ---------------------------------------------------------------------------
-- evaluate
-- ---------------------------------------------------------------------------

-- evaluate( seed, profile, options ) -> report (schema_version 1)
--
-- options:
--   entrances    array of explicit entrance records (see recognize.lua)
--   discovery    optional descriptor of where `entrances` came from. Accepted:
--                  { source = "worldgen", biome_keys = {...}, complete = bool }
--                Anything with complete == true still does NOT make the report
--                complete: reward scoring is delegated and region enumeration
--                only covers the biomes the caller actually scanned.
--   prng         optional shared-PRNG injection (tests / explicit wiring)
--   accept_unverified_entrances
--                default false; when true, `generated = false` records still
--                create instances but every entry is marked verified = false.
--
-- returns report
function M.evaluate( seed, profile, options )
	options = options or {}

	if ( options.prng ~= nil ) then
		M.configure( { prng = options.prng } )
	end
	local gate = options.gate_meditation
	if ( gate == nil and options.entrances ~= nil ) then
		-- Only attach a gate if at least one record could need it; the gate
		-- function itself loads the PRNG lazily.
		gate = function( gate_seed, x, y )
			if ( ensure_prng() == nil ) then
				return nil, "shared PRNG module is not available in this build"
			end
			return recognize.gate_meditation( gate_seed, x, y )
		end
	end

	local report = report_mod.new( {
		seed = seed,
		profile_id = profile and profile.id or nil,
		rule_version = M.RULE_VERSION,
		meta = {
			provider = "puzzles",
			rules = { "R3" },
			region_scope = "Mines, Coal Pits, Snowy Depths only (PRD R3)",
			reward_handoff = { "R1 -> wild_wands", "R2 -> chests", "R5 -> collectibles" },
			native_game_verified = false,
			discovery = "none",
		},
		notes = {
			"R3 existence/bonus scoring and reward prediction are SEPARATE coverage claims.",
			"a supplied-entrance report proves recognition + R3 arithmetic, not that the "
				.. "seed's puzzle set was enumerated",
			"rewards are linked records for R1/R2/R5 owners; this provider does not "
				.. "re-score those rules",
			"native/game parity is NOT verified for any result here",
		},
	} )

	-- ---- pass 1: recognise -------------------------------------------------
	local recognised = recognize.recognize( options.entrances or {}, {
		seed = seed,
		gate_meditation = gate,
		accept_unverified = options.accept_unverified_entrances == true,
	} )

	local instances = recognised.instances
	local folded

	-- ---- pass 2: de-duplicate physical instances ---------------------------
	instances, folded = dedup.dedup_instances( instances )

	-- ---- pass 3: attach rewards -------------------------------------------
	local reward_records = {}
	local reward_reasons = {}
	local unresolved_rewards = 0
	local reward_status_by_kind = {}
	for i = 1, #instances do
		local inst = instances[ i ]
		local built = rewards.build( inst )
		inst.rewards = built.rewards
		inst.reward_status = built.status
		inst.reward_reasons = built.reasons
		reward_status_by_kind[ inst.kind_id ] = built.status
		unresolved_rewards = unresolved_rewards + built.unresolved
		for j = 1, #built.rewards do
			reward_records[ #reward_records + 1 ] = built.rewards[ j ]
		end
		for j = 1, #built.reasons do
			reward_reasons[ #reward_reasons + 1 ] = built.reasons[ j ]
		end
	end

	-- ---- pass 4: score R3 existence + bonuses ------------------------------
	local claimed = dedup.new_registry()
	for i = 1, #instances do
		local entries = M.score_instance( instances[ i ], i, claimed )
		for j = 1, #entries do
			local entry = entries[ j ]
			if ( entry.score_units > 0 ) then
				report:add( entry )
			else
				-- A zero-score entry still has to be visible (PRD: preserve
				-- visible zero/out-of-scope rationale) but the report's add()
				-- requires non-negative integer units, which 0 satisfies.
				report:add( entry )
			end
		end
	end

	-- ---- coverage ---------------------------------------------------------
	--
	-- Existence coverage is only `complete` when the caller asserts a complete
	-- region enumeration AND the regions are actually supported by a real
	-- discovery adapter. In this build no adapter exists, so supplied entrances
	-- always produce a `partial` existence claim.
	local discovery = options.discovery
	local discovery_source = "none"
	local discovery_complete = false
	local discovery_biomes = {}

	if ( type( discovery ) == "table" ) then
		discovery_source = tostring( discovery.source or "unknown" )
		discovery_complete = discovery.complete == true
		if ( type( discovery.biome_keys ) == "table" ) then
			for i = 1, #discovery.biome_keys do
				discovery_biomes[ #discovery_biomes + 1 ] = tostring( discovery.biome_keys[ i ] )
			end
		end
		report.meta.discovery = discovery_source
	elseif ( options.entrances ~= nil and #options.entrances > 0 ) then
		discovery_source = "supplied_entrances"
		report.meta.discovery = "supplied entrances (presence only for those positions)"
	else
		report.meta.discovery = "no entrances supplied"
	end

	local existence_status
	local existence_reason
	if ( options.entrances == nil ) then
		existence_status = report_mod.COVERAGE_UNSUPPORTED
		existence_reason = "puzzle discovery from a seed is not implemented in this "
			.. "build (no worldgen puzzle records, no Snowy Depths pipeline); an "
			.. "empty entrance list does NOT mean this seed has no puzzles"
		report:error( "puzzle_discovery_unimplemented",
			"no entrance records were supplied; R3 existence cannot be enumerated "
				.. "from seed " .. tostring( seed ) )
	else
		-- Supplied entrances: what is claimed is exactly "these instances exist
		-- and were scored", never "the seed's puzzle set is complete".
		existence_status = report_mod.COVERAGE_PARTIAL
		-- Report BOTH fold sites so the message can never read "0 folded" while
		-- trigger markers were in fact folded:
		--   recognised.duplicates = a second trigger/scene marker of one placement
		--   folded               = a whole instance presented twice
		existence_reason = string.format(
			"recognised and scored %d supplied entrance record(s) as %d instance(s); "
				.. "seed-wide puzzle enumeration is NOT claimed (%d record(s) rejected, "
				.. "%d duplicate trigger/scene marker(s) folded, "
				.. "%d duplicate instance(s) folded)",
			#( options.entrances or {} ), #instances, #recognised.rejected,
			recognised.duplicates, folded )
		if ( discovery_complete and discovery_source ~= "none" ) then
			existence_reason = existence_reason
				.. "; the caller reported a complete " .. discovery_source
				.. " enumeration, which this build cannot verify"
		end
	end
	report:claim( data.COVERAGE.EXISTENCE, existence_status, existence_reason )

	-- Reward coverage: what this provider actually resolved, per kind.
	local any_instance = #instances > 0
	local reward_status
	local reward_reason
	if ( not any_instance ) then
		reward_status = report_mod.COVERAGE_UNSUPPORTED
		reward_reason = "no puzzle instance was recognised, so no reward could be "
			.. "predicted; this is not evidence that the seed has no puzzle rewards"
	else
		reward_status = report_mod.COVERAGE_PARTIAL
		local parts = {}
		for kind_id, status in pairs( reward_status_by_kind ) do
			parts[ #parts + 1 ] = kind_id .. "=" .. status
		end
		table.sort( parts )
		reward_reason = "reward prediction is per-kind and delegated: "
			.. table.concat( parts, ", " )
		if ( unresolved_rewards > 0 ) then
			reward_reason = reward_reason .. "; " .. unresolved_rewards
				.. " reward(s) are source-justified but not resolved (see rewards)"
		end
	end
	report:claim( data.COVERAGE.REWARDS, reward_status, reward_reason )

	-- R3 arithmetic coverage, separate from enumeration.
	local scoring_status
	if ( not any_instance ) then
		scoring_status = report_mod.COVERAGE_UNSUPPORTED
	else
		scoring_status = report_mod.COVERAGE_COMPLETE
	end
	report:claim( data.COVERAGE.REWARD_SCORING, scoring_status,
		"R3 existence (+2) and cube/eye bonuses (+5) are scored for every "
			.. "recognised in-region instance; delegated R1/R2/R5 rewards are not "
			.. "scored here" )

	-- Region enumeration coverage: never complete in this build.
	report:claim( data.COVERAGE.DISCOVERY, report_mod.COVERAGE_UNSUPPORTED,
		"no puzzle-capable region discovery adapter is available: Snowy Depths has "
			.. "no worldgen pipeline and the Mines/Coal Pits scanner does not emit "
			.. "puzzle records" )

	report.coverage.complete = false

	-- ---- diagnostics ------------------------------------------------------
	report.meta.instances = #instances
	report.meta.input_entrances = #( options.entrances or {} )
	report.meta.rejected = #recognised.rejected
	-- Two different fold sites, both reported:
	--   * recognition folds a second trigger/scene marker of one placement,
	--   * instance dedup folds a whole instance presented twice.
	-- `duplicates_folded` is their total so a consumer has one number to check.
	report.meta.duplicates_by_recognition = recognised.duplicates
	report.meta.duplicates_by_instance = folded
	report.meta.duplicates_folded = recognised.duplicates + folded
	report.meta.reward_records = #reward_records
	report.meta.unresolved_rewards = unresolved_rewards
	report.meta.by_kind = recognised.by_kind
	report.meta.discovery_source = discovery_source
	report.meta.discovery_complete_claimed = discovery_complete
	report.meta.discovery_biomes = discovery_biomes

	-- Rejected records are never silently dropped.
	if ( #recognised.rejected > 0 ) then
		report.meta.rejected_records = recognised.rejected
	end

	-- Reward records travel with the report so a supervisor can hand them to the
	-- owning providers. They contribute 0 units here by construction.
	report.meta.reward_records = reward_records

	if ( #reward_reasons > 0 ) then
		report.meta.reward_reasons = reward_reasons
	end

	if ( unresolved_rewards > 0 ) then
		report:warning( "unresolved_puzzle_rewards",
			string.format( "%d puzzle reward(s) have source-justified presence but "
				.. "unresolved content/coordinate/marker mapping; they are emitted "
				.. "with resolved=false and score 0", unresolved_rewards ) )
	end
	for i = 1, #recognised.rejected do
		local r = recognised.rejected[ i ]
		if ( r.status == recognize.STATUS_GATE_FAILED ) then
			report:warning( "meditation_gate_failed", r.reason )
		end
	end

	local result = report:finish()
	-- The public contract wants reward records discoverable at meta level; the
	-- report has already sorted entries deterministically.
	result.puzzle_instances = instances
	return result
end

-- Public accessors so a supervisor can use the building blocks without
-- constructing a whole report.
M.recognize = recognize.recognize
M.build_rewards = rewards.build
M.instance_id = recognize.instance_id
M.object_identity = dedup.object_identity

return M
