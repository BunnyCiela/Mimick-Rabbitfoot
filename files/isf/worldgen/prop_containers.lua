-- Installed coalmine.lua spawn_props3 -> spawn(g_props3,x,y,0,0).
-- g_props3: empty weight0.1, one standard potion weight0.3, offset_y=-5.
-- director_helpers.lua spawn adds (5,5); zero scatter and count1 are fixed.
-- This source is distinct from spawn_potions and has no potion-mimic lottery.
local rng=dofile_once("mods/interesting_seed_filter/files/isf/random/prng.lua")
local M={SOURCE="data/scripts/biomes/coalmine.lua spawn_props3 / g_props3; data/scripts/director_helpers.lua spawn"}
function M.handles(biome,func)return biome=="coalmine" and func=="spawn_props3"end
function M.resolve(biome,func,seed,x,y,ng)
 if not M.handles(biome,func)then return nil end
 local roll=rng.new(seed+(ng or 0)):ProceduralRandom(x,y)*(0.1+0.3)
 if roll<=0.1 then return {outcome="empty_prop_band",generated=false,absence_proven=true,roll=roll}end
 return {outcome="container",generated=true,roll=roll,container_kind="potion",
  entity_file="data/entities/items/pickup/potion.xml",load_x=x+5,load_y=y}
end
return M
