-- files/isf/providers/wild_wands.lua
--
-- Wild-wand provider. Predicts where natural wands are in a region and scores
-- them per PRD R1 (wand body + Always Cast + discounted in-wand normal spells).
--
-- Two DIFFERENT things are covered, and they are reported SEPARATELY:
--
--   coverage.categories["wild.wands.discovery"]
--       Does this module enumerate the region from a seed+profile alone? With the
--       full map pipeline (tile postprocessing + spawn scan + nested pixel
--       scenes) this is `complete` for the biome it covered. It stays
--       `unsupported` when a caller supplies placements instead, because then
--       nothing about the seed was discovered.
--
--   coverage.categories["wild.wands.known_placement"]
--       Were all objects (supplied or discovered) scored under R1? `complete`
--       whenever every object was scored, regardless of how it was found.
--
-- The OVERALL report is only `complete` when BOTH are complete. A report built
-- from externally supplied placements therefore stays `partial`: it proves R1
-- arithmetic on known objects, NOT that those objects exist in the seed.
--
-- Native-game parity is unverified for every claim here.
--
-- Lua 5.1 / LuaJIT compatible; no FFI, no external process.

local prng = dofile_once( "mods/interesting_seed_filter/files/isf/random/prng.lua" )
if ( type( prng ) ~= "table" ) then
	error( "wild_wands: files/isf/random/prng.lua did not return a table" )
end

local spells = dofile_once( "mods/interesting_seed_filter/files/isf/data/spells.lua" )
if ( type( spells ) ~= "table" ) then
	error( "wild_wands: files/isf/data/spells.lua did not return a table" )
end

local spell_score = dofile_once( "mods/interesting_seed_filter/files/isf/core/spell_score.lua" )
local units = dofile_once( "mods/interesting_seed_filter/files/isf/core/units.lua" )
local report_mod = dofile_once( "mods/interesting_seed_filter/files/isf/core/report.lua" )
local wand_cfg = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/data/wand_config.lua" )
local spell_select = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/spell_select.lua" )
local wand_gen = dofile_once( "mods/interesting_seed_filter/files/isf/worldgen/wand_gen.lua" )

local M = {}

M.SCHEMA_VERSION = 1
M.RULE_VERSION = "1.0"

M.CATEGORY_DISCOVERY = "wild.wands.discovery"
M.CATEGORY_KNOWN = "wild.wands.known_placement"

-- PRD R1 reward tiers, in score_units (4 units = 1 point).
M.WAND_BODY_UNITS = units.points( 1 )            -- +1
M.ALWAYS_CAST_UNITS = units.points( 5 )          -- +5
M.ALWAYS_CAST_VIGOUR_UNITS = units.points( 100 ) -- +100 more
M.ALWAYS_CAST_VIGOUR_SPELL = "REGENERATION_FIELD"

-- Regions where the wand BODY and Always Cast bonuses apply (PRD R1 / section 2).
local BODY_BONUS_BIOMES = {
	Mines = true,
	["Collapsed Mines"] = true,
	["Coal Pits"] = true,
}

-- Regions where R1 in-wand discounted spells are scored at all.
local WAND_SPELL_BIOMES = {
	Mines = true,
	["Collapsed Mines"] = true,
	["Coal Pits"] = true,
	["Fungal Caverns"] = true,
}

-- Display name -> upstream biome key.
-- Snowy Depths is deliberately ABSENT. It IS discoverable through
-- files/isf/worldgen/discover.lua, but PRD section 2 gives it no wild-wand body,
-- no in-wand spell share, no chest and no R5 item, so this provider refuses the
-- region instead of producing placements it would then have to score as zero.
local BIOME_KEYS = {
	Mines = "coalmine",
	["Collapsed Mines"] = "coalmine_alt",
	["Coal Pits"] = "excavationsite",
	["Fungal Caverns"] = "fungicave",
}
M.BIOME_KEYS = BIOME_KEYS

-- ---------------------------------------------------------------------------
-- Unlock state
-- ---------------------------------------------------------------------------

