-- tools/foundation/diagnostics/init_probe.lua
--
-- ENTRY SCRIPT FOR A FUTURE, EXPLICITLY AUTHORIZED, DISPOSABLE TEST RUN.
--
-- Loaded by the opt-in root init only after all disposable acknowledgement
-- gates pass. It never evaluates a seed automatically. Native behavior of the
-- host's reader, callbacks and UI remains subject to joint testing.

local PROBE_PATH = "mods/interesting_seed_filter/tools/foundation/diagnostics/isf_probe.lua"
local PROBE_FALLBACK = "tools/foundation/diagnostics/isf_probe.lua"

local probe = nil
do
	local ok, loaded = pcall( dofile_once, PROBE_PATH )
	if ( not ok or type( loaded ) ~= "table" ) then
		-- Direct-load path used only by the development harness.
		ok, loaded = pcall( dofile_once, PROBE_FALLBACK )
	end
	if ( ok and type( loaded ) == "table" ) then
		probe = loaded
	end
end

if ( probe == nil ) then
	-- Nothing to do; refuse silently rather than erroring inside the game.
	return
end

-- ---------------------------------------------------------------------------
-- Opt-in resolution
-- ---------------------------------------------------------------------------

-- Reading an environment variable from Lua is intentionally not attempted: Noita
-- does not expose os.getenv to mods. The opt-in is therefore a value the loader
-- must supply. Both mechanisms are explicit and neither is a default-on path.
local ENABLE_TOKEN = "ISF_PROBE_ENABLE_DISPOSABLE_ONLY"

local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(_G,true)
local enabled = session.enabled
local run_id = session.run_id

-- 1. Global set by the reviewer's disposable bootstrap, if any.
if ( type( _G ) == "table" and _G.__isf_probe_opt_in == ENABLE_TOKEN ) then
	enabled = true
	run_id = _G.__isf_probe_run_id
end

-- 2. Mod setting, read only if present. Never written by this file.
if ( not enabled and type( ModSettingGet ) == "function" ) then
	local ok, value = pcall( ModSettingGet, "interesting_seed_filter.probe_opt_in" )
	if ( ok and value == true ) then
		enabled = true
		local okr, id = pcall( ModSettingGet, "interesting_seed_filter.probe_run_id" )
		if ( okr and type( id ) == "string" ) then
			run_id = id
		end
	end
end

if ( not enabled ) then
	-- Default state: completely inert.
	return
end

if ( type( run_id ) ~= "string" or run_id == "" ) then
	-- Refuse to run without an explicit run identifier: records without a run id
	-- cannot be attributed to a session and would be useless as evidence.
	if ( type( GamePrint ) == "function" ) then
		GamePrint( "[isf-probe] refusing to start: no run_id supplied" )
	end
	return
end

-- ---------------------------------------------------------------------------
-- Sink
-- ---------------------------------------------------------------------------

