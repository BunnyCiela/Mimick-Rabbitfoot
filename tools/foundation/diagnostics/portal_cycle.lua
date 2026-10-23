-- Explicit fresh-world diagnostic. Physical liquid input/removal only; all
-- enabling, target updates, transit and player-effect removal remain vanilla.
local M={}
local function read(h,name,...)
 if type(h[name])~="function"then return nil end
 local ok,a,b=pcall(h[name],...);if ok then return a,b end
end
local function near(x,y,tx,ty,r)return type(x)=="number" and type(y)=="number" and math.abs(x-tx)<=r and math.abs(y-ty)<=r end
local function find(h,file,x,y)
 local found={}
 for _,id in ipairs(read(h,"EntityGetInRadius",x,y,8)or {})do
  local xx,yy=read(h,"EntityGetTransform",id)
  if read(h,"EntityGetFilename",id)==file and near(xx,yy,x,y,2)then found[#found+1]=id end
 end
 if #found==1 then return found[1]end
end
local function effects(h,player)
 local count=0
 for _,id in ipairs(read(h,"EntityGetAllChildren",player)or {})do
  if read(h,"EntityHasTag",id,"meditation_cube_effect")==true then count=count+1 end
 end
 return count
end
function M.new(spec,run)
 assert(spec.mode=="eye" or spec.mode=="meditation","invalid portal cycle mode")
 local s={spec=spec,run=run,phase="find",position={x=spec.x,y=spec.y-60}}
 function s:event(h,phase,extra)
  local row={run_id=run,id=spec.id,kind="portal_cycle",phase=phase,mode=spec.mode,entity_id=self.entity,frame=h.GameGetFrameNum()}
  for k,v in pairs(extra or {})do row[k]=v end
  assert(dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_PORTAL_CYCLE",row,h),"portal evidence storage failed")
 end
 function s:transition(h,phase,extra)
  self.phase=phase;self.phase_frame=h.GameGetFrameNum();self:event(h,phase,extra)
 end
 function s:tick(h,player)
  local frame=h.GameGetFrameNum();self.started=self.started or frame
  if frame-self.started>(spec.timeout_frames or 3600)then return nil,"portal cycle timeout: "..self.phase end
  if self.phase=="find"then
   self.entity=find(h,spec.entity_file,spec.x,spec.y)
   if not self.entity then return nil,"natural portal missing or ambiguous"end
   self.teleport=read(h,"EntityGetFirstComponentIncludingDisabled",self.entity,"TeleportComponent")
   if not self.teleport or read(h,"ComponentGetIsEnabled",self.teleport)~=false then return nil,"portal must initially be disabled"end
   self:event(h,"baseline",{x=spec.x,y=spec.y,teleport_enabled=false})
   self:transition(h,spec.mode=="eye" and "fill_initial" or "meditate")
   if spec.mode=="meditation"then self.position={x=spec.x,y=spec.y+40}end
  end
  if self.phase=="fill_initial" or self.phase=="refill"then
   if (frame-self.phase_frame)%10==0 and frame-self.phase_frame<240 then
    if type(h.GameCreateParticle)~="function"then return nil,"physical liquid API unavailable"end
    for dx=-4,4 do h.GameCreateParticle("magic_liquid_teleportation",spec.x+dx,spec.y+100,12,0,2,false,false,false)end
    if not self.fill_logged then self:event(h,"physical_fill",{cycle=self.phase});self.fill_logged=true end
   end
   if read(h,"ComponentGetIsEnabled",self.teleport)==true then
    if self.phase=="fill_initial"then self:transition(h,"drain",{teleport_enabled=true});self.fill_logged=nil
    else self:transition(h,"outbound",{teleport_enabled=true});self.position={x=spec.x,y=spec.y}end
   end
  end
  if self.phase=="drain"then
   if (frame-self.phase_frame)%10==0 and frame-self.phase_frame<240 then
    if type(h.ConvertMaterialOnAreaInstantly)~="function" or type(h.CellFactory_GetType)~="function"then return nil,"bounded material conversion API unavailable"end
    local air=h.CellFactory_GetType("air")
    for _,name in ipairs({"magic_liquid_teleportation","magic_liquid_unstable_teleportation"})do
     h.ConvertMaterialOnAreaInstantly(spec.x-16,spec.y+80,32,44,h.CellFactory_GetType(name),air,false,false)
    end
    if not self.drain_logged then self:event(h,"physical_drain",{x=spec.x-16,y=spec.y+80,w=32,h=44});self.drain_logged=true end
   end
   if read(h,"ComponentGetIsEnabled",self.teleport)==false then self:transition(h,"refill",{teleport_enabled=false})end
  elseif self.phase=="meditate"then
   if read(h,"ComponentGetIsEnabled",self.teleport)==true then
    self:transition(h,"outbound",{teleport_enabled=true,waited_frames=frame-self.started});self.position={x=spec.x,y=spec.y}
   end
  elseif self.phase=="outbound"then
   local x,y=read(h,"EntityGetTransform",player)
   if near(x,y,spec.arrival_x,spec.arrival_y,100)then
    self:transition(h,"room_arrival",{x=x,y=y,effects=effects(h,player)})
    self.position={x=spec.arrival_x,y=spec.arrival_y-30}
   else self.position=(frame-self.phase_frame)%20==0 and {x=spec.x,y=spec.y}or nil end
  elseif self.phase=="room_arrival"then
   self.return_entity=find(h,spec.return_file,spec.return_x,spec.return_y)
   local rc=self.return_entity and read(h,"EntityGetFirstComponentIncludingDisabled",self.return_entity,"TeleportComponent")
   local prefix=spec.mode=="eye" and "TELEPORT_SNOWCAVE_BURIED_EYE_POS_" or "TELEPORT_MEDITATION_CUBE_POS_"
   local bx=tonumber(read(h,"GlobalsGetValue",prefix.."X",""));local by=tonumber(read(h,"GlobalsGetValue",prefix.."Y",""))
   local tx,ty=rc and read(h,"ComponentGetValue2",rc,"target")
   -- Lua's `and` expression discards secondary returns: read target separately.
   if rc then tx,ty=read(h,"ComponentGetValue2",rc,"target")end
   if bx and by and near(tx,ty,bx,by,.01) and read(h,"ComponentGetIsEnabled",rc)==true then
    self.back_x,self.back_y=bx,by
    self:transition(h,"return_enter",{return_entity_id=self.return_entity,x=spec.return_x,y=spec.return_y,target_x=tx,target_y=ty,effects=effects(h,player)})
    self.position={x=spec.return_x,y=spec.return_y}
   end
  elseif self.phase=="return_enter"then
   local x,y=read(h,"EntityGetTransform",player)
   if near(x,y,self.back_x,self.back_y,35)then
    self:transition(h,"returned",{x=x,y=y,target_x=self.back_x,target_y=self.back_y})
    self.position={x=self.back_x-70,y=self.back_y}
   else self.position=(frame-self.phase_frame)%20==0 and {x=spec.return_x,y=spec.return_y}or nil end
  elseif self.phase=="returned" and frame-self.phase_frame>=60 then
   self:event(h,"complete",{effects=effects(h,player)});return true
  end
  return false
 end
 return s
end
return M
