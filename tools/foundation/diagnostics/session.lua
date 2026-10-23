-- Optional local test marker; never included in the distributable archive.
-- Arming is explicit and changes no game save or setting.
local M={}
M.MARKER="mods/interesting_seed_filter/.scratch/interesting-seed-filter/native-session.txt"
M.PROTECTION_MARKER="mods/interesting_seed_filter/.scratch/interesting-seed-filter/native-player-protection.txt"
local function read(host,name,...)
  if type(host[name])~="function" then return nil end
  local ok,value=pcall(host[name],...)
  if ok then return value end
end
function M.resolve(host,include_protection)
  host=host or _G
  local exists=read(host,"ModDoesFileExist",M.MARKER)
  -- ModTextFileGetContent is documented as available in entity script contexts
  -- too; ModDoesFileExist may be absent there. The marker remains read-only.
  if exists==true or (exists==nil and type(host.ModTextFileGetContent)=="function") then
    local text=read(host,"ModTextFileGetContent",M.MARKER)
    local normalized=type(text)=="string" and text:gsub("\r\n","\n") or ""
    local results_id=normalized:match("^ISF_CURRENT_ENV_TEST_V1\n([%w_.:-]+)\nPOST_INIT_RESULTS\n$")
    local id=results_id or normalized:match("^ISF_CURRENT_ENV_TEST_V1\n([%w_.:-]+)\n$")
    if id then
      local protection=nil
      if include_protection==true then
        local present=read(host,"ModDoesFileExist",M.PROTECTION_MARKER)
        if present~=false then protection=read(host,"ModTextFileGetContent",M.PROTECTION_MARKER) end
      end
      local protection_id=type(protection)=="string" and protection:gsub("\r\n","\n"):match("^ISF_PLAYER_PROTECTION_V1\n([%w_.:-]+)\n$")
      return {enabled=true,run_id=id,capture_initializers=true,capture_results=results_id~=nil,protect_player=protection_id==id,environment="user_authorized_current_save"}
    end
  end
  local enabled=read(host,"ModSettingGet","interesting_seed_filter.probe_opt_in")==true
    and read(host,"ModSettingGet","interesting_seed_filter.probe_disposable_ack")=="DISPOSABLE"
  local id=read(host,"ModSettingGet","interesting_seed_filter.probe_run_id")
  return {enabled=enabled,run_id=id,protect_player=false,
    capture_initializers=read(host,"ModSettingGet","interesting_seed_filter.probe_capture_initializers")==true,
    environment="settings_opt_in"}
end
return M
