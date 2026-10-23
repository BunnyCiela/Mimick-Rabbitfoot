-- Explicit local-test route. Moves the existing player only after F7, observes
-- naturally generated entities, and can open a found natural chest via vanilla.
-- Optional puzzle actions supply physical inputs, never rewards. Camera is owned
-- by the game. Optional native precision probes have an explicit plan timing.
local M={KEY_F7=64}
local function read(h,name,...)
 if type(h[name])~="function" then return nil end
 local ok,a,b,c,d=pcall(h[name],...);if ok then return a,b,c,d end
end
local function comp(h,id,name)
 local c=read(h,"EntityGetFirstComponentIncludingDisabled",id,name)
 if type(c)=="number" and c~=0 then return c end
end
local function value(h,c,key)if c then return read(h,"ComponentGetValue2",c,key)end end
local function emit(h,tag,v)return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit(tag,v,h)end
local function message(h,s)if type(h.GamePrint)=="function" then h.GamePrint(s)end end
function M.snapshot(h,plan,index,player)
 local point=plan.points[index].capture or plan.points[index]
 local ident=plan.points[index].id
 local ids=read(h,"EntityGetInRadius",point.x,point.y,point.radius or 220)
 if type(ids)~="table" then return nil,"entity query unavailable" end
 local out={run_id=plan.run_id,declared_seed=plan.seed,point_id=ident,index=index,
  frame=read(h,"GameGetFrameNum"),query={x=point.x,y=point.y,radius=point.radius or 220},
  completeness="loaded_entities_in_query_only",entities={},total_queried=#ids,
  filename_note="engine filename may be inaccurate after world streaming"}
 local radius=point.radius or 220
 out.world_loaded=read(h,"DoesWorldExistAt",point.x-radius,point.y-radius,point.x+radius,point.y+radius)
 out.biome_name=read(h,"BiomeMapGetName",point.x,point.y)
 local cx,cy,cw,ch=read(h,"GameGetCameraBounds")
 out.camera_bounds={x=cx,y=cy,width=cw,height=ch}
 local all,seen={},{}
 local function collect(id,depth)
  if id==player or read(h,"EntityGetRootEntity",id)==player or seen[id] or #all>=1000 then return end
  seen[id]=true;all[#all+1]=id
  if plan.include_owned_items and depth<4 then
   for _,child in ipairs(read(h,"EntityGetAllChildren",id) or {})do collect(child,depth+1)end
  end
 end
 for _,id in ipairs(ids)do collect(id,0)end
 -- Physics can carry a chest out of the small query after a neighbouring
 -- waypoint loaded it. Recover only this waypoint's exact PositionSeed from
 -- currently loaded tagged chests; never substitute the nearest live chest.
 if plan.include_displaced_chests and plan.points[index].open_chest then
  local target=plan.points[index].open_chest_at or point
  out.completeness="loaded_query_and_matching_position_seed_chests"
  out.displaced_chest_ids={}
  for _,id in ipairs(read(h,"EntityGetWithTag","chest")or {})do
   local seed=comp(h,id,"PositionSeedComponent")
   local x,y=value(h,seed,"pos_x"),value(h,seed,"pos_y")
   if type(x)=="number"and type(y)=="number"and math.abs(x-target.x)<1 and math.abs(y-target.y)<1 and not seen[id]then
    collect(id,0)
    if seen[id]then out.displaced_chest_ids[#out.displaced_chest_ids+1]=id end
   end
  end
 end
 for _,id in ipairs(all) do
  local parent=read(h,"EntityGetParent",id) or 0
  if id~=player and (parent==0 or plan.include_owned_items) then
   local path=read(h,"EntityGetFilename",id) or ""
   local item=comp(h,id,"ItemComponent")
   local anchor=path:find("teleport_meditation_cube",1,true) or path:find("teleport_snowcave_buried_eye",1,true)
   if item or anchor or read(h,"EntityHasTag",id,"chest")==true then
    local x,y=read(h,"EntityGetTransform",id)
    local row={entity_id=id,filename=path,x=x,y=y,parent_id=parent,owner_root=read(h,"EntityGetRootEntity",id),tags=read(h,"EntityGetTags",id)}
    local pos=comp(h,id,"PositionSeedComponent")
    if pos then row.position_seed={x=value(h,pos,"pos_x"),y=value(h,pos,"pos_y")}end
    local action=comp(h,id,"ItemActionComponent")
    if action then row.spell_id=value(h,action,"action_id")end
    local cost=comp(h,id,"ItemCostComponent")
    if cost then row.cost=value(h,cost,"cost")end
    local ability=comp(h,id,"AbilityComponent")
    if ability and value(h,ability,"use_gun_script")==true and type(x)=="number" and type(y)=="number"
     and ((math.abs(x-point.x)<=2 and math.abs(y-point.y)<=35) or plan.include_owned_items) then
     row.wand=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/holy_mountain_capture.lua").read_wand(h,id,ability)
    end
    local inventory=comp(h,id,"MaterialInventoryComponent")
    if plan.read_materials and inventory and type(h.CellFactory_GetName)=="function" then
     local vector=value(h,inventory,"count_per_material_type")
     row.materials={}
     for index,amount in pairs(type(vector)=="table" and vector or {})do
      if type(index)=="number" and type(amount)=="number" and amount>0 then
       row.materials[#row.materials+1]={material_id=index-1,name=read(h,"CellFactory_GetName",index-1),amount=amount}
      end
     end
    end
    out.entities[#out.entities+1]=row
   end
  end
 end
 table.sort(out.entities,function(a,b)return a.entity_id<b.entity_id end)
 return out
end
function M.new(plan,run_id)
 assert(type(plan)=="table" and plan.run_id==run_id and plan.schema_version==1,"invalid spatial plan")
 assert(type(plan.points)=="table" and #plan.points>0 and #plan.points<=32,"invalid route size")
 if plan.auto_start_frames~=nil then
  assert(plan.require_fresh_world==true and type(plan.auto_start_frames)=="number" and plan.auto_start_frames>=60 and plan.auto_start_frames<=3600,"invalid auto-start guard")
 end
 for _,p in ipairs(plan.points)do
  assert(type(p.id)=="string" and type(p.x)=="number" and type(p.y)=="number","invalid waypoint")
  assert((p.radius or 220)>0 and (p.radius or 220)<=400,"invalid radius")
  if p.capture then assert(type(p.capture.x)=="number" and type(p.capture.y)=="number" and (p.capture.radius or 220)>0 and (p.capture.radius or 220)<=400,"invalid capture query")end
  if p.action then assert(plan.puzzle_tests==true and plan.require_fresh_world==true,"puzzle action requires fresh opt-in plan")end
 end
 local state={active=false,done=false,index=0,opened={}}
 function state:observe_world_start(h)
  local frame=read(h,"GameGetFrameNum")
  local previous=read(h,"GlobalsGetValue","interesting_seed_filter.native_evidence","")
  self.fresh_world=type(frame)=="number" and frame<=5 and (previous=="" or previous=="ISF_HEX_V1:")
  emit(h,"ISF_SPATIAL_WORLD_START",{run_id=run_id,frame=frame,prior_evidence_empty=previous=="" or previous=="ISF_HEX_V1:",fresh_world=self.fresh_world})
 end
 function state:probe(h)
  if self.probed then return end
  self.probed=true
  for _,p in ipairs(plan.procedural_probes or {})do
   local ok,value=pcall(function()return h.ProceduralRandom(p.x,p.y)end)
   emit(h,"ISF_PROCEDURAL_API",{run_id=run_id,declared_seed=plan.seed,id=p.id,x=p.x,y=p.y,
    timing=plan.probe_at_start and "route_start" or "route_end",
    status=ok and type(value)=="number" and "observed" or "reader_failed",value=ok and value or nil,error=not ok and tostring(value) or nil})
  end
 end
 function state:stop(h,why)
  self.active=false;self.done=true;self.status=why
  emit(h,"ISF_SPATIAL_ROUTE",{run_id=run_id,status=why,index=self.index})
  message(h,"ISF: map test "..why)
  if why=="complete - save and quit" and (type(plan.native_evaluation)=="table"or type(plan.native_performance)=="table")then return end
  if type(h.GamePrintImportant)=="function" then
   pcall(h.GamePrintImportant,why=="complete - save and quit" and "ISF TEST COMPLETE" or "ISF TEST STOPPED","Save and quit")
  end
 end
 function state:finish_evaluation(h,success)
  if self.evaluation_finished or self.status~="complete - save and quit"then return false end
  self.evaluation_finished=true
  if type(h.GamePrintImportant)=="function"then
   pcall(h.GamePrintImportant,success and "ISF TEST COMPLETE"or "ISF TEST FAILED","Save and quit")
  end
  return true
 end
 function state:tick(h)
  local pressed=read(h,"InputIsKeyJustDown",M.KEY_F7)==true
  if not self.active and not self.done and plan.auto_start_frames and self.fresh_world==true
   and (read(h,"GameGetFrameNum") or 0)>=plan.auto_start_frames then pressed=true end
  if self.active and pressed then self:stop(h,"cancelled");return end
  if not self.active then
   if not pressed or self.done then return end
   if plan.require_fresh_world and self.fresh_world~=true then
    emit(h,"ISF_SPATIAL_START_REFUSED",{run_id=run_id,reason="fresh test world required"})
    message(h,"ISF: start a NEW GAME for this test")
    if type(h.GamePrintImportant)=="function" then pcall(h.GamePrintImportant,"ISF: NEW GAME REQUIRED","This test needs a fresh world")end
    return
   end
   for _,name in ipairs({"EntitySetTransform","EntityGetWithTag","EntityGetInRadius","EntityGetFilename","EntityGetTransform","EntityGetParent","EntityAddComponent2","DoesWorldExistAt",
    "EntityGetFirstComponentIncludingDisabled","ComponentGetValue2","GameGetFrameNum","GlobalsGetValue","GlobalsSetValue"})do
    if type(h[name])~="function" then message(h,"ISF: map test missing "..name);return end
   end
   local players=read(h,"EntityGetWithTag","player_unit") or {}
   if not players[1]then return end
   self.player=players[1];self.active=true;self.index=1;self.start_frame=read(h,"GameGetFrameNum")
   emit(h,"ISF_SPATIAL_ROUTE",{run_id=run_id,status="started",declared_seed=plan.seed,points=#plan.points})
   message(h,"ISF: map test started; F7 cancels")
   if plan.probe_at_start then self:probe(h)end
  end
  local players=read(h,"EntityGetWithTag","player_unit") or {}
  if players[1]~=self.player then self:stop(h,"player_changed");return end
  local point=plan.points[self.index]
  -- Hold the player at the camera target while chunks load. Avoid walking,
  -- picking up resources, or physics pushing the chest before observation.
  local position=self.action and self.action.position or {x=point.x,y=point.y-60}
  if self.action and self.action.position==nil then position=nil end
  local ok=true
  if position then ok=pcall(h.EntitySetTransform,self.player,position.x,position.y)end
  if not ok then self:stop(h,"move_failed");return end
  local elapsed=read(h,"GameGetFrameNum")-self.start_frame
  local wait=point.wait_frames or plan.wait_frames or 240
  if elapsed<wait then return end
  if point.action and not self.action then
   local radius=point.radius or 90
   if read(h,"DoesWorldExistAt",point.x-radius,point.y-radius,point.x+radius,point.y+radius)~=true then
    if elapsed>wait+900 then self:stop(h,"source load timeout - save and quit")end
    return
   end
   self.action=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/puzzle_actions.lua").new(point.action,run_id)
  end
  if self.action and not self.action_ready then
   local ready,why=self.action:tick(h,self.player)
   if ready==nil then self:stop(h,why);return end
   if not ready then return end
   self.action_ready=true;self.capture_wait_start=read(h,"GameGetFrameNum")
  end
  local query=point.capture or point
  local radius=query.radius or 220
  if read(h,"DoesWorldExistAt",query.x-radius,query.y-radius,query.x+radius,query.y+radius)~=true then
   if elapsed>wait+900 and (not self.action or read(h,"GameGetFrameNum")-self.capture_wait_start>900) then self:stop(h,"load timeout - save and quit")end
   return
  end
  if not self.captured then
   local snapshot,why=M.snapshot(h,plan,self.index,self.player)
   if not snapshot then self:stop(h,why);return end
   if not emit(h,"ISF_SPATIAL_SNAPSHOT",snapshot) then self:stop(h,"storage_failed");return end
   self.captured=true;self.captured_at=read(h,"GameGetFrameNum")
   if point.open_chest then
    local chest_at=point.open_chest_at or point
    for _,row in ipairs(snapshot.entities)do
     local pos=row.position_seed
     -- Match the original seed coordinate, never the nearest arbitrary chest.
     if pos and math.abs((pos.x or 1e9)-chest_at.x)<1 and math.abs((pos.y or 1e9)-chest_at.y)<1
      and (row.filename=="data/entities/items/pickup/chest_random.xml" or row.filename=="data/entities/items/pickup/chest_random_super.xml")
      and not self.opened[row.entity_id] and type(h.EntityAddComponent2)=="function" then
      local cid=h.EntityAddComponent2(row.entity_id,"LuaComponent",{execute_on_added=true,remove_after_executed=true,
       script_source_file="mods/interesting_seed_filter/tools/foundation/diagnostics/open_natural_chest.lua"})
      self.opened[row.entity_id]=true
      emit(h,"ISF_SPATIAL_OPEN_REQUEST",{run_id=run_id,point_id=point.id,entity_id=row.entity_id,component_id=cid,position_seed=pos})
     end
    end
   end
  end
  if read(h,"GameGetFrameNum")-self.captured_at<60 then return end
  message(h,"ISF: map point "..self.index.."/"..#plan.points.." recorded")
  self.index=self.index+1;self.captured=false;self.captured_at=nil;self.action=nil;self.action_ready=nil;self.capture_wait_start=nil;self.start_frame=read(h,"GameGetFrameNum")
  if self.index>#plan.points then
   self:probe(h)
   self.done=true;self:stop(h,"complete - save and quit")
  end
 end
 return state
end
return M
