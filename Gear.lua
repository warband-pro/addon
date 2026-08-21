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

-- Stable top-level functions rather than a closure built per item: these ran
-- once per equipped slot and once per occupied bag/bank/warbank slot, and a
-- fresh closure for each call was pure allocation for something ns.safe's
-- existing (fn, a, b) arity already covers.
local function getEquippedItemLevel(slot)
  return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot))
end
local function equippedItemLevel(slot)
  return ns.safe(getEquippedItemLevel, slot)
end

local function getContainerItemLevel(bagID, slot)
  return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bagID, slot))
end
local function containerItemLevel(bagID, slot)
  return ns.safe(getContainerItemLevel, bagID, slot)
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

-- Called from inside Scan.lua's container walk (Scan.Walk / combinedVisitor)
-- for every occupied slot, so a bag/bank/warband-tab item is classified as
-- gear during the pass Scan.lua already makes rather than a second walk of
-- the same containers. `where` is nil for the reagent bank, which never
-- holds gear — ns.itemInfo's equipLoc simply will not match anything there,
-- but Scan.lua skips the call entirely (gearEligible = false) to save the
-- lookup.
function Gear.Visit(where, bagID, slot, info, out)
  local itemInfo = ns.itemInfo(info.itemID)
  local canonicalSlot = itemInfo and EQUIPLOC_SLOT[itemInfo.equipLoc or ""]
  if not canonicalSlot then return end
  local s = itemString(info.hyperlink)
  if not s then return end
  out[#out + 1] = {
    slot = canonicalSlot,
    where = where,
    id = info.itemID,
    ilvl = containerItemLevel(bagID, slot),
    s = s,
  }
end

-- The gear list held in four scopes rather than rebuilt wholesale on every
-- scan: Gear.All() used to walk carried bags + bank bags + every warband tab
-- on a plain bag move, because it had no way to know only the bag scope had
-- changed. Each scope now updates only when Scan.lua actually rescans it, and
-- a scope that was not touched this session keeps whatever Gear.Seed loaded
-- from storage instead of going blank.
Gear.parts = { equipped = {}, bag = {}, bank = {}, warbank = {} }
local SCOPE_ORDER = { "equipped", "bag", "bank", "warbank" }

-- Rebuilds Gear.parts from the character's last stored c.gear, before any
-- scan runs this session. Without this, the first bag move after login would
-- commit a gear list missing whatever bank/warbank gear was captured last
-- time, since neither has been rescanned yet this session.
function Gear.Seed()
  Gear.parts = { equipped = {}, bag = {}, bank = {}, warbank = {} }
  local c = Store.Char()
  if not c or not c.gear then return end
  for i = 1, #c.gear do
    local row = c.gear[i]
    local part = Gear.parts[row.where]
    if part then part[#part + 1] = row end
  end
end

function Gear.Commit()
  if Store.db and Store.db.opts and Store.db.opts.includeGear == false then return end
  local out = {}
  for _, scope in ipairs(SCOPE_ORDER) do
    local part = Gear.parts[scope]
    for i = 1, #part do out[#out + 1] = part[i] end
  end
  if #out == 0 then return end
  Store.Put("gear", "gear", out)
end

-- Replaces one scope's rows with a freshly walked result and commits. `rows`
-- is only ever what Scan.lua just found for that scope — a scope Scan.lua
-- has not rescanned this session is never passed here, so it is never
-- cleared. A no-op while gear capture is off: Scan.lua's walk already skips
-- building rows in that case, but this also stops the empty result from
-- overwriting Gear.parts, so turning capture back on has real data to commit
-- instead of the equipped scope alone.
function Gear.SetScope(where, rows)
  if Store.db and Store.db.opts and Store.db.opts.includeGear == false then return end
  Gear.parts[where] = rows
  Gear.Commit()
end

-- opts.includeGear is the release valve if a 20-character bundle gets
-- uncomfortable — /warband gear off, which includeLinks never got. Bag,
-- bank and warband-tab scopes come from Scan.lua's own walks (Gear.SetScope);
-- this handles the one scope Scan.lua does not touch — equipped items — and
-- commits, so a bare login or /warband copy with no prior activity this
-- session still has something to show.
function Gear.All()
  if Store.db and Store.db.opts and Store.db.opts.includeGear == false then return end
  Gear.parts.equipped = Gear.Equipped()
  Gear.Commit()
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
