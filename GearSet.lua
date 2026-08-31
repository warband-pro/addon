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

--- The whole stored record for the character at the keyboard, or nil.
local function storedRecord()
  local db = Store.db
  if not db or not db.gearset then return nil end
  local guid = ns.safe(UnitGUID, "player")
  if not guid then return nil end
  return db.gearset[guid]
end

--- The spec this character is playing right now, or nil.
local function activeSpecID()
  local index = ns.safe(GetSpecialization)
  if not index then return nil end
  return ns.safe(function()
    local id = GetSpecializationInfo(index)
    return id
  end)
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
function GearSet.Stored()
  local rec = storedRecord()
  if not rec then return nil end
  if rec.bySpec then
    local spec = activeSpecID()
    local mine = spec and rec.bySpec[spec]
    if mine then
      return {
        generatedAt = rec.generatedAt,
        spec = mine.spec,
        set = mine.set,
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
        -- Carried on the same record rather than a fourth top-level table:
        -- a build assignment is about which setup to wear on which night, so
        -- it belongs beside the setups, and one record means one write.
        builds = (db.gearset[guid] or {}).builds,
      }
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
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
function GearSet.Resolve()
  local stored = GearSet.Stored()
  if not stored then return nil end
  local byString = scanCarried()
  local already, ready, missing = {}, {}, {}
  for _, it in ipairs(stored.items) do
    if equippedString(it.slot) == it.s then
      already[#already + 1] = it
    else
      local found = byString[it.s]
      if found then
        ready[#ready + 1] = { slot = it.slot, s = it.s, bag = found.bag, bagSlot = found.slot }
      else
        missing[#missing + 1] = it
      end
    end
  end
  return {
    already = already,
    ready = ready,
    missing = missing,
    set = stored.set or "warband.pro",
    generatedAt = stored.generatedAt,
  }
end

--- How short a set name is retried down to before giving up. Each step is one
--- create attempt, so the list is short on purpose.
local NAME_FALLBACKS = { 24, 16, 11 }

--- Find-or-create the named Equipment Manager set and snapshot the paperdoll
--- into it. Out-of-combat only; callers guard.
---
--- **The client's name-length limit is discovered, never assumed.** Set names
--- gained a spec suffix in 1.8.0 (`warband.pro Restoration`), which is longer
--- than anything this ever asked for before, and `C_EquipmentSet` enforces a
--- maximum this addon has no API to read. Hardcoding a guess fails in the
--- worst direction — `CreateEquipmentSet` simply does nothing and the player
--- gets equipped gear with no saved set and no explanation. So the full name
--- is tried first and shorter ones after, and whichever the client actually
--- accepts is the one used. A create that works costs exactly one attempt.
---
--- Truncation drops the spec before the brand: two specs colliding on one
--- truncated name means a player watching one set update twice, where losing
--- `warband.pro` leaves a set they cannot identify among their own.
local function saveSet(name)
  local es = C_EquipmentSet
  if not es then return false, nil end

  local function tryName(candidate)
    if not candidate or candidate == "" then return nil end
    local id = ns.safe(es.GetEquipmentSetID, candidate)
    if id then return id end
    ns.safe(es.CreateEquipmentSet, candidate, ns.ICON)
    return ns.safe(es.GetEquipmentSetID, candidate)
  end

  local id = tryName(name)
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
  if p.saved then parts[#parts + 1] = "saved as \"" .. p.set .. "\"" end
  ns.print(table.concat(parts, " · "))
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
  local saved, savedName = saveSet(p.set)
  p.saved = saved
  if savedName then p.set = savedName end
  receipt(p, verified)
  if ns.UI and ns.UI.RenderGearSet then ns.UI.RenderGearSet() end
end

--- Equip every ready item and arm the verify-then-save. Returns the resolve
--- it acted on, or nil when there was nothing to act on at all.
function GearSet.Apply()
  if InCombatLockdown() then return nil end
  local r = GearSet.Resolve()
  if not r then return nil end

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
    items = r.ready,
    readyCount = #r.ready,
    alreadyCount = #r.already,
    missingCount = #r.missing,
    bankCount = bankCount,
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
