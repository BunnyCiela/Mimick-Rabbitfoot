-- files/isf/core/evaluate.lua
--
-- ISF-12: seed + profile -> multi-region, multi-resource PARTIAL aggregate.
--
-- What this produces
-- ------------------
-- One report covering every region this build can discover (Mines, Collapsed
-- Mines, Coal Pits, Fungal Caverns, Snowy Depths) and every resource rule that has
-- an owning provider:
--
--   R1  wild wands          -> providers/wild_wands.lua
--   R2  chests              -> providers/chests.lua
--   R3  puzzles             -> providers/puzzles.lua  (+ reward routing)
--   R5  teleportium/pouches -> providers/collectibles.lua
--   R6/R7 Holy Mountain     -> providers/holy_mountains*.lua
--   R8  perk opportunities  -> providers/perks.lua
--
-- The aggregate owns discovery, routing, then the rule2 global normal-spell
-- decay after deduplication. Providers supply base awards; AC stays unchanged.
--
-- Discovery is performed once per region per (seed, profile) through
-- files/isf/core/discovery.lua, and the same region object is handed to every
-- adapter that needs it. No provider re-scans the map.
--
-- Coverage honesty
-- ----------------
-- A category is `complete` only when its owning provider claimed complete for
-- every contributing region. Missing provider, missing asset, unknown material,
-- unresolved coordinate frame and unimplemented rule are all `partial`/
-- `unsupported` with a stated reason -- never a silent zero. The aggregate is
-- therefore `partial` whenever any REQUIRED category is not complete, which today
-- is always.
--
-- Lua 5.1 / LuaJIT 2.0 compatible; no FFI, no external process, no require().

local report_lib = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
if ( type( report_lib ) ~= "table" ) then
	error( "evaluate: files/isf/core/report.lua did not return a table" )
end
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
if ( type( units ) ~= "table" ) then
	error( "evaluate: files/isf/core/units.lua did not return a table" )
end
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
if ( type( profile_lib ) ~= "table" ) then
	error( "evaluate: files/isf/adapters/profile.lua did not return a table" )
end
local assets_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/assets.lua" )
if ( type( assets_mod ) ~= "table" ) then
	error( "evaluate: files/isf/core/assets.lua did not return a table" )
end
local discovery_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/discovery.lua" )
if ( type( discovery_mod ) ~= "table" ) then
	error( "evaluate: files/isf/core/discovery.lua did not return a table" )
end
local adapters = dofile_once( "mods/interesting_seed_filter/files/isf/core/adapters.lua" )
if ( type( adapters ) ~= "table" ) then
	error( "evaluate: files/isf/core/adapters.lua did not return a table" )
end
local dedup = dofile_once( "mods/interesting_seed_filter/files/isf/core/dedup.lua" )
local scoring_scope = dofile_once("mods/interesting_seed_filter/files/isf/core/scoring_scope.lua")
local preferences = dofile_once("mods/interesting_seed_filter/files/isf/core/preferences.lua")
if ( type( dedup ) ~= "table" ) then
	error( "evaluate: files/isf/core/dedup.lua did not return a table" )
end

local holy = dofile_once( "mods/interesting_seed_filter/files/isf/providers/holy_mountains.lua" )
local holy_wands = dofile_once( "mods/interesting_seed_filter/files/isf/providers/holy_mountain_wands.lua" )
local perks = dofile_once( "mods/interesting_seed_filter/files/isf/providers/perks.lua" )
local wild_wands = dofile_once( "mods/interesting_seed_filter/files/isf/providers/wild_wands.lua" )
local chests = dofile_once( "mods/interesting_seed_filter/files/isf/providers/chests.lua" )
local puzzles = dofile_once( "mods/interesting_seed_filter/files/isf/providers/puzzles.lua" )
local collectibles = dofile_once( "mods/interesting_seed_filter/files/isf/providers/collectibles.lua" )

-- R4 is loaded optionally: its owner is still finishing that module, so the
-- aggregate must degrade to a NAMED unsupported gap rather than failing to load
-- if the file is absent or its public shape is not yet final. The probe checks
-- for the exact interface this aggregate uses (evaluate + rollup + the aggregate
-- category name); anything else is reported as an interface mismatch.
local wild_shops = nil
local wild_shops_load_error = nil
do
	local ok, loaded = pcall( dofile_once,
		"mods/interesting_seed_filter/files/isf/providers/wild_shops.lua" )
	if ( not ok ) then
		wild_shops_load_error = tostring( loaded )
	elseif ( type( loaded ) ~= "table" ) then
		wild_shops_load_error = "module did not return a table"
	elseif ( type( loaded.evaluate ) ~= "function" ) then
		wild_shops_load_error = "module does not expose evaluate(seed, profile, options)"
	elseif ( type( loaded.rollup ) ~= "function" ) then
		wild_shops_load_error = "module does not expose rollup(report)"
	elseif ( loaded.CATEGORY_AGGREGATE ~= "wild.spell_shops" ) then
		wild_shops_load_error = "aggregate category is now '"
			.. tostring( loaded.CATEGORY_AGGREGATE ) .. "', expected 'wild.spell_shops'"
	else
		wild_shops = loaded
	end
end

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "2.0"

