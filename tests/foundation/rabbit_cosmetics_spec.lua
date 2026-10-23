local rabbit=T.load("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_foot.lua")
local physics=T.load("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_physics.lua")
local config=T.load("mods/interesting_seed_filter/files/isf/cosmetics/rabbit_config.lua")
local file=assert(io.open(ISF_PROJECT_ROOT.."/files/isf/cosmetics/rabbit_spark.xml","rb"))
local emitter_xml=file:read("*a");file:close()
local emitter_defaults={}
for key,value in emitter_xml:match("<ParticleEmitterComponent(.-)/>"):gmatch('([%w_.]+)="([^"]+)"')do
    emitter_defaults[key]=tonumber(value)or value
end

T.describe("rabbit charm: native first-emission scheduling reaches one particle before cleanup")
do
    -- Installed Jan 25 2025 engine: ParticleEmitterSystem::on-add at 0xbc8967
    -- sets next_emit = birth + interval - 1. Update at 0xbc8c88 decrements
    -- emitter_lifetime_frames and removes it at zero BEFORE the emission check.
    -- This fixture checks the XML against that native schedule, not just EntityLoad.
    local entity_life=tonumber(emitter_xml:match('<LifetimeComponent%s+lifetime="(%d+)"'))
    local function emissions(interval,entity_frames,emitter_frames,start_delay)
        local born=10000
        local next_emit=born+interval-1
        local count=0
        for frame=born+start_delay,born+entity_frames-1 do
            if emitter_frames>0 then
                emitter_frames=emitter_frames-1
                if emitter_frames==0 then break end
            end
            if frame>=next_emit then count=count+1;next_emit=frame+interval end
        end
        return count
    end
    T.equal(emissions(120,2,-1,1),0,"previous 120-frame emitter dies before its first emission")
    for _,key in ipairs({'emission_interval_min_frames','emission_interval_max_frames'})do
        for delay=0,1 do
            T.equal(emissions(emitter_defaults[key],entity_life,
                emitter_defaults.emitter_lifetime_frames or -1,delay),1,
                "native scheduler emits once even if first update is delayed by one frame")
        end
    end
end

