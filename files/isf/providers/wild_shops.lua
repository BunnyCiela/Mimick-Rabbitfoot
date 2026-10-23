-- files/isf/providers/wild_shops.lua
--
-- ISF-08 provider: PRD R4 wild spell shops in Mines, Coal Pits and Snowy Depths.
--
-- THREE SEPARATE COVERAGE CLAIMS, deliberately (same discipline as wild_wands and
-- chests):
--
--   wild.spell_shops.discovery
--       Was the region ENUMERATED from seed + profile? `complete` only when a
--       real worldgen scan result was consumed, every record in it was
--       modelable, AND the caller declared the record set exhaustive.
--       `unsupported` whenever shops were supplied by the caller, because then
--       nothing about the seed was discovered.
--
--   wild.spell_shops.shop_existence
--       Was every candidate shop resolved into a real scene or a conclusive
--       non-shop? `complete` when there were no unmodelable/malformed records.
--
--   wild.spell_shops.shop_contents
--       Was every sale slot's card determined? `partial` as soon as one slot's
--       walk produced no card, and `complete` only when every slot resolved.
--
-- The overall report is only `complete` when ALL THREE are complete and there are
-- no errors. A report built from supplied shops therefore stays `partial`: it
-- proves R4 arithmetic on known objects, NOT that those objects exist in the
-- seed, and NOT that the seed has no other shops.
--
-- Interface (WORKER_CONTRACT.md):
--   evaluate( seed, profile, options ) -> {
--     schema_version = 1, rule_version = "1.0", seed, profile_id,
--     coverage, entries, errors, totals, ...
--   }
--
-- options:
--   region        "Mines" | "Coal Pits" | "Snowy Depths" (default: all three).
--                 A single region only restricts which records are accepted;
--                 it does not change R4 arithmetic.
--   ng_plus       NG+ count (default 0; only 0 is supported/in scope).
--   scan          a worldgen scan result table (read-only). When present the
--                 discovery adapter derives shops from its records.
--   scan_complete boolean (default false). Asserts that `scan.records` is the
--                 region's EXHAUSTIVE spawn record set. Only with worldgen
--                 evidence for that claim; without it the report stays partial.
--   shops         array of explicit shop specs (see shops/validate.lua). Used
--                 for known-shop runs and for tests. Each spec may carry
--                 `slots`; when it does not, the installed scene layout supplies
--                 them, so a known shop still gets every real card.
--   predict_cards boolean (default true): predict each slot's card from the seed
--                 when the slot does not carry an explicit `spell_id`.
--   is_unlocked   function(spell_id) -> boolean override (tests).
--   calendar      passed through untouched (shop cards have no calendar
--                 dependence; kept for report symmetry with other providers).
--
-- Native-game parity is unverified for every claim here. Everything is offline.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process, no game globals.

local prng = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
if ( type( prng ) ~= "table" ) then
	error( "wild_shops: files/isf/random/prng.lua did not return a table" )
end

local shops_data = dofile_once( "mods/interesting_seed_filter/files/isf/data/shops.lua" )
if ( type( shops_data ) ~= "table" ) then
	error( "wild_shops: files/isf/data/shops.lua did not return a table" )
end

local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
local report_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
local validate = dofile_once( "mods/interesting_seed_filter/files/isf/shops/validate.lua" )
local discovery = dofile_once( "mods/interesting_seed_filter/files/isf/shops/discovery.lua" )
local shop_score = dofile_once( "mods/interesting_seed_filter/files/isf/shops/score.lua" )
local predict = dofile_once( "mods/interesting_seed_filter/files/isf/shops/predict.lua" )

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"
M.PROVIDER_ID = "wild_shops"

M.CATEGORY_DISCOVERY = shops_data.CATEGORIES.DISCOVERY
M.CATEGORY_EXISTENCE = shops_data.CATEGORIES.EXISTENCE
M.CATEGORY_CONTENTS = shops_data.CATEGORIES.CONTENTS
M.CATEGORY_AGGREGATE = shops_data.CATEGORIES.AGGREGATE

M.CATEGORIES = {
	M.CATEGORY_DISCOVERY,
	M.CATEGORY_EXISTENCE,
	M.CATEGORY_CONTENTS,
}