-- Categories a *complete* PRD seed score must cover, in report order.
M.REQUIRED_CATEGORIES = {
	"holy_mountain.spell_cards",
	"holy_mountain.sold_wands",
	"holy_mountain.perks",
	"wild.wands",
	"wild.chests",
	"wild.puzzles",
	"wild.spell_shops",
	"wild.liquids_and_pouches",
}

-- Human label per category, for the compact report.
M.CATEGORY_LABELS = {
	["holy_mountain.spell_cards"] = "Holy Mountain spell cards (R7)",
	["holy_mountain.sold_wands"] = "Holy Mountain sold wands (R6/R7)",
	["holy_mountain.perks"] = "Holy Mountain perk opportunities (R8)",
	["wild.wands"] = "wild wands (R1)",
	["wild.chests"] = "chests (R2)",
	["wild.puzzles"] = "puzzles (R3)",
	["wild.spell_shops"] = "wild spell shops (R4)",
	["wild.liquids_and_pouches"] = "teleportium / gold pouches (R5)",
}

-- Which provider owns each aggregate category. This is the explicit capability
-- map: no provider's own wording can make a category with no owner look complete.
M.CATEGORY_OWNERS = {
	["holy_mountain.spell_cards"] = "holy_mountains",
	["holy_mountain.sold_wands"] = "holy_mountain_wands",
	["holy_mountain.perks"] = "perks",
	["wild.wands"] = "wild_wands",
	["wild.chests"] = "chests",
	["wild.puzzles"] = "puzzles",
	["wild.spell_shops"] = "wild_shops",
	["wild.liquids_and_pouches"] = "collectibles",
}

-- Provider-internal entry categories that must be re-labelled with the aggregate
-- category when their entries are merged. The perks provider tags its entries
-- `perk_opportunity`; in the aggregate they belong to `holy_mountain.perks`.
-- The original name is preserved as `provider_category` for audit.
M.ENTRY_CATEGORY_ALIASES = {
	perk_opportunity = "holy_mountain.perks",
}

-- Providers known to this build but not yet delivered. Kept as data so the report
-- names the gap precisely instead of saying "unsupported" with no owner.
M.MISSING_PROVIDERS = {}

