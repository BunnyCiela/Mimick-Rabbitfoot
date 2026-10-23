-- Normal games search synchronously at the official pre-generation hook.
-- Explicit diagnostic sessions keep their existing fixed-seed test path.
local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(_G,true)
local function text(key,args)
  return dofile_once("mods/interesting_seed_filter/files/isf/i18n.lua").text(key,args)
end
local fixed_seed,seed_applied
local startup_attempted,startup_result,startup_notice
local rabbit_charm
local function appearance()
  -- Load only during play, never in the synchronous seed search or menu.
  if type(EntityGetWithTag)~="function"or type(EntityGetHotspot)~="function"then return end
  if not rabbit_charm then
    rabbit_charm=dofile_once("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_foot.lua").new(_G)
  end
  return rabbit_charm
end
local rabbit_error
local function update_appearance(method,...)
  if rabbit_error then return end
  local ok,reason=pcall(function(...)
    local charm=appearance()
    if charm then charm[method](...)end
  end,...)
  if not ok then
    rabbit_error=true
    if type(print)=="function"then print("[ISF_RABBIT] "..tostring(reason))end
  end
end
if not session.enabled then
  function OnMagicNumbersAndWorldSeedInitialized()
    if startup_attempted then return end
    startup_attempted=true
    local ok,result=pcall(function()
      return dofile_once("mods/interesting_seed_filter/files/isf/runtime/start.lua").run(_G)
    end)
    startup_result=ok and result or {state="error",reason=tostring(result)}
    if type(print)=="function"then
      print("[ISF_START] state="..tostring(startup_result.state).." seed="..tostring(startup_result.selected_seed).." attempts="..tostring(startup_result.attempts).." reason="..tostring(startup_result.reason))
    end
  end
end
if session.enabled and type(ModDoesFileExist)=="function"
    and ModDoesFileExist("mods/interesting_seed_filter/.scratch/interesting-seed-filter/native-fixed-seed.txt") then
  fixed_seed=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/fixed_test_seed.lua").resolve(_G,session)
  if fixed_seed then
    -- Vanilla's example lists this hook as the world-seed initialization point.
    -- Do not enter an old save while this explicit test marker is armed.
    function OnMagicNumbersAndWorldSeedInitialized()
      if not seed_applied then SetWorldSeed(fixed_seed);seed_applied=true end
    end
  end
end
if session.enabled and type(session.run_id)=="string" and session.run_id~="" then
  print("[ISF_SESSION] "..session.run_id.." environment="..session.environment)
  if session.capture_initializers and type(ModLuaFileAppend)=="function" then
    if session.capture_results then
      local puzzle=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/puzzle_probe.lua")
      if puzzle.resolve(_G,session) then
        for _,source in ipairs({"receptacle_oil","receptacle_steam","receptacle_water","oiltank_puzzle_check","swing_puzzle_target","teleport_meditation_cube","teleport_snowcave_buried_eye","teleport_meditation_cube_return_used","teleport_liquid_check"})do
          ModLuaFileAppend("data/scripts/buildings/"..source..".lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_puzzle.lua")
        end
      end
      local trace=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/biome_trace.lua")
      local trace_cfg=trace.resolve(_G,session)
      if trace_cfg then
        ModLuaFileAppend("data/scripts/biomes/"..trace_cfg.biome..".lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_coalmine.lua")
      end
      ModLuaFileAppend("data/scripts/items/chest_random.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_chest.lua")
      ModLuaFileAppend("data/scripts/items/chest_random_super.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_chest.lua")
      ModLuaFileAppend("data/scripts/items/generate_shop_item.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_shop.lua")
      ModLuaFileAppend("data/scripts/gun/procedural/level_1_wand.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_wand_premade.lua")
    end
    ModLuaFileAppend("data/scripts/items/potion.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_potion_init.lua")
    ModLuaFileAppend("data/scripts/items/powder_stash.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_pouch_init.lua")
    ModLuaFileAppend("data/scripts/items/potion_secret.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_secret_init.lua")
    ModLuaFileAppend("data/scripts/gun/procedural/gun_procedural.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_wand_normal.lua")
    ModLuaFileAppend("data/scripts/gun/procedural/gun_procedural_better.lua","mods/interesting_seed_filter/tools/foundation/diagnostics/capture_wand_better.lua")
  end
  dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/init_probe.lua")
end

-- Usually no-op. Also removes our own saved callback on the next load after
-- protection is disarmed; no other components are touched.
function OnPlayerSpawned(entity)
  local selection=startup_result and startup_result.search_settings
  update_appearance("spawned",entity,selection and selection.luck_level)
  if not session.enabled and not startup_notice then
    startup_notice=true
    local result=startup_result
    local prior=type(GlobalsGetValue)=="function"and GlobalsGetValue("interesting_seed_filter.start_failed","")or ""
    if prior~=""then result={state="error",reason=prior}end
    if result and result.state=="committed"then
      if type(StatsGetValue)=="function"then
        local ok,seed=pcall(StatsGetValue,"world_seed")
        if ok then result.observed_world_seed=tonumber(seed)end
      end
      if type(GlobalsSetValue)=="function"then GlobalsSetValue("interesting_seed_filter.run_seed",tostring(result.selected_seed))end
      dofile_once("mods/interesting_seed_filter/files/isf/runtime/result.lua").write(_G,result)
      if type(GamePrint)=="function"then GamePrint(text("success",{seed=result.selected_seed,attempts=result.attempts}))end
    elseif result and result.state=="unsupported_context"then
      if type(GamePrint)=="function"then GamePrint(text("unsupported"))end
    elseif result and result.state~="skipped_continue"and result.state~="unsupported_context"then
      -- A failure must not silently become a playable fallback candidate.
      if prior==""then dofile_once("mods/interesting_seed_filter/files/isf/runtime/result.lua").write(_G,result)end
      if type(GlobalsSetValue)=="function"then GlobalsSetValue("interesting_seed_filter.start_failed","1")end
      if type(EntityGetComponentIncludingDisabled)=="function"and type(EntitySetComponentIsEnabled)=="function"then
        for _,component in ipairs(EntityGetComponentIncludingDisabled(entity,"ControlsComponent")or {})do EntitySetComponentIsEnabled(entity,component,false)end
      end
      if type(GamePrintImportant)=="function"then
        local message=text(result.state=="configuration_required"and"no_calibration"or"prediction_failed")
        GamePrintImportant(text("failed_title"),message.." "..text("return_menu"))
      end
    end
  end
  if fixed_seed then
    dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_FIXED_TEST_SEED",{
      run_id=session.run_id,requested_seed=fixed_seed,seed_api_called=seed_applied==true})
  end
  local enabled=session.enabled==true and session.protect_player==true
  local existing=type(EntityGetComponentIncludingDisabled)=="function"
    and EntityGetComponentIncludingDisabled(entity,"LuaComponent","isf_test_health_lock") or {}
  if not enabled and #existing==0 then return end
  local protection=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/player_protection.lua")
  local ok,result=pcall(protection.sync,entity,enabled,_G)
  if session.enabled then
    dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_PLAYER_PROTECTION",{
      run_id=session.run_id,entity_id=entity,requested=enabled,result=ok and result or tostring(result)})
  end
  if enabled and type(GamePrint)=="function" then
    GamePrint(text(ok and result.enabled and "health_on" or "health_failed"))
  end
end

function OnWorldPostUpdate()
  update_appearance("update")
end
