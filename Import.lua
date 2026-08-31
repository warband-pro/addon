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
--- The cleanup verdicts off one character entry, or nil for none.
---
--- nil rather than an empty table, because the caller has to tell "this
--- character has no clear-out list" from "this character has an empty one" —
--- the first must leave a stored list alone and the second would replace it.
function Import.CleanupItems(raw)
  if type(raw) ~= "table" then return nil end
  local items, n = {}, 0
  for _, it in ipairs(raw) do
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
  if n == 0 then return nil end
  return items
end

-- ── the one string from warband.pro ─────────────────────────────────────────
-- `wbc1!` carried a cleanup list and nothing else until 1.8.0. It carries
-- everything the website has to say now — the clear-out list, the gear setups
-- best-in-bags picked, and which saved talent build is for which kind of night
-- — because three strings to fetch from two pages was the whole friction:
-- copy, alt-tab, paste, alt-tab, copy again, and a player who did half of it
-- had a set with no cleanup and no way to know.
--
-- **Additive, so the prefix does not move**, and the consequence is what
-- decides that rather than the shape: an addon older than 1.8.0 reads `items`
-- exactly as it always did and never learns the rest exists — it loses setups
-- it never had. Compare the `keep` field the cleanup wire deliberately does
-- not have, where an old client dropping it would have sold a good ring.
--
-- A character may now carry any one section without the others, which is the
-- one thing the old reader could not express: `items` is no longer required,
-- and a character with only setups is a normal entry rather than a dropped
-- one.

--- `builds` — which saved talent build the player assigned to which kind of
--- content, per spec. Config ids, matching what `talents.specs[].loadouts[].id`
--- sent out; the addon already holds the names and strings, so only the
--- mapping has to cross.
---
--- Absent means unassigned, exactly as elsewhere here. A content key naming a
--- config this character has never saved is kept rather than checked: the
--- reader has no business deciding a build is gone when the player may simply
--- not have logged in on that spec since making it.
local CONTENTS = { raid = true, mplus = true, delve = true }

local function readBuilds(raw)
  if type(raw) ~= "table" then return nil end
  local out, n = nil, 0
  for _, b in ipairs(raw) do
    if type(b) == "table" and type(b.spec) == "number" then
      local one
      for key in pairs(CONTENTS) do
        if type(b[key]) == "number" then
          one = one or {}
          one[key] = b[key]
        end
      end
      -- A spec entry naming no content at all is nothing to file, not an
      -- empty assignment to store over a good one.
      if one then
        out = out or {}
        out[b.spec] = one
        n = n + 1
      end
    end
  end
  if n == 0 then return nil end
  return out
end

--- The gear setups off one character entry, **nested under `gear`**.
---
--- Nested rather than flat, and that is not tidiness: `items` at the character
--- level already means the cleanup verdicts on this wire and has since 1.4.0.
--- A gear list sharing that key would be the same word meaning two things in
--- one object, which is exactly the kind of collision a reader gets wrong
--- silently. `gear.items` is the equip list; `items` is the clear-out list.
---
--- The shape inside is `wbg1!`'s character entry verbatim — same `spec`,
--- `set`, `items` and `sets`, validated by the same functions — so there is
--- one gear-set format, carried on two wires, rather than two that must be
--- kept in step.
local function readGear(raw)
  if type(raw) ~= "table" then return nil end

  local legacy = Import.GearSetItems(raw.items)
  local bySpec, n = nil, 0
  if type(raw.sets) == "table" then
    for _, set in ipairs(raw.sets) do
      -- A setup with no spec has nothing to be filed under. On `wbg1!` the
      -- unkeyed character-level fields carry that case; here they do too.
      if type(set) == "table" and type(set.spec) == "number" then
        local items = Import.GearSetItems(set.items)
        if #items > 0 then
          bySpec = bySpec or {}
          bySpec[set.spec] = { spec = set.spec, set = Import.SetName(set.set), items = items }
          n = n + 1
        end
      end
    end
  end

  if #legacy == 0 and n == 0 then return nil end
  return {
    spec = type(raw.spec) == "number" and raw.spec or nil,
    set = Import.SetName(raw.set),
    items = legacy,
    bySpec = bySpec,
  }
end

--- A pasted `wbc1!` -> everything warband.pro had to say, in one table.
---
--- Rejects only when **every** section is empty across every character: a
--- string that carries setups and no verdicts is a perfectly good string, and
--- "no_items" would send the player looking for a problem they do not have.
function Import.DecodePlan(paste)
  if type(paste) ~= "string" then return nil, "empty" end
  local str = paste:gsub("^%s+", ""):gsub("%s+$", "")
  if str == "" then return nil, "empty" end

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

  local chars = {}
  local nJunk, nSets, nBuilds = 0, 0, 0
  for _, c in ipairs(payload.chars) do
    if type(c) == "table" and type(c.guid) == "string" and c.guid ~= "" then
      local junk = Import.CleanupItems(c.items)
      local gear = readGear(c.gear)
      local builds = readBuilds(c.builds)
      -- Any one section is enough. A character with setups and nothing to
      -- sell is a normal entry, which is the case the cleanup-only reader
      -- could not express — it required `items` and dropped the rest.
      if junk or gear or builds then
        chars[c.guid] = {
          name = type(c.name) == "string" and c.name or "?",
          junk = junk,
          gear = gear,
          builds = builds,
        }
        if junk then nJunk = nJunk + 1 end
        if gear then nSets = nSets + 1 end
        if builds then nBuilds = nBuilds + 1 end
      end
    end
  end

  if nJunk + nSets + nBuilds == 0 then return nil, "no_items" end
  return {
    generatedAt = payload.generatedAt,
    chars = chars,
    nJunk = nJunk,
    nSets = nSets,
    nBuilds = nBuilds,
  }
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

