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

--- The stored gear set for the character at the keyboard, or nil.
function GearSet.Stored()
  local db = Store.db
  if not db or not db.gearset then return nil end
  local guid = ns.safe(UnitGUID, "player")
  if not guid then return nil end
  return db.gearset[guid]
end

--- Store a decoded equip payload. Junk.Save's rule verbatim: only guids this
--- account has scanned are kept — the rest of the string belongs to
--- characters that will read it when they log in.
function GearSet.Save(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" then return 0 end
  db.gearset = db.gearset or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    if db.chars[guid] then
      db.gearset[guid] = {
        generatedAt = decoded.generatedAt,
        spec = entry.spec,
        set = entry.set,
        items = entry.items,
      }
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
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

--- Find-or-create the named Equipment Manager set and snapshot the paperdoll
--- into it. Out-of-combat only; callers guard.
local function saveSet(name)
  local es = C_EquipmentSet
  if not es then return false end
  local id = ns.safe(es.GetEquipmentSetID, name)
  if not id then
    ns.safe(es.CreateEquipmentSet, name, ns.ICON)
    id = ns.safe(es.GetEquipmentSetID, name)
  end
  if not id then return false end
  ns.safe(es.SaveEquipmentSet, id)
  return true
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
  p.saved = saveSet(p.set)
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
