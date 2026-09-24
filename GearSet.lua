-- WarbandPro / GearSet.lua
-- The stored equip string, resolved against the bags and the paperdoll that
-- exist right now, applied under the player's click, and saved as an
-- Equipment Manager set once the server confirms what is actually worn.
--
-- Junk.lua's design carries over whole: the wire names an item by its verbatim
-- item string and never by a coordinate, so every PickupContainerItem call
-- below uses a position found by the walk that just happened. The one thing
-- this file adds to that doctrine is a destination — the wire's `slot` is the
-- REAL inventory slot (12 is finger 2), because the website's solve knows
-- which twin it replaces and EquipCursorItem is what places a ring in the
-- chosen one, which EquipItemByName never guarantees.
--
-- Equips are server round-trips, and C_EquipmentSet.SaveEquipmentSet snapshots
-- whatever is worn AT THAT MOMENT — saving in the same frame as the equips
-- saves the old kit. So Apply sets `pending` and the save happens in Verify,
-- driven by PLAYER_EQUIPMENT_CHANGED (Core.lua) with one C_Timer.After
-- deadline as the fallback, event-driven like everything else here. A player
-- moving items mid-apply makes Verify see a mismatch; the deadline saves what
-- verified and reports honestly rather than retrying forever.
--
-- Combat: fail closed, always. No equip starts in combat, and combat starting
-- mid-apply drops the pending save with a line saying to press the button
-- again — never a deferred queue of equips firing when the fight ends.

local _, ns = ...

local GearSet = {}
ns.GearSet = GearSet

local Store = ns.Store
local C = C_Container

-- How long Verify waits for the server before saving what actually verified.
local DEADLINE_SEC = 3

--- Whether the auction house window is open, set from the event in Core.lua.
--- `Junk.merchantOpen`'s twin, and for the same reason: the one thing a
--- shopping-list row can do is search for what it names, and only there.
GearSet.ahOpen = false

--- The whole stored record for the character at the keyboard, or nil.
local function storedRecord()
  local db = Store.db
  if not db or not db.gearset then return nil end
  local guid = ns.safe(UnitGUID, "player")
  if not guid then return nil end
  return db.gearset[guid]
end

--- The spec this character is playing right now: id, name, icon — or nil.
--- The name and icon are what the Equipment Manager set is called and wears,
--- so they come from the client and never from the wire: the client's name
--- is in the player's own language and the icon is only reachable here.
local function activeSpec()
  local index = ns.safe(GetSpecialization)
  if not index then return nil end
  return ns.safe(function()
    local id, name, _, icon = GetSpecializationInfo(index)
    return id, name, icon
  end)
end

local function activeSpecID()
  local id = activeSpec()
  return id
end

--- The brand the set used to carry in its name. Kept only so a set saved by
--- an older build can be found and renamed rather than left beside a new one.
local LEGACY_BRAND = "warband.pro"

--- What the Equipment Manager set for a stored setup is called, and its icon:
--- `name, icon, legacy`, where `legacy` lists the names an older build may
--- have saved this same set under.
---
--- **The set is named after the spec, and nothing else — since 1.11.0.** It
--- was `warband.pro Protection`: the brand first so a player could pick ours
--- out from their own, then the spec so two setups could coexist. The
--- maintainer's read after living with it was the AskMrRobot one — the set
--- for the Protection spec is called `Protection`, wears the Protection
--- icon, and if you already have one by that name it is the one that gets
--- updated. The brand was answering a question nobody asked, and the icon is
--- what actually picks a set out of a list.
---
--- The wire still proposes a name (`set`), and it is the fallback for a
--- character whose spec the client cannot read — an unkeyed record from an
--- older website applies to whoever is standing there, and the client has to
--- call it something. When the spec is known, the client's own word for it
--- wins, in the player's own language.
function GearSet.SetName(stored)
  local proposed = stored and stored.set or LEGACY_BRAND
  local _, specName, icon = activeSpec()
  if not specName or specName == "" then
    return proposed, ns.ICON, {}
  end
  local legacy = { LEGACY_BRAND .. " " .. specName, LEGACY_BRAND }
  if proposed ~= specName then table.insert(legacy, 1, proposed) end
  return specName, icon or ns.ICON, legacy
