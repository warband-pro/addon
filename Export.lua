-- WarbandPro / Export.lua
-- JSON -> raw deflate -> base64url -> "wb1!". Pure apart from the clock.
--
-- Why our own base64 rather than LibDeflate:EncodeForPrint: EncodeForPrint uses
-- LibDeflate's own printable 6-bit alphabet, which is neither base64 nor
-- base64url, and the website decodes with atob/DecompressionStream. The
-- alphabet below is RFC 4648 §5 with the padding dropped, which atob reads back
-- after swapping - and _ for + and /.
--
-- The compressed half is a *raw* deflate stream (LibDeflate:CompressDeflate),
-- so the web side inflates with DecompressionStream("deflate-raw") or
-- pako.inflateRaw. Not "deflate" — that expects a zlib header this does not
-- carry.

local _, ns = ...

local Export = {}
ns.Export = Export

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local CHAR = {}
for i = 0, 63 do CHAR[i] = ALPHABET:sub(i + 1, i + 1) end

local byte, concat, floor = string.byte, table.concat, math.floor

function Export.Base64URL(data)
  local out, n, i = {}, #data, 1
  while i + 2 <= n do
    local a, b, c = byte(data, i, i + 2)
    local v = a * 65536 + b * 256 + c
    local b1 = floor(v / 262144)
    local b2 = floor(v / 4096) % 64
    local b3 = floor(v / 64) % 64
    out[#out + 1] = CHAR[b1] .. CHAR[b2] .. CHAR[b3] .. CHAR[v % 64]
    i = i + 3
  end
  local left = n - i + 1
  if left == 1 then
    local a = byte(data, i)
    out[#out + 1] = CHAR[floor(a / 4)] .. CHAR[(a % 4) * 16]
  elseif left == 2 then
    local a, b = byte(data, i, i + 1)
    local v = a * 256 + b
    out[#out + 1] = CHAR[floor(v / 1024)] .. CHAR[floor(v / 16) % 64] .. CHAR[(v % 16) * 4]
  end
  return concat(out)
end

-- Returns the wb1! string, its length in bytes, and the payload it was built
-- from — the panel needs all three and the slash commands need the first.
function Export.Build(opts)
  local json, payload = ns.Bundle.Encode(opts)
  if not json then return nil, 0, nil end

  local lib = ns.LibDeflate
  if not lib then
    ns.lastError = "LibDeflate missing"
    return nil, 0, payload
  end

  local packed = ns.safe(function() return lib:CompressDeflate(json, { level = 9 }) end)
  if not packed then return nil, 0, payload end

  local str = ns.WIRE .. Export.Base64URL(packed)
  return str, #str, payload, #json
end
