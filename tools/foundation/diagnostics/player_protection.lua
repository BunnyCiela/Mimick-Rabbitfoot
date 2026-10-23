-- Test-only player component management. No generation/RNG/unlock writers.
-- Independent implementation using Noita's damage callback, as Spell Lab does.
local M={TAG="isf_test_health_lock",SCRIPT="mods/interesting_seed_filter/tools/foundation/diagnostics/player_no_damage.lua"}
function M.damage(amount,critical,enabled)
  if enabled==true and type(amount)=="number" and amount>0 then return 0,critical end
  return amount,critical
end
function M.sync(entity,enabled,host)
  host=host or _G
  if type(entity)~="number" or entity<=0 then return {enabled=false,status="invalid_player"} end
  if type(host.EntityGetComponentIncludingDisabled)~="function" or type(host.ComponentGetValue2)~="function" then
    return {enabled=false,status="component_readers_unavailable"}
  end
  local tagged=host.EntityGetComponentIncludingDisabled(entity,"LuaComponent",M.TAG) or {}
  local owned={}
  for _,id in ipairs(tagged) do
    if host.ComponentGetValue2(id,"script_damage_about_to_be_received")==M.SCRIPT then owned[#owned+1]=id end
  end
  local keep=enabled==true and owned[1] or nil
  local removed=0
  for _,id in ipairs(owned) do
    if id~=keep then
      if type(host.EntityRemoveComponent)~="function" then return {enabled=false,status="cleanup_unavailable"} end
      host.EntityRemoveComponent(entity,id);removed=removed+1
    end
  end
  if enabled~=true then return {enabled=false,status="inactive",removed=removed} end
  if not keep then
    if type(host.EntityAddComponent2)~="function" then return {enabled=false,status="component_writer_unavailable"} end
    keep=host.EntityAddComponent2(entity,"LuaComponent",{_tags=M.TAG,execute_every_n_frame=-1,
      script_damage_about_to_be_received=M.SCRIPT})
    if not keep or keep==0 then return {enabled=false,status="install_failed"} end
  end
  return {enabled=true,status="active",component_id=keep,removed=removed}
end
return M
