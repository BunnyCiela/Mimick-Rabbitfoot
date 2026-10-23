-- Release Noita does not forward Lua print to stdout. Keep bounded diagnostic
-- JSON lines in a namespaced run-global, serialized by the game's normal save.
-- Called only by explicitly armed probes; never changes generation state.
local serialize=dofile_once("mods/interesting_seed_filter/files/isf/core/serialize.lua")
local M={KEY="interesting_seed_filter.native_evidence",PREFIX="ISF_HEX_V1:",MAX_BYTES=1048576}
local function hex(text)
  return (text:gsub(".",function(c)return string.format("%02x",c:byte())end))
end
function M.emit(tag,record,host)
  host=host or _G
  local json=serialize.render_json({tag=tag,record=record})
  if type(host.print)=="function" then pcall(host.print,"["..tag.."] "..json) end
  if type(host.GlobalsGetValue)~="function" or type(host.GlobalsSetValue)~="function" then return false end
  local ok,stored=pcall(function()
    local before=host.GlobalsGetValue(M.KEY,"")
    if type(before)~="string" then before="" end
    -- Noita writes global strings into XML attributes without escaping quotes.
    -- Use only ASCII hex so JSON quotes/newlines/XML characters cannot break it.
    if before:sub(1,#M.PREFIX)~=M.PREFIX then before=M.PREFIX end
    local encoded=hex(json.."\n")
    if #before+#encoded>M.MAX_BYTES then return false end
    host.GlobalsSetValue(M.KEY,before..encoded)
    return true
  end)
  return ok and stored==true
end
return M
