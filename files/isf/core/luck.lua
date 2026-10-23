-- Internal empirical percentile gates. Nothing here is a player setting.
-- A level is not a point score: only a matching calibration may resolve it.
local preferences=dofile_once("mods/interesting_seed_filter/files/isf/core/preferences.lua")
local units=dofile_once("mods/interesting_seed_filter/files/isf/core/units.lua")
local M={}
local keys={"profile_identity","rule_version","coverage_identity","scoring_depth_identity"}
local function conditions(value)
 if type(value)~="table"then return nil end
 local out={}
 for _,key in ipairs(keys)do
  if type(value[key])~="string"or value[key]==""then return nil end
  out[key]=value[key]
 end
 return out
end
function M.calibrate(scores,identity)
 local fixed=conditions(identity)
 if not fixed then return nil,"calibration_conditions_required"end
 if type(scores)~="table"or #scores==0 then return nil,"calibration_samples_required"end
 local sorted={}
 for i,value in ipairs(scores)do
  if not units.is_score_units(value)then return nil,"invalid_calibration_score"end
  sorted[i]=value
 end
 table.sort(sorted)
 local result={schema_version=1,conditions=fixed,sample_count=#sorted,levels={}}
 for level=0,6 do
  local fraction=preferences.target_fraction({luck_level=level})
  local count=math.max(1,math.ceil(#sorted*fraction))
  local index=#sorted-count+1
  local gate=sorted[index]
  local first=index;while first>1 and sorted[first-1]==gate do first=first-1 end
  result.levels[level+1]={threshold_units=gate,tail_sample_count=count,
   passing_sample_count=#sorted-first+1}
 end
 return result
end
function M.resolve(calibration,settings,identity)
 local fixed=conditions(identity)
 if not fixed or type(calibration)~="table"or calibration.schema_version~=1 then
  return nil,"calibration_required"
 end
 local stored=conditions(calibration.conditions)
 if not stored then return nil,"invalid_calibration_conditions"end
 for _,key in ipairs(keys)do if stored[key]~=fixed[key]then return nil,"calibration_conditions_mismatch"end end
 if fixed.scoring_depth_identity~=preferences.score_identity(settings)then return nil,"calibration_depth_mismatch"end
 local level=preferences.normalize(settings).luck_level
 local row=type(calibration.levels)=="table"and calibration.levels[level+1]
 -- At least ten observations in the requested tail; Lv6 needs >=10k seeds.
 -- This is an empirical estimate, not a population-frequency guarantee.
 local n=calibration.sample_count
 local fraction=preferences.target_fraction(settings)
 if type(n)~="number"or n~=n or n==math.huge or n~=math.floor(n)or n<math.ceil(10/fraction)then return nil,"calibration_sample_too_small"end
 if type(row)~="table"or not units.is_score_units(row.threshold_units)then return nil,"invalid_calibration_gate"end
 return row.threshold_units
end
return M
