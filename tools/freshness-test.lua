-- Off-client tests for the freshness model: which stamps a scan is allowed to
-- move, and what a partial read may overwrite.
--
--   lua5.1 tools/freshness-test.lua
--
-- Scan.lua and Store.lua are both WoW-bound, so docs/TESTING.md files them
-- under "manual checklist". The part tested here is not the reading — that
-- needs a client — it is the bookkeeping either side of it, which is pure
-- given a fake container API, and which is where being wrong is invisible:
-- every failure this file guards against produces a stamp that looks right and
-- data that is not.
--
-- Three of them shipped:
--
--   * a reagent-bank-only read moved the shared `bank` stamp, so bank contents
--     nobody had looked at since the last banker visit drew a fresh dot;
--   * a warband walk that saw one tab of five replaced the whole stored vault
--     with that one tab and stamped the loss fresh;
--   * Scan.Bank wrote through to the character without Store.Touch, so
--     Export.Build's rev cache could serve a bundle assembled before the bank
--     was read — the contents in the DB and absent from the string.

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

-- [bagID] = { size = n, free = n, items = { [slot] = info } }. A bag absent
-- from this table is one the client will not read right now — which is the
-- same answer it gives for a bag that does not exist, and the whole reason the
-- warband walk needs a purchased-tab count to tell those apart.
local CONTAINERS = {}

local NOW = 1724000000
local OWNED_TABS = 5          -- what C_Bank reports as purchased; nil = won't say

_G.Enum = {
  BagIndex = {
    Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
    Bank = -1, Reagentbank = -3,
    BankBag_1 = 6, BankBag_2 = 7, BankBag_3 = 8, BankBag_4 = 9,
    BankBag_5 = 10, BankBag_6 = 11, BankBag_7 = 12,
    AccountBankTab_1 = 13, AccountBankTab_2 = 14, AccountBankTab_3 = 15,
    AccountBankTab_4 = 16, AccountBankTab_5 = 17,
  },
  BankType = { Account = 2 },
}

_G.C_Container = {
  GetContainerNumSlots = function(id)
    local c = CONTAINERS[id]
    return c and c.size or 0
  end,
  GetContainerNumFreeSlots = function(id)
    local c = CONTAINERS[id]
    return c and c.free or 0
  end,
  GetContainerItemInfo = function(id, slot)
    local c = CONTAINERS[id]
    return c and c.items and c.items[slot] or nil
  end,
}

_G.C_Bank = {
  FetchDepositedMoney = function() return 12345 end,
  FetchPurchasedBankTabData = function()
    if OWNED_TABS == nil then error("no such API on this client") end
    local out = {}
    for i = 1, OWNED_TABS do out[i] = { ID = 12 + i } end
    return out
  end,
}

_G.UnitGUID = function() return "Player-1-TEST" end
_G.UnitName = function() return "Vocnar" end

local ns = {
  WIRE_V = 1,
  STALE_PRUNE = 90 * 86400,
  now = function() return NOW end,
  print = function() end,
  safe = function(fn, a, b, c)
    if type(fn) ~= "function" then return nil end
    local ok, r1, r2, r3 = pcall(fn, a, b, c)
    if ok then return r1, r2, r3 end
    return nil
  end,
  itemInfo = function() return nil end,   -- the consumables rollup, not under test
  slug = function(s) return s end,
}

-- Gear.SetScope is the assertion target for the partial-read rule, so it
-- records rather than no-ops.
local gearScopes = {}
ns.Gear = {
  Visit = function() end,
  SetScope = function(where, rows) gearScopes[where] = rows end,
  All = function() end,
  Talents = function() end,
}

ns.MAX_CHARS = 20
ns.dot = function() return "green" end
ns.ago = function() return "1h ago" end
_G.GetBuildInfo = function() return "12.1.0", "60000", "Aug 2026", 120100 end

assert(loadfile("Store.lua"))("WarbandPro", ns)
assert(loadfile("Scan.lua"))("WarbandPro", ns)
assert(loadfile("Bundle.lua"))("WarbandPro", ns)
local Store, Scan, Bundle = ns.Store, ns.Scan, ns.Bundle

-- ── fixtures ────────────────────────────────────────────────────────────────

local function item(id, count)
  return { itemID = id, stackCount = count or 1, quality = 2 }
end

local function container(size, items)
  return { size = size, free = size - 1, items = items or {} }
end

--- A fresh DB and an empty client, with the clock back at the start.
local function reset()
  _G.WarbandProDB = nil
  CONTAINERS = {}
  gearScopes = {}
  NOW = 1724000000
  OWNED_TABS = 5
  Store.readOnly = nil
  Store.Init()
  Scan.consumableParts = { bag = nil, bank = nil, reagentBank = nil }
end

local function stamps()
  local c = Store.Char()
  return c.seenAt
end

-- ── the bank is two reads, so it is two stamps ──────────────────────────────

reset()
CONTAINERS[-1] = container(28, { [1] = item(211493, 20) })
CONTAINERS[-3] = container(98, { [1] = item(190456, 5) })
Scan.Bank()
check("both containers read, both stamped",
  stamps().bank == NOW and stamps().reagentBank == NOW,
  tostring(stamps().bank) .. "/" .. tostring(stamps().reagentBank))

