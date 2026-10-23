local filter=T.load("mods/interesting_seed_filter/files/isf/core/filter.lua")
local batch=T.load("mods/interesting_seed_filter/files/isf/core/batch.lua")
local function report(seed,units)
 return {seed=seed,profile_identity="p",rule_version="r",meta={coverage_identity="c",native_game_verified=true},
  totals={score_units=units},entries={{score_units=units}},errors={},coverage={complete=true,status="complete",categories={r={status="complete"}}}}
end
local function config(evaluate)
 local seed=0
 return {threshold_units=20,profile_identity="p",rule_version="r",coverage_identity="c",required_categories={"r"},
  next_seed=function() seed=seed+1;return seed end,evaluate=evaluate or function(seed) return report(seed,seed*10) end}
end
local context={new_game=true,mode="normal",ng_plus=0}
T.describe("filter rejects then selects at exact inclusive threshold")
local f=filter.new(config())
T.check(f.start(context),"explicit configuration starts")
T.equal(f.step().state,"searching","first under-threshold report is rejected")
T.equal(f.step().state,"selected","inclusive threshold selects second report")
T.equal(f.view().attempts,2,"two candidates evaluated")
T.equal(f.view().rejected,1,"one rejected")
T.equal(f.selected_report().seed,2,"selected seed matches report")
f.step();T.equal(f.view().attempts,2,"selection does not re-evaluate or create a world")
T.check(f.cancel(),"cancel invalidates pending selection")
T.check(f.selected_report()==nil,"cancel retains no accepted world")

T.describe("filter blocks continue, partial, errors and mismatched conditions")
local calls=0
f=filter.new(config(function(seed) calls=calls+1;return report(seed,100) end))
T.check(not f.start({continue_save=true}),"continuing a save skips filter")
f.step();T.equal(calls,0,"continue path never evaluates")
for _,change in ipairs({
 function(r) r.coverage.complete=false end,
 function(r) r.meta.native_game_verified=false end,
 function(r) r.coverage.categories.r.status="partial" end,
 function(r) r.errors={{code="failed"}} end,
}) do
 f=filter.new(config(function(seed) local r=report(seed,100);change(r);return r end))
 f.start(context);T.equal(f.step().state,"needs_validation","incomplete/unverified report never enters world")
end
f=filter.new(config(function(seed) local r=report(seed,100);r.profile_identity="other";return r end))
f.start(context);T.equal(f.step().state,"error","profile mismatch is fatal")
f=filter.new(config(function() error("injected evaluator failure") end))
f.start(context);T.equal(f.step().state,"error","evaluator failure is explicit")
f=filter.new({});T.check(not f.start(context),"no implicit percentile or threshold default")
f=filter.new(config(function(seed) f.cancel();return report(seed,100) end))
f.start(context);T.equal(f.step().state,"cancelled","cancellation during evaluation wins")

T.describe("batch timing measures evaluator and setup separately on a synthetic clock")
local t=0
local b=batch.run({seeds={1,2},conditions={source="synthetic",mode="cold"},clock=function()return t end,
 setup=function() t=t+.1;return "context" end,
 evaluate=function(seed,ctx) T.equal(ctx,"context","setup context passed");t=t+.02;return report(seed,4) end})
T.equal(b.completed,2,"explicit list evaluated exactly once")
T.check(math.abs(b.setup_ms-100)<.001,"setup timing retained")
T.check(math.abs(b.rows[1].elapsed_ms-20)<.001,"whole evaluator latency retained")
T.check(math.abs(b.elapsed_ms-140)<.001,"total includes setup and scheduling")

T.describe("rule2 filter accepts exact decayed units and preserves inclusive thresholds")
local c=config(function(seed)local r=report(seed,15.5);r.rule_version="2.0";return r end)
c.rule_version="2.0";c.threshold_units=15.5
local half=filter.new(c)
T.check(half.start(context),"fractional final threshold is valid in rule2")
T.equal(half.step().state,"selected","3.875-point result reaches exact threshold")
