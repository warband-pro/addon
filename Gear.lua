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

-- The collapse above is lossy in one way that matters: INVTYPE_2HWEAPON and
-- INVTYPE_WEAPON both become 16, so a consumer reading `slot` alone cannot
-- tell a two-hander from a one-hander and will happily call a 2H an upgrade
-- over a main hand while the shield beside it goes quietly to the bags. This
-- addon knows the answer — it is holding equipLoc when it throws it away —
-- so `th` carries it, and nothing here interprets it beyond the one fact.
--
-- Only INVTYPE_2HWEAPON is claimed. INVTYPE_RANGED and INVTYPE_RANGEDRIGHT
-- cover bows and guns (two-handed) but also wands (not), and no spec that
-- equips any of the three carries an off-hand anyway, so the distinction is
-- unreachable in practice and is not worth a wrong claim. Wrong-direction:
-- an equip location missing from this table reports `false` and costs the
-- consumer a warning it would have shown — quiet and safe — where a wrongly
-- added one warns about a swap that loses nothing.
local TWO_HANDED = { INVTYPE_2HWEAPON = true }

-- The slots where `th` is worth sending at all. Sent as a real boolean on
-- both, never omitted-when-false: `b` is emitted only when true and the
-- website needs a second field to date the bundle before it can read that
-- absence as "not bound". A field that is always present on the entries it
-- describes dates itself — absent means this addon predates it, which is the
-- reading a consumer needs and the one `b` cannot give.
local WEAPON_SLOTS = { [16] = true, [17] = true }

-- Everything between |H and |h — the same substring SimC's own addon exports.
local function itemString(link)
  if type(link) ~= "string" then return nil end
  return link:match("|H(item[^|]+)|h")
end

