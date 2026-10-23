-- files/isf/worldgen/spell_select.lua
--
-- Spell selection for wands: performs the game's `GetRandomActionWithType` /
-- `GetRandomAction` weighted walk over the spell pool.
--
-- Substantial reuse: this is a direct port of
--   noita-telescope, js/spell_generator.js
--   MIT License, Copyright (c) 2026 Lymm
-- which reconstructs the vanilla `data/scripts/gun/gun_actions.lua` selection.
--
-- The POOL (ids, order, spawn weights) is owned by the foundation workflow in
-- files/isf/data/spells.lua and is injected here, so there is exactly one
-- authoritative spell list in the project. This module adds only the selection
-- algorithm and the per-spell type dimension.
--
-- Standalone Lua 5.1: no FFI, no external process, no file access.

local M = {}

-- deps:
--   prng_new(seed)  -> instance (see isf/random/prng.lua)
--   pool            -> foundation spell pool: array of { id, weights[1..11] }
--   spell_types     -> { PROJECTILE = 0, MODIFIER = 2, ... }
--   type_by_id      -> [typeId] = { spell_id, ... }
--   is_unlocked(id) -> boolean, from the generation-condition snapshot
local deps = nil

function M.init(d)
  deps = d
  return M
end

-- Type index of a pool spell id, or nil when unknown.
function M.spell_type(spell_id)
  if not deps then return nil end
  local map = deps.type_index
  if not map then
    -- Build a reverse lookup once per injected data set.
    map = {}
    for type_id, list in pairs(deps.type_by_id or {}) do
      for i = 1, #list do
        map[list[i]] = type_id
      end
    end
    deps.type_index = map
  end
  return map[spell_id]
end

-- Weight of a spell at a tier (0..10). Absent tiers are 0, exactly as the game.
local function weight_at(entry, level)
  if level < 0 then level = 0 end
  if level > 10 then level = 10 end
  local w = entry.weights
  if not w then return 0 end
  return w[level + 1] or 0
end

-- The pool slot is spawnable when it is unlocked for this snapshot and the
-- tier weight is positive.
local function eligible(entry, level, is_unlocked)
  if entry.requires_flag and not is_unlocked(entry.id) then
    return false
  end
  return weight_at(entry, level) > 0
end

-- GetRandomAction(x, y, level[, offset]) -> spell id or "".
-- Mirrors upstream: seed with world_seed + offset, sum every unlocked weight,
-- then walk the pool subtracting weights until the accumulated draw is covered.
function M.get_random_action(world_seed, x, y, level, offset, is_unlocked)
  if not level or level < 0 then
    -- Upstream derives the default tier from depth; callers in this project
    -- always pass an explicit tier, so fall back to depth like the game does.
    local depth_scale = math.floor(y / 512)
    if depth_scale <= 3 then level = 0
    elseif depth_scale <= 6 then level = 1
    elseif depth_scale <= 12 then level = 2
    elseif depth_scale <= 16 then level = 3
    elseif depth_scale <= 20 then level = 4
    elseif depth_scale <= 24 then level = 5
    elseif depth_scale <= 33 then level = 6
    elseif depth_scale > 35 then level = 7
    else level = 0 end
  end
  if level > 10 then level = 10 end

  -- The instance OWNS the world seed, and SetRandomSeed only takes (x, y).
  -- Upstream's three-argument call `SetRandomSeed(world_seed + offset, x, y)`
  -- maps onto "construct with world_seed + offset, then seed by position".
  -- The game does NOT add the NG+ count here.
  local rng = deps.prng_new(world_seed + (offset or 0))
  rng:SetRandomSeed(x, y)
  local multiplier = rng:Next()

  local pool = deps.pool
  local sum = 0.0
  for i = 1, #pool do
    local e = pool[i]
    if is_unlocked(e.id) and weight_at(e, level) > 0 then
      sum = sum + weight_at(e, level)
    end
  end

  local accumulated = sum * multiplier
  for i = 1, #pool do
    local e = pool[i]
    if is_unlocked(e.id) then
      local p = weight_at(e, level)
      if p > 0 then
        if p >= accumulated then
          return e.id
        end
        accumulated = accumulated - p
      end
    end
  end

  -- Expected sometimes: the game creates wands with no usable action.
  return ""
end

-- GetRandomActionWithType(x, y, level, type, offset) -> spell id or "".
function M.get_random_action_with_type(world_seed, x, y, level, type, offset, is_unlocked)
  if level > 10 then level = 10 end
  if level < 0 then level = 0 end
  local rng = deps.prng_new(world_seed + (offset or 0))
  rng:SetRandomSeed(x, y)

  local pool = deps.pool
  local sum = 0.0
  for i = 1, #pool do
    local e = pool[i]
    if is_unlocked(e.id) and M.spell_type(e.id) == type then
      sum = sum + weight_at(e, level)
    end
  end

  local accumulated = sum * rng:Next()
  for i = 1, #pool do
    local e = pool[i]
    if is_unlocked(e.id) and M.spell_type(e.id) == type then
      local p = weight_at(e, level)
      if p > 0 then
        if p >= accumulated then
          return e.id
        end
        accumulated = accumulated - p
      end
    end
  end
  return ""
end

return M