end

--- The stored setup for the spec at the keyboard, or nil.
---
--- **Per spec since 1.8.0, and the nil is the point.** One set per character
--- was fine while the website could only solve the spec you were logged out
--- in; it can solve any of them now, so a stored Feral set is not an answer to
--- a Restoration paperdoll and equipping it would be actively wrong. So a
--- record that names specs answers only for the one being played.
---
--- The exception is a record with no spec at all, which is what an older
--- website sends and what a character with no resolvable spec still gets:
--- it makes no claim, so it applies to whoever is standing there. That is
--- also the downgrade path — the legacy fields are still written, so a player
--- who reverts this addon finds exactly the record the old code expects.
--- `content` is optional and is what `/warband equip raid` passes: since 1.15.0
--- the website solves a spec once per kind of night, so a spec can hold a raid
--- set and a key set at the same time.
---
--- **Asking for a night you have no set for answers nothing, rather than
--- quietly handing over another night's kit.** That is the same rule the spec
--- keying already follows and for the same reason: equipping the wrong set is
--- worse than equipping none, and the panel can say which of the two happened.
--- Asking for no night at all gets the default — the unkeyed set when the
--- website sent one, otherwise the first it sent.
function GearSet.Stored(content)
  local rec = storedRecord()
  if not rec then return nil end
  local spec = activeSpecID()

  if content then
    local forSpec = spec and type(rec.byContent) == "table" and rec.byContent[spec]
    local mine = forSpec and forSpec[content]
    if not mine then return nil end
    return {
      generatedAt = rec.generatedAt,
      spec = mine.spec,
      set = mine.set,
      content = mine.content,
      items = mine.items,
    }
  end

  if rec.bySpec then
    local mine = spec and rec.bySpec[spec]
    if mine then
      return {
        generatedAt = rec.generatedAt,
        spec = mine.spec,
        set = mine.set,
        content = mine.content,
        items = mine.items,
      }
    end
    -- A record that names specs and has none for this one says nothing.
    return nil
  end
  -- No `bySpec` at all: an unkeyed record, which applies to anyone.
  if rec.spec and activeSpecID() and rec.spec ~= activeSpecID() then return nil end
  return rec
end

