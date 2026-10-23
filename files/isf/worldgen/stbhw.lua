-- files/isf/worldgen/stbhw.lua
--
-- Pure-Lua port of the "STB Herringbone Wang" tileset generator Noita uses for
-- biome terrain. Given a wang tileset image (rows of tile patches with an
-- encoded header) and a seeded PRNG, this produces the logical tile grid and
-- the RGB tile buffer the game and upstream predictors consume.
--
-- Substantial reuse: this is a direct port of
--   noita-telescope, js/stbhw.js
--   MIT License, Copyright (c) 2026 Lymm
-- which is itself a port of Sean Barrett's public-domain stb_herringbone_wang.h
-- as used by Nolla Games. The corner-mode colour pass, repetition reduction,
-- the canonical "choose tile" scan, and the pixel blitters are reproduced
-- step for step; the container/loader layer is Lua-specific.
--
-- Standalone Lua 5.1 compatible: no FFI, no external process, no requires.

local M = {}

-- Tileset inputs are immutable. Keep first/second matches in original order,
-- scoped to the actual tile array; never cache an RNG choice. Bound each table
-- so custom assets cannot accumulate an unbounded constraint dictionary.
local match_caches=setmetatable({},{__mode="k"})
local function matching_pair(tiles,num_tiles,a,b,c,d,e,f)
  local cache=match_caches[tiles]
  if not cache or cache.num_tiles~=num_tiles or cache.count>=4096 then
    cache={num_tiles=num_tiles,count=0,rows={}};match_caches[tiles]=cache
  end
  local key=a..","..b..","..c..","..d..","..e..","..f
  local pair=cache.rows[key]
  if pair then return pair[1],pair[2]end
  local first,second=-1,-1
  for i=1,num_tiles do
    local t=tiles[i]
    if (a<0 or a==t.a)and(b<0 or b==t.b)and(c<0 or c==t.c)
      and(d<0 or d==t.d)and(e<0 or e==t.e)and(f<0 or f==t.f)then
      if first<0 then first=i else second=i;break end
    end
  end
  cache.rows[key]={first,second};cache.count=cache.count+1
  return first,second
end

local U32 = 4294967296

-- Upstream caps the logical grids at 300x300 entries.
local MAX_W = 300
local MAX_H = 300
local REPETITION_REDUCTION = true

-- ---------------------------------------------------------------------------
-- Portable 32-bit XOR
--
-- Lua 5.1 has no bitwise operators, and LuaJIT's `bit` library may or may not
-- be reachable from a mod sandbox. Both paths produce identical results; the
-- fast path is used purely as an optimisation.
-- ---------------------------------------------------------------------------
local XOR4 = {}
do
  for i = 0, 15 do
    XOR4[i] = {}
    for j = 0, 15 do
      local a, b, r, p = i, j, 0, 1
      for _ = 1, 4 do
        local abit, bbit = a % 2, b % 2
        if abit ~= bbit then r = r + p end
        a = (a - abit) / 2
        b = (b - bbit) / 2
        p = p * 2
      end
      XOR4[i][j] = r
    end
  end
end

local bitlib = rawget and rawget(_G, "bit") or nil
if type(bitlib) ~= "table" or type(bitlib.bxor) ~= "function" then
  bitlib = nil
end

local xor32
if bitlib then
  local bxor = bitlib.bxor
  xor32 = function(a, b) return bxor(a, b) % U32 end
else
  xor32 = function(a, b)
    a = a % U32
    b = b % U32
    local r, mul = 0, 1
    for _ = 1, 8 do
      local an, bn = a % 16, b % 16
      r = r + XOR4[an][bn] * mul
      a = (a - an) / 16
      b = (b - bn) / 16
      mul = mul * 16
    end
    return r
  end
end
M.xor32 = xor32

-- 32-bit FNV-1a over a byte string.
function M.fnv1a(s)
  local h = 2166136261
  for i = 1, #s do
    h = xor32(h, s:byte(i))
    local lo = h % 65536
    local hi = math.floor(h / 65536)
    h = (lo * 16777619 + ((hi * 16777619) % 65536) * 65536) % U32
  end
  return h
end

local Tileset = {}
Tileset.__index = Tileset

