local decay=T.load("mods/interesting_seed_filter/files/isf/core/spell_decay.lua")
local units=T.load("mods/interesting_seed_filter/files/isf/core/units.lua")
local function card(id,spell,base,provider)
 return {id=id,spell_id=spell,score_units=base,rule_id="R7",category="c",reason="base",provider=provider or "hm"}
end
local function sum(entries)local total=0;for _,e in ipairs(entries)do total=total+e.score_units end;return total end
T.describe("same ordinary spell halves globally, across providers and seeds independently")
local inputs={}
for i=1,5 do inputs[i]=card("card"..i,"BLACK_HOLE",8,i%2==0 and "chest" or "wand")end
local settled,meta=decay.settle(inputs)
T.equal(sum(settled),15.5,"five 2-point cards total3.875 points")
T.equal(units.to_string(sum(settled)),"3.875","no quarter-point truncation in rendering")
T.equal(meta.ordinary_occurrences,5,"all providers share one occurrence count")
T.equal(inputs[2].score_units,8,"input base evidence is never mutated")
T.equal(sum(decay.settle(inputs)),15.5,"new candidate settlement starts fresh")
T.equal(sum(decay.settle(settled)),15.5,"re-settling uses saved base units, never compounds decay")
local four={};for i=1,4 do four[i]=card(tostring(i),"LUMINOUS_DRILL",8)end
T.equal(sum(decay.settle(four)),15,"four drills score3.75 points")

T.describe("same-ID AC remains full and does not consume ordinary occurrences")
local entries={card("one","REGENERATION_FIELD",200),card("two","REGENERATION_FIELD",200),
 {id="ac",rule_id="R6",category="c",reason="AC",score_units=420,spell_id="REGENERATION_FIELD",kind="always_cast_vigour"},
 {id="ac2",rule_id="R1",category="c",reason="AC",score_units=400,spell_id="REGENERATION_FIELD",always_cast_id="REGENERATION_FIELD"}}
local out,info=decay.settle(entries)
T.equal(out[3].score_units,420,"AC bonus is unchanged")
T.equal(out[4].score_units,400,"wild AC bonus is unchanged")
T.equal(info.ordinary_occurrences,2,"AC never takes an ordinary rank")
T.equal(sum(out),1120,"ordinary healing halves; both AC bonuses stay full")
T.equal(out[3].decay_rank,nil,"AC has no decay rank")

T.describe("base value ranks precede traversal order; unrelated spell IDs stay independent")
local a={card("low","BLACK_HOLE",8,"hm"),card("high","BLACK_HOLE",40,"shop"),card("mid","BLACK_HOLE",10,"wand"),card("other","ALPHA",80)}
local b={a[4],a[3],a[2],a[1]}
local x=decay.settle(a);local y=decay.settle(b)
local values={};for _,e in ipairs(x)do values[e.id]=e.score_units end
for _,e in ipairs(y)do T.equal(e.score_units,values[e.id],"per-resource score is traversal independent")end
T.equal(values.high,40,"largest base value gets the full first copy")
T.equal(values.mid,5,"wild-wand copy keeps its region base before halving")
T.equal(values.low,2,"third copy uses the third global coefficient")
T.equal(values.other,80,"different spell has its own first occurrence")
local zero=card("zero","BLACK_HOLE",0);a[#a+1]=zero
T.equal(sum(decay.settle(a)),127,"non-scoring occurrences do not dilute eligible resources")

T.describe("long tails remain finite, bounded and exactly representable")
local many={};for i=1,1000 do many[i]=card(string.format("%04d",i),"ALPHA",80)end
local tail,details=decay.settle(many);local total=sum(tail)
T.check(total<160 and total>159.99,"1000 copies remain strictly below twice one copy")
T.check(units.is_score_units(total),"long tail stays on the fixed binary quantum")
T.check(details.zero_tail_entries>0,"unrepresentable tail is explicit in metadata")
T.check(not units.is_score_units(0/0) and not units.is_score_units(math.huge),"NaN and infinity are rejected")
T.check(not units.is_score_units(0.1),"off-quantum fractions are rejected")
T.equal(units.to_string(1.5),"0.375","fractional units have a real display value")

T.describe("aggregate consumes settlement once; provider and region subtotals reconcile exactly")
local evaluate=T.load("mods/interesting_seed_filter/files/isf/core/evaluate.lua")
local p=T.load("mods/interesting_seed_filter/files/isf/adapters/profile.lua").new({id="decay",unlocked_flags={}})
local result=evaluate.evaluate(48,p,{})
T.equal(result.rule_version,"2.0","old score populations cannot share a rule identity")
T.equal(result.meta.scoring.policy_id,decay.POLICY_ID,"retention and order are attributable")
T.equal(sum(result.entries),result.totals.score_units,"final entry values sum exactly")
T.check(result.totals.base_score_units>result.totals.score_units,"duplicate-rich seed has a lower final score")
local provider_total=0;for _,provider in ipairs(result.details.providers)do provider_total=provider_total+provider.score_units end
T.equal(provider_total,result.totals.score_units,"provider display totals use settled values")
local again=evaluate.evaluate(48,p,{})
T.equal(again.totals.score_units,result.totals.score_units,"candidate evaluation has no retained ranks")
T.check(result.coverage.complete==false,"decay never promotes incomplete coverage")

T.describe("captured seed48 two-shop resources score under the approved new rule")
local native=T.fixture("native_seed48_two_shop_awards.json")
local scored=decay.settle(native.entries)
T.equal(sum(native.entries),92,"old two-shop base score is23 points")
T.equal(sum(scored),50.5,"new scoped score is12.625 points")
for _,e in ipairs(scored)do
 if e.kind=="always_cast_present"then T.equal(e.score_units,20,"actual SPEED AC keeps all5 points")end
end
