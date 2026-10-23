-- Capture active NEW_GAME-scoped settings once before a search. Never read
-- buffered next-run choices during a candidate evaluation.
local preferences=dofile_once("mods/interesting_seed_filter/files/isf/core/preferences.lua")
local M={}
function M.capture(api)
 api=api or _G
 local function read(key)
  if type(api.ModSettingGet)~="function"then return nil end
  local ok,value=pcall(api.ModSettingGet,"interesting_seed_filter."..key)
  if ok then return value end
 end
 return preferences.normalize({luck_level=read("luck_level"),extra_holy_mountains=read("extra_holy_mountains")})
end
function M.evaluation_options(api,base)return preferences.evaluation_options(M.capture(api),base)end
return M