function M.providers()
	local list = {}
	for _, name in ipairs( {
		"holy_mountains", "holy_mountain_wands", "perks",
		"wild_wands", "chests", "puzzles", "wild_shops", "collectibles",
	} ) do
		list[ #list + 1 ] = name
	end
	return list
end

-- Categories owned by any provider (i.e. potentially scoreable today).
function M.implemented_categories()
	local set = {}
	for category, owner in pairs( M.CATEGORY_OWNERS ) do
		set[ category ] = owner
	end
	return set
end

--------------------------------------------------------------------------------
-- Coverage helpers
--------------------------------------------------------------------------------

-- Normalise one provider's claim about one category.
--
-- Providers in this codebase report coverage in two shapes:
--   * core schema:  coverage.categories[cat] = { status, reason }
--   * single-status schema: coverage.status plus coverage.rules
--     (perks reports R8 this way), and collectibles adds details.aggregate.
--
-- `category` is the aggregate category the caller wants; for a single-status
-- provider it is the category that provider owns.
local function read_claim( report, category, provider_name )
	local coverage = report and report.coverage
	if ( type( coverage ) ~= "table" ) then
		return nil
	end
	local categories = coverage.categories
	if ( type( categories ) == "table" and categories[ category ] ~= nil ) then
		local info = categories[ category ]
		return { status = info.status, reason = info.reason or "" }
	end

	-- Collectibles publishes a rollup for exactly one aggregate category.
	if ( provider_name == "collectibles" ) then
		local details = report.details
		if ( type( details ) == "table" and type( details.aggregate ) == "table"
			and details.aggregate.category == category ) then
			return {
				status = details.aggregate.status,
				reason = details.aggregate.reason or "",
			}
		end
	end

	-- Single-status providers (perks): their whole report is one claim.
	if ( type( coverage.status ) == "string" and M.CATEGORY_OWNERS[ category ] == provider_name ) then
		local reasons = {}
		for _, r in ipairs( coverage.reasons or {} ) do
			reasons[ #reasons + 1 ] = tostring( r )
		end
		local reason = #reasons > 0 and table.concat( reasons, "; " ) or ""
		if ( reason == "" ) then
			local rules = coverage.rules or {}
			reason = "provider reported status '" .. coverage.status .. "'"
			if ( #rules > 0 ) then
				reason = reason .. " (rules " .. table.concat( rules, "," ) .. ")"
			end
		end
		return { status = coverage.status, reason = reason }
	end
	return nil
end

-- Merge many per-region claims for the SAME category into one.
--
-- The rule: complete only if EVERY contributing region was complete. Any partial
-- contributor makes the aggregate partial; an all-unsupported set stays
-- unsupported. Real work is never discarded by a single weak region.
local function merge_region_claims( claims )
	if ( #claims == 0 ) then
		return report_lib.COVERAGE_UNSUPPORTED, "no region contributed to this category"
	end
	local complete, partial, unsupported = 0, 0, 0
	local reasons = {}
	for i = 1, #claims do
		local c = claims[ i ]
		if ( c.status == report_lib.COVERAGE_COMPLETE ) then
			complete = complete + 1
		elseif ( c.status == report_lib.COVERAGE_PARTIAL ) then
			partial = partial + 1
			if c.reason ~= "" and #reasons < 4 then
				reasons[ #reasons + 1 ] = c.region .. ": " .. c.reason
			end
		else
			unsupported = unsupported + 1
			if c.reason ~= "" and #reasons < 4 then
				reasons[ #reasons + 1 ] = c.region .. ": " .. c.reason
			end
		end
	end
	if ( complete == #claims ) then
		return report_lib.COVERAGE_COMPLETE,
			string.format( "all %d contributing region(s) complete", complete )
	end
	local status = report_lib.COVERAGE_UNSUPPORTED
	if ( complete > 0 or partial > 0 ) then
		status = report_lib.COVERAGE_PARTIAL
	end
	local head = string.format( "%d complete, %d partial, %d unsupported region claim(s)",
		complete, partial, unsupported )
	if ( #reasons > 0 ) then
		head = head .. "; " .. table.concat( reasons, " | " )
	end
	return status, head
end

--------------------------------------------------------------------------------
-- Provider invocation
--------------------------------------------------------------------------------

-- Run one provider safely. A crash must not lose the rest of the report: it is
-- recorded as an error and that region's claim becomes unsupported.
local function run_provider( fn, ... )
	local ok, result = pcall( fn, ... )
	if ( not ok ) then
		return nil, tostring( result )
	end
	if ( type( result ) ~= "table" ) then
		return nil, "provider returned " .. type( result )
	end
	return result, nil
end

-- Combine a two-category provider's claims into one aggregate status.
local function combine_pair( upper, lower, upper_name, lower_name )
	if ( upper == nil or lower == nil ) then
		return report_lib.COVERAGE_UNSUPPORTED, "provider did not report both categories"
	end
	if ( upper.status == report_lib.COVERAGE_COMPLETE
		and lower.status == report_lib.COVERAGE_COMPLETE ) then
		return report_lib.COVERAGE_COMPLETE, upper.reason
	end
	if ( upper.status == report_lib.COVERAGE_UNSUPPORTED
		and lower.status == report_lib.COVERAGE_UNSUPPORTED ) then
		return report_lib.COVERAGE_UNSUPPORTED,
			upper.reason ~= "" and upper.reason or lower.reason
	end
	return report_lib.COVERAGE_PARTIAL,
		upper_name .. "=" .. tostring( upper.status ) .. ", "
			.. lower_name .. "=" .. tostring( lower.status )
end

--------------------------------------------------------------------------------
-- evaluate
--------------------------------------------------------------------------------

-- Build the options table for one provider call.
--
-- Provider-specific options (a stub asset path, an injected PRNG, a test
-- generator) are passed through `options.provider_options[<provider>]`, so the
-- aggregate never has to grow a field for every provider knob while still
-- allowing a caller to exercise a provider's failure paths.
local function provider_options( options, provider_name, base )
	local merged = {}
	for k, v in pairs( base or {} ) do
		merged[ k ] = v
	end
	local overrides = options.provider_options
	if ( type( overrides ) == "table" and type( overrides[ provider_name ] ) == "table" ) then
		for k, v in pairs( overrides[ provider_name ] ) do
			merged[ k ] = v
		end
	end
	return merged
end

-- evaluate( seed, profile, options )
--
-- options.assets            worldgen bundle from files/isf/core/assets.lua. When
--                           absent, every region-based category is unsupported
--                           (never "no resources").
-- options.region_index      multi-region biome index (default 1)
-- options.ng_plus           NG+ (default 0; only 0 is in scope)
-- options.rng_module        shared PRNG module (host injection / tests)
-- options.provider_options  per-provider option overrides, keyed by provider name
-- options.include_details   include per-provider payloads (default true)
function M.evaluate( seed, profile, options )
	options = options or {}
	if options.search_settings ~= nil then
		options = preferences.evaluation_options(options.search_settings,options)
	end
	local clock = ( type( os ) == "table" and type( os.clock ) == "function" )
		and os.clock or nil
	local started = clock and clock() or nil

	local aggregate = report_lib.new( {
		seed = seed,
		profile_id = type( profile ) == "table" and profile.id or "invalid",
		profile_identity = type( profile ) == "table" and profile_lib.identity( profile ) or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, no perks picked (PRD section 2)",
			"discovery runs once per region and is shared by every resource adapter",
			"coverage is partial until every PRD category has an implemented, verified provider",
			"partial reports are not acceptable filter results (PRD section 5)",
			"native/game parity is NOT verified for any category",
		},
		meta = {
			providers = M.providers(),
			schema_version = M.SCHEMA_VERSION,
			native_game_verified = false,
		},
	} )

	-- ---- input validation -------------------------------------------------
	local input_ok = true
	if ( type( seed ) ~= "number" or seed ~= math.floor( seed )
		or seed < 0 or seed > 4294967295 ) then
		aggregate:error( "bad_seed",
			"seed must be an integer in [0, 2^32-1]; got " .. tostring( seed ) )
		input_ok = false
	end
	if ( type( profile ) ~= "table" ) then
		aggregate:error( "bad_profile",
			"profile must be a normalized profile table (files/isf/adapters/profile.lua)" )
		input_ok = false
	end
	local ng_plus = options.ng_plus or 0
	if ( ng_plus ~= 0 ) then
		aggregate:error( "ng_plus_unsupported",
			"only NG0 is in scope; got " .. tostring( ng_plus ) )
		input_ok = false
	end

	local assets = options.assets
	local assets_usable, assets_reason = assets_mod.is_usable( assets )
	if ( assets ~= nil and not assets_usable ) then
		aggregate:warning( "assets_unusable", tostring( assets_reason ) )
	end

	-- ---- discovery (once per region) --------------------------------------
	-- Snapshot the cumulative cache counters so the report can state what THIS
	-- evaluation did, not the process lifetime totals.
	local discovery_stats_before = discovery_mod.stats()
	local results = {}
	local discovery_errors = {}
	local discovery_ran = false
	if ( input_ok and assets_usable ) then
		discovery_ran = true
		results, discovery_errors = discovery_mod.all( seed, profile, assets, {
			ng_plus = ng_plus,
			region_index = options.region_index,
		} )
	end
	local discovery_stats_after = discovery_mod.stats()
	for i = 1, #discovery_errors do
		aggregate:warning( "region_discovery_unavailable",
			tostring( discovery_errors[ i ].biome_name ) .. ": "
				.. tostring( discovery_errors[ i ].reason ) )
	end

	-- ---- per-provider passes ---------------------------------------------
	local claims = {}
	local provider_details = {}
	local dedup_registry = dedup.new_registry()
	local rng_module = options.rng_module
	local chest_r5_records = {}

	local function add_claim( region, category, status, reason )
		claims[ #claims + 1 ] = {
			region = region, category = category,
			status = status, reason = reason,
		}
	end

	local function record_provider( name, region, report )
		provider_details[ #provider_details + 1 ] = {
			provider = name, region = region, report = report,
		}
	end

	-- Holy Mountain providers are region-independent (fixed anchors).
	if ( input_ok ) then
		local hm_report, hm_err = run_provider( holy.evaluate, seed, profile,
			provider_options( options, "holy_mountains", {
				rng_module = rng_module,
				holy_mountains = options.holy_mountains,
			} ) )
		if ( hm_report == nil ) then
			aggregate:error( "provider_crashed", "holy_mountains: " .. tostring( hm_err ) )
			add_claim( "holy_mountain", "holy_mountain.spell_cards",
				report_lib.COVERAGE_UNSUPPORTED, "provider crashed: " .. tostring( hm_err ) )
		else
			record_provider( "holy_mountains", "holy_mountain", hm_report )
			local claim = read_claim( hm_report, "holy_mountain.spell_cards", "holy_mountains" )
			if ( claim ~= nil ) then
				add_claim( "holy_mountain", "holy_mountain.spell_cards",
					claim.status, claim.reason )
			end
		end

		local hw_report, hw_err = run_provider( holy_wands.evaluate, seed, profile,
			provider_options( options, "holy_mountain_wands", {
				rng_module = rng_module, holy_mountains = options.holy_mountains,
			} ) )
		if ( hw_report == nil ) then
			aggregate:error( "provider_crashed",
				"holy_mountain_wands: " .. tostring( hw_err ) )
			add_claim( "holy_mountain", "holy_mountain.sold_wands",
				report_lib.COVERAGE_UNSUPPORTED, "provider crashed: " .. tostring( hw_err ) )
		else
			record_provider( "holy_mountain_wands", "holy_mountain", hw_report )
			local claim = read_claim( hw_report, "holy_mountain.sold_wands",
				"holy_mountain_wands" )
			if ( claim ~= nil ) then
				add_claim( "holy_mountain", "holy_mountain.sold_wands",
					claim.status, claim.reason )
			end
		end

		local perk_report, perk_err = run_provider( perks.evaluate, seed, profile,
			provider_options( options, "perks", {} ) )
		if ( perk_report == nil ) then
			aggregate:error( "provider_crashed", "perks: " .. tostring( perk_err ) )
			add_claim( "holy_mountain", "holy_mountain.perks",
				report_lib.COVERAGE_UNSUPPORTED, "provider crashed: " .. tostring( perk_err ) )
		else
			record_provider( "perks", "holy_mountain", perk_report )
			local claim = read_claim( perk_report, "holy_mountain.perks", "perks" )
			if ( claim ~= nil ) then
				add_claim( "holy_mountain", "holy_mountain.perks",
					claim.status, claim.reason )
			end
		end
	end

	-- R1 wild wands and R2 chests: per in-scope region, shared discovery.
	if ( discovery_ran ) then
		for _, key in ipairs( discovery_mod.region_keys() ) do
			local region = results[ key ]
			if ( region ~= nil and adapters.WAND_REGION_KEYS[ key ] ) then
				local biome_name = adapters.WAND_BIOME_NAMES[ key ]
				local report, err = run_provider( wild_wands.evaluate, seed, profile,
					provider_options( options, "wild_wands", {
						biome = biome_name,
						assets = assets,
						scan = region,
						region_index = options.region_index,
						object_registry = dedup_registry,
						ng_plus = ng_plus,
						rng_module = rng_module,
					} ) )
				if ( report == nil ) then
					aggregate:error( "provider_crashed",
						"wild_wands on " .. key .. ": " .. tostring( err ) )
					add_claim( key, "wild.wands", report_lib.COVERAGE_UNSUPPORTED,
						"provider crashed: " .. tostring( err ) )
				else
					record_provider( "wild_wands", key, report )
					local upper = read_claim( report, wild_wands.CATEGORY_DISCOVERY, "wild_wands" )
					local lower = read_claim( report, wild_wands.CATEGORY_KNOWN, "wild_wands" )
					local status, reason = combine_pair( upper, lower, "discovery", "R1 scoring" )
					add_claim( key, "wild.wands", status, reason )
				end
			end

			if ( region ~= nil and adapters.CHEST_REGION_KEYS[ key ] ) then
				local scan = adapters.chest_scan( region )
				local report, err = run_provider( chests.evaluate, seed, profile,
					provider_options( options, "chests", {
						biome = adapters.CHEST_BIOME_NAMES[ key ],
						scan = scan,
						scan_complete = false,
						ng_plus = ng_plus,
						rng_module = rng_module,
						calendar = type( profile ) == "table" and profile.calendar or nil,
						r5_records = chest_r5_records,
						object_registry = dedup_registry,
					} ) )
				if ( report == nil ) then
					aggregate:error( "provider_crashed",
						"chests on " .. key .. ": " .. tostring( err ) )
					add_claim( key, "wild.chests", report_lib.COVERAGE_UNSUPPORTED,
						"provider crashed: " .. tostring( err ) )
				else
					record_provider( "chests", key, report )
					local upper = read_claim( report, chests.CATEGORY_DISCOVERY, "chests" )
					local lower = read_claim( report, chests.CATEGORY_KNOWN, "chests" )
					local status, reason = combine_pair( upper, lower, "discovery", "R2 scoring" )
					add_claim( key, "wild.chests", status, reason )
				end
			end
		end
	end

	-- R3 puzzles: entrances from every discovered region, rewards routed onward.
	local reward_routing = nil
	local scope_exclusions={containers={},puzzle_rewards={}}
	if ( discovery_ran ) then
		local entrances = adapters.puzzle_entrances_all( results )
		local biome_keys = {}
		for _, key in ipairs( discovery_mod.region_keys() ) do
			if ( results[ key ] ~= nil ) then biome_keys[ #biome_keys + 1 ] = key end
		end
		local report, err = run_provider( puzzles.evaluate, seed, profile,
			provider_options( options, "puzzles", {
				entrances = entrances,
				prng = rng_module,
				discovery = {
					source = "worldgen discovery",
					complete = false,
					biome_keys = biome_keys,
				},
			} ) )
		if ( report == nil ) then
			aggregate:error( "provider_crashed", "puzzles: " .. tostring( err ) )
			add_claim( "all", "wild.puzzles", report_lib.COVERAGE_UNSUPPORTED,
				"provider crashed: " .. tostring( err ) )
		else
			record_provider( "puzzles", "all", report )
			local upper = read_claim( report, "puzzles.existence", "puzzles" )
			local lower = read_claim( report, "puzzles.reward_scoring", "puzzles" )
			local status, reason = combine_pair( upper, lower,
				"entrance enumeration", "R3 scoring" )
			add_claim( "all", "wild.puzzles", status, reason )

			local reward_records = ( report.meta and report.meta.reward_records ) or {}
			local ok,prepared=pcall(function()
				return dofile_once("mods/interesting_seed_filter/files/isf/puzzles/wand_rewards.lua").prepare(seed,profile,reward_records)
			end)
			if ok then reward_records=prepared
			else aggregate:error("puzzle_wand_preparation_failed",tostring(prepared))end
			reward_records,scope_exclusions.puzzle_rewards=scoring_scope.filter_puzzle_rewards(reward_records)
			reward_routing = adapters.route_puzzle_rewards( reward_records )
		end
	end

	-- Rewards are consumed by their owning scorers, never by R3 arithmetic.
	if reward_routing ~= nil then
		for _, chest in ipairs(reward_routing.chests) do
			local report, err = run_provider(chests.evaluate, seed, profile,
				provider_options(options, "puzzle_chests", {chests={chest},
					r5_records=chest_r5_records,object_registry=dedup_registry}))
			if report then
				record_provider("puzzle_chests",chest.biome,report)
			else
				aggregate:error("puzzle_chest_failed",tostring(err))
			end
		end
		for _, rec in ipairs(reward_routing.wands) do
			if dedup.claim(dedup_registry,{object_id=rec.object_id or rec.id,kind="wand"},{owner="puzzle_wands"}) then
				local scored = wild_wands.score_wand(rec.wand,rec.entrance_biome or rec.biome,rec.object_id or rec.id,1)
				local report=report_lib.new({seed=seed,profile_id=profile.id,rule_version=M.RULE_VERSION})
				for _, entry in ipairs(scored.entries) do
					entry.category="wild.wands";entry.object_id=rec.object_id or rec.id;entry.provenance="puzzle_reward"
					report:add(entry)
				end
				record_provider("puzzle_wands",rec.entrance_biome or rec.biome,report:finish())
			end
		end
		for _, rec in ipairs(reward_routing.unrouted) do
			aggregate:warning("puzzle_reward_unresolved",tostring(rec.id)..": "..tostring(rec.reason))
		end
	end

	-- R4 wild spell shops: only Mines / Coal Pits / Snowy Depths (PRD section 2).
	--
	-- The provider groups discovery records into physical shop scenes and applies
	-- its own rollup over three sub-claims (discovery / shop_existence /
	-- shop_contents). The aggregate must use that rollup rather than re-deriving
	-- the rule, both to avoid duplicating another owner's semantics and so a change
	-- inside the provider cannot silently disagree with the aggregate.
	if ( wild_shops == nil ) then
		add_claim( "all", "wild.spell_shops", report_lib.COVERAGE_UNSUPPORTED,
			"R4 provider unavailable: " .. tostring( wild_shops_load_error ) )
	elseif ( discovery_ran ) then
		local region_names = adapters.SHOP_REGION_NAMES
		for _, key in ipairs( discovery_mod.region_keys() ) do
			local region = results[ key ]
			local name = region_names[ key ]
			if ( region ~= nil and name ~= nil ) then
				local report, err = run_provider( wild_shops.evaluate, seed, profile,
					provider_options( options, "wild_shops", {
						region = name,
						scan = region,
						scan_complete = false,
						ng_plus = ng_plus,
						calendar = type( profile ) == "table" and profile.calendar or nil,
					} ) )
				if ( report == nil ) then
					aggregate:error( "provider_crashed",
						"wild_shops on " .. key .. ": " .. tostring( err ) )
					add_claim( key, "wild.spell_shops", report_lib.COVERAGE_UNSUPPORTED,
						"provider crashed: " .. tostring( err ) )
				else
					record_provider( "wild_shops", key, report )
					local status, reason = wild_shops.rollup( report )
					add_claim( key, "wild.spell_shops", status, reason )
				end
			end
		end
	else
		add_claim( "all", "wild.spell_shops", report_lib.COVERAGE_UNSUPPORTED,
			"R4 shop discovery did not run: worldgen assets were not supplied, "
				.. "so no region could be enumerated" )
	end

	-- R5 collectibles: container records from every discovered region, deduped.
	local collectible_records = {}
	local collectible_stats = {}
	local collectible_dedup_dropped = 0
	if ( discovery_ran ) then
		collectible_records, collectible_stats, collectible_dedup_dropped =
			adapters.collectible_records_all( results, dedup_registry, "collectibles" )
	end
	for _, rec in ipairs(chest_r5_records) do collectible_records[#collectible_records+1] = rec end
	for _, rec in ipairs(reward_routing and reward_routing.collectibles or {}) do
		collectible_records[#collectible_records+1] = rec
	end
	collectible_records,scope_exclusions.containers=scoring_scope.filter_containers(collectible_records)
	-- R5 is a region-scoped rule: without a discovery pass there are no container
	-- records to examine, so the provider is not asked at all. Asking it with an
	-- empty record list would produce "only supplied records were examined", which
	-- reads as "this seed has no containers" -- exactly the confusion the PRD
	-- forbids.
	if ( input_ok and discovery_ran ) then
		local report, err = run_provider( collectibles.evaluate, seed, profile,
			provider_options( options, "collectibles", {
				records = collectible_records,
				enumeration = ( #collectible_records > 0 ) and "supplied" or nil,
				rng_module = rng_module,
				calendar = type( profile ) == "table" and profile.calendar or nil,
			} ) )
		if ( report == nil ) then
			aggregate:error( "provider_crashed", "collectibles: " .. tostring( err ) )
			add_claim( "all", "wild.liquids_and_pouches",
				report_lib.COVERAGE_UNSUPPORTED, "provider crashed: " .. tostring( err ) )
		else
			record_provider( "collectibles", "all", report )
			local r5_status,r5_reason = collectibles.rollup(report,{exclude_natural_pools=true})
			local claim = {status=r5_status,reason=r5_reason}
			if ( claim ~= nil ) then
				-- The provider's own message predates this aggregation: it says
				-- "container discovery is not implemented", which is true of the
				-- provider in isolation but not of this run. Annotate the aggregate
				-- reason with what the aggregate ACTUALLY supplied, so a reader is
				-- not told discovery was skipped when it was performed.
				local reason = claim.reason
				if ( discovery_ran ) then
					reason = string.format(
						"%s [aggregate supplied %d discovered container record(s) from %d region(s); %d duplicate(s) suppressed]",
						tostring( claim.reason ), #collectible_records,
						( function()
							local n = 0
							for _ in pairs( collectible_stats ) do n = n + 1 end
							return n
						end )(),
						collectible_dedup_dropped )
				end
				add_claim( "all", "wild.liquids_and_pouches", claim.status, reason )
			else
				add_claim( "all", "wild.liquids_and_pouches",
					report_lib.COVERAGE_UNSUPPORTED, "provider reported no aggregate claim" )
			end
		end
	end

	if ( input_ok and not discovery_ran ) then
		add_claim( "all", "wild.liquids_and_pouches", report_lib.COVERAGE_UNSUPPORTED,
			"R5 container discovery did not run: worldgen assets were not supplied, "
				.. "so no region could be enumerated" )
	end

	-- ---- merge entries ----------------------------------------------------
	local seen_entry_ids = {}
	local base_entries={}
	for i = 1, #provider_details do
		local item = provider_details[ i ]
		local prefix = item.provider .. "/" .. tostring( item.region )
		local report = item.report
		for j = 1, #( report.entries or {} ) do
			local entry = report.entries[ j ]
			local copy = {}
			for k, v in pairs( entry ) do copy[ k ] = v end
			copy.provider = item.provider
			copy.aggregate_region = item.region
			-- Re-label provider-internal categories onto the aggregate category,
			-- keeping the original for audit.
			local alias = M.ENTRY_CATEGORY_ALIASES[ copy.category ]
			if ( alias ~= nil ) then
				copy.provider_category = copy.category
				copy.category = alias
			end
			local key = prefix .. "|" .. tostring( copy.id )
			if ( seen_entry_ids[ key ] ) then
				aggregate:error( "duplicate_entry", "entry counted twice: " .. key )
			else
				seen_entry_ids[ key ] = true
				base_entries[#base_entries+1]=copy
			end
		end
		for _, err in ipairs( report.errors or {} ) do
			aggregate:error( item.provider .. "." .. tostring( err.code ),
				"[" .. tostring( item.region ) .. "] " .. tostring( err.message ) )
		end
		for _, warn in ipairs( report.warnings or {} ) do
			aggregate:warning( item.provider .. "." .. tostring( warn.code ),
				"[" .. tostring( item.region ) .. "] " .. tostring( warn.message ) )
		end
	end

	local decay=dofile_once("mods/interesting_seed_filter/files/isf/core/spell_decay.lua")
	local settled,settlement=decay.settle(base_entries)
	aggregate.settled_scores=true
	aggregate.meta.scoring=settlement
	for _,entry in ipairs(settled)do aggregate:add(entry)end
	-- ---- coverage merge ---------------------------------------------------
	local by_category = {}
	for i = 1, #claims do
		local c = claims[ i ]
		if ( c.category ~= nil ) then
			by_category[ c.category ] = by_category[ c.category ] or {}
			local bucket = by_category[ c.category ]
			bucket[ #bucket + 1 ] = c
		end
	end

	for _, category in ipairs( M.REQUIRED_CATEGORIES ) do
		local claims_for = by_category[ category ]
		if ( claims_for == nil ) then
			local missing = nil
			for _, info in pairs( M.MISSING_PROVIDERS ) do
				if ( info.category == category ) then missing = info end
			end
			if ( missing ~= nil ) then
				aggregate:claim( category, report_lib.COVERAGE_UNSUPPORTED,
					"no provider: " .. missing.reason .. " (" .. missing.module .. ")" )
			elseif ( not input_ok ) then
				aggregate:claim( category, report_lib.COVERAGE_UNSUPPORTED, "invalid input" )
			elseif ( not discovery_ran ) then
				aggregate:claim( category, report_lib.COVERAGE_UNSUPPORTED,
					"worldgen assets were not supplied, so no region could be enumerated" )
			else
				aggregate:claim( category, report_lib.COVERAGE_UNSUPPORTED,
					"no provider reported this category" )
			end
		else
			local status, reason = merge_region_claims( claims_for )
			aggregate:claim( category, status, reason )
		end
	end

	-- ---- finish -----------------------------------------------------------
	local finished = aggregate:finish()
	finished.totals.base_score_units=settlement.base_score_units
	finished.totals.base_score=units.to_string(settlement.base_score_units)
	finished.meta.asset_identity = assets and assets.content_identity or "no-assets"
	finished.meta.scoring_scope={id=scoring_scope.ID,excluded=scoring_scope.excluded,exhaustive_resource_audit=false}
	local coverage_identity={"rules:"..M.RULE_VERSION,"scope:"..scoring_scope.ID,"natural_pools:excluded","native:false"}
	if options.search_settings ~= nil then
		finished.meta.search_settings=preferences.normalize(options.search_settings)
		finished.meta.scoring_depth_identity=preferences.score_identity(options.search_settings)
		coverage_identity[#coverage_identity+1]=finished.meta.scoring_depth_identity
	end
	for _,category in ipairs(M.REQUIRED_CATEGORIES) do
		local info=finished.coverage.categories[category]
		coverage_identity[#coverage_identity+1]=category..":"..(info and info.status or "unsupported")
	end
	finished.meta.coverage_identity=table.concat(coverage_identity,"|")

	-- Per-region and per-category subtotals, derived from the merged entries so
	-- they can never disagree with the total.
	local by_region = {}
	local by_category_scores = {}
	for i = 1, #finished.entries do
		local e = finished.entries[ i ]
		local region = e.region or e.biome or "unknown"
		by_region[ region ] = by_region[ region ] or {
			region = region, score_units = 0, entries = 0 }
		by_region[ region ].score_units = by_region[ region ].score_units + e.score_units
		by_region[ region ].entries = by_region[ region ].entries + 1

		local cat = e.category or "uncategorized"
		by_category_scores[ cat ] = by_category_scores[ cat ] or {
			category = cat, score_units = 0, entries = 0 }
		by_category_scores[ cat ].score_units =
			by_category_scores[ cat ].score_units + e.score_units
		by_category_scores[ cat ].entries = by_category_scores[ cat ].entries + 1
	end

	local function sorted_rows( source, key_name )
		local names = {}
		for name in pairs( source ) do names[ #names + 1 ] = name end
		table.sort( names )
		local rows = {}
		for _, name in ipairs( names ) do
			local row = source[ name ]
			rows[ #rows + 1 ] = {
				[ key_name ] = name,
				score_units = row.score_units,
				score = units.to_string( row.score_units ),
				entries = row.entries,
			}
		end
		return rows
	end

	-- Per-region discovery rows.
	local discovered_rows = {}
	for _, key in ipairs( discovery_mod.region_keys() ) do
		local region = results[ key ]
		if ( region == nil ) then
			local reason = nil
			for _, e in ipairs( discovery_errors ) do
				if ( e.biome_key == key ) then reason = e.reason end
			end
			discovered_rows[ #discovered_rows + 1 ] = {
				region = key,
				name = discovery_mod.NAME_BY_KEY[ key ],
				discovered = false,
				reason = reason or ( discovery_ran and "not attempted" or "no assets" ),
			}
		else
			discovered_rows[ #discovered_rows + 1 ] = {
				region = key,
				name = region.biome_name,
				discovered = true,
				records = region.record_count,
				scene_markers = region.scene_marker_count,
				region_count = region.region_count,
			}
		end
	end

	local coverage_rows = {}
	local coverage_by_provider = {}
	for _, category in ipairs( M.REQUIRED_CATEGORIES ) do
		local info = finished.coverage.categories[ category ]
		local owner = M.CATEGORY_OWNERS[ category ]
		local status = info and info.status or "unsupported"
		coverage_rows[ #coverage_rows + 1 ] = {
			category = category,
			label = M.CATEGORY_LABELS[ category ] or category,
			owner = owner,
			status = status,
		}
		-- Explicit attribution for machine re-checking: which provider owns the
		-- category and what status it ended up with.
		if ( owner ~= nil ) then
			coverage_by_provider[ category ] = {
				provider = owner,
				status = status,
			}
		end
	end

	local discovered_count = 0
	for _, key in ipairs( discovery_mod.region_keys() ) do
		if ( results[ key ] ~= nil ) then discovered_count = discovered_count + 1 end
	end

	finished.details = {
		providers = {},
		by_region = sorted_rows( by_region, "region" ),
		by_category = sorted_rows( by_category_scores, "category" ),
		coverage_rows = coverage_rows,
		coverage_by_provider = coverage_by_provider,
		regions = discovered_rows,
		-- Discovery ACTIVITY for this evaluation, stated cache-independently.
		--
		-- The cache counters are process state: the second identical run legitimately
		-- hits instead of missing, so reporting hits/misses would make two runs of
		-- the same seed serialize differently. What the report needs is how many
		-- regions were enumerated and whether any failed -- both pure functions of
		-- (seed, profile, assets).
		discovery = {
			regions_attempted = #discovery_mod.region_keys(),
			regions_discovered = discovered_count,
			regions_failed = #discovery_errors,
			ran = discovery_ran,
		},
		dedup = dedup.summary( dedup_registry ),
		assets = assets_mod.describe( assets ),
		reward_routing = reward_routing,
		collectibles = collectible_stats,
		missing_capabilities = M.missing_capabilities(),
		scope_exclusions = scope_exclusions,
	}

	if ( options.include_details ~= false ) then
		for i = 1, #provider_details do
			local item = provider_details[ i ]
			local report = item.report
			local base_score_units = report.totals and report.totals.score_units or 0
			local score_units=0
			for _,entry in ipairs(finished.entries)do
				if entry.provider==item.provider and entry.aggregate_region==item.region then score_units=score_units+entry.score_units end
			end
			finished.details.providers[ #finished.details.providers + 1 ] = {
				provider = item.provider,
				region = item.region,
				rule_version = M.RULE_VERSION,
				base_rule_version = report.rule_version,
				base_score_units = base_score_units,
				details_scores_are_base = true,
				coverage_status = report.coverage and report.coverage.status or nil,
				score_units = score_units,
				score = units.to_string( score_units ),
				meta = report.meta,
				details = report.details,
			}
		end
	end

	if ( started ~= nil and clock ~= nil ) then
		-- Diagnostic only; excluded from serialized output.
		finished.timing_ms = ( clock() - started ) * 1000.0
	end

	return finished
end

-- Named capabilities this build does not have, for the report and the runbook.
function M.missing_capabilities()
	local out = {}
	for name, info in pairs( M.MISSING_PROVIDERS ) do
		out[ #out + 1 ] = {
			capability = name,
			category = info.category,
			module = info.module,
			reason = info.reason,
		}
	end
	-- The selected scope excludes natural pools, special containers and unverified
	-- puzzle variants. Exhaustive source auditing was explicitly waived. Remaining
	-- per-seed generation errors and coverage claims stay in the report itself.
	table.sort( out, function( a, b ) return a.capability < b.capability end )
	return out
end

-- Convenience: evaluate from a raw snapshot table.
function M.evaluate_snapshot( seed, snapshot, options )
	local profile, errors = profile_lib.new( snapshot or {} )
	if ( profile == nil ) then
		local failed = report_lib.new( {
			seed = seed, profile_id = "invalid", profile_identity = "invalid",
			rule_version = M.RULE_VERSION,
		} )
		for _, err in ipairs( errors or {} ) do
			failed:error( err.code, err.message )
		end
		for _, category in ipairs( M.REQUIRED_CATEGORIES ) do
			failed:claim( category, report_lib.COVERAGE_UNSUPPORTED, "invalid profile" )
		end
		return failed:finish()
	end
	return M.evaluate( seed, profile, options )
end

M.UNITS_PER_POINT = units.UNITS_PER_POINT

-- Live entry: capture NEW_GAME-scoped choices once; offline evaluate stays pure.
function M.from_game(seed,profile,options,api)
 local settings=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_settings.lua")
 return M.evaluate(seed,profile,settings.evaluation_options(api,options))
end

return M
