-- Pure candidate lifecycle. Selecting a report never changes the running world.
local M = {}
local units=dofile_once("mods/interesting_seed_filter/files/isf/core/units.lua")
local preferences=dofile_once("mods/interesting_seed_filter/files/isf/core/preferences.lua")
local luck=dofile_once("mods/interesting_seed_filter/files/isf/core/luck.lua")
local practical=dofile_once("mods/interesting_seed_filter/files/isf/core/practical_validation.lua")
local function integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<math.huge end
function M.new(config)
  config=config or {}
  local s={state="idle",attempts=0,rejected=0,elapsed_ms=0,selected=nil,reason=nil}
  local api={}
  local threshold=config.threshold_units
  local identity=config.profile_identity
  local rule=config.rule_version
  local function score(n)
    if rule=="2.0" then return units.is_score_units(n) end
    return integer(n)
  end
  local coverage_id=config.coverage_identity
  local configuration_error
  local scoring_depth_identity=config.scoring_depth_identity
  if config.search_settings~=nil then
    scoring_depth_identity=preferences.score_identity(config.search_settings)
    threshold,configuration_error=luck.resolve(config.calibration,config.search_settings,{
      profile_identity=identity,rule_version=rule,coverage_identity=coverage_id,
      scoring_depth_identity=scoring_depth_identity,
    })
  end
  if config.validation_policy~=nil and config.validation_policy~=practical.ID then configuration_error="unknown_validation_policy"end
  local clock=config.clock
  local started=nil
  local function update_time()
    if started and clock then s.elapsed_ms=math.max(0,(clock()-started)*1000) end
  end
  function api.view()
    update_time()
    return {state=s.state,attempts=s.attempts,rejected=s.rejected,elapsed_ms=s.elapsed_ms,
      score_units=s.score_units,selected_seed=s.selected and s.selected.seed,reason=s.reason}
  end
  function api.start(context)
    if s.state~="idle" then return false,"already started" end
    context=context or {}
    if context.continue_save==true then s.state="skipped_continue"; return false,s.state end
    if context.new_game~=true or context.mode~="normal" or context.ng_plus~=0 then
      s.state="unsupported_context"; return false,s.state
    end
    if configuration_error then
      s.state="configuration_required";s.reason=configuration_error;return false,s.reason
    end
    if not score(threshold) or type(identity)~="string" or identity=="" or type(rule)~="string"
      or type(coverage_id)~="string" or coverage_id=="" or type(config.evaluate)~="function"
      or type(config.next_seed)~="function" then
      s.state="configuration_required"; s.reason="explicit threshold, fixed conditions, coverage and candidate source are required"
      return false,s.reason
    end
    s.state="searching"; started=clock and clock() or nil; return true
  end
  function api.cancel()
    if s.state=="searching" or s.state=="selected" then
      s.state="cancelled"; s.selected=nil; update_time(); return true
    end
    return false
  end
  function api.step()
    if s.state~="searching" then return api.view() end
    local ok,seed=pcall(config.next_seed)
    if not ok or not integer(seed) or seed>4294967295 then
      s.state="error";s.reason="candidate source failed or exhausted";return api.view()
    end
    s.attempts=s.attempts+1
    local success,r=pcall(config.evaluate,seed)
    if not success or type(r)~="table" then s.state="error";s.reason="evaluation failed";return api.view() end
    if s.state~="searching" then return api.view() end -- cancel during evaluation wins
    local total=r.totals and r.totals.score_units
    if r.seed~=seed or r.profile_identity~=identity or r.rule_version~=rule
      or type(r.meta)~="table" or r.meta.coverage_identity~=coverage_id then
      s.state="error";s.reason="report conditions do not match filter configuration";return api.view()
    end
    if scoring_depth_identity and r.meta.scoring_depth_identity~=scoring_depth_identity then
      s.state="error";s.reason="report exploration depth does not match filter configuration";return api.view()
    end
    if not score(total)then s.state="error";s.reason="invalid total score";return api.view()end
    if config.validation_policy==practical.ID then
      local accepted,why=practical.check(r,config.asset_identity)
      if not accepted then s.state="needs_validation";s.reason=why;return api.view()end
    elseif config.validation_policy~=nil then
      s.state="configuration_required";s.reason="unknown_validation_policy";return api.view()
    elseif not r.coverage or r.coverage.complete~=true or r.coverage.status~="complete"
      or r.meta.native_game_verified~=true or #(r.errors or {})>0 or not score(total) then
      s.state="needs_validation";s.reason="candidate report is incomplete, invalid or lacks native validation";return api.view()
    end
    for _,category in ipairs(config.validation_policy==practical.ID and {}or(config.required_categories or {})) do
      local claim=(r.coverage.categories or {})[category]
      if not claim or claim.status~="complete" then
        s.state="needs_validation";s.reason="required category is incomplete: "..category;return api.view()
      end
    end
    local sum=0
    for _,entry in ipairs(r.entries or {}) do
      if not score(entry.score_units) then s.state="error";s.reason="invalid entry";return api.view() end
      sum=sum+entry.score_units
    end
    if sum~=total then s.state="error";s.reason="entry sum differs from total";return api.view() end
    s.score_units=total
    if total>=threshold then s.state="selected";s.selected=r else s.rejected=s.rejected+1 end
    return api.view()
  end
  function api.selected_report() return s.selected end
  -- The pure state machine never mutates a world. The runtime host commits
  -- selected_report only at the pre-generation boundary.
  return api
end
return M
