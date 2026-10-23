-- Opt-in post-init observations. Does not seed RNG, spawn or change an item.
local evidence=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua")
local capture=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/holy_mountain_capture.lua")
local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua")
local M={MARKER=session.MARKER}
local function read(host,name,...)
  if type(host[name])~="function" then return nil end
  local ok,a,b=pcall(host[name],...);if ok then return a,b end
end
function M.enabled(host,run_id)
  if type(run_id)~="string" or run_id=="" then return false end
  local state=session.resolve(host)
  return state.enabled==true and state.capture_results==true and state.run_id==run_id
end
local function component(host,id,kind)
  return read(host,"EntityGetFirstComponentIncludingDisabled",id,kind)
    or read(host,"EntityGetFirstComponent",id,kind)
end
local function base(host,input)
  local x,y=read(host,"EntityGetTransform",input.entity_id)
  return {capture_kind="runtime_post_init_result_observation",run_id=input.run_id,input=input,
    entity_id=input.entity_id,filename=read(host,"EntityGetFilename",input.entity_id),
    frame=read(host,"GameGetFrameNum"),post_init_transform={x=x,y=y}}
end
function M.wand(host,input)
  local record=base(host,input)
  local ability=component(host,input.entity_id,"AbilityComponent")
  if not ability or ability==0 or type(host.ComponentObjectGetValue2)~="function"
      or type(host.ComponentGetValue2)~="function" or type(host.EntityGetAllChildren)~="function" then
    record.status="readers_unavailable"
  else
    record.status="observed";record.wand=capture.read_wand(host,input.entity_id,ability)
  end
  evidence.emit("ISF_WAND_RESULT",record,host)
  return record
end
function M.container(host,input)
  local record=base(host,input);record.materials={};record.material_vector_base=1
  local inventory=component(host,input.entity_id,"MaterialInventoryComponent")
  local vector=inventory and read(host,"ComponentGetValue2",inventory,"count_per_material_type")
  if type(vector)~="table" or type(host.CellFactory_GetName)~="function" then
    record.status="readers_unavailable"
  else
    record.status="observed"
    for index,amount in pairs(vector)do
      if type(amount)=="number" and amount>0 then
        local id=type(index)=="number" and index-1 or -1
        local name=id>=0 and read(host,"CellFactory_GetName",id) or nil
        local reverse=name and read(host,"CellFactory_GetType",name)
        if not name or name=="" or (reverse~=nil and reverse~=id) then record.status="material_lookup_inconsistent" end
        record.materials[#record.materials+1]={vector_index=index,material_id=id,name=name,amount=amount}
      end
    end
    table.sort(record.materials,function(a,b)return a.material_id<b.material_id end)
  end
  evidence.emit("ISF_CONTAINER_RESULT",record,host)
  return record
end
return M
