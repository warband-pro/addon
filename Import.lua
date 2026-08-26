-- WarbandPro / Import.lua
-- "wbc1!" -> base64url -> raw inflate -> JSON -> a cleanup list. Pure: no WoW
-- API, no frames, no SavedVariables. The exact inverse of Export.lua, and the
-- first thing in this addon that reads rather than writes.
--
-- Three rules govern everything here, and all three are about a string a
-- player pasted in from somewhere else:
--
-- 1. **Nothing is executed.** tools/validate.mjs fails the build on every
--    runtime code-building call anywhere in the zip, and it is right to:
--    running a pasted string is the single worst thing an addon can do. The
--    JSON decoder below is hand-rolled for exactly the grammar Bundle.JSON
--    emits. (That validator matched this very comment when it named those
--    functions literally, which is the rule working rather than a false
--    positive — the scan cannot tell prose from code, and should not try.)
-- 2. **Fail closed, and say which failure it was.** Every rejection returns
--    nil plus a code the panel turns into a sentence. A cleanup string pasted
--    into the wrong box is *valid somewhere else*, so "that is not valid" would
--    be a lie; the prefix checks below exist to tell those two apart.
-- 3. **Bound the work before doing it.** LibDeflate:DecompressDeflate has no
--    streaming cap and allocates whatever the stream asks for, so the INPUT
--    length is the real guard and the output check is the second line. See
--    docs/CONTRACT.md's "Reader caps".

local _, ns = ...

local Import = {}
ns.Import = Import

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- The inverse of Export.lua's CHAR table. Built once at load; a character
-- absent from it is a character that cannot appear in base64url, which is what
-- makes an unknown byte a rejection rather than a zero.
local VALUE = {}
for i = 1, 64 do VALUE[ALPHABET:sub(i, i)] = i - 1 end

local byte, char, concat, floor, sub = string.byte, string.char, table.concat, math.floor, string.sub

--- base64url (RFC 4648 §5, unpadded) -> a byte string, or nil.
function Import.Base64URLDecode(str)
  if type(str) ~= "string" then return nil end
  local n = #str
  -- A length of 1 mod 4 cannot come from any input: base64 emits 2, 3 or 4
  -- characters per group, never 1.
  if n % 4 == 1 then return nil end

  local out, oi, acc, bits = {}, 0, 0, 0
  for i = 1, n do
    local v = VALUE[sub(str, i, i)]
    if not v then return nil end
    acc = acc * 64 + v
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local shift = 2 ^ bits
      oi = oi + 1
      out[oi] = char(floor(acc / shift) % 256)
      acc = acc % shift
    end
  end
  return concat(out)
end

-- ── JSON ────────────────────────────────────────────────────────────────────
-- Recursive descent over exactly what Bundle.JSON produces: objects, arrays,
-- strings with \u escapes, numbers, true, false, null. Strict on purpose —
-- trailing garbage is a rejection, not something to ignore, because a decoder
-- that shrugs at the tail is a decoder that accepts two payloads concatenated.

local DEPTH_MAX = 16

local function skipWS(s, i)
  local _, j = s:find("^[ \n\r\t]*", i)
  return (j or i - 1) + 1
end

local decodeValue

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

