-- Resolve only source recipes verified by the seed164 native reward fixture.
-- Entrance existence and resource scope remain the puzzle provider's decision.
-- Never scan a fixed room to manufacture an entrance or grant a Snow R1 score.
local M={}
local hm=dofile_once("mods/interesting_seed_filter/files/isf/providers/holy_mountain_wands.lua")
local prng=dofile_once("mods/interesting_seed_filter/files/isf/random/prng.lua")
function M.prepare(seed,profile,records)
 local out={};local bundle
 for _,source in ipairs(records or {})do
  local rec={};for k,v in pairs(source)do rec[k]=v end
  out[#out+1]=rec
  if rec.kind=="wand" and rec.wand==nil and rec.entrance_generated==true and rec.region_scope_allowed==true then
   local typ,x,y
   if rec.puzzle_kind=="mines_oil_receptacle" and rec.coordinate_frame=="entrance_marker_offset" then
    typ="wand_level_02";x=rec.x;y=rec.y
   elseif rec.puzzle_kind=="coal_meditation_cube" and rec.coordinate_frame=="reward_room_marker" then
    local rng=prng.new(seed)
    typ=rng:ProceduralRandom(rec.x-5,rec.y)<=0.5 and "wand_level_03" or "wand_unshuffle_02"
    x=rec.x;y=rec.y+5
   end
   if typ and type(x)=="number" and type(y)=="number" then
    local err
    if not bundle then bundle,err=hm.load_generator({profile=profile})end
    local wand
    if bundle then wand,err=bundle.wand_gen.generate(seed,0,typ,x,y,{})end
    if wand then
     rec.wand=wand;rec.gen_x=x;rec.gen_y=y;rec.generator_wand_type=typ
     rec.resolved=true;rec.content_status="predicted_from_source_recipe"
     rec.unresolved_reason=nil;rec.marker_mapping="native_seed164_verified_spawn_wands"
     rec.object_id="puzzle_reward_wand/"..tostring(rec.biome_key).."/"..x..","..y
     rec.content_provenance="vanilla recipe and native_puzzles_seed164; ordinary wand init frame"
    else
     rec.resolved=false;rec.unresolved_reason="puzzle wand content unavailable: "..tostring(err)
    end
   end
  end
 end
 return out
end
return M
