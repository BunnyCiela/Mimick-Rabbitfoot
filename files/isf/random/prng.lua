-- files/isf/random/prng.lua
--
-- Isolated, deterministic re-implementation of Noita's world-generation PRNG.
--
-- Every candidate evaluation gets its own instance; no module-level mutable RNG
-- state is shared between candidates, so predicting one seed can never perturb
-- another candidate or the real game RNG.
--
-- The functions mirror the Lua API documented in the shipped
-- tools_modding/lua_api_documentation.txt (SetRandomSeed / Random / Randomf /
-- ProceduralRandom(i|f) / RandomDistribution(f)), including the "messy"
-- optional-argument behaviour of the originals.
--
-- Algorithm provenance (substantial reuse, MIT licensed):
--   * noita-tools, src/services/SeedInfo/wasm/core/nolla_prng.zig and
--     src/services/SeedInfo/wasm/entries/rng.zig
--     MIT License, Copyright (c) 2022 Seva Maltsev <me@seva.dev>
--   * noita-telescope, js/nolla_prng.js
--     MIT License, Copyright (c) 2026 Lymm
-- Both are JavaScript/Zig/WASM ports of Nolla Games' own generator; the numeric
-- behaviour (32-bit wrapping arithmetic, float32 distribution parameters, and
-- the 16807/127773 Park-Miller step) is preserved here in plain Lua 5.1.
--
-- Lua 5.1 / LuaJIT 2.0.4 compatible. No FFI, no external process, no file or
-- network access: this module only does arithmetic. When the host exposes
-- LuaJIT's built-in `bit` library it is used for speed; otherwise a pure-Lua
-- fallback produces identical results.

local M = {}

local U32 = 4294967296 -- 2^32
local U31 = 2147483648 -- 2^31 (sign bit of a u32)
local LCG_MOD = 2147483647
local LCG_MUL = 16807
local LCG_DIV = 127773
local MAGIC = 252645135
local DIDDLE = { 0, 4, 6, 25, 12, 39, 52, 9, 21, 64, 78, 92, 104, 118, 18, 32, 44 }

-- ---------------------------------------------------------------------------
-- 32-bit integer helpers
-- ---------------------------------------------------------------------------

-- Prefer LuaJIT's built-in bit library. It is a language builtin (not an
-- external package), so production code never calls require(). If a host lacks
-- it, the portable fallback below is used and yields bit-identical output.
local bitlib = rawget and rawget(_G, "bit") or nil
if type(bitlib) ~= "table" or type(bitlib.bxor) ~= "function" then
  bitlib = nil
end

local xor32, lshift32, rshift32, sub32

if bitlib then
  local bxor, lshift, rshift = bitlib.bxor, bitlib.lshift, bitlib.rshift
  xor32 = function(a, b)
    return bxor(a, b) % U32
  end
  lshift32 = function(a, n)
    return lshift(a, n) % U32
  end
  rshift32 = function(a, n)
    return rshift(a, n) % U32
  end
else
  -- 4-bit XOR table: 256 entries, plenty fast for the handful of mixing steps
  -- performed per seed call, and exact for the 32-bit unsigned domain.
  local XOR4 = {}
  for i = 0, 15 do
    XOR4[i] = {}
    for j = 0, 15 do
      local a, b, r, p = i, j, 0, 1
      for _ = 1, 4 do
        local abit, bbit = a % 2, b % 2
        if abit ~= bbit then
          r = r + p
        end
        a = (a - abit) / 2
        b = (b - bbit) / 2
        p = p * 2
      end
      XOR4[i][j] = r
    end
  end

  xor32 = function(a, b)
    a = a % U32
    b = b % U32
    local r, mul = 0, 1
    for _ = 1, 8 do
      local an = a % 16
      local bn = b % 16
      r = r + XOR4[an][bn] * mul
      a = (a - an) / 16
      b = (b - bn) / 16
      mul = mul * 16
    end
    return r
  end

  lshift32 = function(a, n)
    local p = 1
    for _ = 1, n do
      p = p * 2
    end
    return (a * p) % U32
  end

  rshift32 = function(a, n)
    local p = 1
    for _ = 1, n do
      p = p * 2
    end
    return math.floor((a % U32) / p)
  end
end

sub32 = function(a, b)
  return (a - b) % U32
end

