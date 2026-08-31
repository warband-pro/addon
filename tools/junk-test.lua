-- Off-client tests for Junk.lua's matching.
--
-- Junk.lua is not pure — it walks containers and sells things — but the part
-- that decides WHICH item a verdict is about is, and that part is the one where
-- being wrong costs somebody an item. This stands a fake bag in front of it.
--
--   lua5.1 tools/junk-test.lua
--
-- What is deliberately not tested here: Junk.Sell and the secure macro, both of
-- which are one call into an API that does not exist outside the client. The
-- QA checklist covers those by hand, because nothing else can.

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

-- ── a fake game ─────────────────────────────────────────────────────────────

local BAGS = {}    -- [bagID] = { [slot] = { itemID, hyperlink, quality } }
local PROFESSIONS = {}

local function link(id, name, s)
  return "|cffa335ee|H" .. (s or ("item:" .. id .. "::::::::80:250::1:1:12053:::")) .. "|h[" .. name .. "]|h|r"
end

_G.UnitGUID = function() return "Player-1-TEST" end
_G.GetProfessions = function() return PROFESSIONS[1], PROFESSIONS[2] end
_G.GetProfessionInfo = function(index)
  -- name, _, skill, maxSkill, _, _, skillLine
  return "Prof", nil, 100, 100, nil, nil, index
end
_G.C_Container = {
  GetContainerNumSlots = function(id) return BAGS[id] and 8 or 0 end,
  GetContainerNumFreeSlots = function() return 0 end,
  GetContainerItemInfo = function(id, slot)
    local b = BAGS[id]
    return b and b[slot] or nil
  end,
  UseContainerItem = function(id, slot)
    BAGS[id][slot] = nil
  end,
}
_G.C_Spell = { GetSpellName = function() return "Disenchant" end }
_G.Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 } }

local ns = {
  safe = function(fn, a, b, c)
    local ok, r = pcall(fn, a, b, c)
    if ok then return r end
    return nil
  end,
  now = function() return 1724000000 end,
  ago = function() return "1h ago" end,
}
-- Only what Junk.lua reaches for out of Scan.
ns.Scan = {
  CARRIED = { 0, 1 },
  Walk = function(id, visit)
    local b = BAGS[id]
    if not b then return 0, 0 end
    for slot = 1, 8 do
      local info = b[slot]
      if info then visit(id, slot, info) end
    end
    return 8, 0
  end,
}
ns.Store = {
  db = { chars = { ["Player-1-TEST"] = { name = "Vocnar" } } },
  Touch = function() end,
}

assert(loadfile("Junk.lua"))("WarbandPro", ns)
local Junk = ns.Junk

-- ── fixtures ────────────────────────────────────────────────────────────────

local S_HELM = "item:221151::::::::80:250::4:6:12053:1:28:::"
local S_RING = "item:215135::::::::80:250::4:6:12053:1:28:::"
local S_GONE = "item:999999::::::::80:250::4:6:12053:1:28:::"

local function resetBags()
  BAGS = {
    [0] = {
      [1] = { itemID = 221151, hyperlink = link(221151, "Ironclaw Warhelm", S_HELM), quality = 3 },
      [3] = { itemID = 215135, hyperlink = link(215135, "Band of the Quiet Grove", S_RING), quality = 4 },
      [5] = { itemID = 3300, hyperlink = link(3300, "Rabbit's Foot"), quality = 0 },
    },
    [1] = {
      -- A second copy of the helm, in a different bag and slot.
      [2] = { itemID = 221151, hyperlink = link(221151, "Ironclaw Warhelm", S_HELM), quality = 3 },
    },
  }
end

local function storeList(items)
  ns.Store.db.junk = { ["Player-1-TEST"] = { generatedAt = 1724000000, items = items } }
end

-- ── matching ────────────────────────────────────────────────────────────────

resetBags()
storeList({
  { k = "de", s = S_HELM, r = "unusable", ilvl = 610 },
  { k = "sell", s = S_RING, r = "gap", g = 56, ilvl = 570 },
  { k = "sell", s = S_GONE, r = "gap", g = 90 },
})

local rows, missing, generatedAt = Junk.Resolve()
check("generatedAt comes back", generatedAt == 1724000000, generatedAt)
check("a verdict that matches nothing is counted, not rendered", missing == 1, missing)

local byName = {}
for _, r in ipairs(rows) do
  byName[r.name] = byName[r.name] or {}
  table.insert(byName[r.name], r)
end

