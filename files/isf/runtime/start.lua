-- Synchronous pre-generation search: no world, entity or RNG mutations until
-- one accepted report has reached the requested gate. No hidden time-out gate.
local context=dofile_once('mods/interesting_seed_filter/files/isf/adapters/start_context.lua')
local M={}
function M.run(api,deps)
 deps=deps or {};local ctx,why=(deps.context or context.capture)(api)
 if not ctx then return {state='unsupported_context',reason=why}end
 if ctx.continue_save then return {state='skipped_continue'}end
 -- Continuing a save must not even load the predictor or PNG byte bundle.
 local settings=dofile_once('mods/interesting_seed_filter/files/isf/adapters/game_settings.lua')
 local game_profile=dofile_once('mods/interesting_seed_filter/files/isf/adapters/game_profile.lua')
 local profile_lib=dofile_once('mods/interesting_seed_filter/files/isf/adapters/profile.lua')
 local game_assets=dofile_once('mods/interesting_seed_filter/files/isf/adapters/game_assets.lua')
 local evaluate=dofile_once('mods/interesting_seed_filter/files/isf/core/evaluate.lua')
 local filter=dofile_once('mods/interesting_seed_filter/files/isf/core/filter.lua')
 local policy=dofile_once('mods/interesting_seed_filter/files/isf/core/practical_validation.lua')
 local binding=dofile_once('mods/interesting_seed_filter/files/isf/core/calibration_binding.lua')
 local calibration=dofile_once('mods/interesting_seed_filter/files/isf/data/luck_calibration.lua')
 local selected_settings=(deps.settings or settings.capture)(api)
 local actual,diagnostics=(deps.profile or game_profile.build)({api=api})
 if not actual or(diagnostics and #(diagnostics.missing_readers or {})>0)then return {state='error',reason='generation_profile_unavailable'}end
 local gate,problem=(deps.bind or binding.resolve)(deps.calibration or calibration,actual,selected_settings)
 if not gate then return {state='configuration_required',reason=problem}end
 if type(api.SetWorldSeed)~='function'then return {state='error',reason='seed_api_unavailable'}end
 local assets=(deps.assets or game_assets.build)()
 if not assets or not assets.content_identity then return {state='error',reason='assets_unavailable'}end
 local clock=type(api.GameGetRealWorldTimeSinceStarted)=='function'and api.GameGetRealWorldTimeSinceStarted or(os and os.clock)
 if type(clock)~='function'then return {state='error',reason='clock_unavailable'}end
 -- Stay within SetWorldSeed's documented signed-int domain. Local Park-Miller
 -- arithmetic is exact in Lua doubles and leaves the engine's RNG untouched.
 local initial=type(api.StatsGetValue)=='function'and tonumber(api.StatsGetValue('world_seed'))or nil
 local state=math.floor(math.abs(initial or clock()*1000000))%2147483646+1
 local next_seed=deps.next_seed or function()state=(state*16807)%2147483647;return state end
 local runner=filter.new({threshold_units=gate.threshold_units,profile_identity=profile_lib.identity(actual),rule_version='2.0',coverage_identity=gate.coverage_identity,
  scoring_depth_identity=gate.scoring_depth_identity,validation_policy=policy.ID,asset_identity=assets.content_identity,clock=clock,next_seed=next_seed,
  evaluate=deps.evaluate or function(seed)return evaluate.evaluate(seed,actual,{assets=assets,search_settings=selected_settings,include_details=false})end})
 local ok,reason=runner.start(ctx);if not ok then return {state=runner.view().state,reason=reason}end
 local last=clock();local view=runner.view()
 while view.state=='searching'do
  if deps.cancelled and deps.cancelled()then runner.cancel();break end
  view=runner.step()
  if api.print and clock()-last>=5 then api.print('[ISF_SEARCH] attempts='..view.attempts..' elapsed_ms='..math.floor(view.elapsed_ms));last=clock()end
 end
 view=runner.view()
 if view.state~='selected'then return view end
 local report=runner.selected_report()
 -- This is the only production seed write, called by the pre-generation hook.
 api.SetWorldSeed(report.seed)
 view.state='committed';view.selected_seed=report.seed
 view.score_units=report.totals.score_units;view.profile_identity=report.profile_identity
 view.reference_profile_identity=gate.reference_profile_identity
 view.search_settings=selected_settings
 view.generation_profile={id=actual.id,game_version=actual.game_version,
  unlocked_flags=profile_lib.flags(actual.unlocked_flags),persistent_flags=profile_lib.flags(actual.persistent_flags),calendar=profile_lib.flags(actual.calendar)}
 view.validation_policy=policy.ID
 view.coverage_identity=report.meta.coverage_identity
 view.asset_identity=report.meta.asset_identity
 return view
end
return M
