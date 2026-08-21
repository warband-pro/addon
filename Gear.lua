-- WarbandPro / Gear.lua
-- Equipped items, bag/bank items that could be equipped, and the active spec's
-- talent loadout. Reads the current character only, same rules as Scan.lua:
-- every WoW API call goes through ns.safe, and a section that cannot be read
-- goes missing rather than throwing.
--
-- Gear rides the item string, not a decomposed model: everything between |H
-- and |h in the hyperlink carries bonus IDs, enchant, gems, crafted-stat
-- modifiers and drop level positionally and losslessly, and it is exactly what
-- SimulationCraft's own addon puts on the wire. Decomposing it here would
-- couple this repo to the website's item model and to SimC semantics;
-- docs/CONTRACT.md documents the positional shape for whoever parses it there.

local _, ns = ...

local Gear = {}
ns.Gear = Gear

local Store = ns.Store
local C = C_Container or {}
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Equipped slots worth sending. 4 (shirt) and 19 (tabard) are cosmetic and
-- excluded everywhere gear appears, matching the website's SLOTS table.
local EQUIPPED_SLOTS = {}
for slot = 1, 19 do
  if slot ~= 4 and slot ~= 19 then EQUIPPED_SLOTS[#EQUIPPED_SLOTS + 1] = slot end
end

-- Bag and bank items carry a generic equip location, not a specific slot — two
-- rings and two trinkets look identical from here. Collapse each family to the
-- slot the item would land in if equipped, so a bag ring and an equipped ring
-- are directly comparable on the website without it knowing the pairing rules.
-- Anything not listed (bags, shirt, tabard, quivers, non-gear entirely) is not
-- gear and is dropped.
local EQUIPLOC_SLOT = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
  INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
  INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15,
  INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
  INVTYPE_RANGED = 16, INVTYPE_RANGEDRIGHT = 16, INVTYPE_THROWN = 16,
  INVTYPE_SHIELD = 17, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17,
}

-- Everything between |H and |h — the same substring SimC's own addon exports.
local function itemString(link)
  if type(link) ~= "string" then return nil end
  return link:match("|H(item[^|]+)|h")
end

local function equippedItemLevel(slot)
  return ns.safe(function()
    return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot))
  end)
end

local function containerItemLevel(bagID, slot)
  return ns.safe(function()
    return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bagID, slot))
  end)
end

function Gear.Equipped()
  local out = {}
  for _, slot in ipairs(EQUIPPED_SLOTS) do
    local link = ns.safe(GetInventoryItemLink, "player", slot)
    local s = itemString(link)
    if s then
      out[#out + 1] = {
        slot = slot,
        where = "equipped",
        id = ns.safe(GetInventoryItemID, "player", slot),
        ilvl = equippedItemLevel(slot),
        s = s,
      }
    end
  end
  return out
end

-- The equip location a stack of items in a bag or bank slot would use if worn.
-- nil for anything that is not gear at all — reagents, consumables, quest items.
local function equipLoc(itemID)
  return ns.safe(function()
    local _, _, _, _, loc = GetInstant(itemID)
    return loc
  end)
end

local function scanForGear(ids, where, out)
  for i = 1, #ids do
    local bagID = ids[i]
    local size = ns.safe(C.GetContainerNumSlots, bagID) or 0
    for slot = 1, size do
      local info = ns.safe(C.GetContainerItemInfo, bagID, slot)
      if info and info.itemID then
        local canonicalSlot = EQUIPLOC_SLOT[equipLoc(info.itemID) or ""]
        if canonicalSlot then
          local s = itemString(info.hyperlink)
          if s then
            out[#out + 1] = {
              slot = canonicalSlot,
              where = where,
              id = info.itemID,
              ilvl = containerItemLevel(bagID, slot),
              s = s,
            }
          end
        end
      end
    end
  end
end

-- The reagent bank never holds gear, so it is the one container Scan.lua walks
-- that this does not.
function Gear.Containers()
  local out = {}
  scanForGear(ns.Scan.CARRIED, "bag", out)
  scanForGear(ns.Scan.BANK, "bank", out)
  scanForGear(ns.Scan.WarbandTabs(), "warbank", out)
  return out
end

-- opts.includeGear is the release valve if a 20-character bundle gets
-- uncomfortable — /warband gear off, which includeLinks never got.
function Gear.All()
  if Store.db and Store.db.opts and Store.db.opts.includeGear == false then return end
  local out = Gear.Equipped()
  local bags = Gear.Containers()
  for i = 1, #bags do out[#out + 1] = bags[i] end
  if #out == 0 then return end
  Store.Put("gear", "gear", out)
end

-- Only the active spec's loadout is readable at any moment, so entries
-- accumulate across a spec switch rather than replacing the list — the same
-- snapshot-accumulates model every other section here already uses.
function Gear.Talents()
  local ct = C_ClassTalents
  if not ct then return end
  local configID = ns.safe(ct.GetActiveConfigID)
  if not configID then return end

  local specIndex = ns.safe(GetSpecialization)
  if not specIndex then return end
  local info = ns.safe(function()
    local id, name, _, _, role = GetSpecializationInfo(specIndex)
    return { id = id, name = name, role = role }
  end)
  if not info or not info.id then return end

  local loadout = ns.safe(function() return (C_Traits.GenerateImportString(configID)) end)
  local heroSpecID = ns.safe(ct.GetActiveHeroTalentSpec)

  local c = Store.Char()
  if not c then return end
  c.talents = c.talents or { specs = {} }
  c.talents.activeSpecID = info.id

  local specs = c.talents.specs
  local found
  for i = 1, #specs do
    if specs[i].specID == info.id then
      found = specs[i]
      break
    end
  end
  if not found then
    found = { specID = info.id }
    specs[#specs + 1] = found
  end
  found.name = info.name
  found.role = info.role
  -- Never overwrite a known value with a failed read — see the Store.Put
  -- comment in Store.lua for why nil means "leave it alone", not "clear it".
  if heroSpecID then found.heroSpecID = heroSpecID end
  if loadout then found.loadout = loadout end
  found.seenAt = ns.now()

  local now = ns.now()
  c.seenAt.talents, c.seenAt.lastSeen = now, now
end
