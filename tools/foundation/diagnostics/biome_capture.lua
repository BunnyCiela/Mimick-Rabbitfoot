-- Explicit test plan only. Read-only engine observations; never travel or edit
-- biome data. BiomeMapGetName API semantics are examined before trusting them
-- as an oracle for entity-spawn edge behavior.
local M={}
function M.run(h,points,run)
 assert(type(points)=="table" and #points>0 and #points<=512,"invalid biome query batch")
 local result={run_id=run,frame=h.GameGetFrameNum(),status="observed",points={}}
 for _,p in ipairs(points)do
  local ok,name=pcall(h.BiomeMapGetName,p.x,p.y)
  result.points[#result.points+1]={x=p.x,y=p.y,name=ok and name or nil,error=not ok and tostring(name)or nil}
  if not ok then result.status="failed"end
 end
 return dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_BIOME_LOOKUP",result,h)
end
return M
