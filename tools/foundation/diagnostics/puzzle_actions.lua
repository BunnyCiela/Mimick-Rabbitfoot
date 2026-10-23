-- Opt-in stimuli on existing natural puzzle entities. No reward EntityLoad,
-- component enabling, countdown editing, callback calls or RNG draws here.
local probe=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/puzzle_probe.lua")
local M={}
local function read(h,name,...)
 if type(h[name])~="function"then return nil end
 local ok,a,b=pcall(h[name],...);if ok then return a,b end
end
local function emit(h,value)
 return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_PUZZLE_ACTION",value,h)
end
function M.new(spec,run)
 if spec.kind=="portal_cycle"then return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/portal_cycle.lua").new(spec,run)end
 assert(spec.kind=="material" or spec.kind=="meditation" or spec.kind=="eye" or spec.kind=="electricity","unsupported puzzle stimulus")
 assert(spec.settle_frames==nil or (type(spec.settle_frames)=="number" and spec.settle_frames>=0 and spec.settle_frames<=600),"invalid puzzle settling time")
 local s={spec=spec,run=run,phase="find",position={x=spec.x,y=spec.y-60}}
 function s:event(h,phase,extra)
  local row={run_id=run,id=spec.id,kind=spec.kind,phase=phase,entity_id=self.entity,frame=read(h,"GameGetFrameNum")}
  for k,v in pairs(extra or {})do row[k]=v end
  return emit(h,row)
 end
 function s:tick(h,player)
  local frame=read(h,"GameGetFrameNum")
  if not self.started then self.started=frame end
  if frame-self.started>(spec.timeout_frames or 2400)then return nil,"puzzle action timeout" end
  if self.phase=="find"then
   local found={}
   for _,id in ipairs(read(h,"EntityGetInRadius",spec.x,spec.y,8) or {})do
    local x,y=read(h,"EntityGetTransform",id)
    if read(h,"EntityGetFilename",id)==spec.entity_file and x and math.abs(x-spec.x)<2 and math.abs(y-spec.y)<2 then found[#found+1]=id end
   end
   if #found~=1 then return nil,"puzzle target missing or ambiguous"end
   self.entity=found[1]
   if read(h,"GlobalsGetValue",probe.key(run,self.entity),"")~=""then return nil,"puzzle was already solved"end
   self.teleport=read(h,"EntityGetFirstComponentIncludingDisabled",self.entity,"TeleportComponent")
   local checker=read(h,"EntityGetFirstComponentIncludingDisabled",self.entity,"MaterialAreaCheckerComponent")
   local material_id=checker and read(h,"ComponentGetValue2",checker,"material")
   self.checker_material=material_id and read(h,"CellFactory_GetName",material_id)
   self.material=spec.material or self.checker_material
   local baseline={x=spec.x,y=spec.y,material=self.material,checker_material=self.checker_material,teleport_enabled=self.teleport and read(h,"ComponentGetIsEnabled",self.teleport)}
   if spec.reward_x then
    baseline.reward_entities_before={}
    for _,id in ipairs(read(h,"EntityGetInRadius",spec.reward_x,spec.reward_y,12) or {})do
     if read(h,"EntityGetFilename",id)==spec.reward_file then baseline.reward_entities_before[#baseline.reward_entities_before+1]=id end
    end
    if #baseline.reward_entities_before>0 then return nil,"reward existed before stimulus"end
   end
   if not self:event(h,"baseline",baseline)then return nil,"puzzle evidence storage failed"end
   if spec.enforce_material_prediction and self.checker_material~=spec.material then return nil,"puzzle material prediction mismatch"end
   if spec.kind=="meditation"then
    if not self.teleport then return nil,"meditation teleporter unavailable"end
    if read(h,"ComponentGetIsEnabled",self.teleport)==true then return nil,"meditation portal already enabled"end
    self.position={x=spec.x,y=spec.y+40};self.phase="wait_meditation"
   elseif spec.kind=="eye"then
    if not self.teleport then return nil,"eye teleporter unavailable"end
    self.material="magic_liquid_teleportation";self.phase="fill_eye"
   elseif spec.kind=="electricity"then
    if not read(h,"EntityGetFirstComponentIncludingDisabled",self.entity,"ElectricityReceiverComponent")then return nil,"electricity receiver unavailable"end
    self.phase="electrify"
   else
    if type(self.material)~="string" or self.material==""then return nil,"puzzle material unavailable"end
    self.phase="fill_material"
   end
  end
  if self.phase=="electrify"then
   if type(h.EntityLoad)~="function" or type(h.GameCreateParticle)~="function"then return nil,"electrical stimulus API unavailable"end
   if read(h,"GlobalsGetValue",probe.key(run,self.entity),"")~=""then
    self.phase="settle";self.completed_at=frame
   elseif (frame-self.started)%60==0 and frame-self.started<180 then
    -- A tiny conducting patch and a vanilla short electrical discharge test
    -- the real receiver. This does not test swinging/cutting the natural rope.
    for dx=-2,2 do h.GameCreateParticle("copper",spec.x+dx,spec.y,6,0,0,false,false,false)end
    local id=h.EntityLoad("data/entities/misc/electricity_weak.xml",spec.x,spec.y)
    if not self:event(h,"native_electric_stimulus",{stimulus_entity=id,filename="data/entities/misc/electricity_weak.xml",x=spec.x,y=spec.y})then return nil,"puzzle evidence storage failed"end
   end
  end
  if self.phase=="fill_material" or self.phase=="fill_eye"then
   if type(h.GameCreateParticle)~="function"then return nil,"particle API unavailable"end
   if (frame-self.started)%10==0 and frame-self.started<240 then
    local dy=spec.fill_dy or (spec.kind=="eye" and 100 or -2)
    for dx=-4,4 do h.GameCreateParticle(self.material,spec.x+dx,spec.y+dy,12,0,2,false,false,false)end
    if not self.stimulus_logged then
     if not self:event(h,"native_material_stimulus",{material=self.material,x=spec.x,y=spec.y+dy})then return nil,"puzzle evidence storage failed"end
     self.stimulus_logged=true
    end
   end
   if spec.kind=="material" and read(h,"GlobalsGetValue",probe.key(run,self.entity),"")~=""then
    self.phase="settle";self.completed_at=frame
   end
  end
  if self.phase=="wait_meditation" or self.phase=="fill_eye"then
   if read(h,"ComponentGetIsEnabled",self.teleport)==true then
    if not self:event(h,"portal_enabled",{elapsed_frames=frame-self.started})then return nil,"puzzle evidence storage failed"end
    self.position={x=spec.x,y=spec.y};self.phase="enter_portal";self.entered_at=frame
   end
  elseif self.phase=="enter_portal"then
   local x,y=read(h,"EntityGetTransform",player)
   if x and math.abs(x-spec.arrival_x)<100 and math.abs(y-spec.arrival_y)<100 then
    if read(h,"GlobalsGetValue",probe.key(run,self.entity),"")==""then return false end
    if not self:event(h,"native_teleport_arrived",{x=x,y=y})then return nil,"puzzle evidence storage failed"end
    self.phase="settle";self.position=nil;self.completed_at=frame
   else
    self.position=(frame-self.entered_at)%20==0 and {x=spec.x,y=spec.y} or nil
   end
  end
  if self.phase=="settle" and frame-self.completed_at>=(spec.settle_frames or 180) then
   if not self.finished_logged then
    if not self:event(h,"complete")then return nil,"puzzle evidence storage failed"end
    self.finished_logged=true
   end
   return true
  end
  return false
 end
 return s
end
return M
