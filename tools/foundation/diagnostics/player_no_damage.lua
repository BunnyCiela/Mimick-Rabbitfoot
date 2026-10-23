-- Explicit local test session only; preserves healing and the critical metadata.
local protection=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/player_protection.lua")
local session=dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/session.lua").resolve(_G,true)
local recorded=false
function damage_about_to_be_received(damage,x,y,responsible,critical_hit_chance)
  local amount,critical=protection.damage(damage,critical_hit_chance,session.enabled==true and session.protect_player==true)
  if amount==0 and type(damage)=="number" and damage>0 and not recorded then
    recorded=true
    pcall(function()
      dofile_once("mods/interesting_seed_filter/tools/foundation/diagnostics/evidence.lua").emit("ISF_PLAYER_PROTECTION_BLOCK",{
        run_id=session.run_id,entity_id=GetUpdatedEntityID(),frame=GameGetFrameNum(),incoming_damage=damage,returned_damage=amount})
    end)
  end
  return amount,critical
end
