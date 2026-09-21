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

-- Vendor sell price by item id, which the client states at position 11 of
-- GetItemInfo and nowhere else.
--
-- **An id absent from this table is an item this session has never cached**,
-- and the call answers nothing at all — not zero. That is the distinction the
-- whole fallback turns on, so the fake has to be able to make it: most fixtures
-- below are deliberately left out of here, which is what keeps them exercising
-- the "no data, still offer Sell" path.
local PRICES = {}

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
_G.C_Item = {
  GetItemInfo = function(hyperlink)
    local text = tostring(hyperlink)
    local id = tonumber(text:match("|Hitem:(%d+)") or text:match("^item:(%d+)"))
    local price = id and PRICES[id]
    if price == nil then return nil end
    -- name, link, quality, ilvl, minLevel, type, subType, stackCount,
    -- equipLoc, icon, sellPrice — the eleventh.
    return "Name", hyperlink, 1, 1, 1, "Armor", "Cloth", 1, "INVTYPE_HEAD", 1, price
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
      [5] = { itemID = 3300, hyperlink = link(3300, "Rabbit's Foot"), quality = 0, stackCount = 4 },
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

-- ── items the vendor will not buy ───────────────────────────────────────────
--
-- The bug: the panel offered Sell for every non-`del` row, so a quest item or a
-- token on the list drew a live button whose only possible outcome was "the
-- vendor doesn't want this". The fix reads the sell price and falls back the
-- same way a `de` row falls back without the profession.

check("an item with a zero sell price is disenchantable at uncommon",
  Junk.Disenchantable({ quality = 2 }) == true)
check("a common item is not worth a disenchant button",
  Junk.Disenchantable({ quality = 1 }) == false)
check("a grey is never the disenchant fallback", Junk.Disenchantable({ grey = true, quality = 4 }) == false)
check("an item of unknown quality is not disenchanted on a guess",
  Junk.Disenchantable({}) == false)
check("nothing is not a row", Junk.Disenchantable(nil) == false)

check("an ordinary sell row is sellable", Junk.Sellable({ k = "sell" }) == true)
check("a del row is not", Junk.Sellable({ k = "del" }) == false)
check("a grey is", Junk.Sellable({ k = "sell", grey = true }) == true)
-- The one the bug was about.
check("an item the vendor refuses is not sellable, whatever the site said",
  Junk.Sellable({ k = "sell", nosell = true }) == false)
check("nor is a grey the vendor refuses",
  Junk.Sellable({ k = "sell", grey = true, nosell = true }) == false)
check("a de row still carries a live sell beside its disenchant, as it always has",
  Junk.Sellable({ k = "de" }) == true)
check("nothing is not a row", Junk.Sellable(nil) == false)

check("an unsellable item an enchanter can break down reads disenchant",
  Junk.VerdictLabel({ k = "sell", nosell = true, quality = 4 }, true) == "disenchant")
check("the same item without the profession reads delete by hand",
  Junk.VerdictLabel({ k = "sell", nosell = true, quality = 4 }, false) == "delete by hand")
check("an unsellable common item reads delete by hand even for an enchanter",
  Junk.VerdictLabel({ k = "sell", nosell = true, quality = 1 }, true) == "delete by hand")
-- The symmetry the fix is built on: the panel already reads "sell" for a
-- disenchant it cannot do, so it reads "delete by hand" for a sale it cannot make.
check("a de row with no profession and no sell price has nothing left but the bin",
  Junk.VerdictLabel({ k = "de", nosell = true }, false) == "delete by hand")
check("a de row with the profession is unaffected by the sell price",
  Junk.VerdictLabel({ k = "de", nosell = true }, true) == "disenchant")
check("a grey nobody will buy reads delete by hand",
  Junk.VerdictLabel({ grey = true, k = "sell", nosell = true }, false) == "delete by hand")
check("a sell row with a price is untouched", Junk.VerdictLabel({ k = "sell" }, true) == "sell")

-- ── the price read, end to end ──────────────────────────────────────────────

local S_TOKEN = "item:210796::::::::80:250::4:6:12053:1:28:::"
PRICES = {}
resetBags()
BAGS[0][6] = { itemID = 210796, hyperlink = link(210796, "Sigil of Something", S_TOKEN), quality = 3 }
storeList({ { k = "sell", s = S_TOKEN, r = "dominated" } })

rows = Junk.Resolve()
check("an item the client has not cached keeps its Sell button", (function()
  for _, r in ipairs(rows) do
    if r.name == "Sigil of Something" then return r.nosell == false and Junk.Sellable(r) == true end
  end
  return false
end)())

PRICES[210796] = 0
rows = Junk.Resolve()
check("a cached zero price is read off the live item and marks the row", (function()
  for _, r in ipairs(rows) do
    if r.name == "Sigil of Something" then return r.nosell == true and Junk.Sellable(r) == false end
  end
  return false
end)())
check("and the row's verdict stops saying sell", (function()
  for _, r in ipairs(rows) do
    if r.name == "Sigil of Something" then return Junk.VerdictLabel(r, false) == "delete by hand" end
  end
  return false
end)())

PRICES[210796] = 4500
rows = Junk.Resolve()
check("a positive price leaves the row alone", (function()
  for _, r in ipairs(rows) do
    if r.name == "Sigil of Something" then return r.nosell == false and Junk.Sellable(r) == true end
  end
  return false
end)())

-- The rest of the list must not move because one row did.
check("the greys and the other rows are untouched by the price read", (function()
  local greys, others = 0, 0
  for _, r in ipairs(rows) do
    if r.grey then greys = greys + 1 elseif r.name ~= "Sigil of Something" then others = others + 1 end
  end
  return greys == 1 and others == 0
end)(), #rows)

-- ── selling the whole list ──────────────────────────────────────────────────
--
-- The vendor window's "Sell list (N)" button. What it counts, what it says the
-- take is, and what it actually sells — all three read the same plan, which is
-- the point of the plan being a function rather than a loop inside a frame.

check("money reads the way the game writes it", Junk.Money(452000) == "45g 20s", Junk.Money(452000))
check("a silver-and-copper take keeps both", Junk.Money(2507) == "25s 7c", Junk.Money(2507))
check("a round gold amount says only gold", Junk.Money(120000) == "12g", Junk.Money(120000))
check("nothing is 0c rather than blank", Junk.Money(0) == "0c", Junk.Money(0))
check("a nonsense amount does not print nil", Junk.Money(nil) == "0c", Junk.Money(nil))

-- The plan takes sell-verdict rows only. A `de` row on an enchanter keeps its
-- own Sell button in the panel — overruling the advice one item at a time is a
-- different act from overruling twelve under one confirm.
local plan = Junk.SellPlan({
  { k = "sell", price = 1000, count = 1 },
  { k = "sell", grey = true, price = 25, count = 4 },
  { k = "de", price = 9999, count = 1, quality = 4 },
  { k = "del", price = 500, count = 1 },
  { k = "sell", nosell = true, price = 0, count = 1 },
}, true)
check("the plan takes the sell rows and the greys", plan.count == 2, plan.count)
check("a stack is priced by the stack", plan.total == 1000 + 25 * 4, plan.total)
check("everything in the plan is priced", plan.unpriced == 0, plan.unpriced)
check("a disenchant row is not swept into a sell-all", (function()
  for _, r in ipairs(plan.rows) do if r.k == "de" then return false end end
  return true
end)())

-- Without the profession that same `de` row reads "sell" in the panel, so the
-- sell-all takes it: the button counts what the player can see offered.
local noProf = Junk.SellPlan({ { k = "de", price = 9999, count = 1, quality = 4 } }, false)
check("a de row the character cannot disenchant is an ordinary sell", noProf.count == 1, noProf.count)

check("an uncached price is still sold, and counted as unpriced", (function()
  local p = Junk.SellPlan({ { k = "sell", count = 1 } }, false)
  return p.count == 1 and p.total == 0 and p.unpriced == 1
end)())
check("a missing stack size counts as one", (function()
  local p = Junk.SellPlan({ { k = "sell", price = 700 } }, false)
  return p.total == 700
end)())
check("nothing is an empty plan, not an error", Junk.SellPlan(nil, false).count == 0)

-- End to end against the fake bags: what the button would say, then what
-- pressing it does.
PRICES = { [3300] = 50, [215135] = 8000, [221151] = 6000 }
resetBags()
storeList({
  { k = "sell", s = S_RING, r = "gap", g = 56 },
  { k = "del", s = S_HELM, r = "dominated" },
})
PROFESSIONS = {}
Junk.merchantOpen = false
plan = Junk.SellPlanNow()
-- The ring, plus the grey stack of four. Both helm copies are `del`.
check("the live plan counts the ring and the grey stack", plan.count == 2, plan.count)
check("and totals the stack at four", plan.total == 8000 + 50 * 4, plan.total)

check("nothing sells away from a merchant", (function()
  local sold, copper = Junk.SellAll(plan)
  return sold == 0 and copper == 0 and BAGS[0][3] ~= nil
end)())

Junk.merchantOpen = true
local sold, copper = Junk.SellAll(plan)
check("every row in the plan sells", sold == 2, sold)
check("the take is what the plan said", copper == 8200, copper)
check("the ring is gone", BAGS[0][3] == nil)
check("the grey is gone", BAGS[0][5] == nil)
-- The safety property, restated for the sell-all: a `del` row is advice, and a
-- button that sold the whole list would have taken it anyway.
check("a delete-by-hand row is still in the bags", BAGS[0][1] ~= nil)

check("with the bags emptied the button has nothing to offer", Junk.SellPlanNow().count == 0)

-- Half the list left the bags between the paste and the vendor. The plan is
-- rebuilt from the walk that just happened, so the rows that went missing are
-- simply not in it — no stale coordinate, no wrong item sold.
resetBags()
BAGS[0][5] = nil
plan = Junk.SellPlanNow()
check("a row that left the bags is not in the plan", plan.count == 1, plan.count)
sold = Junk.SellAll(plan)
check("and only the live row sells", sold == 1, sold)
Junk.merchantOpen = false

print("")
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