function M.new_tileset()
  return setmetatable({
    is_corner = false,
    num_color = { 0, 0, 0, 0, 0, 0 },
    short_side_len = 0,
    h_tiles = {},
    v_tiles = {},
    num_h_tiles = 0,
    num_v_tiles = 0,
    num_vary_x = 0,
    num_vary_y = 0,
  }, Tileset)
end

M.Tileset = Tileset

-- ---------------------------------------------------------------------------
-- Tileset construction
-- ---------------------------------------------------------------------------

-- Copies a w_t x h_t RGB patch out of the source image into a tile record.
--
-- IMPORTANT: the source patch is read as a FLAT buffer, exactly like upstream's
-- `p.data[(ypos + j) * p.stride + (xpos + i) * 3]`. Tile sheets place patches
-- past the right edge deliberately, so those reads intentionally spill into the
-- following rows rather than clamping to zero. Only reads at or past the end of
-- the whole buffer are left as zeros (upstream: `start + 2 < p.data.length`).
local function parse_rect(ts, img, xpos, ypos, a, b, c, d, e, f, is_v)
  local len = ts.short_side_len
  -- Horizontal tiles are wide (2*len x len); vertical tiles are tall
  -- (len x 2*len). Upstream: w_t = isV ? len : len*2, h_t = isV ? len*2 : len.
  local w_t, h_t
  if is_v then
    w_t, h_t = len, len * 2
  else
    w_t, h_t = len * 2, len
  end
  local pixels = {}
  local n = 0
  xpos = xpos + 1
  ypos = ypos + 1

  local src = img.rgb
  local stride = img.width * 3
  local data_len = #src

  for j = 0, h_t - 1 do
    for i = 0, w_t - 1 do
      -- 0-based flat byte offset into the source RGB buffer.
      local start = (ypos + j) * stride + (xpos + i) * 3
      if start + 2 < data_len then
        -- string.char, not the raw numbers: table.concat would stringify a
        -- number as its decimal representation instead of a single byte.
        pixels[n + 1] = src:sub(start + 1, start + 1)
        pixels[n + 2] = src:sub(start + 2, start + 2)
        pixels[n + 3] = src:sub(start + 3, start + 3)
      else
        pixels[n + 1] = "\0"
        pixels[n + 2] = "\0"
        pixels[n + 3] = "\0"
      end
      n = n + 3
    end
  end

  local tile = { pixels = table.concat(pixels, ""), a = a, b = b, c = c, d = d, e = e, f = f }
  if is_v then
    ts.num_v_tiles = ts.num_v_tiles + 1
    ts.v_tiles[ts.num_v_tiles] = tile
  else
    ts.num_h_tiles = ts.num_h_tiles + 1
    ts.h_tiles[ts.num_h_tiles] = tile
  end
end

local function process_h_row(ts, img, xpos, ypos, a0, a1, b0, b1, c0, c1, d0, d1, e0, e1, f0, f1, variants)
  for _ = 1, variants do
    for f = f0, f1 do
      for e = e0, e1 do
        for d = d0, d1 do
          for c = c0, c1 do
            for b = b0, b1 do
              for a = a0, a1 do
                parse_rect(ts, img, xpos, ypos, a, b, c, d, e, f, false)
                xpos = xpos + 2 * ts.short_side_len + 3
              end
            end
          end
        end
      end
    end
  end
end

local function process_v_row(ts, img, xpos, ypos, a0, a1, b0, b1, c0, c1, d0, d1, e0, e1, f0, f1, variants)
  for _ = 1, variants do
    for f = f0, f1 do
      for e = e0, e1 do
        for d = d0, d1 do
          for c = c0, c1 do
            for b = b0, b1 do
              for a = a0, a1 do
                parse_rect(ts, img, xpos, ypos, a, b, c, d, e, f, true)
                xpos = xpos + ts.short_side_len + 3
              end
            end
          end
        end
      end
    end
  end
end

