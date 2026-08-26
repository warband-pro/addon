#!/usr/bin/env lua5.1
-- Gear classification against a fake client — run `lua5.1 tools/gear-test.lua`,
-- 0 failures. CI runs it in the luacheck job, which already has lua5.1.
--
-- This exists because of the off-by-one nothing else could see: ns.itemInfo
-- destructured GetItemInfoInstant's icon (position 5) where it meant
-- itemEquipLoc (position 4), EQUIPLOC_SLOT is keyed by INVTYPE_* strings, so
-- every bag, bank and warband-tab item missed the lookup and Gear.Visit
-- dropped every one — for two minor versions, silently, because an empty gear
-- scope and an empty bag look identical on the wire.
--
-- The fixture is built to make that failure LOUD rather than empty: every fake
-- item carries a *valid* INVTYPE_* string in the icon position, one that maps
-- to a different slot than the real equipLoc. Re-introduce the off-by-one and
-- items sort into the wrong slot, which fails an equality assertion, instead
-- of vanishing and passing a count of zero off as a quiet bag.

-- ── fake client ─────────────────────────────────────────────────────────────

-- id → { itemType, itemSubType, equipLoc, icon, classID, subclassID }.
-- The icon column is the trap: a valid INVTYPE_* string that resolves to a
-- different slot than the equipLoc beside it.
local ITEMS = {
  -- gear
  [101] = { "Armor", "Cloth", "INVTYPE_HEAD", "INVTYPE_FEET", 4, 1 },
  [102] = { "Armor", "Plate", "INVTYPE_ROBE", "INVTYPE_HEAD", 4, 4 },
  [103] = { "Armor", "Miscellaneous", "INVTYPE_FINGER", "INVTYPE_TRINKET", 4, 0 },
  [104] = { "Armor", "Miscellaneous", "INVTYPE_TRINKET", "INVTYPE_FINGER", 4, 0 },
  [105] = { "Armor", "Shields", "INVTYPE_SHIELD", "INVTYPE_WEAPON", 4, 6 },
  [106] = { "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", "INVTYPE_HOLDABLE", 2, 1 },
  [107] = { "Armor", "Leather", "INVTYPE_CLOAK", "INVTYPE_CHEST", 4, 2 },
  -- not gear: a consumable (no equip location)
  [201] = { "Consumable", "Potion", "", "INVTYPE_HEAD", 0, 1 },
  -- gear-shaped but with a nil equipLoc, as a broken client might answer
  [202] = { "Armor", "Cloth", nil, "INVTYPE_HEAD", 4, 1 },
}

local EQUIPPED_LEVELS = { [1] = 639, [16] = 645 }
local CONTAINER_LEVELS = { ["0:1"] = 626, ["0:2"] = 580, ["-1:1"] = 619 }

-- id → GetItemStats answer. 101 has stats; 102 answers an empty table (a
-- stat-less read must omit the field, not send {}); 105 answers junk-typed
-- pairs beside a real one (only the real one survives); everything else is
-- nil, the uncached-item case on a cold login.
local STATS = {
  [101] = { ITEM_MOD_INTELLECT_SHORT = 1204, ITEM_MOD_CRIT_RATING_SHORT = 581, ITEM_MOD_STAMINA_SHORT = 2100 },
  [102] = {},
  [105] = { ITEM_MOD_STAMINA_SHORT = 1800, [7] = 99, ITEM_MOD_BROKEN = "yes" },
}

_G.C_Item = {
  GetItemInfoInstant = function(id)
    local t = ITEMS[id]
    if not t then return nil end
    return id, t[1], t[2], t[3], t[4], t[5], t[6]
  end,
  GetCurrentItemLevel = function(loc)
    if loc.equip then return EQUIPPED_LEVELS[loc.equip] end
    return CONTAINER_LEVELS[loc.bag .. ":" .. loc.slot]
  end,
  GetItemStats = function(link)
    local id = tonumber(type(link) == "string" and link:match("item:(%d+)"))
    return id and STATS[id] or nil
  end,
}
_G.ItemLocation = {
  CreateFromEquipmentSlot = function(_, slot) return { equip = slot } end,
  CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
}

local EQUIPPED_LINKS = {
  [1] = "|cffa335ee|Hitem:212018::::::::80:250::9:6:12053:1:28:2462:::|h[Hood of the Test]|h|r",
  [4] = "|cffffffff|Hitem:9999::::::::80:250::::|h[Test Shirt]|h|r",
  [16] = "|cffa335ee|Hitem:212050:7228::::::80:251::7:1:28:::|h[Blade of the Test]|h|r",
  [19] = "|cffffffff|Hitem:9998::::::::80:250::::|h[Test Tabard]|h|r",
}
local EQUIPPED_IDS = { [1] = 212018, [4] = 9999, [16] = 212050, [19] = 9998 }
_G.GetInventoryItemLink = function(_, slot) return EQUIPPED_LINKS[slot] end
_G.GetInventoryItemID = function(_, slot) return EQUIPPED_IDS[slot] end

-- ── load the real code ──────────────────────────────────────────────────────

local ns = {}
assert(loadfile("Init.lua"))("WarbandPro", ns)
ns.Store = { Char = function() return nil end, Put = function() end }
assert(loadfile("Gear.lua"))("WarbandPro", ns)

-- ── harness ─────────────────────────────────────────────────────────────────

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL  " .. msg .. "\n")
  end
end
local function eq(got, want, msg)
  check(got == want, msg .. " — want " .. tostring(want) .. ", got " .. tostring(got))
end

local function link(id, name)
  return "|cffa335ee|Hitem:" .. id .. "::::::::80:250::4:1:28:::|h[" .. name .. "]|h|r"
