-- Resolve the engine's current language at draw time, including while disabled
-- in the mod list. No writes to the game's shared translation table are needed.
local catalog=dofile_once("mods/interesting_seed_filter/files/isf/i18n/catalog.lua")
local M={}
local languages={
 ["English"]="en",["русский"]="ru",["Português (Brasil)"]="pt-br",
 ["Español"]="es-es",["Deutsch"]="de",["Français"]="fr-fr",
 ["Italiano"]="it",["Polska"]="pl",["简体中文"]="zh-cn",
 ["日本語"]="jp",["한국어"]="ko",
}
function M.language(api)
 api=api or _G
 local reader=api.GameTextGetTranslatedOrNot or api.GameTextGet
 if type(reader)=="function"then
  local ok,name=pcall(reader,"$current_language")
  if ok then return languages[name]or(catalog[name]and name)or"en"end
 end
 return"en"
end
function M.text(key,args,api)
 local language=M.language(api)
 local value=catalog[language][key]or catalog.en[key]or key
 return(value:gsub("{([%w_]+)}",function(name)
  return args and args[name]~=nil and tostring(args[name])or("{"..name.."}")
 end))
end
return M
