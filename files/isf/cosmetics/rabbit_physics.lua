-- Two independently hinged 1px cord links, followed by a rigid 3px pendant.
-- Local Verlet state only; no game RNG or host calls.
local M = {}
local SUBSTEPS, ITERATIONS = 4, 24

function M.new(x, y, facing, frame, config)
    local state = {x=x, y=y, facing=facing, frame=frame, points={}}
    for i=1,config.joint_pixels+1 do
        local distance = i<=config.joint_pixels and i or config.joint_pixels+config.foot_length
        state.points[i] = {x=x, y=y+distance, px=x, py=y+distance}
    end
    state.joint = state.points[config.joint_pixels]
    state.foot = state.points[config.joint_pixels+1]
    return state
end

local function constrain(state, x, y, config)
    local points = state.points
    for _=1,ITERATIONS do
        for i,b in ipairs(points) do
            local a = points[i-1]
            local ax,ay = a and a.x or x, a and a.y or y
            local dx,dy = b.x-ax,b.y-ay
            local distance = math.sqrt(dx*dx+dy*dy)
            local length = i<=config.joint_pixels and 1 or config.foot_length
            if distance<0.000001 then
                b.x,b.y = ax,ay+length
            else
                local correction = (distance-length)/distance
                if not a then
                    b.x,b.y = ax+dx/distance,ay+dy/distance
                else
                    -- Light cord, heavier pendant. No compression or angle clamp.
                    local weight = i==#points and 0.9 or 0.5
                    a.x,a.y = a.x+dx*correction*weight,a.y+dy*correction*weight
                    b.x,b.y = b.x-dx*correction*(1-weight),b.y-dy*correction*(1-weight)
                end
            end
        end
    end
    -- Project forward once to retain exact pixel lengths for rendering.
    local ax,ay = x,y
    for i,b in ipairs(points) do
        local dx,dy = b.x-ax,b.y-ay
        local distance = math.sqrt(dx*dx+dy*dy)
        local length = i<=config.joint_pixels and 1 or config.foot_length
        if distance<0.000001 then b.x,b.y=ax,ay+length
        else b.x,b.y=ax+dx*length/distance,ay+dy*length/distance end
        ax,ay=b.x,b.y
    end
end

function M.step(state,x,y,facing,frame,config)
    local dx,dy=x-state.x,y-state.y
    if frame-state.frame>1 or frame<state.frame
        or dx*dx+dy*dy>config.teleport_distance*config.teleport_distance then
        return M.new(x,y,facing,frame,config)
    end
    if frame==state.frame then return state end
    if facing~=state.facing then
        for _,p in ipairs(state.points) do p.x,p.px=2*state.x-p.x,2*state.x-p.px end
    end
    local dt=1/(60*SUBSTEPS)
    local damping=config.damping^(1/SUBSTEPS)
    for step=1,SUBSTEPS do
        for _,p in ipairs(state.points) do
            local vx,vy=(p.x-p.px)*damping,(p.y-p.py)*damping
            p.px,p.py=p.x,p.y
            p.x,p.y=p.x+vx,p.y+vy+config.gravity*dt*dt
        end
        constrain(state,state.x+dx*step/SUBSTEPS,state.y+dy*step/SUBSTEPS,config)
    end
    state.x,state.y,state.facing,state.frame=x,y,facing,frame
    return state
end

function M.cord_pose(state,index)
    local a,b=state.points[index-1],state.points[index]
    local x,y=a and a.x or state.x,a and a.y or state.y
    return x,y,math.atan2(b.y-y,b.x-x)-math.pi/2
end

function M.foot_angle(state)
    return math.atan2(state.foot.y-state.joint.y,state.foot.x-state.joint.x)-math.pi/2
end

return M