local captured = {}
local evidence=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua")
local hm_capture=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/holy_mountain_capture.lua")
local spatial,spatial_plan,performance
local plan_path="mods/interesting_seed_filter/"..".scratch/interesting-seed-filter/native-spatial-plan.lua"
if session.capture_results and type(ModDoesFileExist)=="function" and ModDoesFileExist(plan_path) then
	local ok,plan=pcall(dofile_once,plan_path)
	if ok and type(plan)=="table" and plan.run_id==run_id then
		local loaded,route=pcall(function()return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/spatial_capture.lua").new(plan,run_id)end)
		if loaded then spatial,spatial_plan=route,plan end
	end
end

local function sink( record )
	captured[ #captured + 1 ] = record
	record.test_environment=session.environment
	print("[ISF_PROBE] "..probe.format(record))
	evidence.emit("ISF_PROBE_JSON",record)
end

local ok, err = probe.configure( {
	enabled = true,
	-- Disposable mode is on purpose: this entry script exists only for a
	-- disposable test run, and enabling it also arms the extra guards.
	disposable_run = true,
	run_id = run_id,
	sink = sink,
} )

if ( not ok ) then
	if ( type( GamePrint ) == "function" ) then
		GamePrint( "[isf-probe] configure failed: " .. tostring( err ) )
	end
	return
end

-- ---------------------------------------------------------------------------
-- Hooks (observation only)
-- ---------------------------------------------------------------------------

-- Flags worth observing: every spell-gating flag plus the persistent markers the
-- adapters care about. Read-only HasFlagPersistent calls.
local function observed_flags()
	local flags = {}
	local ok_spells, spells = pcall( dofile_once,
		"mods/interesting_seed_filter/files/isf/data/spells.lua" )
	if ( ok_spells and type( spells ) == "table" ) then
		for i = 1, #spells.gated_flag_list do
			flags[ #flags + 1 ] = spells.gated_flag_list[ i ]
		end
	end
	flags[ #flags + 1 ] = "biome_0_secret_unlocked"
	flags[ #flags + 1 ] = "TEMPLE_PEACE_WITH_GODS"
	return flags
end

-- Holy Mountain anchors (NG0, main world) and the shop/perk offsets established
-- from the shipped scripts.
local TEMPLES = {
	{ index = 1, x = -32, y = 1410 },
	{ index = 2, x = -32, y = 2946 },
	{ index = 3, x = -32, y = 4994 },
}
local SHOP_OFFSET_X = -299
local SHOP_OFFSET_Y = -15

-- Fires once per world, when the player/world is available.
function OnWorldInitialized()
	if ( not probe.is_enabled() ) then
		return
	end
	-- Observe the saved frame/evidence BEFORE this world's first probe writes.
	if spatial then spatial:observe_world_start(_G)end
	probe.probe_datetime( { scope = "world_initialized" } )
	probe.probe_profile( { scope = "world_initialized", flags = observed_flags() } )
	-- Available without a console: a first-round reader probe only, no scan.
	local ok,result=pcall(ISF_ProbeAssetRead)
	print("[ISF_ASSET_READER] "..tostring(ok and result or "probe failed"))
	evidence.emit("ISF_ASSET_READER",{run_id=run_id,result=ok and result or "probe failed"})
	if not session.protect_player and type(GamePrint)=="function" then GamePrint("ISF: diagnostics recorded") end
end

-- Capture at world initialization only: run-globals do not exist during
-- OnBiomeConfigLoaded, and invoking their API then produces engine error spam.

-- Manual capture trigger. A reviewer calls this from the console once they are
-- standing at a Holy Mountain shop, BEFORE buying anything:
--   ISF_ProbeCaptureHolyMountain(1)
function ISF_ProbeCaptureHolyMountain( index )
	if ( not probe.is_enabled() ) then
		return "probe disabled"
	end
	local temple = TEMPLES[ index or 1 ]
	if ( temple == nil ) then
		return "unknown Holy Mountain index"
	end
	local shop_x = temple.x + SHOP_OFFSET_X
	local shop_y = temple.y + SHOP_OFFSET_Y

	probe.probe_shop_entities( {
		shop_x = shop_x,
		shop_y = shop_y,
		radius = 220,
		label = "hm" .. tostring( temple.index ) .. "_shop",
		scope = "holy_mountain_shop",
	} )
	probe.probe_perk_entities( {
		x = temple.x,
		y = temple.y,
		radius = 180,
		label = "hm" .. tostring( temple.index ) .. "_perks",
		scope = "holy_mountain_perks",
	} )
	return "captured Holy Mountain " .. tostring( temple.index )
end

-- Explicit key press, outside pause menus: capture the current HM before purchases.
function OnWorldPostUpdate()
	if not probe.is_enabled() or type(InputIsKeyJustDown)~="function" then return end
	if spatial then
		local ok,err=pcall(spatial.tick,spatial,_G)
		if not ok then
			evidence.emit("ISF_SPATIAL_ROUTE_ERROR",{run_id=run_id,error=tostring(err)})
			spatial:stop(_G,"failed - save and quit");spatial=nil
		end
	end
	if spatial and spatial.status=="complete - save and quit" and type(spatial_plan.biome_lookup_points)=="table" and not spatial.biomes_captured then
		spatial.biomes_captured=true
		dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/biome_capture.lua").run(_G,spatial_plan.biome_lookup_points,run_id)
	end
	if spatial and spatial.status=="complete - save and quit" and type(spatial_plan.native_evaluation)=="table" then
		local seeds=spatial_plan.native_evaluation
		spatial.eval_index=spatial.eval_index or 1
		local seed=seeds[spatial.eval_index]
		if type(seed)=="number" and seed>=1 and seed<=2147483647 and #seeds<=4 then
			local record,stored=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evaluation_capture.lua").run(_G,seed,run_id)
			spatial.eval_index=spatial.eval_index+1
			if not stored or record.status~="observed" then spatial.eval_index=5 end
			if spatial.eval_index>#seeds then
				local success=stored and record.status=="observed"
				local saved=evidence.emit("ISF_EVALUATION_BATCH_COMPLETE",{run_id=run_id,count=#seeds,status=success and "complete"or "failed"})
				spatial:finish_evaluation(_G,success and saved)
			end
		end
	end
	if spatial and spatial.status=="complete - save and quit"and type(spatial_plan.native_performance)=="table"then
		if not performance or not performance.done then
			local ok,err=pcall(function()
				performance=performance or dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/performance_capture.lua").new(spatial_plan.native_performance,run_id,_G)
				performance:tick()
			end)
			if not ok then
				evidence.emit("ISF_PERFORMANCE_ERROR",{run_id=run_id,error=tostring(err)})
				performance={done=true,status="failed"}
			end
			if performance.done then spatial:finish_evaluation(_G,performance.status=="complete")end
		end
		return
	end
	if not InputIsKeyJustDown(hm_capture.KEY_F8) then return end
	local ok,snapshot,reason=pcall(hm_capture.capture_nearest,_G,run_id)
	local stored=ok and snapshot and evidence.emit("ISF_HM_SNAPSHOT",snapshot)
	if stored then
		local scope="hm"..snapshot.temple_index.."_capture"
		probe.probe_profile({scope=scope,flags=observed_flags()})
		probe.probe_datetime({scope=scope})
	end
	local message=stored and ("ISF: HM"..snapshot.temple_index.." captured") or "ISF: HM capture failed"
	if ok and not snapshot and reason=="enter a Holy Mountain first" then message="ISF: enter a Holy Mountain first" end
	if type(GamePrint)=="function" then GamePrint(message) end
end

-- Full-tuple date probe, callable any time:
--   ISF_ProbeDateTimes()
function ISF_ProbeDateTimes()
	if ( not probe.is_enabled() ) then
		return "probe disabled"
	end
	probe.probe_datetime( { scope = "manual" } )
	return "captured datetimes"
end

-- Dump everything captured so far as formatted text (for a console sweep).
function ISF_ProbeDump()
	if ( not probe.is_enabled() ) then
		return "probe disabled"
	end
	local records = probe.records()
	local out = {}
	for i = 1, #records do
		out[ #out + 1 ] = probe.format( records[ i ] )
	end
	return table.concat( out, "\n" )
end

-- Manual packaged-reader capability check; does not evaluate a candidate.
function ISF_ProbeAssetRead()
	if not probe.is_enabled() then return "probe disabled" end
	local path="mods/interesting_seed_filter/files/isf/worldgen/data/biome_map.png"
	local adapter=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_assets.lua")
	local ok,bytes=pcall(adapter.read,path)
	if not ok or type(bytes)~="string" then return "PNG reader failed" end
	local hex={}
	for i=1,math.min(8,#bytes) do hex[#hex+1]=string.format("%02x",bytes:byte(i)) end
	local image,err=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/png.lua").decode(bytes)
	if not image then return "PNG decode failed: "..tostring(err) end
	return "transport=lua_bytes bytes="..#bytes.." signature="..table.concat(hex).." dimensions="..image.width.."x"..image.height
end

-- Explicit fixed-seed report only. Does not change or replace the current seed.
function ISF_ProbeEvaluate(seed)
	if not probe.is_enabled() then return nil,"probe disabled" end
	local profile,diag=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_profile.lua").build()
	if not profile then return nil,"profile unavailable" end
	local assets=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_assets.lua").build()
	local report=dofile_once("mods/interesting_seed_filter/files/isf/core/evaluate.lua").evaluate(seed,profile,{assets=assets})
	local json=dofile_once("mods/interesting_seed_filter/files/isf/core/serialize.lua").render_json(report)
	print("[ISF_FIXED_REPORT] "..json)
	evidence.emit("ISF_FIXED_REPORT",{run_id=run_id,report=report})
	return report,json,diag
end