-- Truncate toward zero, then reduce into the unsigned 32-bit range. This is
-- exactly what a JS `value >>> 0` (ToUint32) or a Zig
-- `@truncate(@as(u64, @bitCast(@as(i64, @intFromFloat(value)))))` does.
local function trunc_u32(value)
  if value ~= value or value == math.huge or value == -math.huge then
    return 0
  end
  if value >= 9223372036854775808.0 or value < -9223372036854775808.0 then
    return 0
  end
  -- Step 1: truncate toward zero. Lua's modulo is floor-based, so it cannot be
  -- used for this on negative values (it would subtract the wrong fraction).
  local whole
  if value >= 0 then
    whole = math.floor(value)
  else
    whole = math.ceil(value)
  end
  -- Step 2: reduce modulo 2^32. Lua's % already returns a non-negative result
  -- for negative operands, matching ToUint32.
  local r = whole % U32
  if r ~= r then
    return 0
  end
  return r
end

-- Round a double to the nearest IEEE-754 binary32 value (round-half-to-even).
-- Noitool's reference port performs the distribution parameter maths in f32,
-- so matching it requires explicit narrowing on a double-based host.
local f32
do
  local pow2 = {}
  for e = -1074, 1024 do
    pow2[e] = 2 ^ e
  end
  local function p2(e)
    local v = pow2[e]
    if v then
      return v
    end
    return 2 ^ e
  end

  f32 = function(x)
    if x ~= x or x == 0 or x == math.huge or x == -math.huge then
      return x
    end
    local sign = 1
    if x < 0 then
      sign = -1
      x = -x
    end
    -- Values at or above 2^24 are already representable at f32 precision only
    -- if the low bits happen to be zero; handle them by scaling down first.
    local e = math.floor(math.log(x) / math.log(2))
    local p = p2(e)
    while p > x do
      e = e - 1
      p = p2(e)
    end
    while p * 2 <= x do
      e = e + 1
      p = p2(e)
    end
    -- 24 significant bits: mantissa of 2^23 scaled units.
    local scale_e = 23 - e
    if scale_e > 1023 then
      return sign * x -- absurdly small; no f32 precision loss in practice
    end
    local scale = p2(scale_e)
    local m = x * scale
    local r = math.floor(m)
    local frac = m - r
    if frac > 0.5 then
      r = r + 1
    elseif frac == 0.5 then
      if r % 2 == 1 then
        r = r + 1
      end
    end
    return sign * (r / scale)
  end
end

M.f32 = f32

-- ---------------------------------------------------------------------------
-- Core generator
-- ---------------------------------------------------------------------------

local Instance = {}
Instance.__index = Instance

-- Lua 5.1-compatible callable instance support is unnecessary (the contract
-- calls colon methods), so a plain table with metatable is enough.
function Instance:GetWorldSeed()
  return self.world_seed
end

function Instance:GetSeed()
  return self.Seed
end

function Instance:SetSeed(value)
  self.Seed = value
end

-- NollaPrng::next(): Park-Miller minimal standard step (16807 / 127773).
function Instance:Next()
  local s = math.floor(self.Seed)
  -- 16807 * 2^31 and 2147483647 * (2^31 / 127773) both stay below 2^53, so
  -- double arithmetic is exact here and matches the BigInt/exact upstream code.
  local v4 = LCG_MUL * s - LCG_MOD * math.floor(s / LCG_DIV)
  if v4 <= 0 then
    v4 = v4 + LCG_MOD
  end
  self.Seed = v4
  return v4 / LCG_MOD
end

function Instance:Prev()
  local s = math.floor(self.Seed)
  local v4 = (1407677000 * s) % LCG_MOD
  if v4 <= 0 then
    v4 = v4 + LCG_MOD
  end
  self.Seed = v4
  return v4 / LCG_MOD
end

-- NextU: the generator variant used by the Wang tile generator. Note the exact
-- multiplication order, which matters for the truncation.
function Instance:NextU()
  self:Next()
  local r = self.Seed * 4.656612875e-10 * 2147483645.0
  if r ~= r or r < 0 or r >= 18446744073709551616.0 then
    return 0
  end
  return math.floor(r) % U32
end

-- World-seed based initialisation, as used by the Wang generator: a seed at or
-- above 2^31 is halved rather than truncated.
function Instance:SetRandomFromWorldSeed(seed)
  local s = seed
  if s >= 2147483647.0 then
    s = s * 0.5
  end
  self.Seed = s
  return s
end

