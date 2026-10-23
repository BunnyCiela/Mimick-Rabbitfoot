local preferences=dofile_once("mods/interesting_seed_filter/files/isf/core/preferences.lua")
local physics=dofile_once("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_physics.lua")
local config=dofile_once("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_config.lua")
local PREFIX="mods/interesting_seed_filter/files/isf/cosmetics/"
local LEVEL_KEY="interesting_seed_filter.rabbit_luck_level"
local M={}
local glow={0,0.12,0.23,0.36,0.50,0.67,0.85}
local intervals={0,48,32,22,15,10,6}

local function receipt_level(api)
    if type(api.GlobalsGetValue)~="function"then return end
    local receipt=api.GlobalsGetValue("interesting_seed_filter.start_result","")
    local prefix="ISF_START_V1:"
    if type(receipt)~="string"or #receipt>16384 or receipt:sub(1,#prefix)~=prefix then return end
    local hex=receipt:sub(#prefix+1)
    if #hex%2~=0 or hex:find("[^%x]")then return end
    local json=hex:gsub("%x%x",function(pair)return string.char(tonumber(pair,16))end)
    local selection=json:match('"search_settings"%s*:%s*(%b{})')
    local value=selection and tonumber(selection:match('"luck_level"%s*:%s*(%d+)%s*[,}]'))
    if value and value>=0 and value<=6 then return value end
end

function M.style(level)
    level=preferences.normalize({luck_level=level}).luck_level
    return {level=level,glow_alpha=glow[level+1],halo_alpha=glow[level+1]*0.5,
        particle_interval=intervals[level+1]}
end

function M.new(api)
    local states,level={},nil
    local self={}
    local function selected_level(selected)
        if level~=nil and selected==nil then return level end
        local stored=type(api.GlobalsGetValue)=="function"and tonumber(api.GlobalsGetValue(LEVEL_KEY,""))or nil
        local active=type(api.ModSettingGet)=="function"and api.ModSettingGet("interesting_seed_filter.luck_level")or nil
        -- A committed new run supplies its exact selection; continued runs keep it.
        level=preferences.normalize({luck_level=selected~=nil and selected or stored or receipt_level(api)or active}).luck_level
        if type(api.GlobalsSetValue)=="function"then api.GlobalsSetValue(LEVEL_KEY,tostring(level))end
        return level
    end
    local function enabled()
        return type(api.ModSettingGet)~="function"or api.ModSettingGet("interesting_seed_filter.show_rabbit_foot")~=false
    end
    local function eligible(player)
        return player~=0 and api.EntityGetIsAlive(player) and api.EntityHasTag(player,"player_unit")
            and not api.EntityHasTag(player,"polymorphed")
            and api.EntityGetFirstComponent(player,"HotspotComponent","belt_root")~=nil
    end
    local function child(root,tag)
        return (api.EntityGetAllChildren(root,tag)or {})[1]
    end
    local function remove_legacy(player)
        for _,old in ipairs(api.EntityGetAllChildren(player,"lrf_accessory")or {})do api.EntityKill(old)end
    end
    local function trim_old_cord(root)
        local extra=child(root,"isf_rabbit_cord_3")
        if extra then api.EntityKill(extra);states[root]=nil end
        -- Retire the previous build's attached sprite sparkles on continued saves.
        for _,old in ipairs(api.EntityGetAllChildren(root,"isf_rabbit_spark")or {})do api.EntityKill(old)end
    end
    function self.spawned(player,selected)
        selected_level(selected)
        remove_legacy(player)
        if not enabled()or not eligible(player)then return end
        local existing=child(player,"isf_rabbit_foot")
        if existing then trim_old_cord(existing)else
            local x,y=api.EntityGetHotspot(player,"belt_root",true)
            local entity=api.EntityLoad(PREFIX.."rabbit_foot.xml",x,y)
            if entity and entity~=0 then api.EntityAddChild(player,entity)end
        end
    end
    local function pose(entity,x,y,angle)
        api.EntitySetTransform(entity,x,y,angle,1,1)
        -- The installed game's Apply binding only reads x/y; rotation is set above.
        api.EntityApplyTransform(entity,x,y)
    end
    local function visibility(root,visible)
        api.EntitySetComponentsWithTagEnabled(root,"isf_rabbit_visual",visible)
        for _,entity in ipairs(api.EntityGetAllChildren(root)or {})do
            api.EntitySetComponentsWithTagEnabled(entity,"isf_rabbit_visual",visible)
        end
    end
    local function random(state)
        state.random=(state.random*16807)%2147483647
        return state.random/2147483647
    end
    local function sparkle(state,frame,x,y,style)
        if style.particle_interval==0 then return end
        if frame<state.next_sparkle then return end
        state.next_sparkle=frame+math.max(2,math.floor(style.particle_interval*(0.5+random(state))))
        -- Uniform annulus around the foot; motion direction is independently sampled.
        local angle=random(state)*math.pi*2
        local radius=math.sqrt(1.25^2+random(state)*(3.25^2-1.25^2))
        local direction=random(state)*math.pi*2
        local speed=math.sqrt(random(state))*1.5
        local vx,vy=math.cos(direction)*speed,math.sin(direction)*speed
        local alpha=(0.55+style.level*0.025)+(0.30*random(state))
        local lifetime=0.20+random(state)*0.30
        -- Interpolate white (#ffffff) to gold (#ffd050); native color is AABBGGRR.
        local warmth=random(state)
        local green=math.floor(255-47*warmth+0.5)
        local blue=math.floor(255-175*warmth+0.5)
        local color=0xff000000+blue*0x10000+green*0x100+0xff
        -- Unlike the simple Lua particle API, the emitter exposes ultrabright and
        -- lifetime fade used by vanilla star/sun particles. No sprite is created.
        local emitter=api.EntityLoad(PREFIX.."rabbit_spark.xml",x+math.cos(angle)*radius,y+math.sin(angle)*radius)
        if not emitter or emitter==0 then return end
        local component=api.EntityGetFirstComponentIncludingDisabled(emitter,"ParticleEmitterComponent","isf_rabbit_emitter")
        if component then
            for key,value in pairs({color=color,custom_alpha=alpha,lifetime_min=lifetime,lifetime_max=lifetime,
                x_vel_min=vx,x_vel_max=vx,y_vel_min=vy,y_vel_max=vy})do
                api.ComponentSetValue2(component,key,value)
            end
        end
        -- Do not attach or reposition it: the native particles live in world space.
    end
    function self.update()
        local frame=api.GameGetFrameNum()
        if not enabled()then
            for _,root in ipairs(api.EntityGetWithTag("isf_rabbit_foot")or {})do api.EntityKill(root)end
            states={}
            return
        end
        selected_level()
        if frame%30==0 then
            for _,player in ipairs(api.EntityGetWithTag("player_unit")or {})do self.spawned(player)end
        end
        local live={}
        for _,root in ipairs(api.EntityGetWithTag("isf_rabbit_foot")or {})do
            live[root]=true
            trim_old_cord(root)
            local player=api.EntityGetParent(root)
            local foot=child(root,"isf_rabbit_pendant")
            local cord2=child(root,"isf_rabbit_cord_2")
            if eligible(player)and foot and cord2 then
                local x,y=api.EntityGetHotspot(player,"belt_root",true)
                local _,_,_,scale=api.EntityGetTransform(player)
                local facing=scale<0 and -1 or 1
                x,y=x+config.offset_x*facing,y+config.offset_y
                local state=states[root]
                if not state then
                    local clock=type(api.GameGetRealWorldTimeSinceStarted)=="function"and api.GameGetRealWorldTimeSinceStarted()or frame/60
                    local seed=(root*104729+frame*8191+math.floor(clock*1000000))%2147483646+1
                    state={physics=physics.new(x,y,facing,frame,config),random=seed,next_sparkle=frame}
                    state.next_sparkle=frame+math.floor(random(state)*8)
                    states[root]=state
                end
                state.physics=physics.step(state.physics,x,y,facing,frame,config)
                visibility(root,true)
                local p=state.physics
                pose(root,physics.cord_pose(p,1))
                pose(cord2,physics.cord_pose(p,2))
                pose(foot,p.joint.x,p.joint.y,physics.foot_angle(p))
                local style=M.style(level)
                for _,kind in ipairs({"glow","halo"})do
                    local component=api.EntityGetFirstComponentIncludingDisabled(foot,"SpriteComponent","isf_rabbit_"..kind)
                    if component then
                        api.ComponentSetValue2(component,"alpha",style[kind.."_alpha"])
                        if not state.visual_prepared then
                            api.ComponentSetValue2(component,"emissive",kind=="glow")
                            -- A continued save still contains the old non-emissive sprite.
                            if type(api.EntityRefreshSprite)=="function"then api.EntityRefreshSprite(foot,component)end
                        end
                        api.EntitySetComponentIsEnabled(foot,component,level>0)
                    end
                end
                state.visual_prepared=true
                sparkle(state,frame,(p.joint.x+p.foot.x)/2,(p.joint.y+p.foot.y)/2,style)
            else
                visibility(root,false)
                states[root]=nil
            end
        end
        for root in pairs(states)do if not live[root]then states[root]=nil end end
    end
    return self
end
return M
