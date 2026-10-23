-- Observe the exact procedural generation entry; leave the vanilla RNG alone.
local M={}
local function pack(...)return {n=select("#",...),...}end
function M.wrap(original,variant,host)
  assert(type(original)=="function","generate_gun required")
  host=host or _G
  return function(cost,level,force_unshuffle,...)
    local audit,input
    pcall(function()
      local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(host)
      if not session.enabled then return end
      local id=host.GetUpdatedEntityID()
      local x,y=host.EntityGetTransform(id)
      local evidence=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua")
      input={
        capture_kind="runtime_generation_entry_observation",variant=variant,
        run_id=session.run_id,entity_id=id,
        x=x,y=y,coordinate_frame="generate_gun_entity_transform",cost=cost,level=level,force_unshuffle=force_unshuffle,
      }
      evidence.emit("ISF_WAND_GENERATION",input,host)
      if session.capture_results==true then
        audit=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/generation_result.lua")
      end
    end)
    if not audit then return original(cost,level,force_unshuffle,...) end
    local results=pack(original(cost,level,force_unshuffle,...))
    pcall(audit.wand,host,input)
    return unpack(results,1,results.n)
  end
end
-- The shipped level_1_wand.lua initializes premade XML wands without invoking
-- generate_gun. Its appended observer runs after do_level1(), before pickup or
-- physics can move the entity. The script does not change its transform, but
-- this remains explicitly a post-init observation, not a wrapped entry call.
function M.observe_premade(host)
 host=host or _G
 local state=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(host)
 if not state.enabled or not state.capture_results then return nil end
 local id=host.GetUpdatedEntityID()
 local x,y=host.EntityGetTransform(id)
 return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/generation_result.lua").wand(host,{
  capture_kind="runtime_premade_post_init_transform_observation",variant="premade_level1",
  coordinate_frame="post_init_entity_transform",run_id=state.run_id,entity_id=id,x=x,y=y})
end
return M
