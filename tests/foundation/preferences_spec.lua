local prefs=T.load("mods/interesting_seed_filter/files/isf/core/preferences.lua")
local settings=T.load("mods/interesting_seed_filter/files/isf/adapters/game_settings.lua")
local luck=T.load("mods/interesting_seed_filter/files/isf/core/luck.lua")
local filter=T.load("mods/interesting_seed_filter/files/isf/core/filter.lua")
T.describe("player settings: bounded snapshots and actual depth routing")
T.equal(prefs.normalize().luck_level,1,"ordinary luck default")
for extra=0,4 do
 local value={extra_holy_mountains=extra,luck_level=6}
 local opts=prefs.evaluation_options(value)
 T.equal(opts.holy_mountains,3+extra,"spell shops reach selected depth")
 T.equal(opts.provider_options.holy_mountain_wands.holy_mountains,3+extra,"wand shops reach the same depth")
 T.equal(opts.provider_options.perks.initial_altars,extra==0 and 2 or 3+extra,"extended perks reach selected depth, baseline preserved")
end
local dirty={luck_level=99,extra_holy_mountains=-2}
T.equal(prefs.normalize(dirty).luck_level,6,"level clamped")
T.equal(prefs.normalize(dirty).extra_holy_mountains,0,"depth clamped")
T.equal(prefs.normalize({luck_level=0/0,extra_holy_mountains=math.huge}).luck_level,1,"invalid level falls back")
T.equal(prefs.normalize({extra_holy_mountains=math.huge}).extra_holy_mountains,0,"invalid depth falls back")
local base={provider_options={perks={initial_altars=99,row_size=3}}}
local copy=prefs.evaluation_options({extra_holy_mountains=4},base)
T.equal(copy.provider_options.perks.initial_altars,7,"settings control depth consistently")
T.equal(base.provider_options.perks.initial_altars,99,"caller options are not mutated")
local calls=0
local active=settings.capture({ModSettingGet=function(key)
 calls=calls+1;if key=="interesting_seed_filter.luck_level"then return 3 else return 4 end
end,ModSettingGetNextValue=function()error("pending choices must never be read")end})
T.equal(calls,2,"only the two active settings read")
T.equal(active.luck_level,3,"active luck read")
T.equal(active.extra_holy_mountains,4,"active depth read")
T.equal(settings.capture({}).luck_level,1,"missing host reader is safe")
local expected={0.4,0.2,0.1,0.05,0.01,0.003,0.001}
for level=0,6 do T.equal(prefs.target_fraction({luck_level=level}),expected[level+1],"internal tail mapping "..level)end

T.describe("internal calibration: no invented gates, no shallow/deep mixing")
local identity={profile_identity="p",rule_version="2.0",coverage_identity="c",scoring_depth_identity=prefs.score_identity({})}
local samples={};for i=1,100000 do samples[i]=i end
local calibration=luck.calibrate(samples,identity)
for level=0,6 do
 local gate=luck.resolve(calibration,{luck_level=level},identity)
 T.equal(gate,100000-math.ceil(100000*expected[level+1])+1,"upper tail gate "..level)
end
T.equal(samples[1],1,"calibration does not mutate caller samples")
local _,err=luck.resolve(nil,{},identity);T.equal(err,"calibration_required","no implicit threshold")
_,err=luck.resolve(calibration,{extra_holy_mountains=1},identity)
T.equal(err,"calibration_depth_mismatch","cannot use shallow distribution for deeper scoring")
local other={};for k,v in pairs(identity)do other[k]=v end;other.profile_identity="other"
_,err=luck.resolve(calibration,{},other)
T.equal(err,"calibration_conditions_mismatch","unlock/date/profile conditions are bound")
local small=luck.calibrate({1,2,3},identity)
_,err=luck.resolve(small,{luck_level=6},identity)
T.equal(err,"calibration_sample_too_small","rare level cannot use a tiny sample")
local tied={};for i=1,100 do tied[i]=4 end
local ties=luck.calibrate(tied,identity)
T.equal(ties.levels[1].passing_sample_count,100,"boundary ties are reported, never claimed to be exact population frequency")
local f=filter.new({search_settings={},profile_identity="p",rule_version="2.0",coverage_identity="c"})
local ok,why=f.start({new_game=true,mode="normal",ng_plus=0})
T.equal(ok,false,"menu level alone is not a fabricated score")
T.equal(why,"calibration_required","named calibration prerequisite")
