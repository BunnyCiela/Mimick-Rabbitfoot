-- Opt-in performance baseline for the CURRENT evaluator, including partial
-- coverage. Never selects a seed or promotes a report to a valid candidate.
local M={}
local PREFIX="mods/interesting_seed_filter/"
local function runtime(h)
 local out={lua_version=h._VERSION,jit_status="unavailable"}
 if type(h.jit)=="table"then
  out.jit_version=h.jit.version
  if type(h.jit.status)=="function"then
   local ok,enabled=pcall(h.jit.status)
   if ok then out.jit_status=enabled and "enabled"or "disabled"end
  end
 end
 return out
end
local mutations={"SetWorldSeed","SetRandomSeed","Random","Randomf","RandomDistribution","RandomDistributionf",
 "GetRandomAction","GetRandomActionWithType","ProceduralRandom","ProceduralRandomf","ProceduralRandomi",
 "AddFlagPersistent","RemoveFlagPersistent","EntityLoad","EntityKill","EntitySetTransform","GameCreateParticle","GlobalsSetValue"}
local function guarded(h,fn)
 local originals,attempts={},{}
 for _,name in ipairs(mutations)do
  if type(h[name])=="function"then
   originals[name]=h[name]
   h[name]=function()attempts[#attempts+1]=name;error("benchmark attempted native mutation/random: "..name)end
  end
 end
 local ok,result=pcall(fn)
 for name,original in pairs(originals)do h[name]=original end
 return ok,result,attempts
end
local function memory(h)
 if type(h.collectgarbage)~="function"then return nil end
 local ok,kb=pcall(h.collectgarbage,"count")
 if ok and type(kb)=="number"then return kb end
end
function M.new(spec,run,h,deps)
 assert(type(spec)=="table"and type(spec.trials)=="table"and #spec.trials>=3 and #spec.trials<=250,"bounded benchmark plan required")
 for i,q in ipairs(spec.trials)do
  assert(type(q.seed)=="number"and q.seed==math.floor(q.seed)and q.seed>=1 and q.seed<=2147483647,"bad benchmark seed")
  assert(q.phase=="cold"or q.phase=="cached_repeat"or q.phase=="different_seed","bad benchmark phase")
  assert((i==1)==(q.phase=="cold"),"exactly one first-use cold trial required")
 end
 assert(type(h.GameGetRealWorldTimeSinceStarted)=="function","wall clock unavailable")
 deps=deps or {}
 local state={index=1,done=false,failed=false,rows={},run_id=run,runtime=runtime(h)}
 local clock=h.GameGetRealWorldTimeSinceStarted
 local emit=deps.emit or function(tag,row)return dofile_once(PREFIX.."tools/foundation/diagnostics/evidence.lua").emit(tag,row,h)end
 function state:tick()
  if self.done then return true end
  local q=spec.trials[self.index]
  local row={run_id=run,index=self.index,seed=q.seed,phase=q.phase,heap_before_kb=memory(h),native_mutation_attempts={}}
  local started=clock();self.started=self.started or started
  local ok,report,attempts=guarded(h,function()
   if self.evaluator==nil then
    local began=clock()
    self.profile=(deps.profile_build or function()return dofile_once(PREFIX.."files/isf/adapters/game_profile.lua").build({api=h})end)()
    assert(self.profile,"benchmark profile unavailable")
    row.profile_build_seconds=clock()-began
    began=clock()
    self.assets=(deps.assets_build or function()return dofile_once(PREFIX.."files/isf/adapters/game_assets.lua").build()end)()
    assert(self.assets,"benchmark assets unavailable")
    row.assets_build_seconds=clock()-began
    self.evaluator=deps.evaluator or dofile_once(PREFIX.."files/isf/core/evaluate.lua")
    self.discovery=deps.discovery or dofile_once(PREFIX.."files/isf/core/discovery.lua")
   end
   row.cache_before=self.discovery.stats()
   local began=clock()
   local value=self.evaluator.evaluate(q.seed,self.profile,{assets=self.assets})
   row.evaluate_seconds=clock()-began
   return value
  end)
  row.elapsed_seconds=clock()-started
  row.heap_after_kb=memory(h);row.native_mutation_attempts=attempts
  row.cache_after=self.discovery and self.discovery.stats()or nil
  if ok and type(report)=="table"then
   -- Validation/serialization is deliberately outside the evaluation timer.
   local began=clock()
   local projected,value=pcall(deps.project or dofile_once(PREFIX.."tools/foundation/diagnostics/evaluation_capture.lua").project,report)
   if projected then row.projection=value else row.validation_error=tostring(value)end
   row.discovery=report.details and report.details.discovery
   row.validation_seconds=clock()-began
   row.status=projected and row.discovery and row.discovery.regions_discovered==5 and #attempts==0 and "measured"or "invalid_workload"
  else row.status="failed";row.error=tostring(report)end
  if row.status~="measured"then self.failed=true end
  self.rows[#self.rows+1]=row
  if not emit("ISF_PERFORMANCE_SAMPLE",row)then self.failed=true;self.done=true;self.status="storage_failed";return true end
  self.index=self.index+1
  if self.index>#spec.trials or self.failed then
   self.done=true;self.status=self.failed and "failed"or "complete"
   local conditions={}
   if self.profile then conditions=(deps.conditions or dofile_once(PREFIX.."tools/foundation/diagnostics/evaluation_capture.lua").conditions)(self.profile)end
   self.summary={run_id=run,status=self.status,count=#self.rows,runtime=self.runtime,generation_conditions=conditions,
    batch_wall_seconds=clock()-self.started,heap_end_kb=memory(h),cache=self.discovery and self.discovery.stats(),
    scope="current five-region evaluator baseline; coverage may remain partial; not formal complete-filter performance or score distribution",
    timed_work="evaluate(seed, frozen_profile, {assets=shared_assets}); first-use profile/assets/module setup recorded separately; projection/storage/render frames excluded from evaluate_seconds"}
   if not emit("ISF_PERFORMANCE_COMPLETE",self.summary)then self.status="storage_failed"end
   return true
  end
  if self.index%10==0 and type(h.GamePrint)=="function"then h.GamePrint("ISF speed test: "..#self.rows.."/"..#spec.trials)end
  return false
 end
 return state
end
return M