-- The display name inside the same hyperlink's brackets. The website has no
-- item-id-to-name lookup at all, so a bag item without this renders as a bare
-- id in the cleanup list — the whole reason 1.3.0 exists.
local function itemName(link)
  if type(link) ~= "string" then return nil end
  local name = link:match("|h%[(.-)%]|h")
  if name == "" then return nil end
  return name
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
  -- The 1.3.0 fields, owned-gear entries only (equipped items never carry
  -- them — the website resolves an equipped item through the Profile API and
  -- these would be dead weight). All optional on the wire; a nil is dropped
  -- by the canonical encoder rather than sent, and the website reads absence
  -- as "this addon did not send it", never as a value:
  --   n    display name, for a list with no item-id-to-name lookup
  --   q    numeric quality, so greys and heirlooms can be told apart
  --   b    soulbound, emitted only when true — absence means NOT bound,
  --        which is the reading the website's BoE guard depends on
  --   cls  item class id  (2 weapon, 4 armor)
  --   sub  item subclass id, verbatim — for armor 1 cloth … 4 plate, but
  --        ONLY on the eight slots that have an armor weight. A cloak
  --        reports 1 as well and every class wears one, so a consumer
  --        testing sub against a class proficiency has to check the slot
  --        first. See docs/CONTRACT.md; this is sent, never interpreted.
  --   th   two-handed, on weapon-slot entries only (16/17). A real boolean
  --        on every such entry rather than emitted-only-when-true, so its
  --        absence dates the bundle instead of needing a second field to do
  --        it the way `b` does. See TWO_HANDED above for what is claimed.
  --   st   the item's stat values, C_Item.GetItemStats tokens verbatim
  --        (ITEM_MOD_* → number), same posture as sub: sent, never
  --        interpreted, never compacted — a token this addon has not heard
  --        of still reaches the wire, and the website ignores what it does
  --        not know. Omitted when the client could not answer (an uncached
  --        item on a cold login), which absence means — never "no stats".
  local entry = {
    slot = canonicalSlot,
    where = where,
    id = info.itemID,
    ilvl = containerItemLevel(bagID, slot),
    s = s,
    n = itemName(info.hyperlink),
    q = info.quality,
    cls = itemInfo.classID,
    sub = itemInfo.subclassID,
  }
  if info.isBound then entry.b = true end
  if WEAPON_SLOTS[canonicalSlot] then entry.th = TWO_HANDED[itemInfo.equipLoc or ""] == true end
  local stats = ns.safe(C_Item.GetItemStats, info.hyperlink)
  if type(stats) == "table" then
    -- Copy only string-token → number pairs: verbatim on the wire, but the
    -- canonical encoder is owed clean types, and a stat value is a number or
    -- it is not a stat.
    local st
    for k, v in pairs(stats) do
      if type(k) == "string" and type(v) == "number" then
        st = st or {}
        st[k] = v
      end
    end
    entry.st = st
  end
  out[#out + 1] = entry
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

--- Every saved loadout this spec has, merged into what is already stored.
---
--- **Two mechanisms, and the second is the one that makes this reliable.**
---
--- 1. *Enumeration.* `C_ClassTalents.GetConfigIDsBySpecID` lists the player's
---    saved loadouts and `C_Traits.GenerateImportString` is asked for each.
---    When that works, all three of somebody's raid/M+/delve builds arrive in
---    one pass and warband.pro has them the first time they paste.
--- 2. *Accumulation.* The loadout the player is actually ON is recorded every
---    time, name included. This is the guarantee: it uses only the call this
---    file has always made successfully, so even if `GenerateImportString`
---    turns out to refuse an inactive config, the list still fills in as the
---    player switches builds — the same snapshot-accumulates model that fills
---    `specs` across a spec switch.
---
--- The uncertainty is real and unmeasured — nothing in this container runs the
--- client — so the design does not depend on resolving it. Enumeration is an
--- accelerator; accumulation is the floor. If (1) never returns anything, this
--- is strictly better than what came before and nothing regresses.
---
--- A read that fails leaves the stored value alone rather than clearing it,
--- which is Store.Put's rule and matters more here than anywhere: a player who
--- logs in, gets a failed read, and pastes must not lose the three loadouts
--- they captured last week.
---
--- **Accumulation is why a deleted build has to be actively removed.** Nothing
--- else in this file ever needs to: a spec the player abandons is still a spec
--- they have, so `specs` only ever grows honestly. A loadout is the opposite —
--- the player deletes it in the talent UI and it is gone, and a list that only
--- merges keeps offering it to warband.pro forever. That is what a player sees
--- as builds in the website's dropdown that the game does not show them.
---
--- The removal rides on enumeration and nothing else, because enumeration is
--- the only read that can distinguish "deleted" from "not observed yet".
--- Accumulation cannot: it says which build is on, never which builds are all
--- of them. So a pass with no enumeration prunes nothing and behaves exactly
--- as it did before. An **empty** enumeration prunes nothing either — the
--- player always has an active config, so an empty list is far likelier to be
--- a not-yet-loaded read than a genuinely empty shelf, and pruning on it would
--- wipe the accumulated list at the one moment the evidence is weakest.
local function captureLoadouts(found, specID, activeConfigID, activeName, activeString)
  local ct, tr = C_ClassTalents, C_Traits
  found.loadouts = found.loadouts or {}
  local list = found.loadouts

  --- Merge one (id, name, string) into `list`, newest wins, never with a nil.
  local function put(id, name, str)
    if type(id) ~= "number" then return end
    if not name and not str then return end
    for i = 1, #list do
      if list[i].id == id then
        if name then list[i].name = name end
        if str then list[i].s = str end
        list[i].seenAt = ns.now()
        return
      end
    end
    if #list >= ns.MAX_LOADOUTS then return end
    list[#list + 1] = { id = id, name = name, s = str, seenAt = ns.now() }
  end

  -- (1) Everything the client will name and serialize for us.
  local ids
  if ct and tr then ids = ns.safe(ct.GetConfigIDsBySpecID, specID) end
  local enumerated = type(ids) == "table" and #ids > 0

  -- (2) Builds the player has deleted, dropped before anything is added — a
  -- list already at MAX_LOADOUTS must have room for what is still real, or the
  -- cap would hold stale entries in place against their replacements.
  if enumerated then
    local live = {}
    for _, id in ipairs(ids) do live[id] = true end
    -- The active config need not be a saved loadout, so it is never pruned.
    if type(activeConfigID) == "number" then live[activeConfigID] = true end
    for i = #list, 1, -1 do
      if not live[list[i].id] then table.remove(list, i) end
    end
  end

  if enumerated then
    for _, id in ipairs(ids) do
      local info = ns.safe(tr.GetConfigInfo, id)
      local name = type(info) == "table" and type(info.name) == "string" and info.name ~= "" and info.name or nil
      -- Asked per config rather than once: this is the call that may refuse
      -- an inactive loadout, and one refusal must not lose the others.
      local str = ns.safe(function() return (tr.GenerateImportString(id)) end)
      put(id, name, str)
    end
  end

  -- (3) The one the player is on, which is the read that has always worked.
  put(activeConfigID, activeName, activeString)
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
  -- `loadout` above stays exactly as it was — it is what the website's
  -- resolveTalents reads, and this must not move underneath it. `loadouts` is
  -- additive beside it.
  local activeName = ns.safe(function()
    local cfg = C_Traits and C_Traits.GetConfigInfo(configID)
    return type(cfg) == "table" and cfg.name or nil
  end)
  captureLoadouts(found, info.id, configID, activeName, loadout)
  found.seenAt = ns.now()

  local now = ns.now()
  c.seenAt.talents, c.seenAt.lastSeen = now, now
end