-- build(ts, img) -> true | nil, error
-- `img` is { width, height, rgb = <w*h*3 byte string> } (see isf/worldgen/png.lua).
function M.build(ts, img)
  local w, h = img.width, img.height
  local stride = w * 3

  -- Header: the last 9 source bytes of the last-but-one row, XOR-scrambled.
  -- (Upstream reads from `stride - 1 - i`, i.e. the final pixel of the row.)
  local header = {}
  for i = 0, 8 do
    local idx = stride - 1 - i -- 0-based byte index
    if idx >= 0 and idx < #img.rgb then
      header[i] = xor32(img.rgb:byte(idx + 1), (i * 55) % 256)
    else
      header[i] = 0
    end
  end

  if header[7] == 0xc0 then
    ts.is_corner = true
    ts.num_color = { header[0], header[1], header[2], header[3], 0, 0 }
    ts.num_vary_x = header[4]
    ts.num_vary_y = header[5]
    ts.short_side_len = header[6]
  else
    ts.is_corner = false
    ts.num_color = { header[0], header[1], header[2], header[3], header[4], header[5] }
    ts.num_vary_x = header[6]
    ts.num_vary_y = header[7]
    ts.short_side_len = header[8]
  end

  if ts.short_side_len <= 0 or ts.short_side_len > 100 then
    return nil, "invalid short_side_len " .. tostring(ts.short_side_len)
  end

  ts.h_tiles = {}
  ts.v_tiles = {}
  ts.num_h_tiles = 0
  ts.num_v_tiles = 0

  local nc = ts.num_color
  -- Translate the 1-based Lua array into the upstream 0-based c0..c5 names so
  -- the index ranges below can be checked line-by-line against stbhw.js.
  local c0, c1, c2, c3, c4, c5 = nc[1], nc[2], nc[3], nc[4], nc[5], nc[6]
  local ypos = 2

  if ts.is_corner then
    -- for k in 0..c2-1, j in 0..c1-1, i in 0..c0-1, q in 0..num_vary_y-1:
    --   process_h_row(a:0..c1-1, b:0..c2-1, c:0..c3-1, d:i, e:j, f:k, num_vary_x)
    for k = 0, c2 - 1 do
      for j = 0, c1 - 1 do
        for i = 0, c0 - 1 do
          for _q = 1, ts.num_vary_y do
            process_h_row(ts, img, 0, ypos,
              0, c1 - 1,
              0, c2 - 1,
              0, c3 - 1,
              i, i, j, j, k, k, ts.num_vary_x)
            ypos = ypos + ts.short_side_len + 3
          end
        end
      end
    end
    ypos = ypos + 2
    -- for k in 0..c3-1, j in 0..c0-1, i in 0..c1-1, q in 0..num_vary_x-1:
    --   process_v_row(a:0..c0-1, b:0..c3-1, c:0..c2-1, d:i, e:j, f:k, num_vary_y)
    for k = 0, c3 - 1 do
      for j = 0, c0 - 1 do
        for i = 0, c1 - 1 do
          for _q = 1, ts.num_vary_x do
            process_v_row(ts, img, 0, ypos,
              0, c0 - 1,
              0, c3 - 1,
              0, c2 - 1,
              i, i, j, j, k, k, ts.num_vary_y)
            ypos = ypos + ts.short_side_len * 2 + 3
          end
        end
      end
    end
  else
    -- for k in 0..c3-1, j in 0..c4-1, i in 0..c2-1, q in 0..num_vary_y-1:
    --   process_h_row(a:0..c2-1, b:k, c:0..c1-1, d:j, e:0..c0-1, f:i, num_vary_x)
    for k = 0, c3 - 1 do
      for j = 0, c4 - 1 do
        for i = 0, c2 - 1 do
          for _q = 1, ts.num_vary_y do
            process_h_row(ts, img, 0, ypos,
              0, c2 - 1,
              k, k,
              0, c1 - 1,
              j, j,
              0, c0 - 1,
              i, i, ts.num_vary_x)
            ypos = ypos + ts.short_side_len + 3
          end
        end
      end
    end
    ypos = ypos + 2
    -- for k in 0..c3-1, j in 0..c4-1, i in 0..c5-1, q in 0..num_vary_x-1:
    --   process_v_row(a:0..c0-1, b:i, c:0..c1-1, d:j, e:0..c5-1, f:k, num_vary_y)
    for k = 0, c3 - 1 do
      for j = 0, c4 - 1 do
        for i = 0, c5 - 1 do
          for _q = 1, ts.num_vary_x do
            process_v_row(ts, img, 0, ypos,
              0, c0 - 1,
              i, i,
              0, c1 - 1,
              j, j,
              0, c5 - 1,
              k, k, ts.num_vary_y)
            ypos = ypos + ts.short_side_len * 2 + 3
          end
        end
      end
    end
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Generation
-- ---------------------------------------------------------------------------

