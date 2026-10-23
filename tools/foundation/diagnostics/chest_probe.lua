-- Appended to the vanilla chest script. Observe original on_open and its real
-- entity/card creation calls; never call a generator a second time.
local M={}
local function pack(...)return {n=select("#",...),...}end
function M.wrap(original,h)
 h=h or _G
 return function(id,...)
  local s=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(h)
  if not s.enabled or not s.capture_results then return original(id,...)end
  local row={run_id=s.run_id,entity_id=id,loads={},cards={}}
  pcall(function()
   row.x,row.y=h.EntityGetTransform(id);row.filename=h.EntityGetFilename(id)
   local c=h.EntityGetFirstComponentIncludingDisabled(id,"PositionSeedComponent")
   if c then row.position_seed={x=h.ComponentGetValue2(c,"pos_x"),y=h.ComponentGetValue2(c,"pos_y")}end
  end)
  local load,card,convert=h.EntityLoad,h.CreateItemActionEntity,h.EntityConvertToMaterial
  if type(load)=="function" then h.EntityLoad=function(path,x,y,...)
   local r=pack(load(path,x,y,...));row.loads[#row.loads+1]={filename=path,x=x,y=y,entity_id=r[1]};return unpack(r,1,r.n)
  end end
  if type(card)=="function" then h.CreateItemActionEntity=function(spell,x,y,...)
   local r=pack(card(spell,x,y,...));row.cards[#row.cards+1]={spell_id=type(spell)=="string" and spell:upper() or spell,x=x,y=y,entity_id=r[1]};return unpack(r,1,r.n)
  end end
  if type(convert)=="function" then h.EntityConvertToMaterial=function(entity,material,...)
   local r=pack(convert(entity,material,...));row.converted_material=material;return unpack(r,1,r.n)
  end end
  local r=pack(pcall(original,id,...))
  h.EntityLoad,h.CreateItemActionEntity,h.EntityConvertToMaterial=load,card,convert
  row.status=r[1] and "observed" or "original_error"
  pcall(function()dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_CHEST_RESULT",row,h)end)
  if not r[1]then error(r[2],0)end
  return unpack(r,2,r.n)
 end
end
return M