M.ERRORS = {
	bad_seed = "seed is not an integer in [0, 2^32-1]",
	bad_profile = "profile is not a normalized snapshot table",
	unknown_region = "region is not a documented R4 wild spell shop region",
	ng_plus_unsupported = "NG+ shop prediction is not implemented (only NG0)",
	bad_shops = "options.shops is not an array",
	bad_scan = "options.scan is not a worldgen scan result table",
	shop_invalid = "one or more shop specs failed validation",
	shop_errors = "one or more shop scenes could not be fully scored",
	scan_unavailable = "no worldgen scan result was supplied",
	discovery_partial = "the scan result contains records this adapter cannot model",
	prediction_unavailable = "card prediction could not be configured for this profile",
	out_of_region = "a shop record is outside the requested region",
}

M.WARNINGS = {
	invalid_shop = "a shop spec failed validation (details attached)",
	excluded_shop = "a shop record is in a region PRD R4 excludes",
	duplicate_scene = "another shop record already scored the same physical scene",
	duplicate_slot = "another record already scored the same physical sale slot",
	slot_unresolved = "a shop slot's card was not determined",
	non_target_card = "a sold card is not a PRD target",
	scan_unavailable = "no worldgen scan result was supplied, so shop presence is unproven",
	discovery_partial = "the scan result contains records this adapter cannot model",
	scan_exhaustiveness_undeclared = "the scan set's exhaustiveness was not declared",
	contents_predicted = "cards were predicted from the seed, not observed in game",
	out_of_region = "a shop record is outside the requested region",
}

