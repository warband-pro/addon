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

-- Four table slots per three input bytes, no intermediate `..` concatenation
-- — the previous version built three throwaway strings per chunk before the
-- final append. table.concat does the joining once, at the end.
function Export.Base64URL(data)
  local out, n, i, oi = {}, #data, 1, 0
  while i + 2 <= n do
    local a, b, c = byte(data, i, i + 2)
    local v = a * 65536 + b * 256 + c
    out[oi + 1] = CHAR[floor(v / 262144)]
    out[oi + 2] = CHAR[floor(v / 4096) % 64]
    out[oi + 3] = CHAR[floor(v / 64) % 64]
    out[oi + 4] = CHAR[v % 64]
    oi = oi + 4
    i = i + 3
  end
  local left = n - i + 1
  if left == 1 then
    local a = byte(data, i)
    out[oi + 1] = CHAR[floor(a / 4)]
    out[oi + 2] = CHAR[(a % 4) * 16]
  elseif left == 2 then
    local a, b = byte(data, i, i + 1)
    local v = a * 256 + b
    out[oi + 1] = CHAR[floor(v / 1024)]
    out[oi + 2] = CHAR[floor(v / 16) % 64]
    out[oi + 3] = CHAR[(v % 16) * 4]
  end
  return concat(out)
end

-- Keyed on Store.rev + currentOnly: nothing in the bundle can have changed
-- without a Store write bumping rev, so a rev match means the previous
-- string is still exactly what a fresh build would produce. /warband status
-- used to pay a full JSON encode + level-9 deflate of the whole bundle just
-- to print a byte count; this makes a second call in the same state free.
--
-- The one field this does not keep byte-identical to an uncached build is
-- `exportedAt` — a cache hit reports when the bundle was last assembled, not
-- the instant this particular call happened. Nothing in this repo or
-- docs/CONTRACT.md reads exportedAt as anything more precise than that.
local cache = { rev = -1, currentOnly = nil, str = nil, bytes = 0, payload = nil, rawBytes = 0 }

-- Returns the wb1! string, its length in bytes, and the payload it was built
-- from — the panel needs all three and the slash commands need the first.
function Export.Build(opts)
  opts = opts or {}
  local currentOnly = opts.currentOnly and true or false
  local page = math.max(math.floor(tonumber(opts.page) or 1), 1)
  local rev = ns.Store.rev or 0
  if cache.str and cache.rev == rev and cache.currentOnly == currentOnly and cache.page == page then
    return cache.str, cache.bytes, cache.payload, cache.rawBytes
  end

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
  cache.rev, cache.currentOnly, cache.page, cache.str, cache.bytes, cache.payload, cache.rawBytes =
    rev, currentOnly, page, str, #str, payload, #json
  return str, #str, payload, #json
end