-- The unlock check comes from the generation-condition snapshot; providers never
-- read the live save.
--
-- `unlocked_flags` may either list flags explicitly or set ALL_UNLOCKED = true for
-- the fully-completed baseline the wand oracle fixtures use.
local function make_unlock_fn( profile )
	local flags = {}
	if ( profile ~= nil ) then
		-- profile.flags(profile.unlocked_flags) copies the flag MAP. Passing the
		-- profile itself would copy its top-level keys (id, game_version, ...),
		-- which is why ALL_UNLOCKED has to be read from the nested map.
		local ok, copy = pcall( function()
			local profile_lib = dofile_once( "mods/interesting_seed_filter/files/isf/adapters/profile.lua" )
			return profile_lib.flags( profile.unlocked_flags )
		end )
		if ( ok and type( copy ) == "table" ) then
			flags = copy
		else
			local raw = profile.unlocked_flags
			if ( type( raw ) == "table" ) then
				for k, v in pairs( raw ) do flags[ k ] = v end
			end
		end
	end
	local all_unlocked = flags.ALL_UNLOCKED == true

	return function( spell_id )
		local entry = spells.by_id[ spell_id ]
		if ( entry == nil ) then
			return false
		end
		if ( entry.requires_flag == nil ) then
			return true
		end
		if ( all_unlocked ) then
			return true
		end
		return flags[ entry.requires_flag ] == true
	end
end

local function configure( profile )
	local unlocked = make_unlock_fn( profile )
	spell_select.init( {
		prng_new = prng.new,
		pool = spells.pool,
		spell_types = wand_cfg.spell_types,
		type_by_id = wand_cfg.spell_type_by_id,
		is_unlocked = unlocked,
	} )
	wand_gen.init( {
		prng_new = prng.new,
		wand_config = wand_cfg,
		spell_select = spell_select,
		is_unlocked = unlocked,
	} )
	return unlocked
end

M.configure = configure

-- ---------------------------------------------------------------------------
-- R1 scoring
-- ---------------------------------------------------------------------------