-- The shipped bug: the reagent bank alone used to move the bank stamp.
local bankStampWas = stamps().bank
NOW = NOW + 3600
CONTAINERS[-1] = nil                      -- bank bags no longer readable
Scan.Bank()
check("a reagent-bank-only read leaves the bank stamp where it was",
  stamps().bank == bankStampWas, stamps().bank)
check("a reagent-bank-only read does move the reagent-bank stamp",
  stamps().reagentBank == NOW, stamps().reagentBank)
check("a reagent-bank-only read keeps the bank contents it could not re-read",
  Store.Char().bank ~= nil and #Store.Char().bank == 1)

reset()
CONTAINERS[-1] = container(28, { [1] = item(211493, 20) })
Scan.Bank()
check("a bank-bags-only read never claims a reagent bank",
  stamps().bank == NOW and stamps().reagentBank == nil, tostring(stamps().reagentBank))

reset()
Scan.Bank()
check("neither container readable stamps neither",
  stamps().bank == nil and stamps().reagentBank == nil)

-- Export.Build caches on Store.rev, so a write that does not move it is a
-- write the exported string can miss.
reset()
CONTAINERS[-1] = container(28, { [1] = item(211493, 20) })
local revWas = Store.rev
Scan.Bank()
check("a bank read moves the rev the export cache is keyed on",
  Store.rev > revWas, Store.rev .. " vs " .. revWas)

reset()
revWas = Store.rev
Scan.Bank()
check("a bank read that found nothing moves nothing", Store.rev == revWas)

-- ── the warband bank merges tabs, it does not replace them ──────────────────

local function tabIDs()
  local out = {}
  for _, tab in ipairs(Store.db.warbandBank.tabs) do out[#out + 1] = tab.bagID end
  return table.concat(out, ",")
end

reset()
for id = 13, 17 do CONTAINERS[id] = container(98, { [1] = item(200000 + id, 3) }) end
Scan.WarbandBank()
check("a complete walk stores every tab", tabIDs() == "13,14,15,16,17", tabIDs())
check("a complete walk claims no gap", Store.db.warbandBank.partial == nil)
check("a complete walk records what the account owns", Store.db.warbandBank.tabsOwned == 5)
check("a complete walk replaces the warbank gear scope", gearScopes.warbank ~= nil)

-- The shipped bug: ACCOUNT_BANK_TAB_DATA_CHANGED fires per tab as the client
-- streams data in, so the first walk after a banker opens routinely sees one
-- tab. That used to store one tab and drop four.
local firstSeen = NOW
NOW = NOW + 7200
gearScopes = {}
for id = 14, 17 do CONTAINERS[id] = nil end
CONTAINERS[13] = container(98, { [1] = item(200013, 9) })
Scan.WarbandBank()
check("a one-tab walk keeps the other four", tabIDs() == "13,14,15,16,17", tabIDs())
check("the tab it read carries the new stamp", Store.db.warbandBank.tabs[1].seenAt == NOW)
check("the tabs it could not read keep their own older stamp",
  Store.db.warbandBank.tabs[5].seenAt == firstSeen, Store.db.warbandBank.tabs[5].seenAt)
check("the tab it read carries the new contents",
  Store.db.warbandBank.tabs[1].items[1].count == 9)
check("a partial walk does not replace the warbank gear scope", gearScopes.warbank == nil)
check("the oldest tab is what the vault's real age is measured from",
  Store.WarbandBankOldestTab() == firstSeen)
check("the root stamp still says when somebody last looked",
  Store.db.warbandBank.seenAt == NOW)

-- Tabs arriving out of order still land in a stable order: Bundle.JSON sorts
-- keys but cannot sort a list, and a bundle whose bytes move without its
-- meaning moving is one nothing can be diffed against.
reset()
CONTAINERS[16] = container(98)
Scan.WarbandBank()
CONTAINERS[16] = nil
CONTAINERS[13] = container(98)
Scan.WarbandBank()
check("tabs are stored in bagID order however they arrived", tabIDs() == "13,16", tabIDs())

-- ── partial is a claim, and needs a denominator to make it ──────────────────

reset()
CONTAINERS[13] = container(98)
CONTAINERS[14] = container(98)
Scan.WarbandBank()
check("two of five owned tabs is a partial vault", Store.db.warbandBank.partial == true)

for id = 15, 17 do CONTAINERS[id] = container(98) end
Scan.WarbandBank()
check("the claim clears once every owned tab has been seen",
  Store.db.warbandBank.partial == nil)

reset()
OWNED_TABS = nil                          -- a client that will not answer
CONTAINERS[13] = container(98)
Scan.WarbandBank()
check("no purchased-tab count means no completeness claim at all",
  Store.db.warbandBank.partial == nil and Store.db.warbandBank.tabsOwned == nil)
check("and no denominator means the gear scope is replaced as before",
  gearScopes.warbank ~= nil)

-- A vault that was never opened is absent, not empty — the same rule the bank
-- follows, and the one the website turns into "open your warband bank".
reset()
Scan.WarbandBank()
check("a walk that read no tab at all writes nothing",
  Store.db.warbandBank.seenAt == nil and #Store.db.warbandBank.tabs == 0)
check("and stamps no character with a warbank it never saw", stamps().warbank == nil)

-- ── and all of it has to survive the trip to the wire ───────────────────────
--
-- Bundle.lua names the warband bank's fields one at a time rather than copying
-- the stored table, so a field can be right in the DB, right in `/warband
-- status`, and simply absent from the string the player pastes. A website told
-- nothing about a gap presents the vault as whole, which is the bug this whole
-- change is about, one layer further out.

reset()
Store.Char().name = "Vocnar"          -- Bundle.Build wants a character to carry
CONTAINERS[13] = container(98, { [1] = item(200013, 3) })
CONTAINERS[14] = container(98)
Scan.WarbandBank()
local wire = Bundle.Build().warbandBank
check("the payload carries what the account owns", wire.tabsOwned == 5, wire.tabsOwned)
check("the payload carries the gap", wire.partial == true, tostring(wire.partial))
check("the payload carries each tab's own stamp", wire.tabs[1].seenAt == NOW)

for id = 15, 17 do CONTAINERS[id] = container(98) end
Scan.WarbandBank()
check("and stops carrying the gap once there is none",
  Bundle.Build().warbandBank.partial == nil)

-- ── a warband larger than one bundle goes out a page at a time ──────────────
--
-- The slicing is arithmetic on a list, which is exactly the kind of thing that
-- is wrong by one and looks right: an off-by-one here does not error, it
-- silently omits one character from every page, or repeats one across two.
-- The stakes are the same as the vault above — past MAX_CHARS the oldest
-- characters simply did not exist on the website, and the panel's remedy was
-- `/warband clear`, which deletes an alt to make room.

reset()
--- `n` stored characters, newest first by lastSeen so the page order is known.
local function warbandOf(n)
  reset()
  for i = 1, n do
    Store.db.chars["Player-1-" .. i] = {
      guid = "Player-1-" .. i,
      name = "Alt" .. i,
      seenAt = { lastSeen = NOW - i },
    }
  end
end

local function pageNames(page)
  local out = {}
  for _, c in ipairs(Bundle.Build({ page = page }).characters) do out[#out + 1] = c.name end
  return out
end

warbandOf(41)
local p1, p3 = Bundle.Build({ page = 1 }), Bundle.Build({ page = 3 })
check("page 1 of a 41 character warband carries the cap, not the warband",
  p1.bundle.count == 20, p1.bundle.count)
check("and says which page of how many", p1.bundle.page == 1 and p1.bundle.pages == 3)
check("and counts the ones not in it", p1.bundle.droppedOverCap == 21, p1.bundle.droppedOverCap)
check("the last page carries the remainder", p3.bundle.count == 1, p3.bundle.count)

-- The two failures the arithmetic actually risks, stated as the player's loss:
-- a character on no page is one the website never hears about again, and a
-- character on two pages is a page of wire spent saying nothing new.
local seen, dupes = {}, 0
for page = 1, 3 do
  for _, name in ipairs(pageNames(page)) do
    if seen[name] then dupes = dupes + 1 end
    seen[name] = true
  end
end
local missing = 0
for i = 1, 41 do if not seen["Alt" .. i] then missing = missing + 1 end end
check("every character lands on exactly one page", missing == 0 and dupes == 0,
  missing .. " missing, " .. dupes .. " repeated")
check("page 1 is the twenty played most recently", pageNames(1)[1] == "Alt1")
check("and page 2 picks up where it left off", pageNames(2)[1] == "Alt21")

-- Clamped rather than trusted: the page comes from a slash command, and an
-- empty bundle is one the website rejects out of hand.
check("a page past the end clamps to the last one",
  Bundle.Build({ page = 99 }).bundle.page == 3)
check("a page below the first clamps up", Bundle.Build({ page = 0 }).bundle.page == 1)
check("a page that is not a number is page 1",
  Bundle.Build({ page = "nonsense" }).bundle.page == 1)

warbandOf(20)
local whole = Bundle.Build()
check("a warband that fits in one bundle says nothing about pages",
  whole.bundle.page == nil and whole.bundle.pages == nil)
check("and reports nothing left out", whole.bundle.droppedOverCap == nil)

-- ── every stamped section is one the store knows about ──────────────────────

reset()
local known = {}
for _, section in ipairs(Store.SECTIONS) do known[section] = true end
check("reagentBank is a section /warband status will print", known.reagentBank == true)

CONTAINERS[-1] = container(28)
CONTAINERS[-3] = container(98)
Scan.Bank()
for id = 13, 17 do CONTAINERS[id] = container(98) end
Scan.WarbandBank()
local unknown = {}
for section in pairs(stamps()) do
  if section ~= "lastSeen" and not known[section] then unknown[#unknown + 1] = section end
end
check("a scan stamps no section the wire does not document",
  #unknown == 0, table.concat(unknown, ","))

print("")
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
