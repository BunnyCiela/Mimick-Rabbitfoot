-- Resource-only logical cells. No RGB image, rendering or diagnostic hashes.
-- Layout/room/overlay/connectivity semantics match region_map's reference path.
local M={}
function M.block_out_rooms(cells,w,h)
 local rooms={};local n=w*h
 local blocked=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/region_map.lua").BLOCKED_COLORS
 local function get(x,y)local i=y*w+x+1;if i<1 or i>n then return 0 end;return cells[i]or 0 end
 for y=4,h-1 do for x=0,w-1 do
  local color=get(x,y)
  if blocked[color]then
   local sx,sy=x+1,y+1;local ex,ey=x+1,y+1
   while ex<w do local c=get(ex,sy);if c==0 or c==0x323232 then ex=ex+1 else ex=ex-1;break end end
   if ex>=w then ex=w-1 end
   while ey<h do local c=get(sx,ey);if c==0 or c==0x323232 then ey=ey+1 else ey=ey-1;break end end
   if ey>=h then ey=h-1 end
   if ex>sx and ey>sy then for by=sy,ey do for bx=sx,ex do cells[by*w+bx+1]=0xff01ff end end end
   rooms[#rooms+1]={color=color,start_x=sx,start_y=sy,end_x=ex,end_y=ey}
  end
 end end
 return rooms
end
function M.restore_rooms(cells,w,rooms)
 for _,r in ipairs(rooms)do for y=r.start_y,r.end_y do for x=r.start_x,r.end_x do cells[y*w+x+1]=0 end end end
end
function M.apply_main_biome_hack(sx,cells,w,h)
 for y=0,math.min(10,h-1)do for x=math.max(0,sx),math.min(w-1,sx+6)do cells[y*w+x+1]=0 end end
end
local overlays=setmetatable({},{__mode="k"})
function M.apply_coalmine_overlay(cells,w,h,img,undo)
 local rows=overlays[img]
 if not rows then
  rows={}
  for y=0,img.height-1 do for x=0,img.width-1 do
   local r,g,b,a=img.rgba:byte((y*img.width+x)*4+1,(y*img.width+x)*4+4)
   local color=r*65536+g*256+b
   if a and a~=0 and color~=0xffffff then rows[#rows+1]={x=x,y=y,color=color}end
  end end
  overlays[img]=rows
 end
 for _,p in ipairs(rows)do
  if p.x<w and p.y<math.min(h,img.height)and p.y+4<h then cells[(p.y+4)*w+p.x+1]=(p.color==0x000042 or undo)and 0 or 0x010101 end
 end
end
function M.apply_masking(cells,w,bbox,valid)
 local tx=0
 for cx=bbox[1],bbox[3]do
  local cw=51+(cx%5==4 and 1 or 0);local ty=0
  for cy=bbox[2],bbox[4]do
   local ch=51+(cy%5==4 and 1 or 0)
   if not valid[cx..","..cy]then for y=0,ch-1 do for x=0,cw-1 do cells[(ty+y+4)*w+tx+x+1]=0 end end end
   ty=ty+ch
  end
  tx=tx+cw
 end
end
-- Markers come directly from chosen tile templates; no whole-map pixel scan.
-- Filter against final cells to respect later tiles, rooms, overlays and masks.
function M.markers(result,cells,w,h,index)
 assert(type(index)=="table"and index[0xc0ffee]==nil and index[0x010101]==nil,"resource grid requires non-handler terrain fill colors")
 local by_pos={}
 for _,placement in ipairs(result.placements)do
  local tile=placement.tile
  tile.resource_markers=tile.resource_markers or setmetatable({},{__mode="k"})
  local rows=tile.resource_markers[index]
  if not rows then
   rows={}
   for y=0,placement.height-1 do for x=0,placement.width-1 do
    local color=tile.cells[y*placement.width+x+1]
    if color~=0 and color~=0xffffff and index[color]then rows[#rows+1]={x=x,y=y,color=color,spawn_function_index=index[color]}end
   end end
   tile.resource_markers[index]=rows
  end
  for _,p in ipairs(rows)do
   local x,y=placement.x+p.x,placement.y+p.y
   if x>=0 and x<w and y>=4 and y<h then
    local pos=y*w+x+1
    if cells[pos]==p.color then by_pos[pos]={tile_x=x,tile_y=y-4,color=p.color,spawn_function_index=p.spawn_function_index}end
   end
  end
 end
 local order={};for pos in pairs(by_pos)do order[#order+1]=pos end;table.sort(order)
 local out={};for _,pos in ipairs(order)do out[#out+1]=by_pos[pos]end
 return out
end
return M
