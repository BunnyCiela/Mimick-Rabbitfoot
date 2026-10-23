-- Global ordinary-spell settlement, AFTER resource deduplication.
-- No mutable counters survive a candidate. AC awards never enter the buckets.
local units=dofile_once("mods/interesting_seed_filter/files/isf/core/units.lua")
local M={POLICY_ID="ordinary-spell-half-v1",RULE_VERSION="2.0"}
local function key(e)
  return (e.provider or "").."|"..(e.aggregate_region or e.biome or "").."|"..e.id
end
function M.is_ordinary(e)
  return type(e.spell_id)=="string" and e.spell_id~="" and e.rule_id~="R6"
    and not e.always_cast_id and not e.always_cast and e.is_always_cast~=true
    and e.kind~="always_cast_present" and e.kind~="always_cast_vigour"
end
function M.settle(entries)
  local copies,buckets={},{}
  local meta={policy_id=M.POLICY_ID,retention=0.5,precision=units.DECAY_PRECISION,
    order="base_score_units_desc_then_stable_id",base_score_units=0,ordinary_occurrences=0,spell_types=0,zero_tail_entries=0}
  for _,entry in ipairs(entries)do
    local e={};for k,v in pairs(entry)do e[k]=v end
    local base=e.base_score_units or e.score_units
    assert(type(base)=="number" and base>=0 and base==math.floor(base) and units.is_score_units(base),"invalid base score")
    e.base_score_units=base;e.base_reason=e.base_reason or e.reason
    e.reason=e.base_reason;e.score_units=base;e.decay_rank=nil;e.decay_exponent=nil
    meta.base_score_units=meta.base_score_units+base
    copies[#copies+1]=e
    if base>0 and M.is_ordinary(e)then
      local bucket=buckets[e.spell_id]
      if not bucket then bucket={};buckets[e.spell_id]=bucket;meta.spell_types=meta.spell_types+1 end
      bucket[#bucket+1]=e;meta.ordinary_occurrences=meta.ordinary_occurrences+1
    end
  end
  for _,bucket in pairs(buckets)do
    table.sort(bucket,function(a,b)
      if a.base_score_units~=b.base_score_units then return a.base_score_units>b.base_score_units end
      return key(a)<key(b)
    end)
    for rank,e in ipairs(bucket)do
      local ticks=0
      if rank<=53 then ticks=math.floor(e.base_score_units*units.DECAY_PRECISION*0.5^(rank-1))end
      e.score_units=ticks/units.DECAY_PRECISION
      e.decay_rank=rank;e.decay_exponent=rank-1
      e.reason=(e.base_reason or "ordinary spell").."; global copy #"..rank
        .." (base "..units.to_string(e.base_score_units)..", after decay "..units.to_string(e.score_units)..")"
      if ticks==0 then meta.zero_tail_entries=meta.zero_tail_entries+1 end
    end
  end
  return copies,meta
end
return M
