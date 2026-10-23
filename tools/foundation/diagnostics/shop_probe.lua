-- Read actual card/cost only after the original shop function returns.
local M={}
local function pack(...)return {n=select("#",...),...}end
function M.wrap(original,h)
 h=h or _G
 return function(...)
  local args=pack(...);local r=pack(original(unpack(args,1,args.n)))
  pcall(function()
   local s=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(h)
   if not s.enabled or not s.capture_results then return end
   local id=r[1];local action=h.EntityGetFirstComponentIncludingDisabled(id,"ItemActionComponent")
   local cost=h.EntityGetFirstComponentIncludingDisabled(id,"ItemCostComponent")
   dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_SHOP_RESULT",{
    run_id=s.run_id,x=args[1],y=args[2],cheap=args[3],biome_override=args[4],entity_id=id,
    spell_id=action and h.ComponentGetValue2(action,"action_id"),cost=cost and h.ComponentGetValue2(cost,"cost")},h)
  end)
  return unpack(r,1,r.n)
 end
end
return M
