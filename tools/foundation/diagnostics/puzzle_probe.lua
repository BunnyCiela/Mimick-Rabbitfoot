-- Observe vanilla puzzle callbacks, preserving their returns, errors and RNG.
local M={PLAN="mods/interesting_seed_filter/"..".scratch/interesting-seed-filter/native-spatial-plan.lua"}
local function pack(...)return {n=select("#",...),...}end
function M.key(run,id)return "interesting_seed_filter.puzzle_done."..run.."."..id end
function M.resolve(h,session)
 if not session or not session.enabled or not session.capture_results then return nil end
 if type(h.ModDoesFileExist)~="function" or not h.ModDoesFileExist(M.PLAN)then return nil end
 local ok,p=pcall(dofile_once,M.PLAN)
 if ok and type(p)=="table" and p.schema_version==1 and p.run_id==session.run_id and p.puzzle_tests==true then return p end
end
function M.wrap(original,name,h,run)
 return function(...)
  local id=h.GetUpdatedEntityID();local x,y=h.EntityGetTransform(id)
  local record={run_id=run,callback=name,entity_id=id,x=x,y=y,frame=h.GameGetFrameNum(),loads={},cards={}}
  if name=="portal_teleport_used"then
   local player,fx,fy,tx,ty=...
   record.teleport={entity_id=player,from_x=fx,from_y=fy,to_x=tx,to_y=ty}
  end
  local old_load,old_card=h.EntityLoad,h.CreateItemActionEntity
  if type(old_load)=="function" then h.EntityLoad=function(path,lx,ly,...)
   local r=pack(old_load(path,lx,ly,...))
   if #record.loads<32 then record.loads[#record.loads+1]={filename=path,x=lx,y=ly,entity_id=r[1]}else record.truncated=true end
   return unpack(r,1,r.n)
  end end
  if type(old_card)=="function" then h.CreateItemActionEntity=function(spell,cx,cy,...)
   local r=pack(old_card(spell,cx,cy,...));record.cards[#record.cards+1]={spell_id=spell,x=cx,y=cy,entity_id=r[1]};return unpack(r,1,r.n)
  end end
  local result=pack(pcall(original,...))
  h.EntityLoad,h.CreateItemActionEntity=old_load,old_card
  record.status=result[1] and "returned" or "original_error"
  local ok,stored=pcall(function()return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_PUZZLE_CALLBACK",record,h)end)
  if result[1] and ok and stored and name~="material_area_checker_failed"then pcall(h.GlobalsSetValue,M.key(run,id),tostring(record.frame))end
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
 end
end
function M.install(h,session)
 if not M.resolve(h,session)then return false end
 for _,name in ipairs({"material_area_checker_success","material_area_checker_failed","electricity_receiver_switched","portal_teleport_used"})do
  if type(h[name])=="function"then h[name]=M.wrap(h[name],name,h,session.run_id)end
 end
 return true
end
return M