--- Which kinds of night this character has a set for, in the website's own
--- order, for the spec being played. Read by the panel and by `/warband equip`
--- so an unknown argument can be answered with the list rather than a shrug.
function GearSet.Contents()
  local rec = storedRecord()
  local spec = activeSpecID()
  local out = {}
  if not rec or not spec or type(rec.byContent) ~= "table" then return out end
  local forSpec = rec.byContent[spec]
  if type(forSpec) ~= "table" then return out end
  for _, key in ipairs(ns.CONTENTS) do
    if forSpec[key] then out[#out + 1] = key end
  end
  return out
end

--- How many stored setups this character has, and whether any is for the spec
--- being played. Read by the UI so "no set at all" and "a set, for another
--- spec" can be different sentences — the same reason the junk panel names its
--- empty states rather than sharing one.
function GearSet.Summary()
  local rec = storedRecord()
  if not rec then return 0, false end
  if not rec.bySpec then return 1, GearSet.Stored() ~= nil end
  local n = 0
  for _ in pairs(rec.bySpec) do n = n + 1 end
  return n, GearSet.Stored() ~= nil
end

--- Store a decoded equip payload. Junk.Save's rule verbatim: only guids this
--- account has scanned are kept — the rest of the string belongs to
--- characters that will read it when they log in.
---
--- The legacy `spec`/`set`/`items` are written alongside `bySpec` rather than
--- replaced by it, and not out of caution: they are what a downgraded addon
--- reads, and they describe the spec the player was on when they pasted, which
--- is the only one a build that cannot choose should be handed.
--- **A character with no `gear` section is skipped, not cleared** — Junk.Save's
--- rule and for the same reason. One string carries three things since 1.8.0,
--- and a character can legitimately have a clear-out list and no setups.
function GearSet.Save(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" or type(decoded.chars) ~= "table" then return 0 end
  db.gearset = db.gearset or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    local gear = entry.gear
    if db.chars[guid] and gear then
      db.gearset[guid] = {
        generatedAt = decoded.generatedAt,
        spec = gear.spec,
        set = gear.set,
        items = gear.items,
        bySpec = gear.bySpec,
        -- Per spec AND per kind of night, since 1.15.0. Stored beside `bySpec`
        -- rather than replacing it: `bySpec` is still what `/warband equip`
        -- with no argument uses, and is still the whole record for a string
        -- from a website that does not send `c`.
        byContent = gear.byContent,
        -- Carried on the same record rather than a fourth top-level table:
        -- a build assignment is about which setup to wear on which night, so
        -- it belongs beside the setups, and one record means one write.
        --
        -- **Both of these are carried FORWARD, not written here**, and that is
        -- the trap this record keeps setting: the record is replaced wholesale,
        -- so a section that is not named on this line is deleted by a paste
        -- that had nothing to say about it. `builds` learned that in 1.8.0 and
        -- `shop` re-learned it the same way in 1.15.0, with a test that saved a
        -- list and then pasted a gear-only string over it.
        builds = (db.gearset[guid] or {}).builds,
        shop = (db.gearset[guid] or {}).shop,
      }
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
end

--- Store the shopping list — the gems and enchants the solved set wants and
--- this character does not have.
---
--- Written separately from the setups for the reason every other section here
--- is: a string can carry one and not the other, and an absent section is
--- skipped rather than cleared. A player who pastes a gear-only string must not
--- silently lose the list of what to go and buy for it.
---
--- Kept on the gearset record rather than a fourth table, because the list is
--- *about* the set — it is what the set is missing — and one record means one
--- write.
function GearSet.SaveShop(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" or type(decoded.chars) ~= "table" then return 0 end
  db.gearset = db.gearset or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    if db.chars[guid] and entry.shop then
      local rec = db.gearset[guid]
      if not rec then
        rec = { generatedAt = decoded.generatedAt }
        db.gearset[guid] = rec
      end
      rec.shop = entry.shop
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
end

--- The stored shopping list for the character at the keyboard, or nil.
function GearSet.Shop()
  local rec = storedRecord()
  local list = rec and rec.shop
  return type(list) == "table" and #list > 0 and list or nil
end

--- Store the build assignments — which saved talent build is for raid, for m+,
--- for delves — per spec.
---
--- Written separately from the setups so each section survives the other being
--- absent: a `wbg1!` string from before 1.8.0 carries setups and no builds,
--- and must not erase assignments the player made on the site.
function GearSet.SaveBuilds(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" or type(decoded.chars) ~= "table" then return 0 end
  db.gearset = db.gearset or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    if db.chars[guid] and entry.builds then
      local rec = db.gearset[guid]
      if not rec then
        rec = { generatedAt = decoded.generatedAt }
        db.gearset[guid] = rec
      end
      rec.builds = entry.builds
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
end

--- Which saved talent build the player assigned to this kind of night, for the
--- spec at the keyboard. Returns the config id, or nil.
---
--- Spec-scoped for the reason the setups are: a config id belongs to a spec,
--- and answering with another spec's build would be worse than answering with
--- nothing.
function GearSet.BuildFor(content)
  local rec = storedRecord()
  local spec = activeSpecID()
  if not rec or not spec or type(rec.builds) ~= "table" then return nil end
  local forSpec = rec.builds[spec]
  if type(forSpec) ~= "table" then return nil end
  local id = forSpec[content]
  return type(id) == "number" and id or nil
end

--- The name of the saved build assigned to this kind of night, or nil.
---
--- Read out of `Gear`'s own capture rather than the wire: the addon already
--- holds every loadout's name and string, so only the *assignment* has to
--- cross. That is the whole reason `builds` is three numbers rather than three
--- talent strings — the site is telling the addon which of its own builds it
--- means, not handing it back something it exported an hour ago.
function GearSet.BuildName(content)
  local id = GearSet.BuildFor(content)
  if not id then return nil end
  local db = Store.db
  local guid = ns.safe(UnitGUID, "player")
  local spec = activeSpecID()
  if not db or not guid or not spec then return nil end
  local c = db.chars[guid]
  local specs = c and c.talents and c.talents.specs
  if type(specs) ~= "table" then return nil end
  for _, s in ipairs(specs) do
    if s.specID == spec and type(s.loadouts) == "table" then
      for _, l in ipairs(s.loadouts) do
        if l.id == id then return l.name, l.s end
      end
    end
  end
  return nil
end

local function itemString(link)
  if type(link) ~= "string" then return nil end
  return link:match("|H(item[^|]+)|h")
end

local function equippedString(slot)
  return itemString(ns.safe(GetInventoryItemLink, "player", slot))
end

--- Everything currently in the carried bags, indexed by item string. The bank
--- is deliberately not walked, same as Junk: an item there cannot be equipped
--- from here, and `w` on the wire is what lets a missing row say so.
local function scanCarried()
  local byString = {}
  for _, bag in ipairs(ns.Scan.CARRIED) do
    ns.Scan.Walk(bag, function(bagID, slot, info)
      local s = itemString(info.hyperlink)
      if s and not byString[s] then
        -- First match wins: two items with the same string are the same item
        -- in every respect the game exposes, so there is no copy to prefer.
        byString[s] = { bag = bagID, slot = slot }
      end
    end)
  end
  return byString
end

--- The stored set matched against the live paperdoll and bags.
---
--- Returns `already` (target slot holds the exact item), `ready` (found in a
--- carried bag, with live coordinates), `missing` (nowhere reachable, with
--- the wire's `w` for the "in your bank" line), plus `set` and `generatedAt`.
--- `content` is passed straight through to `Stored` — `/warband equip raid`
--- resolves the raid set and nothing else.
function GearSet.Resolve(content)
  local stored = GearSet.Stored(content)
  if not stored then return nil end
  local byString = scanCarried()
  local already, ready, missing = {}, {}, {}
  for _, it in ipairs(stored.items) do
    if equippedString(it.slot) == it.s then
      already[#already + 1] = it
    else
      local found = byString[it.s]
      if found then
        -- The wire's own fields ride along with the live coordinates: the
        -- Import tab's rows ask an item's icon by `id` before the client has
        -- its name, and a row is the same shape whichever bucket it is in.
        ready[#ready + 1] = {
          slot = it.slot, s = it.s, id = it.id, w = it.w, g = it.g, bag = found.bag, bagSlot = found.slot,
        }
      else
        missing[#missing + 1] = it
      end
    end
  end
  local set, icon, legacy = GearSet.SetName(stored)
  return {
    already = already,
    ready = ready,
    missing = missing,
    -- The name the CLIENT will save under, so the panel's header and the
    -- receipt name the set that will actually exist — not the wire's proposal.
    set = set,
    icon = icon,
    legacy = legacy,
    generatedAt = stored.generatedAt,
  }
end

-- ── the set, as a list a person reads ───────────────────────────────────────
--
-- The Import tab drew the stored set as one line of counts — `3 to equip ·
-- 1 already worn · 1 missing` — and a button, which is a receipt of what the
-- button would do and not a picture of the set. The maintainer's own walk
-- through AskMrRobot's addon (app#71) put the gap in one sentence: their
-- import shows the equipment set, slot by slot, with a mark on every slot
-- that is already worn. So does this now. Rows() is the model and UI.lua is
-- left with layout, the Roster.lua rule: everything that decides what a row
-- SAYS is here, pure, and tested in tools/gearset-test.lua.
--
-- This is still the addon rendering a fact and not a judgement (the app's
-- the-loop.md draws that line): which item the site chose is the site's
-- decision, already made; where that item is right now is something only
-- the client standing in the game can know, and it is the only thing a row
-- adds.

--- The inventory slot, as a player names it. Real slots only, the wire's own
--- range (1-17 minus the shirt); `ring 1`/`ring 2` rather than `finger`
--- because the Equipment Manager's own tooltip says ring.
GearSet.SLOT_NAMES = {
  [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist",
  [7] = "legs", [8] = "feet", [9] = "wrist", [10] = "hands",
  [11] = "ring 1", [12] = "ring 2", [13] = "trinket 1", [14] = "trinket 2",
  [15] = "back", [16] = "main hand", [17] = "off hand",
}

--- The resolve as rows, one per item on the wire, in slot order.
---
--- Each row carries the wire's identity (`s`, `id`, `slot`, `w`) and one of
--- three states, which are exactly Resolve's three buckets: `worn` (the slot
--- already holds it), `ready` (in a carried bag, so the button will equip it)
--- and `missing` (nowhere reachable). Slot order rather than state order,
--- because a set is read top to bottom like a paperdoll, and the state is
--- what the eye picks out — grouping by state would make `ring 2` land above
--- `head` for no reason a player can see.
function GearSet.Rows(r)
  local rows = {}
  local function add(list, state)
    for _, it in ipairs(list or {}) do
      rows[#rows + 1] = {
        slot = it.slot,
        name = GearSet.SLOT_NAMES[it.slot] or ("slot " .. tostring(it.slot)),
        s = it.s,
        id = it.id,
        w = it.w,
        g = it.g,
        state = state,
      }
    end
  end
  if r then
    add(r.already, "worn")
    add(r.ready, "ready")
    add(r.missing, "missing")
    table.sort(rows, function(a, b) return a.slot < b.slot end)
  end

  -- The shopping list rides the SAME rows the panel already draws, appended
  -- after the gear and deliberately outside the sort: these are not slots and
  -- have no slot number to sort by, and a list of things to buy belongs under
  -- the set it is for rather than interleaved with it.
  --
  -- Reusing the row model rather than growing a second one is the point. The
  -- panel's frame pool, its icon lookup and its tooltip all work unchanged,
  -- and everything deciding what a row SAYS stays here where it is tested —
  -- `docs/TESTING.md`'s "a display gets a model, and the model gets the tests".
  for _, e in ipairs(GearSet.Shop() or {}) do
    rows[#rows + 1] = {
      slot = nil,
      name = e.k == "enchant" and "enchant" or "gem",
      id = e.id,
      -- No `s`: a shopping row names something that is NOT in a bag, so there
      -- is no item string to match and nothing for a click to act on. Every
      -- action in this file keys on `s`, so its absence is what keeps a buy
      -- row inert rather than a check at each call site.
      s = nil,
      buy = e.n or 1,
      d = e.d,
      sl = e.sl,
      state = "buy",
    }
  end
  return rows
end

--- What the row's state says, and in what tone: `text, tone`, where tone is
--- one of `good`, `warn`, `muted` and the colours are UI.lua's to pick.
---
--- `worn` is muted because it asks nothing of the player — it is AMR's `E`,
--- the mark that says this slot is already right. `ready` is the good news
--- and the thing the button will act on. Missing splits on the wire's `w`:
--- an item the site last saw in a bank is a walk, an item it saw in a bag
--- that is no longer there has moved since the paste, and the two are
--- different errands.
function GearSet.StateText(row)
  if row.state == "worn" then return "worn", "muted" end
  if row.state == "ready" then return "in bags", "good" end
  if row.state == "buy" then
    -- How many, and what for. The count is the trip — four sockets wanting one
    -- gem is one stack of four — and the slots are why four, which is the
    -- difference between a shopping list and a number.
    local n = row.buy or 1
    local where = row.sl and #row.sl > 0 and (" for " .. table.concat(row.sl, ", ")) or ""
    return string.format("buy %d%s", n, where), "warn"
  end
  if row.w == "bank" or row.w == "warbank" then return "in your bank", "warn" end
  return "not in your bags", "warn"
end

--- The site's estimated gain for a row, as it prints — `+2.1% est.` — or ""
--- when the wire carried none. The number is the website's, made against
--- SimulationCraft's season tables, and the suffix is what says so; this
--- side formats it and never computes, ranks or acts on it. Tenths of a
--- percent on the wire so the JSON stays free of floats.
function GearSet.GainText(row)
  local g = row and row.g
  if type(g) ~= "number" then return "" end
  g = math.floor(g + 0.5)
  local sign = g < 0 and "-" or "+"
  local abs = math.abs(g)
  return string.format("%s%d.%d%% est.", sign, math.floor(abs / 10), abs % 10)
end

--- What equipping the ready rows is worth, summed, in tenths of a percent —
--- or nil when none of them carried a gain. Ready rows only: the worn ones
--- are already on, and a total that counted them would promise a gain the
--- player already has.
function GearSet.Gain(r)
  if not r then return nil end
  local total, any = 0, false
  for _, it in ipairs(r.ready or {}) do
    if type(it.g) == "number" then
      total = total + it.g
      any = true
    end
  end
  if not any then return nil end
  return math.floor(total + 0.5)
end

--- How short a set name is retried down to before giving up. Each step is one
--- create attempt, so the list is short on purpose.
local NAME_FALLBACKS = { 24, 16, 11 }

--- Find-or-create the named Equipment Manager set and snapshot the paperdoll
--- into it. Out-of-combat only; callers guard.
---
--- **The client's name-length limit is discovered, never assumed.**
--- `C_EquipmentSet` enforces a maximum this addon has no API to read, and
--- hardcoding a guess fails in the worst direction — `CreateEquipmentSet`
--- simply does nothing and the player gets equipped gear with no saved set
--- and no explanation. So the full name is tried first and shorter ones
--- after, and whichever the client actually accepts is the one used. A
--- create that works costs exactly one attempt. Spec names are short, so
--- since 1.11.0 the fallbacks are insurance rather than the common path;
--- they earned their place when the name was `warband.pro Restoration`.
---
--- **A set an older build saved is renamed, not left behind.** Until 1.11.0
--- the set was `warband.pro Protection`; a player updating would otherwise
--- end an evening with that set AND a `Protection` set holding the same kit,
--- and the Equipment Manager has room for ten. So before creating, the names
--- an older build used (`legacy`) are looked up and the first one found is
--- renamed to `name` with `icon` via ModifyEquipmentSet — one set, carried
--- forward. A set the player already has under the new name is theirs: it is
--- updated in place and its icon is left alone; the icon is set only on a set
--- this addon creates or migrates.
local function saveSet(name, icon, legacy)
  local es = C_EquipmentSet
  if not es then return false, nil end
  icon = icon or ns.ICON

  local function tryName(candidate)
    if not candidate or candidate == "" then return nil end
    local id = ns.safe(es.GetEquipmentSetID, candidate)
    if id then return id end
    ns.safe(es.CreateEquipmentSet, candidate, icon)
    return ns.safe(es.GetEquipmentSetID, candidate)
  end

  local id = ns.safe(es.GetEquipmentSetID, name)
  if not id then
    for _, old in ipairs(legacy or {}) do
      local oldID = ns.safe(es.GetEquipmentSetID, old)
      if oldID then
        ns.safe(es.ModifyEquipmentSet, oldID, name, icon)
        -- Only if the client took the new name. A rename it refused leaves
        -- the old set as it was and the create path below takes over.
        id = ns.safe(es.GetEquipmentSetID, name)
        break
      end
    end
  end
  if not id then id = tryName(name) end
  if not id then
    for _, len in ipairs(NAME_FALLBACKS) do
      if #name > len then
        id = tryName(name:sub(1, len))
        if id then
          name = name:sub(1, len)
          break
        end
      end
    end
  end
  if not id then return false, nil end
  ns.safe(es.SaveEquipmentSet, id)
  return true, name
end

GearSet.pending = nil

--- The receipt, printed once per apply, from counts the apply itself took.
local function receipt(p, verified)
  local parts = {}
  if verified > 0 then parts[#parts + 1] = "equipped " .. verified end
  if p.alreadyCount > 0 then parts[#parts + 1] = p.alreadyCount .. " already worn" end
  if p.missingCount > 0 then
    local line = p.missingCount .. " missing"
    if p.bankCount > 0 then line = line .. " (" .. p.bankCount .. " in your bank)" end
    parts[#parts + 1] = line
  end
  local unconfirmed = p.readyCount - verified
  if unconfirmed > 0 then parts[#parts + 1] = unconfirmed .. " did not equip" end
  -- The talent half, named where it happened. Silent when no build was
  -- assigned to this night, which is the common case and not worth a line.
  if type(p.build) == "string" then
    parts[#parts + 1] = "build \"" .. p.build .. "\""
  elseif p.build then
    parts[#parts + 1] = "build loaded"
  end
  if p.saved then parts[#parts + 1] = "saved as \"" .. p.set .. "\"" end
  ns.print(table.concat(parts, " · "))
  -- The site cannot see an equip until the next export lands; nothing told
  -- the player that, so the character page went on proposing the kit they
  -- were already wearing. One line, only when something actually moved.
  if verified > 0 then
    ns.print("|cffffd100/warband|r and paste on warband.pro so it sees the new kit")
  end
end

--- Re-check every equip the apply started; save the set once all confirm or
--- the deadline passes. Runs from PLAYER_EQUIPMENT_CHANGED (throttled, in
--- Core.lua) and once from the deadline timer, never from a poll.
function GearSet.Verify(fromDeadline)
  local p = GearSet.pending
  if not p then return end
  if InCombatLockdown() then
    GearSet.pending = nil
    ns.print("combat — press equip again after the fight")
    return
  end
  local verified = 0
  for _, it in ipairs(p.items) do
    if equippedString(it.slot) == it.s then verified = verified + 1 end
  end
  if verified < p.readyCount and not fromDeadline then return end
  GearSet.pending = nil
  -- The name the client accepted, which may be shorter than the one asked
  -- for — the receipt must say what is actually in the Equipment Manager.
  local saved, savedName = saveSet(p.set, p.icon, p.legacy)
  p.saved = saved
  if savedName then p.set = savedName end
  receipt(p, verified)
  if ns.UI and ns.UI.RenderGearSet then ns.UI.RenderGearSet() end
end

--- Load the talent build assigned to this kind of night, if there is one.
---
--- The other half of a setup. `setups.ts` on the website binds a gear set and a
--- talent build to the same content precisely because a raid kit without the
--- raid build is half an answer, and the player then does the other half by
--- hand — which is the click AskMrRobot's addon saved them and this one did
--- not.
---
--- Returns the build's name on success, nil on anything else. Nil covers a
--- content with no assignment, a config this character no longer has, a client
--- without the API, and combat — and the caller reports "equipped" either way,
--- because the gear half genuinely happened and a failure here is a talent
--- build that stayed where it was, not a half-applied one.
---
--- **Never in combat, and never a queue.** The same rule every other action in
--- this file follows: `LoadConfig` is refused in combat by the client anyway,
--- and deferring it would apply a build minutes later in a fight the player has
--- long since finished.
---
--- **The spec itself is not switched**, deliberately. Changing specialization
--- is a cast with its own protections, and this addon has not measured what an
--- addon may and may not do there; a setup is applied to the spec you are
--- standing in. `Stored` already refuses to hand over another spec's kit, so
--- the worst case is that nothing happens and the panel says which spec the
--- setup was for.
function GearSet.ApplyBuild(content)
  if not content or InCombatLockdown() then return nil end
  local id = GearSet.BuildFor(content)
  if not id then return nil end
  local ct = C_ClassTalents
  if not ct or type(ct.LoadConfig) ~= "function" then return nil end

  local name = GearSet.BuildName(content)
  -- `true` is autoApply: commit the build rather than only staging it in the
  -- talent UI, which is what a player pressing an equip button means.
  local ok = ns.safe(ct.LoadConfig, id, true)
  if ok == false or ok == nil then return nil end
  -- The client remembers which saved build is "current" for the spec; without
  -- this the talent UI keeps showing the previous one as selected.
  if type(ct.UpdateLastSelectedSavedConfigID) == "function" then
    local spec = activeSpecID()
    if spec then ns.safe(ct.UpdateLastSelectedSavedConfigID, spec, id) end
  end
  return name or true
end

--- Equip every ready item and arm the verify-then-save. Returns the resolve
--- it acted on, or nil when there was nothing to act on at all.
function GearSet.Apply(content)
  if InCombatLockdown() then return nil end
  local r = GearSet.Resolve(content)
  if not r then return nil end

  -- The talent half, before the equips: a build load is one call that either
  -- works or does not, where the equips are a string of server round-trips
  -- this function then has to wait on. Doing it first means the receipt can
  -- name it, and means a build that fails does not leave the gear unapplied.
  r.build = GearSet.ApplyBuild(content)

  local bankCount = 0
  for _, it in ipairs(r.missing) do
    if it.w == "bank" or it.w == "warbank" then bankCount = bankCount + 1 end
  end

  for _, it in ipairs(r.ready) do
    -- Coordinate from the walk Resolve just made; EquipCursorItem places the
    -- item in the wire's chosen slot, ring twins included.
    ns.safe(C.PickupContainerItem, it.bag, it.bagSlot)
    ns.safe(EquipCursorItem, it.slot)
    ns.safe(ClearCursor)
  end

  GearSet.pending = {
    set = r.set,
    icon = r.icon,
    legacy = r.legacy,
    items = r.ready,
    readyCount = #r.ready,
    alreadyCount = #r.already,
    missingCount = #r.missing,
    bankCount = bankCount,
    -- What ApplyBuild did, so the receipt can name it. `true` means a build
    -- loaded whose name this character could not look up, which is a real
    -- state — the assignment names a config id and the name comes from the
    -- addon's own capture, which a fresh character may not have yet.
    build = r.build,
  }
  if #r.ready == 0 then
    -- Nothing to wait for: everything wearable is worn (or missing). Save
    -- and report now — the paperdoll is already its final shape.
    GearSet.Verify(true)
  else
    ns.safe(C_Timer.After, DEADLINE_SEC, function() GearSet.Verify(true) end)
  end
  return r
end

--- Search the auction house for what a shopping row names.
---
--- **Returns false for every reason it did not, and there are several**: the
--- window is shut, the client has no browse API, the row names something whose
--- name this session has never cached. The caller says so rather than leaving a
--- click that looks broken.
---
--- `SendBrowseQuery` is wrapped like every other client call here. This addon
--- has not measured what that API does across every retail build, and the
--- doctrine covers exactly that case: a section that cannot be read goes
--- missing rather than throwing, and a search that does not happen costs one
--- click.
function GearSet.SearchAuction(row)
  if not GearSet.ahOpen or type(row) ~= "table" or row.state ~= "buy" then return false end
  local ah = C_AuctionHouse
  if not ah or type(ah.SendBrowseQuery) ~= "function" then return false end

  -- The NAME, not the id: the auction house browses by text, and an id means
  -- nothing in that box. An item this session has not cached has no name yet,
  -- and searching for the wrong thing is worse than not searching.
  local name = row.id and ns.safe(function() return (C_Item.GetItemInfo(row.id)) end)
  if type(name) ~= "string" or name == "" then return false end

  local ok = ns.safe(ah.SendBrowseQuery, {
    searchString = name,
    sorts = {},
    filters = {},
    itemClassFilters = {},
    minLevel = 0,
    maxLevel = 0,
  })
  return ok ~= nil
end
