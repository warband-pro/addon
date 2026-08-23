-- Off-client tests for Gear.lua's classification.
--
-- This file exists because of a bug that survived from 1.1.0 to 1.3.0 in
-- plain sight: `ns.itemInfo` read `GetItemInfoInstant`'s return list one
-- position off, handing `equipLoc` the icon file id instead of the
-- `INVTYPE_*` string. `EQUIPLOC_SLOT[<number>]` is always nil, so Gear.Visit
-- returned early for every bag, bank and warband-bank item ever scanned, and
-- the wire carried equipped gear only for two minor versions.
--
-- Nothing caught it. luacheck cannot see it, the contract vectors are
-- hand-written so they had bag entries the real client never produced, and
-- `Gear.Equipped()` walks fixed slot numbers and never consults equipLoc — so
-- the half of the feature that worked masked the half that never did.
--
--   lua5.1 tools/gear-test.lua   (5.1 is what WoW runs; 5.4 works too)
--
-- The fixture below returns the REAL 7-tuple, and deliberately puts an
-- INVTYPE_* string in the icon position so that reading the wrong field fails
-- loudly rather than emptily. An off-by-one here must never again look like
-- "this character has no bag gear".

package.path = "./?.lua;" .. package.path

local pass, fail = 0, 0
local function check(label, cond, extra)
  if cond then
    pass = pass + 1
    print("PASS " .. label)
  else
    fail = fail + 1
    print("FAIL " .. label .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
end

-- ── a fake client ───────────────────────────────────────────────────────────

-- [id] = { equipLoc, classID, subclassID, decoyIcon }
--
-- `decoyIcon` is the trap. GetItemInfoInstant's 5th return is the icon file
-- id — a number in the real client — but here it is a *valid EQUIPLOC_SLOT
-- key*. Code that reads position 5 therefore classifies items into the wrong
-- slot instead of dropping them, which is a failing assertion rather than an
-- empty list. The original bug was invisible precisely because reading the
-- wrong field produced silence.
local ITEMS = {
  [1001] = { "INVTYPE_HEAD", 4, 2, "INVTYPE_TRINKET" },
  [1002] = { "INVTYPE_FINGER", 4, 0, "INVTYPE_HEAD" },
  [1003] = { "INVTYPE_TRINKET", 4, 0, "INVTYPE_HEAD" },
  [1004] = { "INVTYPE_HOLDABLE", 4, 0, "INVTYPE_HEAD" },
  [1005] = { "INVTYPE_2HWEAPON", 2, 10, "INVTYPE_HEAD" },
  [1006] = { "INVTYPE_ROBE", 4, 1, "INVTYPE_HEAD" },
  -- A reagent: not gear at all. equipLoc is "" in the live client, never nil.
  [2001] = { "", 7, 12, "INVTYPE_HEAD" },
  -- Cosmetic, excluded everywhere gear appears.
  [2002] = { "INVTYPE_TABARD", 4, 0, "INVTYPE_HEAD" },
  [2003] = { "INVTYPE_BODY", 4, 0, "INVTYPE_HEAD" },
}

_G.C_Item = {
  -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
  GetItemInfoInstant = function(id)
    local e = ITEMS[id]
    if not e then return nil end
    return id, "Armor", "Plate", e[1], e[4], e[2], e[3]
  end,
  GetCurrentItemLevel = function(loc)
    return loc and loc.ilvl or nil
  end,
}
-- Both are methods on the real ItemLocation table and are called with `:`, so
-- the fixture takes self. Getting this wrong makes every item level nil, which
-- looks exactly like the API failing rather than the test lying.
_G.ItemLocation = {
  CreateFromBagAndSlot = function(_, bag, slot) return { ilvl = 600 + bag * 10 + slot } end,
  CreateFromEquipmentSlot = function(_, slot) return { ilvl = 700 + slot } end,
}
_G.GetInventoryItemLink = function(_, slot)
  if slot ~= 1 then return nil end
  return "|cffa335ee|Hitem:1001::::::::86:66::11:1:13573:::::|h[Aureate Greathelm]|h|r"
end
_G.GetInventoryItemID = function(_, slot) return slot == 1 and 1001 or nil end
_G.C_Timer = { After = function() end }

local function link(id, name)
  return "|cffa335ee|Hitem:" .. id .. "::::::::86:66::11:1:13573:::::|h[" .. name .. "]|h|r"
end

-- Init.lua owns ns.itemInfo, which is the function under test, so it is loaded
-- for real rather than stubbed. Store is stubbed: Gear.Visit never touches it.
local ns = {}
assert(loadfile("Init.lua"))("WarbandPro", ns)
ns.Store = { db = { opts = {} }, Char = function() return nil end, Put = function() end }
assert(loadfile("Gear.lua"))("WarbandPro", ns)
local Gear = ns.Gear

-- ── ns.itemInfo reads the right positions ───────────────────────────────────

local info = ns.itemInfo(1001)
check("itemInfo returns a table", type(info) == "table")
-- The assertion the bug would have failed for two minor versions.
check("equipLoc is the INVTYPE string, not the icon", info and info.equipLoc == "INVTYPE_HEAD", info and info.equipLoc)
check("classID is position 6", info and info.classID == 4, info and info.classID)
check("subclassID is position 7", info and info.subclassID == 2, info and info.subclassID)
-- An id the client cannot answer for returns a table of nils rather than nil,
-- and that is fine: equipLoc nil means EQUIPLOC_SLOT misses and the item is
-- dropped, which is the same outcome by a shorter road.
check("an unknown id yields no equip location", (ns.itemInfo(999999) or {}).equipLoc == nil)
check("a non-number id is refused", ns.itemInfo("1001") == nil)

-- ── Gear.Visit classifies bag items ─────────────────────────────────────────

local function visit(id, name, where, bag, slot)
  local out = {}
  Gear.Visit(where or "bag", bag or 0, slot or 1, {
    itemID = id,
    hyperlink = link(id, name or "Thing"),
    quality = 3,
    isBound = true,
  }, out)
  return out
end

local head = visit(1001, "Aureate Greathelm")
check("a bag helm produces one entry", #head == 1, #head)
check("classified to slot 1", head[1] and head[1].slot == 1, head[1] and head[1].slot)
check("carries where=bag", head[1] and head[1].where == "bag")
check("carries the item string verbatim", head[1] and head[1].s == "item:1001::::::::86:66::11:1:13573:::::")
check("carries an item level from the live bag", head[1] and head[1].ilvl == 601, head[1] and head[1].ilvl)

-- The paired collapse the contract documents: the addon cannot know which of
-- two ring slots a bagged ring would fill, so it does not guess.
check("any ring collapses to 11", (visit(1002, "Band")[1] or {}).slot == 11)
check("any trinket collapses to 13", (visit(1003, "Charm")[1] or {}).slot == 13)
check("an off-hand-family item collapses to 17", (visit(1004, "Tome")[1] or {}).slot == 17)
check("a two-hander lands on 16", (visit(1005, "Greatstaff")[1] or {}).slot == 16)
check("a robe lands on chest", (visit(1006, "Vestments")[1] or {}).slot == 5)

-- ── and drops what is not gear ──────────────────────────────────────────────

check("a reagent produces nothing", #visit(2001, "Herb") == 0)
check("a tabard is cosmetic and excluded", #visit(2002, "Tabard") == 0)
check("a shirt is cosmetic and excluded", #visit(2003, "Shirt") == 0)
check("an item with no hyperlink produces nothing", (function()
  local out = {}
  Gear.Visit("bag", 0, 1, { itemID = 1001, hyperlink = nil }, out)
  return #out == 0
end)())

-- ── the 1.3.0 fields ────────────────────────────────────────────────────────

local e = head[1]
check("name comes off the hyperlink", e and e.n == "Aureate Greathelm", e and e.n)
check("quality rides along", e and e.q == 3, e and e.q)
check("bound is emitted when true", e and e.b == true)
check("item class is the real classID", e and e.cls == 4, e and e.cls)
check("item subclass is the real subclassID", e and e.sub == 2, e and e.sub)

local unbound = {}
Gear.Visit("bag", 0, 1, { itemID = 1001, hyperlink = link(1001, "X"), quality = 3 }, unbound)
-- Absent rather than false: the website dates the bundle by `cls` and reads a
-- missing `b` as not-bound, which is the BoE case its guard exists for.
check("bound is absent rather than false when unbound", unbound[1] and unbound[1].b == nil)

-- ── every scope, not just bags ──────────────────────────────────────────────

for _, where in ipairs({ "bag", "bank", "warbank" }) do
  local out = visit(1001, "Helm", where)
  check("scope " .. where .. " classifies", #out == 1 and out[1].where == where)
end

-- ── equipped still works, and is the reason this went unseen ────────────────

local eq = Gear.Equipped()
check("equipped reads its fixed slots", #eq == 1, #eq)
check("equipped slot is the real inventory slot", eq[1] and eq[1].slot == 1)
check("equipped carries the 1.3.0 name", eq[1] and eq[1].n == "Aureate Greathelm")
check("equipped carries cls/sub", eq[1] and eq[1].cls == 4 and eq[1].sub == 2)
-- Equipped never consults equipLoc, which is exactly why it kept working while
-- every bag item was being dropped. Stated as an assertion so the asymmetry is
-- on the record rather than in a comment.
check("equipped carries no quality — nothing judges what is already worn", eq[1] and eq[1].q == nil)

print("")
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