-- generate(ts, rng, out_w, out_h) -> {
--   rgb        = byte string, out_w * out_h * 3
--   tile_indices = array (1-based here, 0-based values as upstream)
--   xmax, ymax = logical grid dimensions
-- }
--
-- `rng` must provide NextU() returning a 32-bit unsigned integer, matching
-- prng.lua's Instance:NextU(). Results are written into a plain Lua array
-- (`rgb`) and then concatenated once, which keeps peak memory low.
function M.generate(ts, rng, out_w, out_h, options)
  local resource_only=options and options.resource_only==true
  local sidelen = ts.short_side_len
  if sidelen <= 0 then
    return nil, "invalid short_side_len"
  end

  -- Noita repeats tile data after 1024 px horizontally and 1028 vertically.
  local w = math.min(out_w, 1024)
  local h = math.min(out_h, 1028)

  local xmax = math.floor(w / sidelen) + 6
  local ymax = math.floor(h / sidelen) + 6
  if xmax > MAX_W then xmax = MAX_W end
  if ymax > MAX_H then ymax = MAX_H end

  -- Constraint grids, 1-based with an offset so the logic indices of the
  -- original (-1 .. xmax) map directly. get/set clamp out-of-range to -1.
  local c_color = {}
  local CV = {} -- stride for c_color
  local cstride = xmax + 8
  local function cidx(x, y) return (y + 4) * cstride + (x + 4) + 1 end
  local function get_c(x, y)
    local i = cidx(x, y)
    local v = c_color[i]
    if v == nil then return -1 end
    return v
  end
  local function set_c(x, y, v)
    c_color[cidx(x, y)] = v
  end

  local tile_indices = {}
  local num_vary_product = ts.num_vary_x * ts.num_vary_y
  local nc = ts.num_color

  -- --- PASS 1: colour generation ---
  for j = 0, ymax - 1 do
    for i = 0, xmax - 1 do
      local p = ((i - j + 1) % 4) + 1
      local n = nc[p]
      if n == nil or n < 1 then n = 1 end
      set_c(i, j, (rng:NextU() % n))
    end
  end

  -- --- PASS 2: repetition reduction ---
  local function match(i, j)
    return get_c(i, j) == get_c(i + 1, j + 1)
  end

  local function change_color(old_color, num_options)
    local offset = 1 + (rng:NextU() % (num_options - 1))
    return (old_color + offset) % num_options
  end

  if REPETITION_REDUCTION then
    for j = 0, ymax - 4 do
      for i = 0, xmax - 4 do
        if match(i, j) and match(i, j + 1) and match(i, j + 2)
          and match(i + 1, j) and match(i + 1, j + 1) and match(i + 1, j + 2) then
          local p = (((i + 1) - (j + 1) + 1) % 4) + 1
          if nc[p] and nc[p] > 1 then
            local curr = get_c(i + 1, j + 1)
            set_c(i + 1, j + 1, change_color(curr, nc[p]))
          end
        end
        if match(i, j) and match(i + 1, j) and match(i + 2, j)
          and match(i, j + 1) and match(i + 1, j + 1) and match(i + 2, j + 1) then
          local p = (((i + 2) - (j + 1) + 1) % 4) + 1
          if nc[p] and nc[p] > 1 then
            local curr = get_c(i + 2, j + 1)
            set_c(i + 2, j + 1, change_color(curr, nc[p]))
          end
        end
      end
    end
  end

  -- --- PASS 3: logic + draw ---
  local rgb = {}
  local rgb_n = 0
  local stride = out_w * 3
  local out_bytes_max = out_w * out_h * 3
  local cells,placements
  if resource_only then
    cells={packed_rgb=true};placements={}
    for k=1,out_w*out_h do cells[k]=0 end
  end
  local function draw_cells(x,y,tile,tw,th)
    local source=tile.cells
    if not source then
      source={};local data=tile.pixels
      for k=1,tw*th do local r,g,b=data:byte((k-1)*3+1,(k-1)*3+3);source[k]=r*65536+g*256+b end
      tile.cells=source
    end
    placements[#placements+1]={x=x,y=y,width=tw,height=th,tile=tile}
    for j=math.max(0,-y),math.min(th-1,out_h-1-y)do
      local dst=(y+j)*out_w+x+1;local src=j*tw+1
      for i=math.max(0,-x),math.min(tw-1,out_w-1-x)do cells[dst+i]=source[src+i]end
    end
  end

  local function choose_tile(tiles, num_tiles, a_i, b_i, c_i, d_i, e_i, f_i)
    local a = get_c(a_i[1], a_i[2])
    local b = get_c(b_i[1], b_i[2])
    local c = get_c(c_i[1], c_i[2])
    local d = get_c(d_i[1], d_i[2])
    local e = get_c(e_i[1], e_i[2])
    local f = get_c(f_i[1], f_i[2])

    local first,second=matching_pair(tiles,num_tiles,a,b,c,d,e,f)

    if first < 0 then return nil end
    local tile_stride = (second == -1) and 0 or (second - first)

    local m = rng:NextU() % num_vary_product
    -- `first` is 1-based here (Lua arrays), but upstream's tile indices are
    -- 0-based and the 0x4000/0x8000/0xC000 flags are OR-ed onto that value, so
    -- convert back to 0-based before returning.
    local final_idx = first + m * tile_stride
    local t = tiles[final_idx]
    if not t then return nil end

    set_c(a_i[1], a_i[2], t.a)
    set_c(b_i[1], b_i[2], t.b)
    set_c(c_i[1], c_i[2], t.c)
    set_c(d_i[1], d_i[2], t.d)
    set_c(e_i[1], e_i[2], t.e)
    set_c(f_i[1], f_i[2], t.f)
    return final_idx - 1, t
  end

  local function draw_h_tile(x, y, tile)
    if resource_only then draw_cells(x,y,tile,sidelen*2,sidelen);return end
    local sz = sidelen
    local tp = tile.pixels
    for j = 0, sz - 1 do
      local oy = y + j
      if oy >= 0 and oy < out_h then
        local row_base = oy * stride
        for i = 0, sz * 2 - 1 do
          local ox = x + i
          if ox >= 0 and ox < out_w then
            local src = (j * (sz * 2) + i) * 3 + 1
            local dst = row_base + ox * 3 + 1
            rgb[dst] = tp:sub(src, src)
            rgb[dst + 1] = tp:sub(src + 1, src + 1)
            rgb[dst + 2] = tp:sub(src + 2, src + 2)
            if dst + 2 > rgb_n then rgb_n = dst + 2 end
          end
        end
      end
    end
  end

  local function draw_v_tile(x, y, tile)
    if resource_only then draw_cells(x,y,tile,sidelen,sidelen*2);return end
    local sz = sidelen
    local tp = tile.pixels
    for j = 0, sz * 2 - 1 do
      local oy = y + j
      if oy >= 0 and oy < out_h then
        local row_base = oy * stride
        for i = 0, sz - 1 do
          local ox = x + i
          if ox >= 0 and ox < out_w then
            local src = (j * sz + i) * 3 + 1
            local dst = row_base + ox * 3 + 1
            rgb[dst] = tp:sub(src, src)
            rgb[dst + 1] = tp:sub(src + 1, src + 1)
            rgb[dst + 2] = tp:sub(src + 2, src + 2)
            if dst + 2 > rgb_n then rgb_n = dst + 2 end
          end
        end
      end
    end
  end

  local yIdx = -1
  local ypos = -1 * sidelen
  local j = -1

  while (yIdx * sidelen) < h do
    local phase = (j % 4)
    if phase < 0 then phase = phase + 4 end
    local i
    if phase == 0 then i = 0 else i = phase - 4 end

    while true do
      local xIdx = i
      local xpos = xIdx * sidelen
      if xpos >= w then break end

      local h_ok = true
      if xIdx + 2 >= 0 and yIdx >= 0 then
        local ti, tile = choose_tile(ts.h_tiles, ts.num_h_tiles,
          { i + 2, j + 2 }, { i + 3, j + 2 }, { i + 4, j + 2 },
          { i + 2, j + 3 }, { i + 3, j + 3 }, { i + 4, j + 3 })
        if ti == nil then
          return nil, "no matching horizontal tile"
        end
        if xIdx >= 0 then
          tile_indices[yIdx * xmax + xIdx + 1] = ti
        end
        if xIdx + 1 >= 0 then
          tile_indices[yIdx * xmax + xIdx + 2] = ti + 0x8000
        end
        draw_h_tile(xpos, ypos, tile)
      end

      local xIdxV = i + 3
      local xposV = xIdxV * sidelen
      if xposV < w then
        local ti, tile = choose_tile(ts.v_tiles, ts.num_v_tiles,
          { i + 5, j + 2 }, { i + 5, j + 3 }, { i + 5, j + 4 },
          { i + 6, j + 2 }, { i + 6, j + 3 }, { i + 6, j + 4 })
        if ti == nil then
          return nil, "no matching vertical tile"
        end
        if yIdx >= 0 then
          tile_indices[yIdx * xmax + xIdxV + 1] = ti + 0x4000
        end
        if (yIdx + 1) * sidelen < (h + sidelen) then
          tile_indices[(yIdx + 1) * xmax + xIdxV + 1] = ti + 0xC000
        end
        draw_v_tile(xposV, ypos, tile)
      end

      i = i + 4
    end

    yIdx = yIdx + 1
    ypos = ypos + sidelen
    j = j + 1
  end

  if resource_only then
    return {cells=cells,placements=placements,tile_indices=tile_indices,tile_index_count=xmax*ymax,xmax=xmax,ymax=ymax,width=out_w,height=out_h}
  end
  -- Materialise a dense buffer so downstream consumers (pathfinding, spawn
  -- scan) can index it directly. Missing cells stay 0, as upstream's
  -- zero-initialised Uint8Array.
  local blank = string.rep("\0", out_bytes_max)
  local pieces = {}
  local piece = {}
  local pn = 0
  local limit = math.min(out_bytes_max, rgb_n)
  for idx = 1, limit do
    local b = rgb[idx]
    if b == nil then b = "\0" end
    pn = pn + 1
    piece[pn] = b
    if pn >= 8192 then
      pieces[#pieces + 1] = table.concat(piece)
      piece, pn = {}, 0
    end
  end
  if pn > 0 then pieces[#pieces + 1] = table.concat(piece) end
  local body = table.concat(pieces)
  local rgb_str = body .. string.rep("\0", out_bytes_max - #body)

  return {
    rgb = rgb_str,
    tile_indices = tile_indices,
    tile_index_count = xmax * ymax,
    xmax = xmax,
    ymax = ymax,
    width = out_w,
    height = out_h,
  }
end

-- Minimal FNV-1a used by tests and by the report's reproducibility ids.
M.fnv1a = function(s)
  local h = 2166136261
  local U32 = 4294967296
  local bitlib = rawget and rawget(_G, "bit") or nil
  for i = 1, #s do
    local byte = s:byte(i)
    if bitlib and type(bitlib.bxor) == "function" then
      h = bitlib.bxor(h, byte) % U32
    else
      -- pure-Lua xor of a 32-bit value with one byte
      local r, mul, a, b = 0, 1, h, byte
      for _ = 1, 8 do
        local an, bn = a % 16, b % 16
        local rr, p = 0, 1
        local aa, bb = an, bn
        for _ = 1, 4 do
          local abit, bbit = aa % 2, bb % 2
          if abit ~= bbit then rr = rr + p end
          aa = (aa - abit) / 2
          bb = (bb - bbit) / 2
          p = p * 2
        end
        r = r + rr * mul
        a = (a - an) / 16
        b = (b - bn) / 16
        mul = mul * 16
      end
      h = r % U32
    end
    local lo = h % 65536
    local hi = math.floor(h / 65536)
    h = (lo * 16777619 + ((hi * 16777619) % 65536) * 65536) % U32
  end
  return h
end

return M
