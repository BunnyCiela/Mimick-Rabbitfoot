-- Acceptance of the user-approved practical model, not a coverage upgrade.
local scope=dofile_once('mods/interesting_seed_filter/files/isf/core/scoring_scope.lua')
local M={ID='accepted-practical-model-v1'}
local categories={'holy_mountain.spell_cards','holy_mountain.sold_wands','holy_mountain.perks','wild.wands','wild.chests','wild.puzzles','wild.spell_shops','wild.liquids_and_pouches'}
local warnings={
 ['perks.non_default_initial_altars']=true,['chests.scan_exhaustiveness_undeclared']=true,
 ['puzzles.unresolved_puzzle_rewards']=true,['wild_shops.enumeration_unproven']=true,
 ['wild_shops.out_of_scope_card']=true,['collectibles.out_of_scope']=true,
 ['chests.non_target_card']=true,['chests.converted_to_gold']=true,
 ['collectibles.unresolved_content']=true,['puzzle_chests.scan_unavailable']=true,
 ['chests.discovery_partial']=true,['puzzle_chests.converted_to_gold']=true,
 ['chests.heal_only_not_maxhp']=true,['puzzle_chests.non_target_card']=true,
 ['puzzle_chests.heal_only_not_maxhp']=true,
}
function M.check(report,expected_assets)
 local meta=report.meta or {};local model=meta.scoring_scope
 if report.rule_version~='2.0'or type(model)~='table'or model.id~=scope.ID then return false,'practical_model_mismatch'end
 if type(meta.asset_identity)~='string'or meta.asset_identity=='no-assets'or(expected_assets and meta.asset_identity~=expected_assets)then return false,'asset_identity_mismatch'end
 local activity=report.details and report.details.discovery
 if not activity or activity.ran~=true or activity.regions_attempted~=5 or activity.regions_discovered~=5 or activity.regions_failed~=0 then return false,'region_discovery_failed'end
 local regions={coalmine=true,coalmine_alt=true,excavationsite=true,fungicave=true,snowcave=true}
 local count=0
 for _,row in ipairs(report.details.regions or {})do
  if not regions[row.region]or row.discovered~=true then return false,'region_discovery_failed'end
  regions[row.region]=nil;count=count+1
 end
 if count~=5 then return false,'region_discovery_failed'end
 for _,name in ipairs(categories)do
  local claim=report.coverage and report.coverage.categories and report.coverage.categories[name]
  if not claim or(claim.status~='complete'and claim.status~='partial')then return false,'unsupported_category:'..name end
 end
 for _,entry in ipairs(report.errors or {})do
  if entry.code~='collectibles.unresolved_records'then return false,'evaluation_error:'..tostring(entry.code)end
 end
 for _,entry in ipairs(report.warnings or {})do
  if not warnings[entry.code]then return false,'unexpected_warning:'..tostring(entry.code)end
 end
 return true
end
return M