--- A sanity cap on a pasted set name. **Not** the client's equipment-set
--- limit, which this addon deliberately does not hardcode — see `GearSet`'s
--- `saveSet`, which discovers it by asking the client instead. This only stops
--- a pathological string reaching storage.
local MAX_SET_NAME = 64

--- A proposed set name, sanity-capped. The website proposes; the client is the
--- authority on what it will accept, and the retry in `saveSet` is where that
--- is settled rather than by a constant here guessing at a build it never runs
--- in.
function Import.SetName(raw)
  local name = type(raw) == "string" and raw ~= "" and raw or "warband.pro"
  if #name > MAX_SET_NAME then name = name:sub(1, MAX_SET_NAME) end
  return name
end

--- The wire's `items` -> validated equip rows. Shared by the legacy fields and
--- by every `sets[]` entry, so one list cannot be checked more loosely than
--- the other.
---
--- `s` is the identity, `slot` is the destination. A real slot only: 1-17
--- minus 4 (shirt) — the collapsed representatives gear[] uses outbound are
--- never valid here, and 18/19 hold nothing equippable this addon should touch.
function Import.GearSetItems(raw)
  local items, n = {}, 0
  if type(raw) ~= "table" then return items end
  for _, it in ipairs(raw) do
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
  return items
end

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
      local items = Import.GearSetItems(c.items)
      if #items > 0 then
        -- `sets` is additive, added by the website in 1.8.0: one entry per
        -- spec it solved. The legacy `spec`/`set`/`items` above describe the
        -- FIRST of them (the spec being played), so a build older than this
        -- one reads that and behaves exactly as it always did — it simply
        -- never learns the off-spec setups exist. Nothing here depends on
        -- `sets` being present.
        local bySpec
        if type(c.sets) == "table" then
          for _, set in ipairs(c.sets) do
            -- A setup with no spec has no key to be filed under, so it is
            -- dropped rather than guessed at — the legacy fields already
            -- carry the unkeyed case.
            if type(set) == "table" and type(set.spec) == "number" then
              local setItems = Import.GearSetItems(set.items)
              if #setItems > 0 then
                bySpec = bySpec or {}
                bySpec[set.spec] = {
                  spec = set.spec,
                  set = Import.SetName(set.set),
                  items = setItems,
                }
              end
            end
          end
        end
        chars[c.guid] = {
          name = type(c.name) == "string" and c.name or "?",
          spec = type(c.spec) == "number" and c.spec or nil,
          set = Import.SetName(c.set),
          items = items,
          bySpec = bySpec,
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
  empty = "paste the string from warband.pro/gear",
  is_export = "that is your export string — this box takes the strings warband.pro gives back",
  is_gearset = "that is an equip string — it reads itself in this same box",
  wrong_prefix = "a warband.pro string starts with " .. "wbc1!" .. " — copy it from warband.pro/gear",
  too_large = "that string is too big to have come from warband.pro",
  not_base64 = "that does not decode — copy the whole string, all on one line",
  not_deflate = "that string is damaged — copy it again from warband.pro/gear",
  not_json = "that decoded to something warband.pro did not send",
  wrong_version = "that string is from a newer warband.pro — update this addon",
  -- Not "nothing to clean up" any more: the string carries three things now,
  -- and an empty one is empty of all of them.
  no_items = "nothing in that string for any character on this account",
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

--- **The one entry point the paste box uses.** One string in, one plan out,
--- whichever prefix it happens to carry.
---
--- Two wires reach this box and only one of them is current. `wbc1!` is what
--- warband.pro sends now and carries everything; `wbg1!` is the equip-only
--- string it sent before 1.8.0, still read because a player may have one on
--- the clipboard, in a note, or in a guild chat scrollback from last week.
--- Normalising both into one shape here is what keeps the panel from growing a
--- second code path for a format that is on its way out.
---
--- Returns `plan, nil, kind` or `nil, code, kind`, where `kind` picks the
--- message table — a `wbg1!` rejection still reads in that wire's own words.
function Import.DecodeInbound(paste)
  local str = type(paste) == "string" and paste:gsub("^%s+", ""):gsub("%s+$", "") or ""

  if str:sub(1, #ns.GEARSET_WIRE) == ns.GEARSET_WIRE then
    local gs, code = Import.DecodeGearSet(paste)
    if not gs then return nil, code, "gearset" end
    local chars = {}
    for guid, e in pairs(gs.chars) do
      chars[guid] = {
        name = e.name,
        gear = { spec = e.spec, set = e.set, items = e.items, bySpec = e.bySpec },
      }
    end
    return {
      generatedAt = gs.generatedAt,
      chars = chars,
      nJunk = 0,
      nSets = gs.count,
      nBuilds = 0,
    }, nil, "gearset"
  end

  local plan, code = Import.DecodePlan(paste)
  return plan, code, "plan"
end

--- The message for a code, in the words of the wire it came from.
function Import.InboundMessage(code, kind)
  if kind == "gearset" then return Import.GearSetMessage(code) end
  return Import.Message(code)
end
