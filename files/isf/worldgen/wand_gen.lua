-- files/isf/worldgen/wand_gen.lua
--
-- Reproduces Noita's random wand generation: stats (capacity, recharge, cast
-- delay, spread, speed, mana), shuffle behaviour, Always Cast, and the spell
-- cards inside the wand.
--
-- Substantial reuse: this is a direct port of
--   noita-telescope, js/gun_generation.js  (and the level-1 premade path from
--   js/wand_generation.js)
--   MIT License, Copyright (c) 2026 Lymm
-- which reconstructs vanilla `data/scripts/gun/gun.lua` / `gun_actions.lua`.
--
-- Standalone Lua 5.1: no FFI, no external process, no file access. The spell
-- pool and its type dimension are injected (see isf/worldgen/spell_select.lua).
--
-- Interoperability notes for report consumers:
--   * `deck_capacity` is a float in upstream too (capacity += cost/5). It is
--     NOT rounded here so downstream comparisons match the predictor; use
--     math.floor(...) when a physical slot count is needed.
--   * `always_casts` is a list; the game also permits two on special wands.

local M = {}

local deps = nil

-- deps:
--   prng_new(seed)
--   wand_config        -> files/isf/worldgen/data/wand_config.lua
--   spell_select       -> isf/worldgen/spell_select.lua
--   is_unlocked(id)    -> boolean
function M.init(d)
  deps = d
  return M
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Round half to even, matching utils.js:roundHalfOfEven.
local function round_half_even(v)
  local f = math.floor(v)
  local diff = v - f
  if diff < 0.5 then return f end
  if diff > 0.5 then return f + 1 end
  if f % 2 == 0 then return f end
  return f + 1
end
M.round_half_even = round_half_even

