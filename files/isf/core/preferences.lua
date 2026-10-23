-- Player choices -> internal search/scoring policy. No host reads here.
local M={DEFAULT_LUCK=1,DEFAULT_EXTRA_DEPTH=0,MAX_EXTRA_DEPTH=4}
local tails={0.40,0.20,0.10,0.05,0.01,0.003,0.001}
local function integer(value,default,maximum)
 if type(value)~="number"or value~=value or value==math.huge or value==-math.huge then return default end
 return math.max(0,math.min(maximum,math.floor(value+0.5)))
end
function M.normalize(raw)
 raw=type(raw)=="table"and raw or {}
 return {luck_level=integer(raw.luck_level,1,6),extra_holy_mountains=integer(raw.extra_holy_mountains,0,4)}
end
function M.target_fraction(raw)return tails[M.normalize(raw).luck_level+1]end
function M.depth(raw)
 local extra=M.normalize(raw).extra_holy_mountains
 return 3+extra,extra==0 and 2 or 3+extra
end
function M.score_identity(raw)
 local shops,perks=M.depth(raw)
 return "holy-depth-v1:shops="..shops..":perks="..perks
end
local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
function M.evaluation_options(raw,base)
 local out=copy(base);local shops,perks=M.depth(raw)
 out.search_settings=M.normalize(raw)
 out.holy_mountains=shops
 out.provider_options=copy(out.provider_options)
 for _,name in ipairs({"holy_mountains","holy_mountain_wands","perks"})do
  out.provider_options[name]=copy(out.provider_options[name])
 end
 out.provider_options.holy_mountains.holy_mountains=shops
 out.provider_options.holy_mountain_wands.holy_mountains=shops
 out.provider_options.perks.initial_altars=perks
 return out
end
return M
