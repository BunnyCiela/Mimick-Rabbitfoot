-- Read-only, conservative guard at the official pre-generation hook.
local M={}
local function read(api,name,...)
 if type(api[name])~='function'then return nil end
 local ok,value=pcall(api[name],...);if ok then return value end
end
function M.capture(api)
 local frame=read(api,'GameGetFrameNum')
 local played=tonumber(read(api,'StatsGetValue','playtime'))
 local saved=read(api,'GlobalsGetValue','interesting_seed_filter.run_seed','')
 if type(api.print)=='function'then api.print('[ISF_INIT_CONTEXT] frame='..tostring(frame)..' playtime='..tostring(played)..' filtered_save='..tostring(type(saved)=='string'and saved~=''))end
 if type(frame)~='number'or frame<0 then return nil,'start_context_unavailable'end
 if frame>0 or(played and played>0)or(type(saved)=='string'and saved~='')then return {continue_save=true},'skipped_continue'end
 local daily=read(api,'GameIsDailyRunOrDailyPracticeRun')
 if daily==nil then daily=read(api,'GameIsDailyRun')end
 local ng=tonumber(read(api,'SessionNumbersGetValue','NEW_GAME_PLUS_COUNT'))
 local map=read(api,'MagicNumbersGetValue','BIOME_MAP')
 if daily~=false or ng~=0 or map~='data/scripts/biome_map.lua'or read(api,'ModIsEnabled','nightmare')==true then return nil,'unsupported_context'end
 return {new_game=true,mode='normal',ng_plus=0}
end
return M
