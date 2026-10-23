-- NG0 main-world biome edge lookup. Algorithm adapted from noita-telescope
-- js/edge_noise.js and js/utils.js, MIT, Copyright (c) 2026 Lymm.
-- Source parity is tested separately from native-game parity. No RNG or API use.
local data=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/data/edge_noise_data.lua")
local M={}
local F=(math.sqrt(3)-1)/2
local G=(3-math.sqrt(3))/6
local perm,signs=data.permutation,data.signs
local function p(i)return perm[i%256+1]end
local function trunc(x)return x<0 and math.ceil(x)or math.floor(x)end
-- Preserve the upstream uint cast, including its behavior outside positive
-- shifted main-world coordinates. It is not interchangeable with math.floor.
local function cast_floor(x)
 local n=trunc(x)%4294967296
 if x<n then n=n-1 end
 return n
end
local function corner(x,y,i,j)
 local t=(0.5-x*x)-y*y
 if t<0 then return 0 end
 local n=p(p(j)+i)%12*4
 return (signs[n+2]*y+signs[n+1]*x)*t*t*t*t
end
function M.simplex(x,y)
 local s=(x+y)*F
 local i,j=cast_floor(s+x),cast_floor(s+y)
 local t=(i+j)*G
 local dx,dy=x-(i-t),y-(j-t)
 i,j=i%256,j%256
 local a=dy<dx and 1 or 0
 local b=dx<=dy and 1 or 0
 local c0=corner(dx,dy,i,j)
 local c1=corner((dx-a)+G,(dy-b)+G,i+a,j+b)
 local c2=corner((dx-1)+G*2,(dy-1)+G*2,i+1,j+1)
 return (c1+c0+c2)*70
end
local function flag(color,key)
 local row=data.biomes[color]
 if not row then return nil end
 if row[key]~=nil then return row[key]end
 return key=="noise_biome_edges" and 1 or 0
end
local function parity(x,y)return x%2*2+y%2 end
function M.offset(x,y)
 local sx,sy=x+17920,y+7168
 local cx,cy=math.floor(sx/512)%70,math.floor(sy/512)
 local original=parity(cx,cy)
 local bx,by=math.floor(sx)%512,math.floor(sy)%512
 local actual=parity(cx,math.max(0,math.min(47,cy)))
 if bx<42 or bx>470 or by<42 or by>470 then
  local n=M.simplex(sx*0.05,sy*0.05)
  actual=parity(math.floor((math.sin(sy*0.005)*30+n*11+sx)/512),
    math.floor((math.cos(sx*0.005)*30+n*11+sy)/512))
 end
 return (math.floor(actual/2)-math.floor(original/2))%2*(x%512<42 and -1 or x%512>470 and 1 or 0),
  (actual-original)%2*(y%512<42 and -1 or y%512>470 and 1 or 0)
end
local function access(map)
 assert(map and map.width==70 and map.height==48,"edge noise requires NG0 70x48 biome map")
 return function(x,y)
  x=x%70;y=math.max(0,math.min(47,y))
  local i=(y*70+x)*3+1
  local r,g,b=map.rgb:byte(i,i+2)
  return r*65536+g*256+b,x,y
 end
end
local function first_neighbor(at,cx,cy,bx,by,original)
 local probes={}
 local function add(x,y)probes[#probes+1]={x,y}end
 if bx<42 then add(cx-1,cy)end
 if by<42 then add(cx,cy-1)end
 if bx>470 then add(cx+1,cy)end
 if by>470 then add(cx,cy+1)end
 if bx<42 then
  if by<42 then add(cx-1,cy-1)end
  if by>470 then add(cx-1,cy+1)end
 end
 if bx>470 then
  if by<42 then add(cx+1,cy-1)end
  if by>470 then add(cx+1,cy+1)end
 end
 for _,q in ipairs(probes)do local c=at(q[1],q[2]);if c~=original then return c end end
end
-- Terrain spawn gate: direct wobbled chunk after ordered neighbor eligibility.
function M.resolve(map,x,y)
 local at=access(map)
 local sx,sy=x+17920,y+7168
 local fx,fy=math.floor(sx),math.floor(sy)
 local original,cx,cy=at(math.floor(fx/512),math.floor(fy/512))
 if flag(original,"noise_biome_edges")==0 or flag(original,"fat_biome_edges")==1 then return original,original,cx,cy end
 local n=first_neighbor(at,cx,cy,fx%512,fy%512,original)
 if not n or flag(n,"noise_biome_edges")==0 then return original,original,cx,cy end
 local v=M.simplex(sx*0.05,sy*0.05)
 local color,wx,wy=at(math.floor(trunc(math.sin(sy*0.005)*30+v*11+sx)/512),
  math.floor(trunc(math.cos(sx*0.005)*30+v*11+sy)/512))
 if flag(color,"noise_biome_edges")==0 then return original,original,cx,cy end
 return color,original,wx,wy
end
-- Scene-center lookup: parity offset branch used by the source scene scanner.
function M.lookup(map,x,y,use_noise)
 local at=access(map)
 local original,cx,cy=at(math.floor(((x+17920)%35840)/512),math.floor(((y+7168)%24576)/512))
 if not use_noise then return original,original,cx,cy end
 local ox,oy=M.offset(x,y)
 local color,wx,wy=at(cx+ox,cy+oy)
 local n=first_neighbor(at,cx,cy,x%512,y%512,original)
 if flag(original,"noise_biome_edges")==0 or flag(color,"noise_biome_edges")==0
  or not n or flag(n,"noise_biome_edges")==0 then return original,original,cx,cy end
 return color,original,wx,wy
end
function M.tile_scan_point(x,y)
 local function axis(w)
  local phase=(math.floor(w/512)*512)%10
  local base=(phase-w)%10
  return w+(base>=5 and base or base+10)
 end
 return axis(x),axis(y)
end
M.biomes=data.biomes
return M
