-- Optional wrapper for a disposable native run. Observe the exact init-entry
-- transform before the original vanilla function seeds its RNG. Never rerun init.
local M={}
local function pack(...)return {n=select("#",...),...}end
function M.wrap(generator,original,host)
  assert(type(original)=="function","container init function required")
  host=host or _G
  return function(entity_id,...)
    local audit,input
    pcall(function()
      local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(host)
      if not session.enabled then return end
      local x,y=host.EntityGetTransform(entity_id)
      local evidence=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua")
      local date={}
      if type(host.GameGetDateAndTimeLocal)=="function" then
        local year,month,day,hour,minute,second,jussi,mammi=host.GameGetDateAndTimeLocal()
        date={year=year,month=month,day=day,hour=hour,minute=minute,second=second,jussi=jussi,mammi=mammi}
      end
      input={
        capture_kind="runtime_init_entry_observation",run_id=session.run_id,
        generator=generator,entity_id=entity_id,x=x,y=y,coordinate_frame="init_entity_transform",calendar=date,
      }
      evidence.emit("ISF_CONTAINER_INIT",input,host)
      if session.capture_results==true then
        audit=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/generation_result.lua")
      end
    end)
    if not audit then return original(entity_id,...) end
    local results=pack(original(entity_id,...))
    pcall(audit.container,host,input)
    return unpack(results,1,results.n)
  end
end
return M