-- The rule the contract states: one verdict, every live match.
check("both copies of the helm are listed from one verdict", #(byName["Ironclaw Warhelm"] or {}) == 2,
  #(byName["Ironclaw Warhelm"] or {}))
check("the two copies carry different bag positions",
  byName["Ironclaw Warhelm"] and byName["Ironclaw Warhelm"][1].slot ~= byName["Ironclaw Warhelm"][2].slot)
check("the ring matched once", #(byName["Band of the Quiet Grove"] or {}) == 1)
check("positions come from the live bag", byName["Band of the Quiet Grove"]
  and byName["Band of the Quiet Grove"][1].bag == 0
  and byName["Band of the Quiet Grove"][1].slot == 3)
check("the verdict rides along", byName["Ironclaw Warhelm"] and byName["Ironclaw Warhelm"][1].k == "de")

-- Greys are never on the wire; they come from the bag walk.
check("grey trash is listed without being on the list", #(byName["Rabbit's Foot"] or {}) == 1)
check("a grey is marked as one", byName["Rabbit's Foot"] and byName["Rabbit's Foot"][1].grey == true)

-- The safety property: a moved item is a miss, never a different item.
resetBags()
BAGS[0][3] = nil
BAGS[0][7] = { itemID = 4444, hyperlink = link(4444, "Something Precious"), quality = 4 }
rows, missing = Junk.Resolve()
local names = {}
for _, r in ipairs(rows) do names[r.name] = true end
check("an item that moved away is missed rather than mismatched", not names["Band of the Quiet Grove"])
check("the item now in its old slot is not sold in its place", not names["Something Precious"])
-- The ring and the never-there item, both unmatched now.
check("the moved item joins the missing count", missing == 2, missing)

-- No stored list at all: still lists greys, still reports no verdicts.
ns.Store.db.junk = nil
resetBags()
rows, missing, generatedAt = Junk.Resolve()
check("with no list, greys still surface", #rows == 1 and rows[1].grey == true, #rows)
check("with no list there is nothing missing", missing == 0)
check("with no list there is no date", generatedAt == nil)

-- ── saving ──────────────────────────────────────────────────────────────────

ns.Store.db.junk = nil
local kept = Junk.Save({
  generatedAt = 99,
  chars = {
    ["Player-1-TEST"] = { name = "Vocnar", junk = { { k = "sell", s = S_HELM } } },
    ["Player-9-OTHER"] = { name = "Someone", junk = { { k = "sell", s = S_RING } } },
  },
})
check("saves the list for a character this account has", kept == 1, kept)
check("stores it under the guid", ns.Store.db.junk["Player-1-TEST"] ~= nil)
-- A cleanup string covers a whole warband, and most of it belongs to alts this
-- install may never have seen. Keeping those would be storing somebody else's.
check("ignores a guid this account has never scanned", ns.Store.db.junk["Player-9-OTHER"] == nil)

-- The failure the one-string change could have introduced, and the reason
-- Save guards on its own section: since 1.8.0 one paste carries the clear-out
-- list, the gear setups and the build assignments, and a character can
-- legitimately have setups and nothing to sell. Writing an absent section
-- would delete a list the player still wants, silently.
check("a paste carrying no clear-out list leaves the stored one alone", (function()
  local before = ns.Store.db.junk["Player-1-TEST"]
  Junk.Save({
    generatedAt = 100,
    chars = { ["Player-1-TEST"] = { name = "Vocnar", gear = { items = {} } } },
  })
  return ns.Store.db.junk["Player-1-TEST"] == before
end)())

check("and reports it kept nothing, rather than counting a character it skipped", (function()
  return Junk.Save({
    generatedAt = 100,
    chars = { ["Player-1-TEST"] = { name = "Vocnar", builds = { [103] = { raid = 7 } } } },
  }) == 0
end)())

check("a paste that does carry one still replaces it", (function()
  Junk.Save({
    generatedAt = 101,
    chars = { ["Player-1-TEST"] = { name = "Vocnar", junk = { { k = "de", s = S_RING } } } },
  })
  local rec = ns.Store.db.junk["Player-1-TEST"]
  return rec ~= nil and rec.generatedAt == 101 and #rec.items == 1 and rec.items[1].k == "de"
end)())

-- ── selling ─────────────────────────────────────────────────────────────────

resetBags()
Junk.merchantOpen = false
check("will not sell away from a merchant", Junk.Sell(0, 1) == false)
check("the item is still there", BAGS[0][1] ~= nil)
Junk.merchantOpen = true
check("sells at a merchant", Junk.Sell(0, 1) == true)
check("the item is gone", BAGS[0][1] == nil)
check("refuses a nonsense position", Junk.Sell(nil, nil) == false)
Junk.merchantOpen = false

-- ── professions ─────────────────────────────────────────────────────────────

PROFESSIONS = {}
check("no professions, no disenchant", Junk.CanDisenchant() == false)
PROFESSIONS = { 164, 197 }          -- blacksmithing, tailoring
check("wrong professions, no disenchant", Junk.CanDisenchant() == false)
PROFESSIONS = { 333, 164 }          -- enchanting
check("enchanting is found", Junk.CanDisenchant() == true)

-- ── labels ──────────────────────────────────────────────────────────────────

check("a de verdict reads as sell without the profession",
  Junk.VerdictLabel({ k = "de" }, false) == "sell")
check("a de verdict reads as disenchant with it",
  Junk.VerdictLabel({ k = "de" }, true) == "disenchant")
check("delete is advice, and says so", Junk.VerdictLabel({ k = "del" }, true) == "delete by hand")
check("a grey is always a sell", Junk.VerdictLabel({ grey = true, k = "de" }, true) == "sell")
check("a gap reason names its number", Junk.ReasonText({ r = "gap", g = 30 }) == "30 behind")
check("an unusable reason says why", Junk.ReasonText({ r = "unusable" }) == "cannot wear")
check("a grey needs no explanation", Junk.ReasonText({ grey = true }) == "grey")
check("a gap with no number says nothing rather than nil", Junk.ReasonText({ r = "gap" }) == "")
check("a dupe reason names what is on your body", Junk.ReasonText({ r = "dupe" }) == "already wearing one")
check("a dominated reason names the better item, not the worse one",
  Junk.ReasonText({ r = "dominated" }) == "you own a better one")
check("a reason this build does not know reads blank, not nil",
  Junk.ReasonText({ r = "something-newer" }) == "")

print("")
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