-- shuffleTable: Fisher-Yates driven by the wand PRNG.
local function shuffle_table(t, rng)
  for i = #t, 2, -1 do
    local j = rng:Random(0, i - 1) + 1
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- getGunProbs: weighted pick over a stat's probability rows.
--
-- Returns nil when a stat has no probability table. That is not an error:
-- `shuffle_deck_when_empty` has no table upstream, and the important detail is
-- that the missing table means the seed draw is NOT consumed here. Returning
-- early without touching the PRNG is what keeps downstream stats aligned.
local function get_gun_probs(wand_flavour, variable, rng)
  local flavour = deps.wand_config.gun_probs[wand_flavour]
  if not flavour then return nil end
  local entry = flavour[variable]
  if not entry then return nil end
  local total = 0
  for i = 1, #entry do
    total = total + entry[i].prob
  end
  local r = rng:Next() * total
  for i = 1, #entry do
    if r < entry[i].prob then
      return entry[i]
    end
    r = r - entry[i].prob
  end
  -- Possible when the seeded draw lands exactly on the summed total.
  return entry[#entry]
end

local function apply_random_variable(gun, variable, rng)
  local probs = get_gun_probs(gun.wand_type, variable, rng)

  if variable == "shuffle_deck_when_empty" then
    -- No probability table for this stat: draw directly, exactly as upstream.
    local r = rng:Random(0, 1)
    if gun.force_unshuffle == 1 then
      r = 1
    end
    if r == 1 and gun.cost >= 15 + gun.deck_capacity * 5 and gun.deck_capacity <= 9 then
      gun[variable] = 0
      gun.cost = gun.cost - (15 + gun.deck_capacity * 5)
    end
    return
  end

  if not probs then
    error("wand_gen: no gun probs for " .. tostring(gun.wand_type) .. "/" .. tostring(variable))
  end

  if variable == "reload_time" then
    local min = clamp(60 - gun.cost * 5, 1, 240)
    local max = 1024
    gun[variable] = clamp(rng:RandomDistribution(probs.min, probs.max, probs.mean, probs.sharpness), min, max)
    gun.cost = gun.cost - (60 - gun[variable]) / 5
  elseif variable == "fire_rate_wait" then
    local min = clamp(16 - gun.cost, -50, 50)
    local max = 50
    gun[variable] = clamp(rng:RandomDistribution(probs.min, probs.max, probs.mean, probs.sharpness), min, max)
    gun.cost = gun.cost - (16 - gun[variable])
  elseif variable == "spread_degrees" then
    local min = clamp(gun.cost / -1.5, -35, 35)
    local max = 35
    gun[variable] = clamp(rng:RandomDistribution(probs.min, probs.max, probs.mean, probs.sharpness), min, max)
    -- Upstream subtracts the same (16 - value) expression here as well; this
    -- looks like a bug in the predictor but it is what the game does, so it is
    -- preserved bit for bit.
    gun.cost = gun.cost - (16 - gun[variable])
  elseif variable == "speed_multiplier" then
    gun[variable] = rng:RandomDistributionf(probs.min, probs.max, probs.mean, probs.sharpness)
  elseif variable == "deck_capacity" then
    local min = 1
    local max = clamp(gun.cost / 5 + 6, 1, 20)
    if gun.force_unshuffle == 1 then
      min = 1
      max = (gun.cost - 15) / 5
      if max > 6 then
        max = 6 + (gun.cost - (15 + 6 * 5)) / 10
      end
    end
    max = clamp(max, 1, 20)
    gun[variable] = clamp(rng:RandomDistribution(probs.min, probs.max, probs.mean, probs.sharpness), min, max)
    gun.cost = gun.cost - (gun[variable] - 6) * 5
  elseif variable == "actions_per_round" then
    local action_costs = {
      0,
      5 + gun.deck_capacity * 2,
      15 + gun.deck_capacity * 3.5,
      35 + gun.deck_capacity * 5,
      45 + gun.deck_capacity * gun.deck_capacity,
    }
    local min, max = 1, 1
    for i = 1, 5 do
      if action_costs[i] <= gun.cost then
        max = i
      end
    end
    max = clamp(max, 1, gun.deck_capacity)
    gun[variable] = math.floor(clamp(
      rng:RandomDistribution(probs.min, probs.max, probs.mean, probs.sharpness), min, max))
    gun.cost = gun.cost - action_costs[clamp(gun[variable], 1, 5)]
  end
end

-- getWandSprite: picks the closest cosmetic sprite shape. The SPRITE ITSELF IS
-- NOT SCORED, but the roll consumes RNG state, and the card generation that
-- follows depends on that state, so this must run in the same order upstream
-- runs it or every downstream card differs.
local function get_wand_sprite(gun, rng)
  local shapes = deps.wand_config.wand_shapes
  if not shapes or #shapes == 0 then
    -- Without shape data the roll cannot be reproduced; fail loudly rather than
    -- silently shifting the PRNG stream.
    error("wand_gen: wand_shapes data missing; the sprite roll consumes RNG")
  end

  local function wand_diff(wand)
    local score = 0
    score = score + math.abs(gun.fire_rate_wait - wand[6]) * 2
    score = score + math.abs(gun.actions_per_round - wand[7]) * 20
    score = score + math.abs(gun.shuffle_deck_when_empty - wand[8]) * 30
    score = score + math.abs(gun.deck_capacity - wand[9]) * 5
    score = score + math.abs(gun.spread_degrees - wand[10])
    score = score + math.abs(gun.reload_time - wand[11])
    return score
  end

  local gun_in_wand_space = {
    fire_rate_wait = clamp((gun.fire_rate_wait + 5) / 7 - 1, 0, 4),
    actions_per_round = clamp(gun.actions_per_round - 1, 0, 2),
    shuffle_deck_when_empty = clamp(gun.shuffle_deck_when_empty, 0, 1),
    deck_capacity = clamp((gun.deck_capacity - 3) / 3, 0, 7),
    spread_degrees = clamp((gun.spread_degrees + 5) / 5 - 1, 0, 2),
    reload_time = clamp((gun.reload_time + 5) / 25 - 1, 0, 2),
  }
  -- wandDiff indexes the shape array positionally, so build a probe row in the
  -- same layout (indices 6..11 are fire_rate_wait..reload_time).
  local probe = {
    [6] = gun_in_wand_space.fire_rate_wait,
    [7] = gun_in_wand_space.actions_per_round,
    [8] = gun_in_wand_space.shuffle_deck_when_empty,
    [9] = gun_in_wand_space.deck_capacity,
    [10] = gun_in_wand_space.spread_degrees,
    [11] = gun_in_wand_space.reload_time,
  }

  local best, best_score = nil, 1000
  for i = 1, #shapes do
    local score = wand_diff(probe)
    -- wand_diff above must read from the SHAPE for the shape's own coordinates
    -- and from the probe for the gun's; recompute properly:
    local s = shapes[i]
    score = math.abs(probe[6] - s[6]) * 2
      + math.abs(probe[7] - s[7]) * 20
      + math.abs(probe[8] - s[8]) * 30
      + math.abs(probe[9] - s[9]) * 5
      + math.abs(probe[10] - s[10])
      + math.abs(probe[11] - s[11])
    if score <= best_score then
      best, best_score = s, score
      if score == 0 then
        if rng:Random(0, 100) < 33 then break end
      end
    end
  end

  if not best then return end
  gun.grip = { x = best[2], y = best[3] }
  gun.tip = { x = best[4], y = best[5] }
  gun.sprite = string.format("wand_%04d", best[1])
end

-- Always Cast + in-wand cards. The two upstream variants differ only in the
-- `better` extra card block, which is reproduced here in order.
local function add_random_cards(world_seed, ng_plus, gun, x, y, level, rng, better)
  local ss = deps.spell_select
  local unlocked = deps.is_unlocked

  local good_cards = 5
  local first = rng:Random(0, 100)
  if first < 7 then
    good_cards = rng:Random(20, 50)
  end
  if gun.is_rare ~= 0 then
    good_cards = good_cards * 2
  end

  local orig_level = level
  level = level - 1
  local deck_capacity = gun.deck_capacity
  local actions_per_round = gun.actions_per_round
  local card_count = rng:Random(1, 3)
  local bullet_card = ss.get_random_action_with_type(world_seed, x, y, level,
    deps.wand_config.spell_types.PROJECTILE, 0, unlocked)

  if deps.trace then
    deps.trace("cards.entry", {
      better = better, level = level, deck_capacity = deck_capacity,
      actions_per_round = actions_per_round, card_count = card_count,
      is_rare = gun.is_rare, bullet_card = bullet_card,
    })
  end

  -- Upstream line 411: draw unconditionally, bump only when card_count < 3.
  -- This is a DIFFERENT draw from the 50% branch selection at line 442 below.
  if rng:Random(0, 100) < 50 and card_count < 3 then card_count = card_count + 1 end
  if rng:Random(0, 100) < 10 or gun.is_rare == 1 then
    card_count = card_count + rng:Random(1, 2)
  end

  good_cards = rng:Random(5, 45)
  local half_lo = round_half_even(0.51 * deck_capacity)
  local half_hi = round_half_even(deck_capacity)
  card_count = rng:Random(half_lo, half_hi)
  local raw_count = card_count
  card_count = clamp(card_count, 1, deck_capacity - 1)
  gun.card_count = card_count
  if deps.trace then
    deps.trace("cards.count", {
      half_lo = half_lo, half_hi = half_hi, raw_count = raw_count,
      clamped = card_count, card_count_before = gun.card_count,
    })
  end

  local random_bullets = 0
  if rng:Random(0, 100) < orig_level * 10 - 5 then random_bullets = 1 end

  -- Always Cast roll
  if rng:Random(0, 100) < 4 or gun.is_rare == 1 then
    local p = rng:Random(0, 100)
    local card
    local T = deps.wand_config.spell_types
    if p < 77 then
      card = ss.get_random_action_with_type(world_seed, x, y, level + 1, T.MODIFIER, 666, unlocked)
    elseif p < 85 then
      card = ss.get_random_action_with_type(world_seed, x, y, level + 1, T.MODIFIER, 666, unlocked)
    elseif p < 93 then
      card = ss.get_random_action_with_type(world_seed, x, y, level + 1, T.STATIC_PROJECTILE, 666, unlocked)
    else
      card = ss.get_random_action_with_type(world_seed, x, y, level + 1, T.PROJECTILE, 666, unlocked)
    end
    if card ~= "" then
      gun.always_casts = { card }
    else
      gun.always_casts = {}
    end
  else
    gun.always_casts = {}
  end

  local T = deps.wand_config.spell_types

  if better then
    -- betterAddRandomCards: no extra-level reroll loop (that loop consumes RNG,
    -- so omitting it is required for alignment), but everything else matches.
    if card_count < 3 then
      if card_count > 1 and rng:Random(0, 100) < 20 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.MODIFIER, 2, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      for _ = 1, math.floor(card_count) do
        if bullet_card ~= "" then gun.cards[#gun.cards + 1] = bullet_card end
      end
    else
      if rng:Random(0, 100) < 40 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, 1, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      if card_count > 3 and rng:Random(0, 100) < 40 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, 1, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      if rng:Random(0, 100) < 80 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.MODIFIER, 2, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      for _ = 1, math.floor(card_count) do
        if bullet_card ~= "" then gun.cards[#gun.cards + 1] = bullet_card end
      end
    end
    return
  end

  -- Upstream line 442: a separate 50% branch selects "fill from the bullet card"
  -- versus the per-card "good card" loop. This draw must happen AFTER the
  -- Always Cast block above, which also consumes RNG.
  if rng:Random(0, 100) < 50 then
    local extra_level = level
    while rng:Random(1, 10) == 10 do
      extra_level = extra_level + 1
      bullet_card = ss.get_random_action_with_type(world_seed, x, y, extra_level,
        T.PROJECTILE, 0, unlocked)
    end
    if card_count < 3 then
      if card_count > 1 and rng:Random(0, 100) < 20 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.MODIFIER, 2, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      for _ = 1, math.floor(card_count) do
        if bullet_card ~= "" then gun.cards[#gun.cards + 1] = bullet_card end
      end
    else
      if rng:Random(0, 100) < 40 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, 1, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      if card_count > 3 and rng:Random(0, 100) < 40 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, 1, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      if rng:Random(0, 100) < 80 then
        local card = ss.get_random_action_with_type(world_seed, x, y, level, T.MODIFIER, 2, unlocked)
        if card ~= "" then gun.cards[#gun.cards + 1] = card end
        card_count = card_count - 1
      end
      for _ = 1, math.floor(card_count) do
        if bullet_card ~= "" then gun.cards[#gun.cards + 1] = bullet_card end
      end
    end
    return
  end

  local good_card_count = 0
  -- Upstream iterates i = 0 .. floor(card_count)-1 and passes `i + 1` as the
  -- selection offset. This loop is 1-based, so the offset is exactly `i`.
  for i = 1, math.floor(card_count) do
    local r = rng:Random(0, 100)
    if r < good_cards and card_count > 2 then
      local card
      if good_card_count == 0 and actions_per_round == 1 then
        card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, i, unlocked)
        good_card_count = good_card_count + 1
      else
        if rng:Random(0, 100) < 83 then
          card = ss.get_random_action_with_type(world_seed, x, y, level, T.MODIFIER, i, unlocked)
        else
          card = ss.get_random_action_with_type(world_seed, x, y, level, T.DRAW_MANY, i, unlocked)
        end
      end
      if card ~= "" then gun.cards[#gun.cards + 1] = card end
    else
      if bullet_card ~= "" then gun.cards[#gun.cards + 1] = bullet_card end
      if random_bullets == 1 then
        bullet_card = ss.get_random_action_with_type(world_seed, x, y, level,
          T.PROJECTILE, i, unlocked)
      end
    end
  end
end

-- generate_level1_premade(world_seed, ng_plus, type_name, x, y)
--
-- Premade wands (`premade_1` .. `premade_17`) are a SEPARATE generation path from
-- the procedural one: they clone a fixed template and add at most a few cards.
-- Port of wand_generation.js:generateLevel1Wand.
function M.generate_level1_premade(world_seed, ng_plus, type_name, x, y)
  local cfg = deps.wand_config
  local premades = cfg.premade_wands
  if premades == nil or #premades == 0 then
    return nil, "premade_wands data missing"
  end

  -- `premade_N` -> index N-1 (mod list length), matching upstream.
  local index = tonumber(string.match(type_name, "^premade_(%d+)$"))
  if index == nil then
    return nil, "unknown premade wand type " .. tostring(type_name)
  end
  local ref = premades[((index - 1) % #premades) + 1]

  local rng = deps.prng_new(world_seed + (ng_plus or 0))
  rng:SetRandomSeed(x, y)

  local gun = {
    x = x, y = y,
    cards = {},
    is_rare = 0,
    wand_type = type_name,
    force_unshuffle = 0,
    original_force_unshuffle = 0,
    always_casts = {},
    name = ref.name,
    level = 1,
    cost = 0,
    actions_per_round = ref.actions_per_round,
    deck_capacity = ref.deck_capacity,
    reload_time = ref.reload_time,
    shuffle_deck_when_empty = ref.shuffle_deck_when_empty,
    fire_rate_wait = ref.fire_rate_wait,
    spread_degrees = ref.spread_degrees,
    mana_max = ref.mana_max,
    mana_charge_speed = ref.mana_charge_speed,
    speed_multiplier = ref.speed_multiplier,
    prob_unshuffle = 0.1,
    prob_draw_many = 0.15,
  }

  local reload_time = gun.reload_time
  local fire_rate_wait = gun.fire_rate_wait
  local spread_degrees = gun.spread_degrees
  local deck_capacity = gun.deck_capacity
  local total = reload_time + fire_rate_wait + spread_degrees
  total = total + rng:Random(-10, 20)

  local level_1_cards = {
    "LIGHT_BULLET", "RUBBER_BALL", "ARROW", "DISC_BULLET",
    "BOUNCY_ORB", "BULLET", "AIR_BULLET", "SLIMEBALL",
  }
  local card_count = rng:Random(1, 5)

  if rng:Random(1, 100) <= 85 then
    level_1_cards[#level_1_cards + 1] = "BUBBLESHOT"
    if rng:Random(1, 100) <= 70 then
      level_1_cards[#level_1_cards + 1] = "SPITTER"
      if rng:Random(1, 100) <= 40 then
        level_1_cards[#level_1_cards + 1] = "LIGHT_BULLET_TRIGGER"
        card_count = 1
        if rng:Random(1, 100) <= 20 then
          level_1_cards[#level_1_cards + 1] = "DISC_BULLET_BIG"
          if rng:Random(1, 100) <= 10 then
            level_1_cards[#level_1_cards + 1] = "TENTACLE_PORTAL"
            if rng:Random(1, 100) <= 10 then
              level_1_cards[#level_1_cards + 1] = "BLACK_HOLE_BIG"
            end
          end
        end
      end
    end
  end

  if total > 50 then
    level_1_cards = { "GRENADE", "BOMB", "ROCKET" }
    if rng:Random(1, 100) <= 75 then
      level_1_cards[#level_1_cards + 1] = "DYNAMITE"
      if rng:Random(1, 100) <= 50 then
        level_1_cards[#level_1_cards + 1] = "FIREBALL"
        if rng:Random(1, 100) <= 40 then
          level_1_cards[#level_1_cards + 1] = "ACIDSHOT"
          if rng:Random(1, 100) <= 30 then
            level_1_cards[#level_1_cards + 1] = "GLITTER_BOMB"
            if rng:Random(1, 100) <= 30 then
              level_1_cards[#level_1_cards + 1] = "MINE"
            end
          end
        end
      end
    end
    card_count = 1
  end

  local do_util = rng:Random(0, 100)
  if do_util < 30 then
    level_1_cards = {
      "CLOUD_WATER", "X_RAY", "FREEZE_FIELD", "BLACK_HOLE", "TORCH", "SHIELD_FIELD",
    }
    if rng:Random(1, 100) <= 75 then
      level_1_cards[#level_1_cards + 1] = "ELECTROCUTION_FIELD"
      if rng:Random(1, 100) <= 50 then
        level_1_cards[#level_1_cards + 1] = "DIGGER"
        if rng:Random(1, 100) <= 50 then
          level_1_cards[#level_1_cards + 1] = "TORCH_ELECTRIC"
          if rng:Random(1, 100) <= 50 then
            level_1_cards[#level_1_cards + 1] = "POWERDIGGER"
            if rng:Random(1, 100) <= 50 then
              level_1_cards[#level_1_cards + 1] = "SOILBALL"
              if rng:Random(1, 100) <= 50 then
                level_1_cards[#level_1_cards + 1] = "LUMINOUS_DRILL"
                if rng:Random(1, 100) <= 50 then
                  level_1_cards[#level_1_cards + 1] = "CHAINSAW"
                end
              end
            end
          end
        end
      end
    end
    card_count = 1
  end

  if card_count > deck_capacity then card_count = deck_capacity end

  local card_index = rng:Random(0, #level_1_cards - 1) + 1
  local card = level_1_cards[card_index]

  for _ = 1, card_count do
    gun.cards[#gun.cards + 1] = card
  end

  gun.grip = { x = 0, y = 0 }
  gun.tip = { x = 0, y = 0 }
  gun.sprite = nil
  return gun
end

-- generate(world_seed, ng_plus, wand_type_name, x, y[, opts])
-- opts.no_more_shuffle -- the No More Shuffle perk, which forces non-shuffle.
-- Returns the generated wand table, or nil + reason.
function M.generate(world_seed, ng_plus, wand_type_name, x, y, opts)
  opts = opts or {}
  local cfg = deps.wand_config

  -- Premade wands take their own path; they are not in wand_types.
  if string.match(wand_type_name or "", "^premade_") then
    return M.generate_level1_premade(world_seed, ng_plus, wand_type_name, x, y)
  end

  local wt = cfg.wand_types[wand_type_name]
  if not wt then
    return nil, "unknown wand type " .. tostring(wand_type_name)
  end

  -- The instance OWNS the world seed, and SetRandomSeed only takes (x, y).
  -- Upstream's `SetRandomSeed(world_seed + ng, x, y)` maps onto "construct with
  -- world_seed + ng, then seed by position".
  local rng = deps.prng_new(world_seed + (ng_plus or 0))
  rng:SetRandomSeed(x, y)

  local gun = {
    x = x,
    y = y,
    cards = {},
    level = wt.level,
    cost = wt.cost,
    deck_capacity = 0,
    actions_per_round = 0,
    reload_time = 0,
    shuffle_deck_when_empty = 1,
    fire_rate_wait = 0,
    spread_degrees = 0,
    speed_multiplier = 0,
    prob_unshuffle = 0.1,
    prob_draw_many = 0.15,
    force_unshuffle = 0,
    is_rare = 0,
    wand_type = wt.type,
  }

  if gun.level == 1 then
    if rng:Random(0, 100) < 50 then
      gun.cost = gun.cost + 5
    end
  end
  gun.cost = gun.cost + rng:Random(-3, 3)

  gun.mana_charge_speed = 50 * gun.level + rng:Random(-5, 5 * gun.level)
  gun.mana_max = 50 + 150 * gun.level + rng:Random(-5, 5) * 10

  local p = rng:Random(0, 100)
  if p < 20 then
    gun.mana_charge_speed = (50 * gun.level + rng:Random(-5, 5 * gun.level)) / 5
    gun.mana_max = (50 + 150 * gun.level + rng:Random(-5, 5) * 10) * 3
    if gun.wand_type == "better" and gun.mana_charge_speed < 10 then
      gun.mana_charge_speed = 10
    end
  end

  p = rng:Random(0, 100)
  if gun.wand_type == "better" then
    if p < 15 + gun.level * 6 then
      gun.force_unshuffle = 1
    end
  else
    if p < 15 then
      gun.mana_charge_speed = (50 * gun.level + rng:Random(-5, 5 * gun.level)) * 5
      gun.mana_max = (50 + 150 * gun.level + rng:Random(-5, 5) * 10) / 3
    end
    if gun.mana_max < 50 then gun.mana_max = 50 end
    if gun.mana_charge_speed < 10 then gun.mana_charge_speed = 10 end

    p = rng:Random(0, 100)
    if p < 15 + gun.level * 6 then
      gun.force_unshuffle = 1
    end
  end

  p = rng:Random(0, 100)
  if p < 5 then
    gun.is_rare = 1
    gun.cost = gun.cost + 65
  end

  local vars1 = { "reload_time", "fire_rate_wait", "spread_degrees", "speed_multiplier" }
  local vars2 = { "deck_capacity" }
  local vars3 = { "shuffle_deck_when_empty", "actions_per_round" }

  shuffle_table(vars1, rng)
  if gun.force_unshuffle ~= 1 then shuffle_table(vars3, rng) end

  for i = 1, #vars1 do apply_random_variable(gun, vars1[i], rng) end
  for i = 1, #vars2 do apply_random_variable(gun, vars2[i], rng) end
  for i = 1, #vars3 do apply_random_variable(gun, vars3[i], rng) end

  if gun.cost > 5 then
    local rare_nonincrease_roll = rng:Random(0, 1000)
    if rare_nonincrease_roll < 995 then
      if gun.shuffle_deck_when_empty == 1 then
        gun.deck_capacity = gun.deck_capacity + gun.cost / 5
        gun.cost = 0
      else
        gun.deck_capacity = gun.deck_capacity + gun.cost / 10
        gun.cost = 0
      end
    end
  end

  -- Wand name. `better` wands draw a random adjective, which CONSUMES RNG before
  -- the card stage, so it must happen here even though the name is not scored.
  if gun.wand_type == "better" then
    local names = deps.wand_config.gun_names
    if not names or #names == 0 then
      error("wand_gen: gun_names data missing; the better-wand name roll consumes RNG")
    end
    gun.name = names[rng:Random(0, #names - 1) + 1] .. " Wand"
  else
    gun.name = "Wand"
  end
  if wt.force_unshuffle or opts.no_more_shuffle then
    gun.shuffle_deck_when_empty = 0
  end
  gun.original_force_unshuffle = wt.force_unshuffle and 1 or 0

  local rare_capacity_roll = rng:Random(0, 10000)
  if rare_capacity_roll <= 9999 then
    gun.deck_capacity = clamp(gun.deck_capacity, 2, 26)
  end
  if gun.deck_capacity <= 1 then gun.deck_capacity = 2 end

  if gun.reload_time >= 60 then
    local function random_add_actions_per_round()
      gun.actions_per_round = gun.actions_per_round + 1
      if rng:Random(0, 100) < 70 then
        random_add_actions_per_round()
      end
    end
    random_add_actions_per_round()
    if rng:Random(0, 100) < 50 then
      local new_apr = gun.deck_capacity
      for _ = 1, 6 do
        local temp = rng:Random(round_half_even(gun.actions_per_round),
          round_half_even(gun.deck_capacity))
        if temp < new_apr then
          new_apr = temp
        end
      end
      gun.actions_per_round = new_apr
    end
  end

  gun.actions_per_round = clamp(gun.actions_per_round, 1, gun.deck_capacity)

  -- Card order matters: `better` fills cards before the sprite roll, normal
  -- rolls the sprite first. Both consume RNG, so this cannot be reordered.
  if gun.wand_type == "better" then
    add_random_cards(world_seed, ng_plus, gun, x, y, gun.level, rng, true)
    get_wand_sprite(gun, rng)
  else
    get_wand_sprite(gun, rng)
    add_random_cards(world_seed, ng_plus, gun, x, y, gun.level, rng, false)
  end

  return gun
end

-- get_wand_type(world_seed, ng_plus, x, y, biome): the per-biome wand lottery.
function M.get_wand_type(world_seed, ng_plus, x, y, biome)
  local data = deps.wand_config.wand_spawn_data[biome]
  if not data then return nil end
  local total = 0
  for i = 1, #data.weights do
    total = total + data.weights[i]
  end
  local rng = deps.prng_new(world_seed + (ng_plus or 0))
  -- NOTE the -5 x offset: the game's wand spawner scans slightly to the left of
  -- the pixel the scene reports.
  local r = rng:ProceduralRandom(x - 5, y) * total
  for i = 1, #data.weights do
    if r <= data.weights[i] then
      return data.types[i]
    end
    r = r - data.weights[i]
  end
  return nil
end

return M