--- A codepoint to UTF-8. WoW's Lua has no utf8.char in every context we run in,
--- and the payload is ASCII in practice — but an item name is not ours to
--- assume, so the four-branch encoder stays.
local function utf8Encode(cp)
  if cp < 0x80 then
    return char(cp)
  elseif cp < 0x800 then
    return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return char(
    0xF0 + floor(cp / 0x40000),
    0x80 + floor(cp / 0x1000) % 0x40,
    0x80 + floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

local function decodeString(s, i)
  -- i points at the opening quote.
  local out, oi = {}, 0
  i = i + 1
  while true do
    local c = sub(s, i, i)
    if c == "" then return nil, i, "unterminated string" end
    if c == '"' then return concat(out), i + 1 end
    if c == "\\" then
      local e = sub(s, i + 1, i + 1)
      local simple = ESCAPES[e]
      if simple then
        oi = oi + 1
        out[oi] = simple
        i = i + 2
      elseif e == "u" then
        local hex = sub(s, i + 2, i + 5)
        if not hex:match("^%x%x%x%x$") then return nil, i, "bad \\u escape" end
        oi = oi + 1
        out[oi] = utf8Encode(tonumber(hex, 16))
        i = i + 6
      else
        return nil, i, "bad escape"
      end
    else
      -- A raw control character is invalid JSON; Bundle.JSON escapes every one.
      if byte(c) < 0x20 then return nil, i, "raw control character" end
      oi = oi + 1
      out[oi] = c
      i = i + 1
    end
  end
end

local function decodeNumber(s, i)
  local numStr = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
  if not numStr or numStr == "" then return nil, i, "bad number" end
  local v = tonumber(numStr)
  if not v then return nil, i, "bad number" end
  return v, i + #numStr
end

function decodeValue(s, i, depth)
  if depth > DEPTH_MAX then return nil, i, "too deeply nested" end
  i = skipWS(s, i)
  local c = sub(s, i, i)

  if c == "" then
    return nil, i, "unexpected end"
  elseif c == '"' then
    return decodeString(s, i)
  elseif c == "{" then
    local obj = {}
    i = skipWS(s, i + 1)
    if sub(s, i, i) == "}" then return obj, i + 1 end
    while true do
      i = skipWS(s, i)
      if sub(s, i, i) ~= '"' then return nil, i, "object key must be a string" end
      local key, ni, err = decodeString(s, i)
      if key == nil then return nil, ni, err end
      i = skipWS(s, ni)
      if sub(s, i, i) ~= ":" then return nil, i, "expected :" end
      local val
      val, i, err = decodeValue(s, i + 1, depth + 1)
      if err then return nil, i, err end
      obj[key] = val
      i = skipWS(s, i)
      local d = sub(s, i, i)
      if d == "," then
        i = i + 1
      elseif d == "}" then
        return obj, i + 1
      else
        return nil, i, "expected , or }"
      end
    end
  elseif c == "[" then
    local arr, n = {}, 0
    i = skipWS(s, i + 1)
    if sub(s, i, i) == "]" then return arr, i + 1 end
    while true do
      local val, err
      val, i, err = decodeValue(s, i, depth + 1)
      if err then return nil, i, err end
      n = n + 1
      arr[n] = val
      i = skipWS(s, i)
      local d = sub(s, i, i)
      if d == "," then
        i = i + 1
      elseif d == "]" then
        return arr, i + 1
      else
        return nil, i, "expected , or ]"
      end
    end
  elseif sub(s, i, i + 3) == "true" then
    return true, i + 4
  elseif sub(s, i, i + 4) == "false" then
    return false, i + 5
  elseif sub(s, i, i + 3) == "null" then
    -- Lua cannot hold a nil in a table, and the payload never needs one. A
    -- literal null becomes false, which every reader below treats as absent.
    return false, i + 4
  end
  return decodeNumber(s, i)
end

--- JSON text -> a Lua value, or nil plus a reason.
function Import.JSONDecode(str)
  if type(str) ~= "string" or str == "" then return nil, "empty" end
  local value, i, err = decodeValue(str, 1, 1)
  if err then return nil, err end
  i = skipWS(str, i)
  if i <= #str then return nil, "trailing garbage" end
  return value
end

-- ── the cleanup string ──────────────────────────────────────────────────────

Import.MAX_WIRE = 40 * 1024
Import.MAX_DECODED = 512 * 1024
local VERDICTS = { sell = true, de = true, del = true }

--- A pasted string -> { generatedAt, chars = { [guid] = { name, items } } }.
--- Returns nil plus a code on every failure; the codes are what UI.lua turns
--- into a sentence, so each one names a different thing to do about it.
function Import.DecodeCleanup(paste)
  if type(paste) ~= "string" then return nil, "empty" end
  local str = paste:gsub("^%s+", ""):gsub("%s+$", "")
  if str == "" then return nil, "empty" end

  -- Checked before the wbc1! test rather than after: a bundle is a perfectly
  -- good string that belongs in the other direction, and an equip string is a
  -- perfectly good string for the box next door — telling someone either is
  -- invalid would send them looking for a problem that does not exist.
  if str:sub(1, #ns.WIRE) == ns.WIRE then return nil, "is_export" end
  if str:sub(1, #ns.GEARSET_WIRE) == ns.GEARSET_WIRE then return nil, "is_gearset" end
  if str:sub(1, #ns.CLEANUP_WIRE) ~= ns.CLEANUP_WIRE then return nil, "wrong_prefix" end
  if #str > Import.MAX_WIRE then return nil, "too_large" end

  local raw = Import.Base64URLDecode(str:sub(#ns.CLEANUP_WIRE + 1))
  if not raw or raw == "" then return nil, "not_base64" end

  local json = ns.safe(function() return ns.LibDeflate:DecompressDeflate(raw) end)
  if not json or json == "" then return nil, "not_deflate" end
  if #json > Import.MAX_DECODED then return nil, "too_large" end

  local payload = Import.JSONDecode(json)
  if type(payload) ~= "table" then return nil, "not_json" end
  if payload.v ~= 1 then return nil, "wrong_version" end
  if type(payload.generatedAt) ~= "number" then return nil, "not_json" end
  if type(payload.chars) ~= "table" then return nil, "not_json" end

  local chars, count = {}, 0
  for _, c in ipairs(payload.chars) do
    if type(c) == "table" and type(c.guid) == "string" and c.guid ~= "" and type(c.items) == "table" then
      local items, n = {}, 0
      for _, it in ipairs(c.items) do
        -- `s` is the entire identity mechanism: an entry without one names no
        -- item this addon can ever find, so it is dropped rather than kept as
        -- a row that can never resolve.
        if type(it) == "table" and VERDICTS[it.k] and type(it.s) == "string" and it.s ~= "" then
          n = n + 1
          items[n] = {
            k = it.k,
            s = it.s,
            id = type(it.id) == "number" and it.id or nil,
            r = type(it.r) == "string" and it.r or nil,
            g = type(it.g) == "number" and it.g or nil,
            ilvl = type(it.ilvl) == "number" and it.ilvl or nil,
          }
        end
      end
      if n > 0 then
        chars[c.guid] = { name = type(c.name) == "string" and c.name or "?", items = items }
        count = count + 1
      end
    end
  end

  if count == 0 then return nil, "no_items" end
  return { generatedAt = payload.generatedAt, chars = chars, count = count }
end

-- ── the gear-set string ─────────────────────────────────────────────────────
-- wbg1! — the second inbound direction, added in 1.6.0: the set warband.pro's
-- best-in-bags picked, one entry per slot that CHANGES. Slots already right
-- are omitted (SaveEquipmentSet snapshots the live paperdoll, so keepers join
-- the set for free), and the wire carries no bag coordinates for the same
-- reason wbc1! never has: an item is named by its verbatim item string and
-- found by a live walk at click time. One asymmetry with gear[], stated in
-- CONTRACT.md: `slot` here is the REAL inventory slot (12 means finger 2),
-- uncollapsed, because the website knows which twin its solve replaces and
-- this addon cannot.

--- A pasted string -> { generatedAt, chars = { [guid] = { name, spec, set, items } } }.
--- Same caps, same envelope, same fail-closed posture as DecodeCleanup.
function Import.DecodeGearSet(paste)
  if type(paste) ~= "string" then return nil, "empty" end
  local str = paste:gsub("^%s+", ""):gsub("%s+$", "")
  if str == "" then return nil, "empty" end

  if str:sub(1, #ns.WIRE) == ns.WIRE then return nil, "is_export" end
  if str:sub(1, #ns.CLEANUP_WIRE) == ns.CLEANUP_WIRE then return nil, "is_cleanup" end
  if str:sub(1, #ns.GEARSET_WIRE) ~= ns.GEARSET_WIRE then return nil, "wrong_prefix" end
  if #str > Import.MAX_WIRE then return nil, "too_large" end

  local raw = Import.Base64URLDecode(str:sub(#ns.GEARSET_WIRE + 1))
  if not raw or raw == "" then return nil, "not_base64" end

  local json = ns.safe(function() return ns.LibDeflate:DecompressDeflate(raw) end)
  if not json or json == "" then return nil, "not_deflate" end
  if #json > Import.MAX_DECODED then return nil, "too_large" end

  local payload = Import.JSONDecode(json)
  if type(payload) ~= "table" then return nil, "not_json" end
  if payload.v ~= 1 then return nil, "wrong_version" end
  if type(payload.generatedAt) ~= "number" then return nil, "not_json" end
  if type(payload.chars) ~= "table" then return nil, "not_json" end

  local chars, count = {}, 0
  for _, c in ipairs(payload.chars) do
    if type(c) == "table" and type(c.guid) == "string" and c.guid ~= "" and type(c.items) == "table" then
      local items, n = {}, 0
      for _, it in ipairs(c.items) do
        -- `s` is the identity, `slot` is the destination. A real slot only:
        -- 1-17 minus 4 (shirt) — the collapsed representatives gear[] uses
        -- outbound are never valid here, and 18/19 hold nothing equippable
        -- this addon should touch.
        local slot = type(it) == "table" and it.slot
        if type(slot) == "number" and slot >= 1 and slot <= 17 and slot ~= 4
          and type(it.s) == "string" and it.s ~= "" then
          n = n + 1
          items[n] = {
            slot = slot,
            s = it.s,
            id = type(it.id) == "number" and it.id or nil,
            w = type(it.w) == "string" and it.w or nil,
          }
        end
      end
      if n > 0 then
        chars[c.guid] = {
          name = type(c.name) == "string" and c.name or "?",
          spec = type(c.spec) == "number" and c.spec or nil,
          set = type(c.set) == "string" and c.set ~= "" and c.set or "warband.pro",
          items = items,
        }
        count = count + 1
      end
    end
  end

  if count == 0 then return nil, "no_items" end
  return { generatedAt = payload.generatedAt, chars = chars, count = count }
end

--- One rejection code -> the line the panel prints. Written for the person who
--- just pasted the wrong thing, not for a log.
local MESSAGES = {
  empty = "paste the cleanup string from warband.pro/gear",
  is_export = "that is your export string — this box takes the strings warband.pro gives back",
  is_gearset = "that is an equip string — it reads itself in this same box",
  wrong_prefix = "a cleanup string starts with " .. "wbc1!" .. " — copy it from warband.pro/gear",
  too_large = "that string is too big to be a cleanup list",
  not_base64 = "that does not decode — copy the whole string, all on one line",
  not_deflate = "that string is damaged — copy it again from warband.pro/gear",
  not_json = "that decoded to something that is not a cleanup list",
  wrong_version = "that cleanup string is from a newer warband.pro — update this addon",
  no_items = "nothing to clean up in that string",
}

function Import.Message(code)
  return MESSAGES[code] or "that string could not be read"
end

--- The gear-set codes that read differently from their cleanup twins. The
--- rest fall through to MESSAGES, so the two maps cannot drift on the shared
--- failures.
local GEARSET_MESSAGES = {
  is_cleanup = "that is a cleanup string — it reads itself in this same box",
  wrong_prefix = "an equip string starts with " .. "wbg1!" .. " — copy it from warband.pro/gear",
  too_large = "that string is too big to be an equip string",
  not_deflate = "that string is damaged — copy it again from warband.pro/gear",
  not_json = "that decoded to something that is not a gear set",
  wrong_version = "that equip string is from a newer warband.pro — update this addon",
  no_items = "no slots change in that string — the set is already what you are wearing",
}

function Import.GearSetMessage(code)
  return GEARSET_MESSAGES[code] or MESSAGES[code] or "that string could not be read"
end
