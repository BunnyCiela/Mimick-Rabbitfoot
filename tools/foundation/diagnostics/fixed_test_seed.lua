-- Explicit local joint-test seed. This is not the product's candidate selector.
local M={MARKER="mods/interesting_seed_filter/.scratch/interesting-seed-filter/native-fixed-seed.txt"}
function M.resolve(host,session)
  if not session or session.enabled~=true or session.environment~="user_authorized_current_save" then return nil end
  if type(host.ModDoesFileExist)~="function" or not host.ModDoesFileExist(M.MARKER) then return nil end
  if type(host.ModTextFileGetContent)~="function" then return nil end
  local ok,text=pcall(host.ModTextFileGetContent,M.MARKER)
  if not ok or type(text)~="string" then return nil end
  local id,digits=text:gsub("\r\n","\n"):match("^ISF_FIXED_TEST_SEED_V1\n([%w_.:-]+)\n(%d+)\n$")
  local seed=tonumber(digits)
  if id~=session.run_id or not seed or seed<1 or seed>2147483647 then return nil end
  return seed
end
return M
