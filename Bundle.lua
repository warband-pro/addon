-- WarbandPro / Bundle.lua
-- Pure. No WoW API beyond the clock, so every function here is testable off
-- the game client: characters in, wire JSON out.

local _, ns = ...

local Bundle = {}
ns.Bundle = Bundle

local concat, sort, format, floor = table.concat, table.sort, string.format, math.floor

-- ── JSON ────────────────────────────────────────────────────────────────────
-- Encode only, with sorted keys, so the same data always produces byte-identical
-- output and a contract vector can be diffed rather than parsed.
--
-- One rule worth stating: an empty table encodes as [], not {}. SavedVariables
-- strips metatables, so a marker on a list would not survive a /reload, and
-- every empty table this payload can produce is a list — an empty bank is
-- `{free=null, items=[]}`, never a bare `{}`.

local ESCAPE = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
  ['\r'] = '\\r', ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
}

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(ch)
    return ESCAPE[ch] or format('\\u%04x', ch:byte())
  end) .. '"'
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  if n == floor(n) and n < 1e15 and n > -1e15 then return format("%d", n) end
  return format("%.14g", n)
end

local function encode(value, out)
  local t = type(value)
  if value == nil then
    out[#out + 1] = "null"
  elseif t == "boolean" then
    out[#out + 1] = value and "true" or "false"
  elseif t == "number" then
    out[#out + 1] = encodeNumber(value)
  elseif t == "string" then
    out[#out + 1] = encodeString(value)
  elseif t == "table" then
    local len = #value
    if len > 0 or next(value) == nil then
      out[#out + 1] = "["
      for i = 1, len do
        if i > 1 then out[#out + 1] = "," end
        encode(value[i], out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(value) do
        if type(k) == "string" then keys[#keys + 1] = k end
      end
      sort(keys)
      out[#out + 1] = "{"
      for i = 1, #keys do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = encodeString(keys[i])
        out[#out + 1] = ":"
        encode(value[keys[i]], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function Bundle.JSON(value)
  local out = {}
  encode(value, out)
  return concat(out)
end

-- ── payload ─────────────────────────────────────────────────────────────────

-- The warband bank rides at the root of the payload, not inside each character.
-- CONTRACT.md v1 puts it on CharacterObject, and measuring says that is wrong:
-- five tabs of items repeated across six characters costs ~22KB of wire for one
-- vault that every character shares, because deflate's window does not reach
-- back far enough to fold the copies together. One object, one stamp, one
-- "by Vocnar" credit; each character keeps its own seenAt.warbank so the dots
-- still say which character last stood at the banker.
local function warbandBank(root)
  if not root or not root.seenAt then return nil end
  return {
    seenAt = root.seenAt,
    seenByGuid = root.seenByGuid,
    seenByName = root.seenByName,
    gold = root.gold,
    tabs = root.tabs or {},
  }
end

-- opts.currentOnly restricts the bundle to the character at the keyboard, which
-- is what /warband copy current is for.
function Bundle.Build(opts)
  opts = opts or {}
  local db = ns.Store.db
  if type(db) ~= "table" then return nil end

  local chars = ns.Store.Characters()
  if opts.currentOnly then
    local guid = UnitGUID and UnitGUID("player")
    local one = guid and db.chars[guid]
    chars = one and { one } or {}
  end

  -- CONTRACT.md rejects more than MAX_CHARS, and Store.Characters() is already
  -- newest-first, so the ones that fall off the end are the ones you have not
  -- played in longest.
  local dropped = 0
  if #chars > ns.MAX_CHARS then
    dropped = #chars - ns.MAX_CHARS
    for i = #chars, ns.MAX_CHARS + 1, -1 do chars[i] = nil end
  end

  local freshest, oldest
  for i = 1, #chars do
    local seen = chars[i].seenAt and chars[i].seenAt.lastSeen or 0
    if not freshest or seen > freshest then freshest = seen end
    if not oldest or seen < oldest then oldest = seen end
  end

  return {
    v = ns.WIRE_V,
    addon = ns.VERSION,
    exportedAt = ns.now(),
    gameVersion = ns.safe(function() return (GetBuildInfo()) end),
    interface = tonumber(ns.safe(function() return select(4, GetBuildInfo()) end)),
    bundle = {
      count = #chars,
      freshestSeenAt = freshest,
      oldestSeenAt = oldest,
      droppedOverCap = dropped > 0 and dropped or nil,
    },
    warbandBank = warbandBank(db.warbandBank),
    characters = chars,
  }
end

function Bundle.Encode(opts)
  local payload = Bundle.Build(opts)
  if not payload then return nil end
  return Bundle.JSON(payload), payload
end

-- One line per character for the panel header, from the same stamps the website
-- turns into dots.
function Bundle.Summary(payload)
  if not payload then return {} end
  local rows = {}
  local warbank = payload.warbandBank
  for _, c in ipairs(payload.characters) do
    local seen = c.seenAt or {}
    rows[#rows + 1] = {
      name = c.name or "?",
      realm = c.realm,
      level = c.level,
      dot = ns.dot(seen.lastSeen),
      ago = ns.ago(seen.lastSeen),
      bankAgo = ns.ago(seen.bank),
      warbankAgo = ns.ago(warbank and warbank.seenAt),
    }
  end
  return rows
end