local DEFAULT_OPTIONS = {
	ng_plus = 0,
	predict_cards = true,
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
-- Generation conditions
-------------------------------------------------------------------------------

-- The unlock predicate is built by wild_wands.configure (via shops/predict), so
-- shop cards obey exactly the same snapshot as every other spell-content path.
-- This fallback is only for callers that inject their own `is_unlocked`.
local function make_unlock_fn( profile )
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
				if ( flags[ k ] == nil ) then flags[ k ] = v end
			end
		end
	end
	local all_unlocked = flags.ALL_UNLOCKED == true
	return function( spell_id )
		if ( type( spell_id ) ~= "string" ) then return false end
		if ( all_unlocked ) then return true end
		return flags[ spell_id ] == true
	end
end

-------------------------------------------------------------------------------
-- evaluate
-------------------------------------------------------------------------------

function M.evaluate( seed, profile, options )
	local resolved = merge_options( options )

	local report = report_mod.new( {
		seed = seed,
		profile_id = ( type( profile ) == "table" and profile.id ) or "invalid",
		profile_identity = ( type( profile ) == "table" and profile_lib.identity( profile ) )
			or "invalid",
		rule_version = M.RULE_VERSION,
		notes = {
			"scope: main world NG0, normal mode, no perks picked (PRD section 2)",
			"R4.1 each real wild spell shop SCENE +5, once, however many slots it has",
			"R4.2 each target card sold: full G10/G20/G50 wild-direct value",
			"R4.3 the same card at two real slots accumulates; one slot is counted once",
			"R4.4 Collapsed Mines / Fungal Caverns / Holy Mountain shops are not R4",
			"card contents come from the vanilla generate_shop_item chain, not upstream",
			"discovery, shop existence and shop contents are separate coverage claims",
			"native/game parity is NOT verified for any result here",
		},
		meta = {
			provider = M.PROVIDER_ID,
			schema_version = M.SCHEMA_VERSION,
			data = {
				game_version_hash = shops_data.GAME_VERSION_HASH,
				regions = shops_data.REGION_ORDER,
				shop_spawn_function = shops_data.SHOP_SPAWN_FUNCTION,
				shop_marker_color = string.format( "0x%06x", shops_data.SHOP_MARKER_COLOR ),
			},
			options = {
				region = resolved.region or "all R4 regions",
				ng_plus = resolved.ng_plus,
				predict_cards = resolved.predict_cards == true,
				shops_supplied = type( resolved.shops ) == "table" and #resolved.shops or 0,
				scan_supplied = type( resolved.scan ) == "table",
				scan_complete = resolved.scan_complete == true,
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
	if ( resolved.region ~= nil and type( resolved.region ) ~= "string" ) then
		report:error( "unknown_region", M.ERRORS.unknown_region )
		input_ok = false
	elseif ( resolved.region ~= nil ) then
		local region = shops_data.region( resolved.region )
		if ( region == nil ) then
			report:error( "unknown_region", M.ERRORS.unknown_region .. ": "
				.. tostring( resolved.region ) )
			input_ok = false
		end
	end
	if ( resolved.ng_plus ~= nil and resolved.ng_plus ~= 0 ) then
		report:error( "ng_plus_unsupported", M.ERRORS.ng_plus_unsupported
			.. " (got " .. tostring( resolved.ng_plus ) .. ")" )
		input_ok = false
	end
	if ( resolved.shops ~= nil and type( resolved.shops ) ~= "table" ) then
		report:error( "bad_shops", M.ERRORS.bad_shops )
		input_ok = false
	end
	if ( resolved.scan ~= nil and type( resolved.scan ) ~= "table" ) then
		report:error( "bad_scan", M.ERRORS.bad_scan )
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

	-- ---- generation conditions -------------------------------------------
	-- The weighted walk must be wired before any slot is predicted, whichever
	-- form the caller's snapshot takes. An injected predicate goes through the
	-- same shared selector as a profile does, so exactly one implementation of
	-- the walk exists in the project.
	local unlock_fn = resolved.is_unlocked
	if ( type( unlock_fn ) == "function" ) then
		local wired, why = predict.configure_predicate( unlock_fn )
		if ( wired == nil ) then
			report:warning( "prediction_unavailable",
				M.ERRORS.prediction_unavailable .. ": " .. tostring( why ) )
		end
	else
		local configured, why = predict.configure( profile )
		if ( configured ~= nil ) then
			unlock_fn = configured
		else
			report:warning( "prediction_unavailable",
				M.ERRORS.prediction_unavailable .. ": " .. tostring( why )
					.. "; cards will be reported as unresolved" )
			unlock_fn = make_unlock_fn( profile )
		end
	end

	-- ---- discovery --------------------------------------------------------
	local discovery_status, discovery_reason
	local discovered = {}
	local adapter = nil

	if ( type( resolved.scan ) == "table" ) then
		adapter = discovery.discover( resolved.scan, {
			region = resolved.region,
			is_unlocked = unlock_fn,
		} )
		discovered = adapter.shops
		report.meta.discovery = "worldgen scan records"
		report.meta.scan_examined = adapter.examined
		report.meta.scan_rejected = #adapter.rejected
		report.meta.scan_unsupported = #adapter.unsupported
		report.meta.scan_out_of_region = #adapter.out_of_region
		report.meta.scan_placements = #adapter.placements
		report.meta.enumeration_evidence = adapter.evidence
		report.meta.enumeration_proven = adapter.enumeration_proven
		report.meta.enumeration_gaps = adapter.gaps

		-- Discovery completeness is decided by EVIDENCE, never by a caller
		-- boolean. Two things can carry it:
		--   * placement records for every shop scene the report knows about, or
		--   * a validated, non-contradicted capability declaration.
		-- The legacy `scan_complete` option is still accepted for interface
		-- compatibility but it can no longer promote the claim: a declaration is
		-- not evidence. It is surfaced as a warning when it disagrees.
		if ( adapter.enumeration_proven and adapter.complete ) then
			discovery_status = report_mod.COVERAGE_COMPLETE
			discovery_reason = string.format(
				"enumeration proven by %s: all %d scan records were modelable "
					.. "(%d shop scene(s), %d slot(s)) and every shop scene carries "
					.. "placement evidence",
				adapter.evidence, adapter.examined, #adapter.shops,
				M.count_slots( adapter.shops ) )
		else
			discovery_status = report_mod.COVERAGE_PARTIAL
			discovery_reason = string.format(
				"shop presence and absence are not proven: %s",
				table.concat( adapter.gaps, "; " ) )
			report:warning( "enumeration_unproven", discovery_reason )
			if ( resolved.scan_complete == true ) then
				report:warning( "scan_complete_ignored",
					"scan_complete = true was supplied but is not evidence; the report "
						.. "stays partial until the worldgen result carries placement "
						.. "records or a capability declaration" )
			end
			if ( not adapter.complete ) then
				report:warning( "discovery_partial", string.format(
					"scan result is not fully modelable: %s",
					table.concat( adapter.reasons, "; " ) ) )
			end
		end

		for i = 1, #adapter.out_of_region do
			report:warning( "out_of_region", adapter.out_of_region[ i ].reason )
		end
		report.meta.scan_rejected_reasons = {}
		for i = 1, #adapter.rejected do
			report.meta.scan_rejected_reasons[ i ] = adapter.rejected[ i ].reason
		end
		report.meta.scan_unsupported_reasons = {}
		for i = 1, #adapter.unsupported do
			report.meta.scan_unsupported_reasons[ i ] = adapter.unsupported[ i ].reason
		end
		report.meta.scan_invalid_reasons = {}
		for i = 1, #adapter.invalid do
			report.meta.scan_invalid_reasons[ i ] = adapter.invalid[ i ].reason
		end
	else
		discovery_status = report_mod.COVERAGE_UNSUPPORTED
		discovery_reason = M.ERRORS.scan_unavailable
			.. "; shop presence is unproven for this seed/region"
		report:warning( "scan_unavailable", discovery_reason )
	end

	-- ---- shop set ---------------------------------------------------------
	local normalized = {}
	local invalid_count = 0
	local excluded_count = 0
	local out_of_region_count = 0
	local seen_scenes = {}

	local function add_shop( raw, origin )
		local shop, errors, fatal = validate.validate_scene( raw, { origin = origin } )
		if ( shop == nil ) then
			local excluded = false
			for _, err in ipairs( errors or {} ) do
				if ( err.code == "excluded_region" ) then
					excluded = true
					excluded_count = excluded_count + 1
					report:warning( "excluded_shop", err.message )
				else
					invalid_count = invalid_count + 1
					report:warning( "invalid_shop", tostring(
						( type( raw ) == "table" and raw.id ) or origin ) .. ": "
						.. err.code .. " (" .. err.message .. ")" )
				end
			end
			if ( not excluded and ( errors == nil or #errors == 0 ) ) then
				invalid_count = invalid_count + 1
				report:warning( "invalid_shop", tostring( origin ) .. ": failed validation" )
			end
			return
		end
		local identity = shop.object_id
		if ( seen_scenes[ identity ] ~= nil ) then
			report:warning( "duplicate_scene",
				"shop scene " .. tostring( identity ) .. " was already supplied; "
					.. "the score layer will not count it twice" )
			-- Deliberately still appended: the score layer's registry decides,
			-- so "supplied twice" is exercised through the same path as
			-- "discovered twice" instead of being special-cased here.
		end
		seen_scenes[ identity ] = true
		normalized[ #normalized + 1 ] = shop
	end

	for i = 1, #( resolved.shops or {} ) do
		add_shop( resolved.shops[ i ], "supplied" )
	end
	for i = 1, #discovered do
		add_shop( discovered[ i ], "discovered" )
	end

	-- ---- slot resolution and scoring -------------------------------------
	local registry = shop_score.new_registry()
	local counts = {
		shops = 0,
		scored_shops = 0,
		slots = 0,
		scored_slots = 0,
		target_cards = 0,
		non_target_cards = 0,
		unresolved_slots = 0,
		deduplicated_scenes = 0,
		deduplicated_slots = 0,
		shop_errors = 0,
		out_of_scope = 0,
		invalid = 0,
		excluded = 0,
	}
	local unresolved = {}
	local all_card_entries = {}

	for index = 1, #normalized do
		local shop = normalized[ index ]
		counts.shops = counts.shops + 1

		-- Slot resolution. If the record came from the discovery adapter it
		-- already carries real slot records. If it came from a caller that only
		-- knows the scene, the installed layout supplies every real slot, so a
		-- known shop still gets its full card set instead of a silent zero.
		if ( shop.slots == nil or #shop.slots == 0 ) then
			local layout_slots, why = validate.layout_slots( shop )
			if ( layout_slots == nil ) then
				report:error( "shop_errors", string.format(
					"shop %s at (%s, %s) has no slot records and its installed layout "
						.. "could not be resolved: %s", tostring( shop.scene_name ),
					tostring( shop.scene_x ), tostring( shop.scene_y ), tostring( why ) ) )
				counts.shop_errors = counts.shop_errors + 1
				unresolved[ #unresolved + 1 ] = shop.object_id
			else
				shop.slots = layout_slots
				shop.slot_source = "installed_layout"
			end
		else
			-- Validate each caller/discovery slot through the same contract so a
			-- mis-framed slot is refused rather than predicted at.
			local validated = {}
			local bad_slots = 0
			for i = 1, #shop.slots do
				local slot, errors = validate.validate_slot( shop, shop.slots[ i ], i )
				if ( slot == nil ) then
					bad_slots = bad_slots + 1
					for _, err in ipairs( errors or {} ) do
						report:error( err.code, err.message )
					end
				else
					-- Preserve the discovery-side object id when present.
					if ( shop.slots[ i ].object_id ~= nil and slot.object_id == nil ) then
						slot.object_id = shop.slots[ i ].object_id
					end
					validated[ #validated + 1 ] = slot
				end
			end
			if ( bad_slots > 0 ) then
				counts.shop_errors = counts.shop_errors + 1
				unresolved[ #unresolved + 1 ] = shop.object_id
			end
			shop.slots = validated
			shop.slot_source = "records"
			local expected = validate.layout_slots(shop)
			local present = {}
			for _, slot in ipairs(validated) do present[tostring(slot.x)..","..tostring(slot.y)] = true end
			local missing = 0
			for _, slot in ipairs(expected or {}) do
				if not present[tostring(slot.x)..","..tostring(slot.y)] then missing = missing + 1 end
			end
			if expected == nil or missing > 0 then
				counts.shop_errors = counts.shop_errors + 1
				report:error("missing_layout_slots", "supplied shop slots omit "..missing.." installed layout slot(s), or layout is unavailable")
			end
		end

		local predictor = nil
		if ( resolved.predict_cards == true ) then
			predictor = function( slot, owning_shop )
				local result, why = predict.predict_slot( seed, owning_shop.level,
					slot.x, slot.y, unlock_fn )
				if ( result == nil ) then
					return nil, why
				end
				if ( not result.resolved ) then
					return nil, result.reason
				end
				return result.spell_id
			end
		end

		local scored = shop_score.score_shop( shop, {
			claimed = registry,
			predict = predictor,
			is_unlocked = unlock_fn,
		} )

		for _, entry in ipairs( scored.entries ) do
			entry.shop_origin = shop.origin
			entry.slot_source = shop.slot_source
			report:add( entry )
		end

		-- Every DETERMINED slot, target or not, for the contents projection. A
		-- non-target card earns nothing but is still evidence about the shop,
		-- and "what did this shop sell" must not silently drop it.
		for _, card in ipairs( scored.cards or {} ) do
			card.scene_name = shop.scene_name
			card.scene_x = shop.scene_x
			card.scene_y = shop.scene_y
			card.biome = shop.region
			card.shop_origin = shop.origin
			card.slot_source = shop.slot_source
			card.shop_object_id = shop.object_id
			all_card_entries[ #all_card_entries + 1 ] = card
		end

		for _, err in ipairs( scored.errors ) do
			-- Duplicate scenes/slots are not errors; they are expected views of
			-- one object, and the score layer reports them as warnings.
			report:error( err.code, err.message )
			counts.shop_errors = counts.shop_errors + 1
			if ( err.code ~= "no_slots" ) then
				unresolved[ #unresolved + 1 ] = shop.object_id
			end
		end
		for _, warn in ipairs( scored.warnings ) do
			if ( warn.code == "duplicate_scene" ) then
				counts.deduplicated_scenes = counts.deduplicated_scenes + 1
			elseif ( warn.code == "duplicate_slot" ) then
				counts.deduplicated_slots = counts.deduplicated_slots + 1
			end
			report:warning( warn.code, warn.message )
		end
		for _, item in ipairs( scored.unresolved ) do
			unresolved[ #unresolved + 1 ] = item.slot_id
		end

		local c = scored.counts
		counts.slots = counts.slots + c.slots
		counts.scored_slots = counts.scored_slots + c.scored_slots
		counts.target_cards = counts.target_cards + c.target_cards
		counts.non_target_cards = counts.non_target_cards + c.non_target_cards
		counts.unresolved_slots = counts.unresolved_slots + c.unresolved_slots
		if ( c.scene_award and c.scene_award > 0 ) then
			counts.scored_shops = counts.scored_shops + 1
		end
	end

	if ( invalid_count > 0 ) then
		counts.invalid = invalid_count
		report:error( "shop_invalid", string.format(
			"%d shop spec(s) failed validation", invalid_count ) )
	end
	counts.excluded = excluded_count
	counts.out_of_scope = out_of_region_count

	-- ---- coverage ---------------------------------------------------------
	if ( #normalized == 0 and type( resolved.shops ) == "table"
		and #resolved.shops > 0 ) then
		-- Every supplied shop was rejected; do not let an empty set look like a
		-- completed examination.
		excluded_count = excluded_count or 0
	end

	if ( counts.shop_errors == 0 and invalid_count == 0 ) then
		report:claim( M.CATEGORY_EXISTENCE, report_mod.COVERAGE_COMPLETE,
			string.format( "resolved all %d known shop scene(s) and every other record "
				.. "conclusively", #normalized ) )
	else
		local reasons = {}
		if ( counts.shop_errors > 0 ) then
			reasons[ #reasons + 1 ] = string.format( "%d shop scene(s) could not be fully "
				.. "scored", counts.shop_errors )
		end
		if ( invalid_count > 0 ) then
			reasons[ #reasons + 1 ] = string.format(
				"%d shop spec(s) failed validation", invalid_count )
		end
		report:claim( M.CATEGORY_EXISTENCE, report_mod.COVERAGE_PARTIAL,
			table.concat( reasons, "; " ) )
	end

	-- Contents coverage: complete only when every slot's card is known. A scene
	-- with zero slot records leaves this partial, never "sold nothing".
	if ( counts.unresolved_slots == 0 and counts.shop_errors == 0 and invalid_count == 0
		and counts.slots > 0 ) then
		report:claim( M.CATEGORY_CONTENTS, report_mod.COVERAGE_COMPLETE,
			string.format( "determined the card at every one of %d sale slot(s)",
				counts.slots ) )
	elseif ( counts.slots == 0 and counts.shop_errors == 0 and invalid_count == 0 ) then
		report:claim( M.CATEGORY_CONTENTS, report_mod.COVERAGE_PARTIAL,
			"no sale slot was present in the examined record set, so card contents "
				.. "are not claimed for this seed" )
	else
		report:claim( M.CATEGORY_CONTENTS, report_mod.COVERAGE_PARTIAL,
			string.format( "%d of %d sale slot(s) could not be determined",
				counts.unresolved_slots, counts.slots ) )
	end

	-- A supplied-shop run never proves discovery, even when the adapter is
	-- available; only a consumed scan result can claim anything about the seed.
	local supplied_only = ( type( resolved.shops ) == "table" and #resolved.shops > 0 )
		and type( resolved.scan ) ~= "table"
	if ( supplied_only ) then
		discovery_status = report_mod.COVERAGE_UNSUPPORTED
		discovery_reason = "shops were supplied by the caller; the seed/region was not "
			.. "enumerated, so shop PRESENCE and ABSENCE are both unproven"
	end
	report:claim( M.CATEGORY_DISCOVERY, discovery_status, discovery_reason )

	report.meta.shops_scored = counts.scored_shops
	report.meta.shops_found = counts.shops

	local finished = report:finish()

	-- Overall completeness requires ALL sub-claims AND no errors.
	local cats = finished.coverage.categories
	local discovery_cat = cats[ M.CATEGORY_DISCOVERY ]
	local existence_cat = cats[ M.CATEGORY_EXISTENCE ]
	local contents_cat = cats[ M.CATEGORY_CONTENTS ]
	local all_complete = discovery_cat ~= nil and existence_cat ~= nil and contents_cat ~= nil
		and discovery_cat.status == report_mod.COVERAGE_COMPLETE
		and existence_cat.status == report_mod.COVERAGE_COMPLETE
		and contents_cat.status == report_mod.COVERAGE_COMPLETE
		and #finished.errors == 0
	if ( all_complete ) then
		finished.coverage.complete = true
		finished.coverage.status = report_mod.COVERAGE_COMPLETE
	end

	-- ---- details (never affects totals) ----------------------------------
	finished.details = {
		summary = counts,
		discovery = {
			implemented = ( type( resolved.scan ) == "table" ),
			status = discovery_status,
			reason = discovery_reason,
			missing = {
				"a per-seed exhaustive shop-scene enumeration claim from the worldgen "
					.. "pipeline (shop scenes are not on tracked_scene_names)",
				"native in-game verification of every card and coordinate",
			},
		},
		unresolved = unresolved,
		projection = nil,
		regions = {},
	}

	-- Per-region projection, so a caller can see "Mines: 1 shop, 15 units".
	for _, name in ipairs( shops_data.REGION_ORDER ) do
		finished.details.regions[ #finished.details.regions + 1 ] = {
			region = name,
			biome_key = shops_data.REGIONS[ name ].biome_key,
			level = shops_data.REGIONS[ name ].level,
		}
	end

	-- Contents projection: which slot sold which card, in report order. This is
	-- the "shop scene vs many spawn_shopitem markers" distinction made visible.
	local projection = {}
	for i = 1, #all_card_entries do
		local entry = all_card_entries[ i ]
		projection[ #projection + 1 ] = {
			region = entry.biome,
			scene_name = entry.scene_name,
			scene_x = entry.scene_x,
			scene_y = entry.scene_y,
			slot_x = entry.x,
			slot_y = entry.y,
			spell_id = entry.spell_id,
			spell_group = entry.spell_group,
			score_units = entry.score_units,
			is_target = entry.is_target == true or ( entry.score_units or 0 ) > 0,
			content_source = entry.content_source,
			slot_source = entry.slot_source,
			shop_origin = entry.shop_origin,
		}
	end
	finished.details.projection = projection

	return finished
end

-- Number of sale slots across a list of shops (diagnostics only).
function M.count_slots( shops )
	local n = 0
	for i = 1, #( shops or {} ) do
		n = n + #( shops[ i ].slots or {} )
	end
	return n
end

function M.empty_details( reason )
	return {
		summary = {
			shops = 0, scored_shops = 0, slots = 0, scored_slots = 0,
			target_cards = 0, non_target_cards = 0, unresolved_slots = 0,
			deduplicated_scenes = 0, deduplicated_slots = 0, shop_errors = 0,
			out_of_scope = 0, invalid = 0, excluded = 0,
		},
		discovery = {
			implemented = false,
			status = report_mod.COVERAGE_UNSUPPORTED,
			reason = reason,
			missing = {},
		},
		unresolved = {},
		projection = {},
		regions = {},
	}
end

-------------------------------------------------------------------------------
-- Pure helpers for tests and for callers that already hold a shop
-------------------------------------------------------------------------------

-- Predict one slot's card without building a report.
function M.predict_slot( seed, region_name, x, y, is_unlocked )
	local region = shops_data.region( region_name )
	if ( region == nil ) then
		return nil, "unknown R4 region " .. tostring( region_name )
	end
	return predict.predict_slot( seed, region.level, x, y, is_unlocked )
end

-- Classify one scan record without running a whole discovery pass.
function M.classify_scan_record( record, opts )
	return discovery.classify_record( record, opts )
end

-- Roll the three sub-claims up into the aggregate evaluator's single
-- `wild.spell_shops` category, without editing the foundation-owned aggregator.
--
--   * any sub-claim unsupported -> "unsupported" + that reason
--   * any sub-claim partial     -> "partial" + the first reason
--   * all complete              -> "complete"
--
-- Because a supplied-shop run always leaves discovery unsupported, and a scan
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
	return report_mod.COVERAGE_COMPLETE, "every shop sub-claim resolved"
end

M.SHOPS_DATA = shops_data
M.SCORE = shop_score
M.DISCOVERY = discovery
M.VALIDATE = validate
M.PREDICT = predict
M.UNITS = units

return M
