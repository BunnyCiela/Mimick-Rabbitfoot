-- Explicit full-evaluator timing harness. Never runs on module load.
local M={}
function M.run(options)
  assert(type(options)=="table" and type(options.seeds)=="table","explicit seed list required")
  assert(type(options.evaluate)=="function" and type(options.clock)=="function","evaluator and monotonic clock required")
  assert(type(options.conditions)=="table","record build/device/Lua/coverage/cold-warm conditions")
  local t0=options.clock()
  local context=options.setup and options.setup() or nil
  local setup_ms=(options.clock()-t0)*1000
  local rows={}
  for _,seed in ipairs(options.seeds) do
    if options.cancelled and options.cancelled() then break end
    local start=options.clock()
    local ok,report=pcall(options.evaluate,seed,context)
    local elapsed=(options.clock()-start)*1000
    rows[#rows+1]={seed=seed,elapsed_ms=elapsed,report=ok and report or nil,error=not ok and tostring(report) or nil}
  end
  return {conditions=options.conditions,setup_ms=setup_ms,elapsed_ms=(options.clock()-t0)*1000,
    requested=#options.seeds,completed=#rows,cancelled=#rows<#options.seeds,rows=rows}
end
return M
