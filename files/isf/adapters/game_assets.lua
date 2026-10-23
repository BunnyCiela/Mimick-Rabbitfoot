-- Noita's text-file API rejects PNGs. Load exactly the same packaged bytes
-- through the sandbox's Lua loader; no native file access or image mutation.
local bytes=dofile_once("mods/interesting_seed_filter/files/isf/worldgen/data/png_bytes.lua")
local assets=dofile_once("mods/interesting_seed_filter/files/isf/core/assets.lua")
local M={}
function M.read(path)
  return bytes[path]
end
function M.build()
  return assets.build({read=M.read,version="packaged-png-bytes-v1"})
end
return M