local function set_random_seed_helper2(a, b, ws)
  local v2 = xor32(sub32(sub32(a, b), ws), rshift32(ws, 13))
  local v1 = xor32(sub32(sub32(b, v2), ws), lshift32(v2, 8))
  local v3 = xor32(sub32(sub32(ws, v2), v1), rshift32(v1, 13))
  v2 = xor32(sub32(sub32(v2, v1), v3), rshift32(v3, 12))
  v1 = xor32(sub32(sub32(v1, v2), v3), lshift32(v2, 16))
  v3 = xor32(sub32(sub32(v3, v2), v1), rshift32(v1, 5))
  v2 = xor32(sub32(sub32(v2, v1), v3), rshift32(v3, 3))
  v1 = xor32(sub32(sub32(v1, v2), v3), lshift32(v2, 10))
  return xor32(sub32(sub32(v3, v2), v1), rshift32(v1, 15))
end

-- SetRandomSeed(x, y): reproducible position-based seeding used everywhere in
-- worldgen (biomes, wands, chests, puzzles, shops).
--
-- The world seed comes from the INSTANCE (set by new(world_seed)).
--
-- Note for porters: the upstream Telescope JavaScript takes (world_seed, x, y)
-- because it has no instance state, and Noitool's WASM takes (x, y) with a
-- module-level SetWorldSeed. Noita's Lua API and this module use (x, y) plus
-- instance state, which is what makes concurrent candidate evaluation safe.
-- Passing three arguments here is therefore always a porting mistake, so it is
-- rejected loudly instead of silently seeding against the wrong world.
function Instance:SetRandomSeed(x, y, ...)
  if select("#", ...) > 0 then
    error("prng.SetRandomSeed takes (x, y); the world seed belongs to the "
      .. "instance created by prng.new(world_seed)", 2)
  end
  local ws = trunc_u32(self.world_seed)
  local a = xor32(ws, 0x93262e6f)
  local b = a % 4096          -- a & 0xfff
  local c = math.floor(a / 4096) % 4096 -- (a >> 12) & 0xfff

  local x_adj = x + b
  local y_adj = y + c

  local material = x_adj * 134217727.0
  local e = trunc_u32(material)

  -- Compare the absolute magnitudes exactly as upstream: |y| >= 102400 or
  -- |x| <= 1 selects the degenerate path. Negative coordinates matter here, so
  -- the test must be on the float magnitude, not on a reinterpreted u32.
  if math.abs(y_adj) >= 102400.0 or math.abs(x_adj) <= 1.0 then
    material = y_adj * 134217727.0
  else
    local y_work = y_adj * 3483.328
    y_work = y_work + e
    y_adj = y_adj * y_work
    material = y_adj
  end

  local f = trunc_u32(material)
  local g = set_random_seed_helper2(e, f, ws)

  local t = g
  t = (t + (g < U31 and 1 or 0) + (g == 0 and 1 or 0)) % U32
  t = (t - math.floor(g / MAGIC)) % U32
  local idx = math.floor(g / MAGIC)
  if idx < 17 then
    if (g % MAGIC < DIDDLE[idx + 1]) and (g < 3284386759 or g >= 3284386817) then
      t = (t + 1) % U32
    end
  end
  t = math.floor(((t + (g > U31 and 1 or 0)) % U32) / 2)
  t = (t + (g == 4294967295 and 1 or 0)) % U32

  self.Seed = t
  self:Next()

  local h = ws % 4
  while h > 0 do
    self:Next()
    h = h - 1
  end
end

-- Game-faithful "cast a double to int32" used by the integer random helpers.
local function to_i32(value)
  local v = value % U32
  if v >= U31 then
    v = v - U32
  end
  return v
end

-- Float returns are narrowed to IEEE binary32. The game's generator hands its
-- float draws to C++ `float` variables, and Noitool's game-validated wand
-- fixtures confirm it (e.g. speed_multiplier 1.08233642578125 is exactly a
-- binary32 value). Narrowing keeps this port bit-compatible with the reference
-- reimplementation that was checked against real game output.

-- Random([a][, b]) -- integer draw. See the shipped Lua API documentation:
--   no args  -> float in [0, 1)
--   one arg  -> integer in [0, a]
--   two args -> integer in [a, b]
function Instance:Random(a, b)
  local r = self:Next()
  if a == nil then
    return f32(r)
  end
  a = math.floor(a)
  if b == nil then
    local v = math.floor((a + 1) * r)
    if v > a then
      v = a
    end
    return v
  end
  b = math.floor(b)
  return a + math.floor((b + 1 - a) * r)
end

-- Randomf([a][, b]) -- float draw.
function Instance:Randomf(a, b)
  local r = self:Next()
  if a == nil then
    return f32(r)
  end
  if b == nil then
    return f32(a * r)
  end
  return f32(a + (b - a) * r)
