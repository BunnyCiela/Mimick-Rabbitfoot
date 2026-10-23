-- Small per-run receipt, saved by Noita itself. ASCII hex avoids the engine's
-- unescaped XML-attribute handling; never write arbitrary error text directly.
local serialize=dofile_once('mods/interesting_seed_filter/files/isf/core/serialize.lua')
local M={KEY='interesting_seed_filter.start_result',PREFIX='ISF_START_V1:',MAX_BYTES=16384}
-- The full asset identity is a 12 KiB manifest already checked by the filter.
-- Store its bounded diagnostic checksum, not another copy of that manifest.
function M.asset_checksum(identity)
 local a,b=1,0
 for i=1,#identity do a=(a+identity:byte(i))%65521;b=(b+a)%65521 end
 return string.format('%08x',b*65536+a)
end
function M.write(api,result)
 if type(api.GlobalsSetValue)~='function'then return false end
 local ok,value=pcall(function()
  local receipt={}
  for k,v in pairs(result)do if k~='asset_identity'then receipt[k]=v end end
  if type(result.asset_identity)=='string'then
   receipt.asset_identity_adler32=M.asset_checksum(result.asset_identity)
   receipt.asset_identity_bytes=#result.asset_identity
  end
  local json=serialize.render_json(receipt)
  local encoded=M.PREFIX..json:gsub('.',function(c)return string.format('%02x',c:byte())end)
  if #encoded>M.MAX_BYTES then return false end
  api.GlobalsSetValue(M.KEY,encoded);return true
 end)
 return ok and value==true
end
return M