local function host(luck,values)
    local api={frame=0,clock=123.45,luck=luck,show=true,values=values or {},entities={},components={},sparks={},loads=0,killed={}}
    api.entities[1]={parent=0,tags={player_unit=true},x=0,y=0,angle=0,scale=1,children={}}
    local next_id=10
    local function entity(tags)
        local id=next_id;next_id=next_id+1
        api.entities[id]={parent=0,tags=tags,x=0,y=0,angle=0,scale=1,children={},visual=true}
        return id
    end
    function api.ModSettingGet(key)
        if key=="interesting_seed_filter.luck_level"then return api.luck end
        if key=="interesting_seed_filter.show_rabbit_foot"then return api.show end
    end
    function api.ModSettingGetNextValue()error("next-game selections must not affect the current charm")end
    function api.GlobalsGetValue(key,default)return api.values[key]or default end
    function api.GlobalsSetValue(key,value)api.values[key]=value end
    function api.EntityGetIsAlive(id)return api.entities[id]~=nil end
    function api.EntityHasTag(id,tag)return api.entities[id]and api.entities[id].tags[tag]or false end
    function api.EntityGetFirstComponent(id,kind,tag)
        if id==1 and kind=="HotspotComponent"and tag=="belt_root"and not api.no_belt then return 1 end
    end
    function api.EntityGetFirstComponentIncludingDisabled(id,kind,tag)
        if kind=="ParticleEmitterComponent"then return api.entities[id].emitter end
        return api.entities[id].sprites and api.entities[id].sprites[tag]
    end
    function api.EntityGetAllChildren(id,tag)
        local out={}
        for _,child in ipairs(api.entities[id].children)do
            if api.entities[child]and(not tag or api.entities[child].tags[tag])then out[#out+1]=child end
        end
        return out
    end
    function api.EntityGetWithTag(tag)
        local out={}
        for id,e in pairs(api.entities)do if e.tags[tag]then out[#out+1]=id end end
        table.sort(out);return out
    end
    function api.EntityGetParent(id)return api.entities[id].parent end
    function api.EntityGetHotspot(id)
        local e=api.entities[id];return e.x-2*e.scale,e.y-3
    end
    function api.EntityGetTransform(id)
        local e=api.entities[id];return e.x,e.y,e.angle,e.scale,1
    end
    function api.EntitySetTransform(id,x,y,angle)
        T.check(not api.entities[id].emitter,"particle emitter is never moved with the foot")
        local e=api.entities[id];e.x,e.y,e.angle=x,y,angle
    end
    function api.EntityApplyTransform(id,x,y,...)
        -- Installed engine ignores extra arguments; the full pose must be set first.
        local e=api.entities[id];e.x,e.y=x,y;e.sprite_angle=e.angle
    end
    function api.EntitySetComponentsWithTagEnabled(id,tag,visible)api.entities[id].visual=visible end
    function api.ComponentSetValue2(id,key,value)api.components[id][key]=value end
    function api.EntitySetComponentIsEnabled(_,id,enabled)api.components[id].enabled=enabled end
    function api.EntityAddChild(parent,child)
        api.entities[child].parent=parent
        table.insert(api.entities[parent].children,child)
    end
    function api.EntityLoad(path,x,y)
        if path=="mods/interesting_seed_filter/files/isf/cosmetics/rabbit_spark.xml"then
            local id=entity({isf_rabbit_particle_emitter=true})
            local e=api.entities[id];e.x,e.y,e.emitter=x,y,id*10+3
            local settings={};for k,v in pairs(emitter_defaults)do settings[k]=v end
            api.components[e.emitter]=settings
            local foot=api.foot()
            api.sparks[#api.sparks+1]={x=x,y=y,id=id,frame=api.frame,settings=settings,
                cx=foot.x-math.sin(foot.angle)*1.5,cy=foot.y+math.cos(foot.angle)*1.5}
            return id
        end
        T.equal(path,"mods/interesting_seed_filter/files/isf/cosmetics/rabbit_foot.xml","self-contained ISF entity path")
        api.loads=api.loads+1
        local root=entity({isf_rabbit_foot=true})
        for _,tag in ipairs({"isf_rabbit_cord_2","isf_rabbit_pendant"})do
            local id=entity({[tag]=true});api.EntityAddChild(root,id)
            if tag=="isf_rabbit_pendant"then
                api.entities[id].sprites={isf_rabbit_glow=id*10+1,isf_rabbit_halo=id*10+2}
                -- Match a continued save from the previous build.
                api.components[id*10+1]={emissive=false};api.components[id*10+2]={emissive=false}
            end
        end
        return root
    end
    function api.EntityKill(id)
        api.killed[id]=true
        for _,child in ipairs(api.entities[id].children)do if api.entities[child]then api.EntityKill(child)end end
        api.entities[id]=nil
    end
    function api.EntityRefreshSprite(_,id)
        api.components[id].applied_emissive=api.components[id].emissive
    end
    function api.GameGetFrameNum()return api.frame end
    function api.GameGetRealWorldTimeSinceStarted()return api.clock end
    function api.GameCreateSpriteForXFrames()error("sparkles must use native cosmetic particles")end
    function api.GameCreateCosmeticParticle()error("use the native emitter's ultrabright/lifetime fade options")end
    function api.SetRandomSeed()error("cosmetics must not reseed gameplay RNG")end
    function api.Random()error("cosmetics must not consume gameplay RNG")end
    function api.SetWorldSeed()error("cosmetics must not touch world generation")end
    function api.legacy()
        local id=entity({lrf_accessory=true});api.EntityAddChild(1,id);return id
    end
    function api.old_third_link(root)
        local id=entity({isf_rabbit_cord_3=true});api.EntityAddChild(root,id);return id
    end
    function api.old_sprite_spark(root)
        local id=entity({isf_rabbit_spark=true});api.EntityAddChild(root,id);return id
    end
    function api.foot()
        local id=api.EntityGetWithTag("isf_rabbit_pendant")[1];return api.entities[id],id
    end
    return api
end

T.describe("rabbit charm: Lv0 dark, monotonic local glow and sparkle density")
local last_glow,last_sparks=-1,-1
for level=0,6 do
    local style=rabbit.style(level)
    T.check(style.glow_alpha>last_glow,"glow increases at level "..level)
    last_glow=style.glow_alpha
    local api=host(level)
    local controller=rabbit.new(api);controller.spawned(1,level)
    for frame=1,180 do
        api.frame=frame;controller.update()
    end
    local foot,id=api.foot()
    T.check(#api.sparks>last_sparks,"particle density increases at level "..level)
    last_sparks=#api.sparks
    T.equal(api.components[id*10+1].enabled,level>0,"glow activation matches level")
    T.equal(api.components[id*10+2].enabled,level>0,"halo activation matches level")
    T.equal(api.components[id*10+1].alpha,style.glow_alpha,"actual brightness follows style")
    if level>0 then
        T.equal(api.components[id*10+1].emissive,true,"glow stays visible without ambient scene lighting")
        T.equal(api.components[id*10+1].applied_emissive,true,"continued-save sprite properties are refreshed")
    end
    T.equal(api.loads,1,"periodic reconcile does not duplicate charm")
    local root=api.EntityGetWithTag('isf_rabbit_foot')[1]
    T.equal(api.entities[root].y,-4,"anchor is one pixel above the belt hotspot")
    if level==0 then
        T.equal(#api.sparks,0,"Lv0 emits no particles")
        T.equal(style.glow_alpha,0,"Lv0 has no additive highlight")
    end
    for _,spark in ipairs(api.sparks)do
        local settings=spark.settings
        local r2=(spark.x-spark.cx)^2+(spark.y-spark.cy)^2
        T.check(r2>=1.25^2-1e-9 and r2<=3.25^2+1e-9,"particle originates in the small annulus")
        T.equal(settings.emitted_material_name,"spark_white_bright","vanilla constellation bright point material")
        T.equal(settings.render_ultrabright,1,"native particle glow multiplier enabled")
        T.equal(settings.fade_based_on_lifetime,1,"native lifetime fade enabled")
        T.equal(settings.particle_single_width,1,"point-sized particle")
        T.equal(settings.draw_as_long,0,"no streaks")
        T.equal(settings.count_min,1,"one particle per emission")
        T.equal(settings.count_max,1,"one particle per emission")
        T.check(settings.lifetime_min>=0.2 and settings.lifetime_max<=0.5,"short random lifetime")
        T.check(settings.custom_alpha>=0.55 and settings.custom_alpha<=1,"bright random intensity")
        T.check(settings.x_vel_min^2+settings.y_vel_min^2<=1.5^2+1e-9,"initial speed near zero")
        T.equal(settings.render_back,0,"foreground native emitter")
        T.equal(settings.emit_cosmetic_particles,1,"cosmetic particles only")
        T.equal(settings.create_real_particles,0,"no material cells")
        T.equal(settings.emit_real_particles,0,"no real particles")
        T.equal(settings.collide_with_grid,0,"no grid collision")
        T.equal(settings['gravity.x'],0,"no horizontal acceleration")
        T.equal(settings['gravity.y'],0,"no downward acceleration")
        T.equal(api.entities[spark.id].parent,0,"emitter is independent of player hierarchy")
    end
end
T.describe("rabbit charm: emitted particles are independent of subsequent player movement")
do
    local api=host(6);local controller=rabbit.new(api);controller.spawned(1,6)
    local first,first_x,first_y
    for frame=1,240 do
        api.entities[1].x=frame*0.75
        api.entities[1].y=frame*2
        api.frame=frame;controller.update()
        if not first and api.sparks[1]then first=api.sparks[1];first_x,first_y=first.x,first.y end
        T.equal(#api.EntityGetWithTag('isf_rabbit_spark'),0,"no sparkle sprite entities attached to charm")
    end
    T.check(first~=nil,"native emission occurred")
    T.equal(first.x,first_x,"emitted world x is never repositioned with player")
    T.equal(first.y,first_y,"emitted world y is never repositioned with player")
    T.equal(api.loads,1,"only charm entity is loaded")
    local count=#api.sparks
    api.show=false;api.frame=241;controller.update()
    T.equal(#api.sparks,count,"hiding charm stops emission; engine expires existing particles")
end

T.describe("rabbit charm: varied particle timing, position, direction, brightness and launch seed")
do
    local api=host(6);local controller=rabbit.new(api);controller.spawned(1,6)
    for frame=1,1200 do api.frame=frame;controller.update()end
    local quadrants,velocities,gaps,alphas,lifetimes={},{},{},{},{}
    local vx_sum,vy_sum=0,0
    for i,spark in ipairs(api.sparks)do
        local s=spark.settings
        quadrants[(spark.x>spark.cx and 1 or 0)+(spark.y>spark.cy and 2 or 0)]=true
        velocities[(s.x_vel_min>0 and 1 or 0)+(s.y_vel_min>0 and 2 or 0)]=true
        if i>1 then gaps[spark.frame-api.sparks[i-1].frame]=true end
        alphas[math.floor(s.custom_alpha*100)]=true
        lifetimes[math.floor(s.lifetime_min*100)]=true
        vx_sum,vy_sum=vx_sum+s.x_vel_min,vy_sum+s.y_vel_min
    end
    local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
    T.equal(count(quadrants),4,"spawn positions cover all four quadrants")
    T.equal(count(velocities),4,"initial velocities cover all directions")
    T.check(count(gaps)>=4,"emission has varied timing instead of a metronome")
    T.check(count(alphas)>=12,"particles have varied brightness")
    T.check(count(lifetimes)>=12,"particles have varied lifetimes")
    T.check(math.abs(vx_sum/#api.sparks)<0.2 and math.abs(vy_sum/#api.sparks)<0.2,"no systematic upward or sideways drift")
    local another=host(6);another.clock=456.78
    local next_controller=rabbit.new(another);next_controller.spawned(1,6)
    for frame=1,30 do another.frame=frame;next_controller.update()end
    T.check(api.sparks[1].x~=another.sparks[1].x or api.sparks[1].y~=another.sparks[1].y,
        "separate sessions do not replay a fixed entity-ID pattern")
end

T.describe("rabbit charm: current-run luck persists independently of pending settings")
do
    local api=host(1);local controller=rabbit.new(api)
    local legacy=api.legacy()
    controller.spawned(1,4)
    T.equal(api.values['interesting_seed_filter.rabbit_luck_level'],'4',"committed search selection wins")
    T.check(api.killed[legacy],"saved standalone charm is replaced")
    local root=api.EntityGetWithTag('isf_rabbit_foot')[1]
    local extra=api.old_third_link(root)
    local old_spark=api.old_sprite_spark(root)
    controller.spawned(1)
    T.check(api.killed[extra],"continued three-link charm loses obsolete third link")
    T.check(api.killed[old_spark],"continued save loses attached sprite sparkles")
    T.equal(api.loads,1,"existing charm migrates without a duplicate")
    api.luck=6
    controller=rabbit.new(api);api.frame=1;controller.update()
    local _,id=api.foot()
    T.equal(api.components[id*10+1].alpha,rabbit.style(4).glow_alpha,"continue keeps original run level")
    controller.spawned(1,0)
    api.frame=2;controller.update()
    T.equal(api.components[id*10+1].enabled,false,"committed Lv0 overrides an early fallback capture")
    api.no_belt=true;api.frame=3;controller.update()
    T.equal(api.entities[id].visual,false,"polymorph without belt hides charm")
    api.no_belt=false;api.frame=4;controller.update()
    T.equal(api.entities[id].visual,true,"return restores charm")
    api.show=false;api.frame=5;controller.update()
    T.equal(#api.EntityGetWithTag('isf_rabbit_foot'),0,"switch removes owned entities")
    T.check(api.entities[1]~=nil,"visibility never removes player")
end
do
    local json='{"search_settings":{"extra_holy_mountains":0,"luck_level":5}}'
    local receipt='ISF_START_V1:'..json:gsub('.',function(c)return string.format('%02x',c:byte())end)
    local api=host(1,{['interesting_seed_filter.start_result']=receipt})
    local controller=rabbit.new(api);controller.spawned(1)
    T.equal(api.values['interesting_seed_filter.rabbit_luck_level'],'5',"pre-integration save uses its actual search receipt")
end

T.describe("rabbit charm: two independent pixel joints transmit rotation and allow inversion")
do
    local api=host(0);local controller=rabbit.new(api);controller.spawned(1,0)
    local max_angle,bent=0,false
    for frame=1,240 do
        api.frame=frame
        local player=api.entities[1]
        player.x=math.min(frame,30)*0.5
        local t=math.max(0,frame-30)/60
        player.y=t<=200/350 and 175*t*t or 200*t-200*200/(2*350)
        controller.update()
        local root=api.entities[api.EntityGetWithTag('isf_rabbit_foot')[1]]
        local cord2=api.entities[api.EntityGetWithTag('isf_rabbit_cord_2')[1]]
        local foot=api.foot()
        local links={root,cord2,foot}
        for i=1,2 do
            local a,b=links[i],links[i+1]
            T.check(math.abs(b.x-(a.x-math.sin(a.angle)))<0.000001,"cord pixel x remains connected")
            T.check(math.abs(b.y-(a.y+math.cos(a.angle)))<0.000001,"cord pixel y remains connected")
        end
        T.equal(foot.sprite_angle,foot.angle,"rendering uses actual pendant rotation")
        max_angle=math.max(max_angle,math.abs(foot.angle))
        if math.abs(root.angle-cord2.angle)>0.01 then bent=true end
    end
    T.check(bent,"red cord bends between pixels rather than rotating as a rigid bar")
    T.check(max_angle>math.rad(160),"high fall can invert pendant")
end

T.describe("rabbit charm: solver preserves 1+1+3 lengths and resets large teleports")
do
    local state=physics.new(0,0,1,0,config)
    for frame=1,600 do
        local x=frame<180 and frame*0.5 or 90
        state=physics.step(state,x,0,1,frame,config)
        local ax,ay=x,0
        for i,p in ipairs(state.points)do
            local distance=math.sqrt((p.x-ax)^2+(p.y-ay)^2)
            T.check(math.abs(distance-(i<=2 and 1 or 3))<0.000001,"exact chain lengths")
            ax,ay=p.x,p.y
        end
    end
    T.check(math.abs(physics.foot_angle(state))<0.001,"settles after stopping")
    state=physics.step(state,1000,1000,-1,602,config)
    T.equal(state.foot.y,1005,"teleport/load gap restores five-pixel hanging length")
end
