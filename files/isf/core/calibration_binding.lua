-- Fixed product gates apply to all unlock/progression states and dates.
-- Prediction and report identities still use the actual player's conditions.
-- Actual calendar facts must be available; build compatibility stays guarded.
local profile=dofile_once('mods/interesting_seed_filter/files/isf/adapters/profile.lua')
local content=dofile_once('mods/interesting_seed_filter/files/isf/items/content.lua')
local preferences=dofile_once('mods/interesting_seed_filter/files/isf/core/preferences.lua')
local luck=dofile_once('mods/interesting_seed_filter/files/isf/core/luck.lua')
local scope=dofile_once('mods/interesting_seed_filter/files/isf/core/scoring_scope.lua')
local M={}
function M.resolve(data,actual,settings)
 if type(data)~='table'or data.rule_version~='2.0'or data.scope~=scope.ID then return nil,'calibration_required'end
 local reference=data.source_profile
 if type(reference)~='table'or actual.game_version~=reference.game_version then return nil,'calibration_generation_conditions_mismatch'end
 local _,calendar_error=content.normalize_calendar(actual.calendar)
 if calendar_error then return nil,'generation_calendar_unavailable'end
 local row=data.depths and data.depths[preferences.normalize(settings).extra_holy_mountains+1]
 if type(row)~='table'or not row.conditions then return nil,'calibration_required'end
 local threshold,err=luck.resolve(row,settings,row.conditions)
 if not threshold then return nil,err end
 return {threshold_units=threshold,coverage_identity=row.conditions.coverage_identity,
  scoring_depth_identity=preferences.score_identity(settings),profile_identity=profile.identity(actual),
  reference_profile_identity=row.conditions.profile_identity,threshold_policy='fixed-across-unlocks-and-dates-v1'}
end
return M