-- Scores one generated wand under PRD R1.
function M.score_wand( wand, biome, source_id, wand_index )
	local entries = {}
	local total = 0
	local prefix = string.format( "%s/wand%d", source_id, wand_index or 1 )

	local function add( suffix, category, rule_id, score_units, reason, extra )
		if ( score_units <= 0 ) then
			return
		end
		local entry = {
			id = prefix .. "/" .. suffix,
			rule_id = rule_id,
			category = category,
			biome = biome,
			source_id = source_id,
			x = wand.x,
			y = wand.y,
			score_units = score_units,
			reason = reason,
		}
		if ( extra ) then
			for k, v in pairs( extra ) do
				entry[ k ] = v
			end
		end
		entries[ #entries + 1 ] = entry
		total = total + score_units
	end

	if ( BODY_BONUS_BIOMES[ biome ] ) then
		add( "body", "wild_wands", "R1", M.WAND_BODY_UNITS,
			"natural wand body in " .. biome,
			{ wand_type = wand.wand_type, wand_name = wand.name } )

		local always = wand.always_casts or {}
		if ( #always > 0 ) then
			add( "always_cast", "wild_wands", "R1", M.ALWAYS_CAST_UNITS,
				"wand has an Always Cast", { always_cast_id = always[ 1 ] } )
			for i = 1, #always do
				if ( always[ i ] == M.ALWAYS_CAST_VIGOUR_SPELL ) then
					add( "always_cast_vigour", "wild_wands", "R1",
						M.ALWAYS_CAST_VIGOUR_UNITS,
						"Always Cast is Circle of Vigour",
						{ always_cast_id = always[ i ] } )
				end
			end
		end
	end

	-- R1 in-wand NORMAL spells at the wild 1/4 rate. Always Cast is a wand
	-- property and must never be routed through spell_score.
	if ( WAND_SPELL_BIOMES[ biome ] ) then
		local cards = wand.cards or {}
		for slot = 1, #cards do
			local spell_id = cards[ slot ]
			local spell_units = spell_score.score_spell( spell_id,
				spell_score.CONTEXT_WILD_WAND )
			if ( spell_units > 0 ) then
				add( "card" .. slot, "wild_wand_spells", "R1", spell_units,
					"in-wand target spell " .. spell_id .. " at 1/4 value",
					{ spell_id = spell_id, slot = slot } )
			end
		end
	end

	return { entries = entries, score_units = total, wand = wand }
end

-- ---------------------------------------------------------------------------
-- Discovery (seed -> placements)
-- ---------------------------------------------------------------------------
--
-- The tile + scene + spawn pipeline itself lives in the NEUTRAL module
-- files/isf/worldgen/discover.lua. That module knows nothing about R1 scoring,
-- which is what lets Snowy Depths be discoverable for puzzles without this
-- provider ever growing a Snowy R1 score. This provider only:
--   1. restricts the biome set to the R1 regions,
--   2. keeps the wand-producing records out of the scan result, and
--   3. reports the discovery/known-placement coverage split.
--
-- `discover_biome` keeps its exact old signature and return shape so existing
-- consumers (chests, tools, tests) do not change.

-- Set to true once a real discovery run has completed in this session. Used only
-- for diagnostics; never to claim coverage for a different seed.
local discovery_proven = false

-- biome_scripts.spawn_wands calls spawn(g_items,x-5,y,0,0), then
-- director_helpers.spawn adds (5,5). The lottery uses the marker frame;
-- procedural content uses the resulting EntityLoadCameraBound transform.
-- Trap wands use direct EntityLoad(x,y), without this offset. Legacy supplied
-- placements without a spawn_kind continue to specify initialization positions.
function M.init_transform(spot)
	if type(spot.gen_x)=="number" and type(spot.gen_y)=="number" then return spot.gen_x,spot.gen_y end
	local kind=spot.spawn_kind
	local offset=(kind=="wild_wand" or kind=="altar_wand" or kind=="scene_wand") and 5 or 0
	return spot.world_x,spot.world_y+offset
end

-- The neutral discovery module, loaded lazily so a caller that only needs R1
-- arithmetic on supplied placements never pays for it.
local discover_mod = nil

-- Drop the cached discovery stack. Tests call this between cases; production
-- callers use it when the asset set changes (e.g. a different game version).
function M.reset_discovery()
	if ( discover_mod ~= nil ) then
		discover_mod.reset()
	end
end

local function get_discover_mod()
	if ( discover_mod == nil ) then
		discover_mod = dofile_once(
			"mods/interesting_seed_filter/files/isf/worldgen/discover.lua" )
		if ( type( discover_mod ) ~= "table" ) then
			error( "wild_wands: files/isf/worldgen/discover.lua did not return a table" )
		end
	end
	return discover_mod
end

-- Which wang tilesets must be present for a biome to be discoverable.
local function required_wang( assets, biome_key )
	if ( type( assets ) ~= "table" or type( assets.wang ) ~= "table" ) then
		return false
	end
	return assets.wang[ biome_key ] ~= nil
end

-- Discovers wild wand sources in ONE biome from a seed + profile.
-- Returns { wands, records, ... } or nil + reason.
--
-- R1 regions only: Snowy Depths is discoverable through
-- files/isf/worldgen/discover.lua, not here (see BIOME_KEYS above).
function M.discover_biome( seed, profile, biome, assets, ng_plus, region_index, shared_region )
	local biome_key = BIOME_KEYS[ biome ]
	if ( biome_key == nil ) then
		return nil, "unknown R1 biome " .. tostring( biome )
	end

	if ( required_wang( assets, biome_key ) == false ) then
		return nil, "assets.wang." .. biome_key .. " is required for discovery"
	end

	local discover = get_discover_mod()

	configure( profile )

	local region, reason = shared_region, nil
	if region == nil then region, reason = discover.region( seed, profile, biome_key, assets, {
		ng_plus = ng_plus or 0,
		region_index = region_index,
		-- The layer is part of this entry point's long-standing return value.
		with_layer = true,
	} ) end
	if ( region == nil ) then
		return nil, reason
	end

	-- Only VERIFIED GENERATED wands from the two wand-producing mechanisms this
	-- provider scores: trap wands (a wand inside terrain) and wild wand drops
	-- (spawn_wands / the altar scene's own spawn_wands marker). Wand traps,
	-- chests, potions and generic scene markers are deliberately excluded: they
	-- are not wild wands.
	local wands = {}
	for _, group in ipairs( { region.trap_wands, region.wild_wands } ) do
		for _, rec in ipairs( group ) do
			if ( rec.generated == true and rec.wand_type ~= nil ) then
				local gen_x,gen_y=M.init_transform(rec)
				wands[ #wands + 1 ] = {
					source_id = rec.source_id,
					object_id = rec.object_id,
					biome = biome,
					biome_key = biome_key,
					world_x = rec.world_x,
					world_y = rec.world_y,
					gen_x = gen_x, gen_y = gen_y,
					spawn_kind = rec.spawn_kind,
					wand_type = rec.wand_type,
					generated = true,
					scene_name = rec.scene_name,
					gate = rec.gate,
				}
			end
		end
	end

	discovery_proven = true

	return {
		wands = wands,
		records = region.records,
		scenes_placed = region.scenes_placed,
		layer = region.layer,
		biome_key = biome_key,
		spawn_pixel_count = region.spawn_pixel_count,
		scene_marker_count = region.scene_marker_count,
		record_count = region.record_count,
		potential_count = region.potential_count,
		wand_altar_count = #region.wand_altars,
		trap_wand_count = #region.trap_wands,
		wild_wand_count = #region.wild_wands,
		extra_rerolls = region.extra_rerolls,
		note = "tile pipeline + spawn scan + nested pixel scenes complete for "
			.. biome_key .. " at NG" .. tostring( ng_plus or 0 ),
	}
end

-- ---------------------------------------------------------------------------
-- Placement normalisation
-- ---------------------------------------------------------------------------

local function normalize_placement( spot, index )
	if ( type( spot ) ~= "table" ) then
		return nil, "placement entry " .. index .. " is not a table"
	end
	local x = spot.world_x or spot.x
	local y = spot.world_y or spot.y
	if ( type( x ) ~= "number" or type( y ) ~= "number" ) then
		return nil, "placement entry " .. index .. " needs numeric x/world_x and y/world_y"
	end
	return {
		world_x = x,
		world_y = y,
		gen_x = spot.gen_x, gen_y = spot.gen_y,
		wand_type = spot.wand_type,
		source_id = spot.source_id,
		object_id = spot.object_id,
		biome = spot.biome,
		spawn_kind = spot.spawn_kind,
		generated = spot.generated,
	}
end

-- ---------------------------------------------------------------------------
-- evaluate
-- ---------------------------------------------------------------------------

-- evaluate( seed, profile, options ) -> report (schema_version = 1)
--
-- options:
--   biome      -- "Mines" | "Collapsed Mines" | ... (default "Mines")
--   ng_plus    -- NG+ count (default 0; only 0 is supported)
--   assets     -- { biome_map, wang = { coalmine }, overlay, scene_image(fn) }
--                 required for real discovery
--   placement  -- OPTIONAL explicit objects to score INSTEAD of discovering.
--                 Using this makes discovery `unsupported` and the overall
--                 report `partial`, because the seed was not enumerated.
function M.evaluate( seed, profile, options )
	options = options or {}
	local biome = options.biome or "Mines"
	local ng_plus = options.ng_plus or 0

	local report = report_mod.new( {
		seed = seed,
		profile_id = profile and profile.id or nil,
		rule_version = M.RULE_VERSION,
		meta = {
			provider = "wild_wands",
			biome = biome,
			generator = "files/isf/worldgen/wand_gen.lua",
			prng = "files/isf/random/prng.lua",
			ng_plus = ng_plus,
			discovery = "not attempted",
			native_game_verified = false,
		},
		notes = {
			"R1 scoring and Mines discovery are SEPARATE coverage claims.",
			"native/game parity is NOT verified for any result here.",
			"a supplied-placement report proves R1 arithmetic, not object presence",
		},
	} )

	local outside = ( not BODY_BONUS_BIOMES[ biome ] ) and ( not WAND_SPELL_BIOMES[ biome ] )
	if ( outside ) then
		report:claim( M.CATEGORY_DISCOVERY, report_mod.COVERAGE_UNSUPPORTED,
			"biome " .. tostring( biome ) .. " is outside the R1 scoring regions" )
		report:claim( M.CATEGORY_KNOWN, report_mod.COVERAGE_UNSUPPORTED,
			"biome " .. tostring( biome ) .. " is outside the R1 scoring regions" )
		report.coverage.complete = false
		return report:finish()
	end

	configure( profile )

	local wands = {}
	local discovery_status, discovery_reason

	if ( options.placement ~= nil ) then
		-- Explicit placements: score them, but do NOT claim the seed was
		-- enumerated. This path previously reported overall `complete`, which
		-- overstated what was actually known.
		local normalized = {}
		for i = 1, #options.placement do
			local spot, err = normalize_placement( options.placement[ i ], i )
			if ( spot == nil ) then
				report:error( "bad_placement", err )
			else
				normalized[ #normalized + 1 ] = spot
			end
		end
		wands = normalized
		discovery_status = report_mod.COVERAGE_UNSUPPORTED
		discovery_reason = "placements were supplied by the caller; the seed/region "
			.. "was not enumerated, so object PRESENCE is unproven"
		report.meta.discovery = "supplied placements (presence unproven)"
	else
		local discovered, err = M.discover_biome( seed, profile, biome, options.assets, ng_plus, options.region_index, options.scan )
		if ( discovered == nil ) then
			discovery_status = report_mod.COVERAGE_UNSUPPORTED
			discovery_reason = tostring( err )
			report:error( "wand_discovery_unavailable", tostring( err ) )
			report.meta.discovery = "unavailable: " .. tostring( err )
		else
			wands = discovered.wands
			discovery_status = report_mod.COVERAGE_COMPLETE
			discovery_reason = discovered.note
			report.meta.discovery = "mines pipeline"
			report.meta.spawn_pixel_count = discovered.spawn_pixel_count
			report.meta.scene_marker_count = discovered.scene_marker_count
			report.meta.extra_rerolls = discovered.extra_rerolls
		end
	end

	report:claim( M.CATEGORY_DISCOVERY, discovery_status, discovery_reason )

	-- Deduplicate physical wand views before scoring all their attributes.
	local unique,seen={},{}
	local dedup=dofile_once("mods/interesting_seed_filter/files/isf/core/dedup.lua")
	for _,spot in ipairs(wands) do
		local id=spot.object_id or spot.source_id
		local accepted=true
		if id and options.object_registry then
			accepted=dedup.claim(options.object_registry,{object_id=id,kind="wand"},{owner="wild_wands",id=id})
		elseif id then accepted=not seen[id];seen[id]=true end
		if accepted then unique[#unique+1]=spot else report:warning("duplicate_wand","physical wand already counted: "..tostring(id)) end
	end
	wands=unique
	-- Score every known wand.
	local scored = 0
	local scored_all = true
	for i = 1, #wands do
		local spot = wands[ i ]
		local wand_type = spot.wand_type
		if ( wand_type == nil ) then
			wand_type = wand_gen.get_wand_type( seed, ng_plus, spot.world_x, spot.world_y,
				BIOME_KEYS[ biome ] )
		end

		if ( wand_type == nil ) then
			report:warning( "no_wand_type",
				string.format( "no wand type resolved at (%s, %s)",
					tostring( spot.world_x ), tostring( spot.world_y ) ) )
			scored_all = false
		else
			local gen_x,gen_y=M.init_transform(spot)
			local wand, err = wand_gen.generate( seed, ng_plus, wand_type,
				gen_x, gen_y, { no_more_shuffle = false } )
			if ( wand == nil ) then
				report:error( "wand_generation_failed",
					string.format( "(%s, %s): %s", tostring( spot.world_x ),
						tostring( spot.world_y ), tostring( err ) ) )
				scored_all = false
			else
				local source_id = spot.source_id
					or string.format( "%s/%d,%d", BIOME_KEYS[ biome ] or biome,
						spot.world_x, spot.world_y )
				local result = M.score_wand( wand, biome, source_id, i )
				for _, entry in ipairs( result.entries ) do
					entry.object_id=spot.object_id or spot.source_id
					report:add( entry )
				end
				scored = scored + 1
			end
		end
	end

	if ( scored_all ) then
		report:claim( M.CATEGORY_KNOWN, report_mod.COVERAGE_COMPLETE,
			"scored every supplied/discovered wand under R1" )
	else
		report:claim( M.CATEGORY_KNOWN, report_mod.COVERAGE_PARTIAL,
			"some objects could not be scored (see errors/warnings)" )
	end

	report.meta.wands_scored = scored
	report.meta.wands_found = #wands

	-- Overall complete ONLY when both sub-claims are complete.
	local cats = report.coverage.categories
	local discovery_cat = cats[ M.CATEGORY_DISCOVERY ]
	local known_cat = cats[ M.CATEGORY_KNOWN ]
	local all_complete = discovery_cat ~= nil and known_cat ~= nil
		and discovery_cat.status == report_mod.COVERAGE_COMPLETE
		and known_cat.status == report_mod.COVERAGE_COMPLETE
		and #report.errors == 0

	report.coverage.complete = all_complete

	return report:finish()
end

-- True only when a real (non-supplied) discovery run has completed this session.
function M.discovery_has_run()
	return discovery_proven
end

return M
