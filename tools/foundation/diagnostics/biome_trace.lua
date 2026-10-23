-- Local-plan opt-in only. Observe calls vanilla already makes; never draw RNG.
-- External local plan, deliberately absent from the distributable archive.
local M={PLAN="mods/interesting_seed_filter/"..".scratch/interesting-seed-filter/native-spatial-plan.lua"}
local biomes={coalmine=true,coalmine_alt=true,excavationsite=true,fungicave=true,snowcave=true}
local function pack(...)return {n=select("#",...),...}end
function M.resolve(h,session)
 if not session or not session.enabled or not session.capture_results then return nil end
 if type(h.ModDoesFileExist)~="function" or not h.ModDoesFileExist(M.PLAN)then return nil end
 local ok,p=pcall(dofile_once,M.PLAN)
 if not ok or type(p)~="table" or p.run_id~=session.run_id or p.schema_version~=1 then return nil end
 local c=p.biome_trace
 if type(c)~="table" or not biomes[c.biome] then return nil end
 for _,k in ipairs({"min_x","max_x","min_y","max_y"})do if type(c[k])~="number" then return nil end end
 if c.max_x<c.min_x or c.max_y<c.min_y or c.max_x-c.min_x>600 or c.max_y-c.min_y>600 then return nil end
 return c
end
function M.wrap(original,name,h,cfg,run_id)
 return function(x,y,...)
  if type(x)~="number" or type(y)~="number" or x<cfg.min_x or x>cfg.max_x or y<cfg.min_y or y>cfg.max_y then
   return original(x,y,...)
  end
  local steps,apis={},{}
  local record={run_id=run_id,biome=cfg.biome or "coalmine",callback=name,x=x,y=y,steps=steps}
  if type(h.GameGetFrameNum)=="function" then
   local ok,f=pcall(h.GameGetFrameNum);if ok then record.frame=f end
  end
  for _,key in ipairs({"ProceduralRandom","Random","SetRandomSeed","LoadPixelScene","EntityLoad"})do
   local old=h[key]
   if type(old)=="function" then
    apis[key]=old
    h[key]=function(...)
     local args=pack(...);local result=pack(old(...))
     if #steps<64 then
      local row={api=key}
      if key=="ProceduralRandom" or key=="SetRandomSeed" then row.x=args[1];row.y=args[2];row.value=result[1]
      elseif key=="Random" then row.min=args[1];row.max=args[2];row.value=result[1]
      elseif key=="LoadPixelScene" then row.path=args[1];row.x=args[3];row.y=args[4]
      else row.path=args[1];row.x=args[2];row.y=args[3];row.entity_id=result[1]end
      steps[#steps+1]=row
     else record.truncated=true end
     return unpack(result,1,result.n)
    end
   end
  end
  local result=pack(pcall(original,x,y,...))
  for key,old in pairs(apis)do h[key]=old end
  record.status=result[1] and "returned" or "original_error"
  pcall(function()dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_BIOME_CALLBACK",record,h)end)
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
 end
end
function M.install(h,session)
 local cfg=M.resolve(h,session);if not cfg then return false end
 for _,name in ipairs({"spawn_items","spawn_wands","spawn_heart","spawn_chest","spawn_bbqbox"})do
  if type(h[name])=="function" then h[name]=M.wrap(h[name],name,h,cfg,session.run_id)end
 end
 return true
end
return M
