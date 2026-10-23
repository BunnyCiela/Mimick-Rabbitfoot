-- Explicit local diagnostic only: compare the implemented evaluator across
-- runtimes. Partial coverage never becomes a valid candidate or full benchmark.
local M={}
local serialize=dofile_once("mods/interesting_seed_filter/files/isf/core/serialize.lua")
function M.conditions(profile)
 local lib=dofile_once("mods/interesting_seed_filter/files/isf/adapters/profile.lua")
 local cal={};for _,k in ipairs({"year","month","day","jussi","mammi"})do cal[k]=profile.calendar[k]end
 return {calendar=cal,unlocked_flags=lib.flags(profile.unlocked_flags),persistent_flags=lib.flags(profile.persistent_flags)}
end
function M.project(report)
 local entries={};local puzzle={};local coverage={}
 for _,e in ipairs(report.entries or {})do
  local row={}
  for _,k in ipairs({"id","provider","rule_id","category","biome","spell_id","object_id","score_units","base_score_units","decay_rank","always_cast_id"})do row[k]=e[k]end
  entries[#entries+1]=row
  if e.provider=="puzzle_wands"then puzzle[#puzzle+1]=row end
 end
 local text=serialize.render_json(entries);local a,b,rolling=1,0,0
 for i=1,#text do local n=text:byte(i);a=(a+n)%65521;b=(b+a)%65521;rolling=(rolling*31+n)%4294967296 end
 for k,v in pairs(report.coverage.categories or {})do coverage[k]=v.status end
 return {entry_count=#entries,entry_digest=string.format("%d:%08x:%08x",#text,b*65536+a,rolling),
  totals={score_units=report.totals.score_units,base_score_units=report.totals.base_score_units},
  coverage_complete=report.coverage.complete,coverage_status=report.coverage.status,categories=coverage,
  rule_version=report.rule_version,error_count=#(report.errors or {}),puzzle_wands=puzzle}
end
function M.run(h,seed,run)
 local record={run_id=run,seed=seed,frame=h.GameGetFrameNum(),scope="implemented partial evaluator only; not a complete validated scan or distribution sample"}
 local started=h.GameGetRealWorldTimeSinceStarted and h.GameGetRealWorldTimeSinceStarted()
 local originals={};local attempts={}
 for _,name in ipairs({"SetWorldSeed","SetRandomSeed","Random","Randomf","RandomDistribution","RandomDistributionf","GetRandomAction","GetRandomActionWithType","ProceduralRandom","ProceduralRandomf","ProceduralRandomi","AddFlagPersistent","RemoveFlagPersistent","EntityLoad","EntityKill","EntitySetTransform","GameCreateParticle","GlobalsSetValue"})do
  if type(h[name])=="function"then
   originals[name]=h[name]
   h[name]=function()attempts[#attempts+1]=name;error("evaluation attempted native mutation/random: "..name)end
  end
 end
 local ok,value=pcall(function()
  local profile=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_profile.lua").build({api=h})
  assert(profile,"native profile unavailable")
  record.generation_conditions=M.conditions(profile)
  local assets=dofile_once("mods/interesting_seed_filter/files/isf/adapters/game_assets.lua").build()
  return M.project(dofile_once("mods/interesting_seed_filter/files/isf/core/evaluate.lua").evaluate(seed,profile,{assets=assets}))
 end)
 for name,fn in pairs(originals)do h[name]=fn end
 record.native_mutation_attempts=attempts;record.status=ok and #attempts==0 and "observed" or "failed"
 if ok then record.projection=value else record.error=tostring(value)end
 if started then record.elapsed_seconds=h.GameGetRealWorldTimeSinceStarted()-started end
 local stored=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_EVALUATION_PARITY",record,h)
 return record,stored
end
return M