end

local function visit(id, over)
  local info = { itemID = id, hyperlink = link(id, over and over.name or "Test Item " .. id) }
  if over then
    for k, v in pairs(over) do
      if k ~= "name" then info[k] = v end
    end
  end
  local out = {}
  ns.Gear.Visit(over and over.where or "bag", over and over.bagID or 0, over and over.slotIn or 1, info, out)
  return out[1], #out
end

-- ── classification: the poisoned icon position makes a drifted read loud ────

local head = visit(101)
check(head, "head classified at all — a dropped entry is the silent 1.1.0 failure")
eq(head and head.slot, 1, "INVTYPE_HEAD lands on slot 1, not the icon position's INVTYPE_FEET")
eq(visit(102).slot, 5, "INVTYPE_ROBE collapses to chest (5)")
eq(visit(103).slot, 11, "any ring lands on finger 1 (11)")
eq(visit(104).slot, 13, "any trinket lands on trinket 1 (13)")
eq(visit(105).slot, 17, "a shield lands on the off-hand family (17)")
eq(visit(106).slot, 16, "a two-hander lands on main hand (16)")
eq(visit(107).slot, 15, "a cloak lands on back (15)")

local _, dropped = visit(201)
eq(dropped, 0, "a consumable is not gear and is dropped")
local _, noLoc = visit(202)
eq(noLoc, 0, "a nil equip location drops the item rather than guessing")
local _, unknown = visit(999)
eq(unknown, 0, "an id the client cannot describe is dropped")

local noLink = {}
ns.Gear.Visit("bag", 0, 1, { itemID = 101 }, noLink)
eq(#noLink, 0, "no hyperlink, no entry — the item string is the identity key")

-- ── the 1.3.0 fields ────────────────────────────────────────────────────────

local e = visit(101, { name = "Vagabond's Torn Hood", quality = 2 })
eq(e.n, "Vagabond's Torn Hood", "n is the display name out of the hyperlink brackets")
eq(e.q, 2, "q is the container info's quality")
eq(e.cls, 4, "cls is classID from position 6")
eq(e.sub, 1, "sub is subclassID from position 7")
eq(e.b, nil, "an unbound item carries no b at all — absence means NOT bound")
eq(e.where, "bag", "where passes through")
eq(e.ilvl, 626, "ilvl comes from C_Item.GetCurrentItemLevel for the container slot")
check(e.s and e.s:find("^item:101:") ~= nil, "s is the substring between |H and |h")
check(e.s and not e.s:find("|"), "s carries no link markup")

local bound = visit(102, { isBound = true })
eq(bound.b, true, "a soulbound item carries b = true")
local boundFalse = visit(102, { isBound = false })
eq(boundFalse.b, nil, "isBound false emits nothing, matching AddonItem.isBound")

local banked = visit(103, { where = "bank", bagID = -1 })
eq(banked.where, "bank", "bank entries carry their scope")
eq(banked.ilvl, 619, "bank ilvl reads the bank container slot")

local weird = visit(106, { name = "Grim-Veiled \"Edge\"" })
eq(weird.n, "Grim-Veiled \"Edge\"", "a name with punctuation survives the bracket match")

-- ── st: stat values, verbatim tokens, absence over emptiness ────────────────

local statted = visit(101)
check(type(statted.st) == "table", "an item with stats carries st")
eq(statted.st and statted.st.ITEM_MOD_INTELLECT_SHORT, 1204, "st keeps GetItemStats tokens verbatim")
eq(statted.st and statted.st.ITEM_MOD_CRIT_RATING_SHORT, 581, "every stat pair rides along")
eq(visit(102).st, nil, "an empty stats read omits st entirely — absence, never {}")
eq(visit(103).st, nil, "a nil stats read (uncached item) omits st")
local scrubbed = visit(105)
eq(scrubbed.st and scrubbed.st.ITEM_MOD_STAMINA_SHORT, 1800, "a real pair survives beside junk-typed ones")
eq(scrubbed.st and scrubbed.st[7], nil, "a numeric key never reaches the wire")
eq(scrubbed.st and scrubbed.st.ITEM_MOD_BROKEN, nil, "a non-number value never reaches the wire")

-- ── equipped entries stay lean ──────────────────────────────────────────────

local eq_out = ns.Gear.Equipped()
eq(#eq_out, 2, "equipped walk finds the two real slots and skips shirt and tabard")
for _, row in ipairs(eq_out) do
  eq(row.where, "equipped", "equipped rows carry where = equipped")
  eq(row.n, nil, "equipped rows never carry n — the Profile API resolves them")
  eq(row.q, nil, "equipped rows never carry q")
  eq(row.cls, nil, "equipped rows never carry cls")
  eq(row.b, nil, "equipped rows never carry b")
  eq(row.st, nil, "equipped rows never carry st — the Profile API resolves them")
end
eq(eq_out[1].slot, 1, "equipped head keeps its real slot number")
eq(eq_out[1].ilvl, 639, "equipped ilvl reads the equipment slot location")

-- ── the memo caches, and caches the right shape ─────────────────────────────

local before = ns.itemInfoStats.misses
local a = ns.itemInfo(101)
local b = ns.itemInfo(101)
check(a == b, "ns.itemInfo memoizes per id")
eq(ns.itemInfoStats.misses, before, "a second lookup is a hit, not a miss")
eq(a and a.equipLoc, "INVTYPE_HEAD", "the memo holds equipLoc from position 4")
eq(a and a.classID, 4, "the memo holds classID from position 6")
eq(a and a.subclassID, 1, "the memo holds subclassID from position 7")

-- ── verdict ─────────────────────────────────────────────────────────────────

print(string.format("gear-test: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
