-- files/isf/worldgen/png.lua
--
-- Minimal, dependency-free PNG decoder for the tilesets the worldgen port needs.
--
-- Runtime constraints (see WORKER_CONTRACT.md): the shipped mod is standalone
-- Lua 5.1. No FFI, no native DLL, no external process. Bytes are supplied by
-- an injected reader. The game adapter loads generated Lua byte strings;
-- the native text-file API rejects the packaged PNGs.
--
-- Supports exactly what Noita's wang/overlay tilesets use: 8-bit
-- non-interlaced RGB (colour type 2) and RGBA (colour type 6), PNG filter
-- types 0-4, and zlib streams built from stored/fixed/dynamic Huffman blocks.
-- Anything else raises a clear error instead of silently mis-decoding.
--
-- The zlib/inflate implementation is original code written for this project.
-- PNG format references: RFC 2083 (PNG) and RFC 1951 (DEFLATE).

local M = {}

local U32 = 4294967296

-- Portable 32-bit XOR (LuaJIT `bit` fast path, pure-Lua fallback otherwise).
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
    -- h * 16777619 mod 2^32, keeping each product inside 2^53.
    local lo = h % 65536
    local hi = math.floor(h / 65536)
    h = (lo * 16777619 + ((hi * 16777619) % 65536) * 65536) % U32
  end
  return h
end

-- ---------------------------------------------------------------------------
-- DEFLATE / zlib
-- ---------------------------------------------------------------------------

local LENGTH_BASE = {
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
  83, 99, 115, 131, 163, 195, 227, 258,
}
local LENGTH_EXTRA = {
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5,
  5, 5, 5, 0,
}
local DIST_BASE = {
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513,
  769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
}
local DIST_EXTRA = {
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
  11, 11, 12, 12, 13, 13,
}
-- RFC 1951 3.2.7: the order in which code-length code lengths are transmitted.
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Canonical Huffman decode table (RFC 1951 3.2.2). Codes are stored
-- bit-reversed because DEFLATE packs Huffman codes least-significant-bit first.
--
-- `lengths` is a 0-based array of code lengths for symbols 0..nsym-1. Codes
-- must be assigned in ascending symbol order within each length, so iteration
-- here is strictly numeric (never `pairs`).
local function build_huffman(lengths, nsym)
  local maxbits = 0
  local count = {}
  for sym = 0, nsym - 1 do
    local l = lengths[sym] or 0
    if l > maxbits then maxbits = l end
    if l > 0 then count[l] = (count[l] or 0) + 1 end
  end
  local tbl = {}
  if maxbits == 0 then
    return { maxbits = 0, table = tbl }
  end
  local next_code = {}
  local code = 0
  for bits = 1, maxbits do
    code = (code + (count[bits - 1] or 0)) * 2
    next_code[bits] = code
  end
  for sym = 0, nsym - 1 do
    local l = lengths[sym] or 0
    if l > 0 then
      local c = next_code[l]
      next_code[l] = c + 1
      local rev = 0
      for _ = 1, l do
        rev = rev * 2 + (c % 2)
        c = math.floor(c / 2)
      end
      tbl[rev] = { sym = sym, len = l }
    end
  end
  return { maxbits = maxbits, table = tbl }
end