end

-- ProceduralRandom(x, y[, a][, b]) -- reseeds from position, then draws.
function Instance:ProceduralRandom(x, y, a, b)
  self:SetRandomSeed(x, y)
  if a == nil then
    return f32(self:Next())
  end
  if b == nil then
    local r = self:Next()
    return math.floor(math.floor(a) * r)
  end
  local r = self:Next()
  local lo = math.floor(a)
  local hi = math.floor(b)
  return lo + math.floor((hi + 1 - lo) * r)
end

-- ProceduralRandomf(x, y[, a][, b]) -- reseeds from position, then draws a float.
function Instance:ProceduralRandomf(x, y, a, b)
  self:SetRandomSeed(x, y)
  local r = self:Next()
  if a == nil then
    return f32(r)
  end
  if b == nil then
    return f32(a * r)
  end
  return f32(a + (b - a) * r)
end

-- ProceduralRandomi(x, y[, a][, b]) -- integer variant. With only x and y the
-- original returns 0 or 1.
function Instance:ProceduralRandomi(x, y, a, b)
  self:SetRandomSeed(x, y)
  local r = self:Next()
  if a == nil then
    return math.floor(2 * r)
  end
  if b == nil then
    return math.floor(math.floor(a) * r)
  end
  local lo = math.floor(a)
  local hi = math.floor(b)
  return lo + math.floor((hi + 1 - lo) * r)
end

-- getDistribution: rejection sampling used by the wand stat generator.
--
-- Precision note: Noitool's game-validated Zig port computes this in f32 and
-- narrows the result. Telescope's JS uses float64 + Math.pow. The two differ in
-- the last bit for some inputs, which shifts wand `speed_multiplier`. This
-- implementation follows the float64 form because that is what the wand oracle
-- (upstream Telescope, the only implementation that also reproduces wand card
-- contents) produces, and cards are what ISF-02 scores. The f32 helpers below
-- remain available for callers that need them explicitly.
local function get_distribution(self, mean, sharpness, baseline)
  local pi = 3.1415
  local mean_offset = 0.5 - mean
  for _ = 1, 100 do
    local r1 = self:Next()
    local r2 = self:Next()
    local div = math.abs(r1 - mean)
    if r2 < (1.0 - div) * baseline then
      return r1
    end
    if div < 0.5 then
      local v11 = math.sin((mean_offset + r1) * pi)
      local v12
      if v11 < 0 then
        v12 = -(math.abs(v11) ^ sharpness)
      else
        v12 = v11 ^ sharpness
      end
      if v12 > r2 then
        return r1
      end
    end
  end
  return self:Next()
end

-- RandomDistribution(min, max, mean[, sharpness[, baseline]]) -> integer
function Instance:RandomDistribution(min, max, mean, sharpness, baseline)
  if sharpness == nil then
    sharpness = 1
  end
  if baseline == nil then
    baseline = 0.005
  end
  if sharpness == 0 then
    return self:Random(min, max)
  end
  local span = max - min
  local adj_mean = (mean - min) / span
  local v7 = get_distribution(self, adj_mean, sharpness, baseline)
  local scaled = span * v7
  local delta = math.floor(scaled + 0.5)
  if scaled < 0 then
    delta = -math.floor(-scaled + 0.5)
  end
  return min + delta
end

-- RandomDistributionf(min, max, mean[, sharpness[, baseline]]) -> float
function Instance:RandomDistributionf(min, max, mean, sharpness, baseline)
  if sharpness == nil then
    sharpness = 1
  end
  if baseline == nil then
    baseline = 0.005
  end
  if sharpness == 0 then
    local value = self:Next()
    return value * (max - min) + min
  end
  local span = max - min
  local adj_mean = (mean - min) / span
  local v7 = get_distribution(self, adj_mean, sharpness, baseline)
  return min + span * v7
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

-- new(world_seed) -> fresh instance. Each candidate owns one instance; nothing
-- is shared, so evaluation order cannot change results.
function M.new(world_seed)
  local self = setmetatable({}, Instance)
  self.world_seed = world_seed
  self.Seed = world_seed
  self:Next()
  return self
end

-- Exposed for tests / tooling that need an object with no initial advance.
function M.new_raw(world_seed)
  local self = setmetatable({}, Instance)
  self.world_seed = world_seed
  self.Seed = world_seed
  return self
end

M.Instance = Instance
M.DIDDLE = DIDDLE

return M
