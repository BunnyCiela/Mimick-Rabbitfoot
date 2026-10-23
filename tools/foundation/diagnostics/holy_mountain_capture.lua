-- Read already-loaded pickup entities. Never spawns, picks, rerolls or seeds.
local M={KEY_F8=65} -- data/scripts/debug/keycodes.lua: Key_F8 = 65
M.TEMPLES={{x=-32,y=1410},{x=-32,y=2946},{x=-32,y=4994}}
local function read(host,name,...)
  if type(host[name])~="function" then return nil end
  local ok,a,b=pcall(host[name],...)
  if ok then return a,b end
end
local function component(host,id,name)
  local fn=type(host.EntityGetFirstComponentIncludingDisabled)=="function"
    and "EntityGetFirstComponentIncludingDisabled" or "EntityGetFirstComponent"
  local value=read(host,fn,id,name)
  if type(value)=="number" and value~=0 then return value end
end
local function value(host,id,field)
  if id then return read(host,"ComponentGetValue2",id,field) end
end
local function perk_id(host,id)
  local components=read(host,"EntityGetComponentIncludingDisabled",id,"VariableStorageComponent") or {}
  for _,c in ipairs(components) do
    if value(host,c,"name")=="perk_id" then return value(host,c,"value_string") end
  end
end
local function wand(host,id,ability)
  local result={gun_config={},gunaction_config={},cards={},always_cast={}}
  for _,field in ipairs({"deck_capacity","actions_per_round","reload_time","shuffle_deck_when_empty"}) do
    result.gun_config[field]=read(host,"ComponentObjectGetValue2",ability,"gun_config",field)
  end
  for _,field in ipairs({"fire_rate_wait","spread_degrees","speed_multiplier"}) do
    result.gunaction_config[field]=read(host,"ComponentObjectGetValue2",ability,"gunaction_config",field)
  end
  result.mana_max=value(host,ability,"mana_max")
  result.mana_charge_speed=value(host,ability,"mana_charge_speed")
  local children=read(host,"EntityGetAllChildren",id) or {}
  for _,child in ipairs(children) do
    local action=component(host,child,"ItemActionComponent")
    if action then
      local item=component(host,child,"ItemComponent")
      local slot= item and value(host,item,"inventory_slot")
      local card={entity_id=child,spell_id=value(host,action,"action_id"),slot=slot}
      local target=value(host,item,"permanently_attached")==true and result.always_cast or result.cards
      target[#target+1]=card
    end
  end
  local function order(a,b)
    if (a.slot or -1)==(b.slot or -1) then return a.entity_id<b.entity_id end
    return (a.slot or -1)<(b.slot or -1)
  end
  table.sort(result.cards,order);table.sort(result.always_cast,order)
  return result
end
-- Same read-only component view for post-generation probes outside shops.
M.read_wand=wand
function M.capture_nearest(host,run_id)
  local players=read(host,"EntityGetWithTag","player_unit") or {}
  if not players[1] then return nil,"player unavailable" end
  local _,y=read(host,"EntityGetTransform",players[1])
  if type(y)~="number" then return nil,"player position unavailable" end
  local nearest,distance
  for index,temple in ipairs(M.TEMPLES) do
    local delta=math.abs(y-temple.y)
    if not distance or delta<distance then nearest,distance=index,delta end
  end
  if distance>260 then return nil,"enter a Holy Mountain first" end
  return M.capture(host,nearest,run_id)
end
function M.capture(host,index,run_id)
  local temple=M.TEMPLES[index]
  if not temple then return nil,"unknown Holy Mountain" end
  for _,name in ipairs({"EntityGetWithTag","EntityGetTransform","EntityGetInRadius",
      "ComponentGetValue2","EntityGetComponentIncludingDisabled"}) do
    if type(host[name])~="function" then return nil,"missing reader: "..name end
  end
  local players=read(host,"EntityGetWithTag","player_unit") or {}
  if not players[1] then return nil,"player unavailable" end
  local px,py=read(host,"EntityGetTransform",players[1])
  if type(px)~="number" or type(py)~="number" then return nil,"player position unavailable" end
  if math.abs(py-temple.y)>260 or math.abs(px-(temple.x-200))>900 then
    return nil,"enter Holy Mountain "..index.." first"
  end
  local list=read(host,"EntityGetInRadius",temple.x-200,temple.y,650)
  if type(list)~="table" then return nil,"entity query failed" end
  local snapshot={schema_version=1,capture_kind="runtime_loaded_entity_observation",run_id=run_id,
    temple_index=index,frame=read(host,"GameGetFrameNum"),player={x=px,y=py},
    query={x=temple.x-200,y=temple.y,radius=650},shop_items={},perks={},other_priced_entities={},
    counters={next_perk_index=read(host,"GlobalsGetValue","TEMPLE_NEXT_PERK_INDEX","1"),
      reroll_index=read(host,"GlobalsGetValue","TEMPLE_REROLL_PERK_INDEX","uninitialized"),
      reroll_count=read(host,"GlobalsGetValue","TEMPLE_PERK_REROLL_COUNT","0")},
    completeness="observed_loaded_entities_only"}
  snapshot.player.money=value(host,component(host,players[1],"WalletComponent"),"money")
  -- Vanilla refreshes every loaded entity tagged 'perk'. Preserve that actual
  -- count and their positions so multiple loaded altars cannot pass as one row.
  local active=read(host,"EntityGetWithTag","perk")
  if type(active)=="table" then
    snapshot.active_perk_count=#active;snapshot.active_perks={}
    for _,id in ipairs(active) do
      local x,y=read(host,"EntityGetTransform",id)
      snapshot.active_perks[#snapshot.active_perks+1]={entity_id=id,x=x,y=y,perk_id=perk_id(host,id)}
    end
  end
  local seen={}
  for _,id in ipairs(list) do
    if not seen[id] then
      seen[id]=true
      local parent=read(host,"EntityGetParent",id)
      local x,y=read(host,"EntityGetTransform",id)
      if (parent==nil or parent==0) and type(y)=="number" and math.abs(y-temple.y)<260 then
        local cost=component(host,id,"ItemCostComponent")
        local perk=perk_id(host,id)
        if cost or perk then
          local row={entity_id=id,x=x,y=y,name=read(host,"EntityGetName",id),
            filename=read(host,"EntityGetFilename",id),tags=read(host,"EntityGetTags",id)}
          if perk then row.perk_id=perk;snapshot.perks[#snapshot.perks+1]=row end
          if cost then
            row.cost=value(host,cost,"cost")
            local action=component(host,id,"ItemActionComponent")
            local ability=component(host,id,"AbilityComponent")
            row.spell_id=value(host,action,"action_id")
            -- Some custom spell cards (e.g. SUMMON_ROCK) have an AbilityComponent.
            -- A priced reroll machine also has ItemCostComponent. Neither is a wand.
            if action then
              row.item_kind="spell_card"
            elseif ability and (","..(row.tags or "")..","):find(",wand,",1,true) then
              row.item_kind="wand";row.wand=wand(host,id,ability)
            end
            local target=row.item_kind and snapshot.shop_items or snapshot.other_priced_entities
            target[#target+1]=row
          end
        end
      end
    end
  end
  local function order(a,b)
    if a.x==b.x then return a.y<b.y end
    return a.x<b.x
  end
  table.sort(snapshot.shop_items,order);table.sort(snapshot.perks,order)
  return snapshot
end
return M
