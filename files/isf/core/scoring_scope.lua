-- User-approved scope reduction, 2026-10-22. Legacy low-level predictors remain
-- available for fixtures; the aggregate scores only this selected resource model.
local M={ID="standard-resources-20261022",exhaustive_resource_audit=false,
 excluded={"natural liquid pools","special/nonstandard containers","unverified puzzle reward variants"}}
local standard={
 ["data/entities/items/pickup/potion.xml"]=true,
 ["data/entities/items/pickup/powder_stash.xml"]=true,
}
local main_puzzles={mines_swing_rope=true,mines_oil_receptacle=true,mines_oiltank_material=true,
 coal_puzzleroom=true,coal_meditation_cube=true,snow_capsule_a=true,snow_capsule_b=true,snow_buried_eye=true}
function M.container_exclusion(rec)
 if type(rec)~="table"then return nil end
 if rec.kind=="natural_pool"then return "natural pools excluded by scoring scope"end
 if rec.kind=="potion"or rec.kind=="powder_pouch"then
  if rec.entity_file and not standard[rec.entity_file]then return "nonstandard container excluded by scoring scope"end
  if rec.generator and rec.generator~="potion"and rec.generator~="powder_stash"then return "special container generator excluded by scoring scope"end
 end
end
function M.filter_containers(records)
 local kept,excluded={},{}
 for _,rec in ipairs(records or {})do
  local why=M.container_exclusion(rec)
  if why then excluded[#excluded+1]={id=rec.id,object_id=rec.object_id,entity_file=rec.entity_file,reason=why}
  else kept[#kept+1]=rec end
 end
 return kept,excluded
end
function M.filter_puzzle_rewards(records)
 local kept,excluded={},{}
 for _,rec in ipairs(records or {})do
  -- A failure in a validated main recipe remains an error, not an exclusion.
  if not main_puzzles[rec.puzzle_kind]then
   excluded[#excluded+1]={id=rec.id,puzzle_kind=rec.puzzle_kind,reason="unverified puzzle reward variant excluded by scoring scope"}
  else kept[#kept+1]=rec end
 end
 return kept,excluded
end
return M