-- inflate_zlib(bytes) -> decoded byte string
function M.inflate_zlib(data)
  local pos = 1
  local bitbuf = 0
  local bitcnt = 0
  local n = #data

  local function get_bits(k)
    if k == 0 then return 0 end
    while bitcnt < k do
      local byte = data:byte(pos)
      if not byte then error("png: unexpected end of compressed stream", 0) end
      pos = pos + 1
      bitbuf = bitbuf + byte * (2 ^ bitcnt)
      bitcnt = bitcnt + 8
    end
    local mask = 2 ^ k
    local v = bitbuf % mask
    bitbuf = math.floor(bitbuf / mask)
    bitcnt = bitcnt - k
    return v
  end

  local function decode(huff)
    if huff.maxbits == 0 then error("png: empty huffman table", 0) end
    local code = 0
    local bits = 0
    while bits < huff.maxbits do
      bits = bits + 1
      code = code + get_bits(1) * (2 ^ (bits - 1))
      local e = huff.table[code]
      if e and e.len == bits then return e.sym end
    end
    error("png: invalid huffman code", 0)
  end

  if n < 2 then error("png: truncated zlib header", 0) end
  local cmf, flg = data:byte(1), data:byte(2)
  if cmf % 16 ~= 8 then error("png: unsupported zlib compression method", 0) end
  if (cmf * 256 + flg) % 31 ~= 0 then error("png: bad zlib header checksum", 0) end
  if math.floor(flg / 32) % 2 == 1 then
    error("png: preset zlib dictionary unsupported", 0)
  end
  pos = 3

  local out = {}
  local outn = 0
  local fixed_lit, fixed_dist

  while true do
    local bfinal = get_bits(1)
    local btype = get_bits(2)

    if btype == 0 then
      -- Stored block: drop to a byte boundary before reading LEN.
      bitbuf = 0
      bitcnt = 0
      if pos + 3 > n then error("png: truncated stored block header", 0) end
      local b1, b2, b3, b4 = data:byte(pos, pos + 3)
      local len = b1 + b2 * 256
      local nlen = b3 + b4 * 256
      if len + nlen ~= 65535 then
        error("png: stored block length check failed", 0)
      end
      pos = pos + 4
      if pos + len - 1 > n then error("png: truncated stored block", 0) end
      for i = 0, len - 1 do
        outn = outn + 1
        out[outn] = data:byte(pos + i)
      end
      pos = pos + len
    elseif btype == 1 or btype == 2 then
      local lit, dist
      if btype == 1 then
        if not fixed_lit then
          local ll = {}
          for i = 0, 143 do ll[i] = 8 end
          for i = 144, 255 do ll[i] = 9 end
          for i = 256, 279 do ll[i] = 7 end
          for i = 280, 287 do ll[i] = 8 end
          fixed_lit = build_huffman(ll, 288)
          local dd = {}
          for i = 0, 29 do dd[i] = 5 end
          fixed_dist = build_huffman(dd, 30)
        end
        lit, dist = fixed_lit, fixed_dist
      else
        local hlit = get_bits(5) + 257
        local hdist = get_bits(5) + 1
        local hclen = get_bits(4) + 4
        local cl = {}
        for i = 0, 18 do cl[i] = 0 end
        for i = 0, hclen - 1 do
          cl[CL_ORDER[i + 1]] = get_bits(3)
        end
        local clh = build_huffman(cl, 19)
        local lengths = {}
        local idx = 0
        while idx < hlit + hdist do
          local sym = decode(clh)
          if sym < 16 then
            lengths[idx] = sym
            idx = idx + 1
          elseif sym == 16 then
            local prev = lengths[idx - 1]
            if prev == nil then error("png: repeat with no previous length", 0) end
            local rep = 3 + get_bits(2)
            for _ = 1, rep do lengths[idx] = prev; idx = idx + 1 end
          elseif sym == 17 then
            local rep = 3 + get_bits(3)
            for _ = 1, rep do lengths[idx] = 0; idx = idx + 1 end
          else
            local rep = 11 + get_bits(7)
            for _ = 1, rep do lengths[idx] = 0; idx = idx + 1 end
          end
        end
        local ll, dd = {}, {}
        for i = 0, hlit - 1 do ll[i] = lengths[i] or 0 end
        for i = 0, hdist - 1 do dd[i] = lengths[hlit + i] or 0 end
        lit = build_huffman(ll, hlit)
        dist = build_huffman(dd, hdist)
      end

      while true do
        local sym = decode(lit)
        if sym < 256 then
          outn = outn + 1
          out[outn] = sym
        elseif sym == 256 then
          break
        else
          local lbase = LENGTH_BASE[sym - 256]
          if not lbase then error("png: bad length symbol " .. tostring(sym), 0) end
          local len = lbase + get_bits(LENGTH_EXTRA[sym - 256])
          local dsym = decode(dist)
          local dbase = DIST_BASE[dsym + 1]
          if not dbase then error("png: bad distance symbol " .. tostring(dsym), 0) end
          local d = dbase + get_bits(DIST_EXTRA[dsym + 1])
          local start = outn - d + 1
          if start < 1 then error("png: back-reference before start", 0) end
          for i = 0, len - 1 do
            local v = out[start + i]
            if v == nil then error("png: corrupt back-reference", 0) end
            outn = outn + 1
            out[outn] = v
          end
        end
      end
    else
      error("png: reserved deflate block type", 0)
    end

    if bfinal == 1 then break end
  end

  local chunks, chunk, cn = {}, {}, 0
  for i = 1, outn do
    cn = cn + 1
    chunk[cn] = string.char(out[i])
    if cn >= 8192 then
      chunks[#chunks + 1] = table.concat(chunk)
      chunk, cn = {}, 0
    end
  end
  if cn > 0 then chunks[#chunks + 1] = table.concat(chunk) end
  return table.concat(chunks)
end

-- ---------------------------------------------------------------------------
-- PNG container
-- ---------------------------------------------------------------------------

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- decode(bytes) -> { width, height, rgb = <w*h*3 byte string>, channels }
function M.decode(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then
    error("png: empty or non-string input", 0)
  end
  if bytes:sub(1, 8) ~= "\137\80\78\71\13\10\26\10" then
    error("png: bad signature", 0)
  end
  if #bytes > 64 * 1024 * 1024 then
    error("png: input too large", 0)
  end

  local pos = 9
  local width, height, bitdepth, colortype, interlace
  local idat = {}
  while pos + 7 <= #bytes do
    local len = be32(bytes, pos)
    local ctype = bytes:sub(pos + 4, pos + 7)
    local dstart = pos + 8
    if dstart + len - 1 > #bytes then
      error("png: truncated chunk " .. tostring(ctype), 0)
    end
    if ctype == "IHDR" then
      width = be32(bytes, dstart)
      height = be32(bytes, dstart + 4)
      bitdepth = bytes:byte(dstart + 8)
      colortype = bytes:byte(dstart + 9)
      interlace = bytes:byte(dstart + 12)
    elseif ctype == "IDAT" then
      idat[#idat + 1] = bytes:sub(dstart, dstart + len - 1)
    elseif ctype == "IEND" then
      break
    end
    pos = dstart + len + 4
  end

  if not width or width <= 0 or height <= 0 then
    error("png: missing or invalid IHDR", 0)
  end
  if bitdepth ~= 8 then
    error("png: only 8-bit images are supported (got " .. tostring(bitdepth) .. ")", 0)
  end
  if interlace ~= 0 then
    error("png: interlaced images are not supported", 0)
  end
  local channels
  if colortype == 2 then
    channels = 3
  elseif colortype == 6 then
    channels = 4
  else
    error("png: only RGB/RGBA colour types are supported (got " .. tostring(colortype) .. ")", 0)
  end
  if #idat == 0 then
    error("png: no IDAT data", 0)
  end

  local raw = M.inflate_zlib(table.concat(idat))
  local stride = width * channels
  if #raw < height * (stride + 1) then
    error("png: decompressed data is too short", 0)
  end

  local rgb = {}
  local rgba_parts = (channels == 4) and {} or nil
  local outn = 0
  local prev = {}
  for i = 1, stride do prev[i] = 0 end

  local p = 1
  for _ = 0, height - 1 do
    local filter = raw:byte(p)
    local cur = { raw:byte(p + 1, p + stride) }
    p = p + stride + 1

    if filter == 1 then
      for i = 1, stride do
        local a = (i > channels) and cur[i - channels] or 0
        cur[i] = (cur[i] + a) % 256
      end
    elseif filter == 2 then
      for i = 1, stride do
        cur[i] = (cur[i] + prev[i]) % 256
      end
    elseif filter == 3 then
      for i = 1, stride do
        local a = (i > channels) and cur[i - channels] or 0
        cur[i] = (cur[i] + math.floor((a + prev[i]) / 2)) % 256
      end
    elseif filter == 4 then
      for i = 1, stride do
        local a = (i > channels) and cur[i - channels] or 0
        local b = prev[i]
        local c = (i > channels) and prev[i - channels] or 0
        local pp = a + b - c
        local pa, pb, pc = math.abs(pp - a), math.abs(pp - b), math.abs(pp - c)
        local add
        if pa <= pb and pa <= pc then add = a
        elseif pb <= pc then add = b
        else add = c end
        cur[i] = (cur[i] + add) % 256
      end
    elseif filter ~= 0 then
      error("png: unknown filter type " .. tostring(filter), 0)
    end
    prev = cur

    if channels == 3 then
      for i = 1, stride do
        outn = outn + 1
        rgb[outn] = string.char(cur[i])
      end
    else
      -- RGBA source: emit RGB for pixel reads AND the full RGBA string, since
      -- overlays must honour alpha (a transparent pixel is skipped entirely).
      local k = 1
      while k <= stride do
        rgb[outn + 1] = string.char(cur[k])
        rgb[outn + 2] = string.char(cur[k + 1])
        rgb[outn + 3] = string.char(cur[k + 2])
        outn = outn + 3
        rgba_parts[#rgba_parts + 1] = string.char(cur[k], cur[k + 1], cur[k + 2], cur[k + 3])
        k = k + 4
      end
    end
  end

  local result = { width = width, height = height, rgb = table.concat(rgb), channels = channels }
  if rgba_parts then
    result.rgba = table.concat(rgba_parts)
  end
  return result
end

-- RGBA bytes at (x, y), 0-based.
function M.rgba_at(img, x, y)
  if x < 0 or y < 0 or x >= img.width or y >= img.height or not img.rgba then
    return 0, 0, 0, 0
  end
  local i = (y * img.width + x) * 4 + 1
  local r, g, b, a = img.rgba:byte(i, i + 3)
  return r, g, b, a
end

-- RGB byte at (x, y), 0-based, matching upstream buffer conventions.
function M.rgb_at(img, x, y)
  if x < 0 or y < 0 or x >= img.width or y >= img.height then
    return 0, 0, 0
  end
  local i = (y * img.width + x) * 3 + 1
  local r, g, b = img.rgb:byte(i, i + 2)
  return r, g, b
end

return M
