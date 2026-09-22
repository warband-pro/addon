-- Off-client tests for the generated vault choice capture: what a vault pass
-- stores, what it must never destroy, and the one transition that clears.
--
--   lua5.1 tools/vault-test.lua
--
-- Instances.Vault is WoW-bound, so docs/TESTING.md files the reading itself
-- under "manual checklist". What is tested here is the bookkeeping either
-- side of it — which pass may write `vaultChoices`, which stamp it moves,
-- and what an empty read may overwrite — and that is where being wrong is
-- invisible: every failure this file guards against leaves a stamp that
-- looks right and data that is not.
--
-- Three of them would have shipped:
--
--   * a claim wiping nothing, so the site kept ranking choices already
--     taken — a stale pick presented as tonight's answer;
--   * a fresh week's empty read wiping last week's choices before the
--     site's reset gate had anything to age out;
--   * a currency or quest reward landing on the wire as an "item" the
--     best-in-bags solve would then try to equip.

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

local NOW = 1724000000

local CHEST, RING, KEYSTONE, BAUBLE = 250456, 215135, 999999, 555001

local ITEMS = {
  [CHEST] = { equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 4 },
  [RING] = { equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0 },
  [KEYSTONE] = { equipLoc = "INVTYPE_RELIC", classID = 0, subclassID = 0 },
  -- An equip slot nothing here recognises: shaped to nil, never stored.
  [BAUBLE] = { equipLoc = "INVTYPE_HOLDABLE", classID = 4, subclassID = 0 },
}

local ILVL = { [CHEST] = 681, [RING] = 675, [KEYSTONE] = 700, [BAUBLE] = 670 }

local function link(id, name)
  return "|Hitem:" .. id .. "::::::::80:250|h[" .. name .. "]|h"
end

local LINKS = {
  ["dbid-chest"] = link(CHEST, "Cuirass of Dawn"),
  ["dbid-ring"] = link(RING, "Seal of the Poisoned Pact"),
  ["dbid-key"] = link(KEYSTONE, "Keystone"),
  ["dbid-bauble"] = link(BAUBLE, "Bauble of Holding"),
}

local STATS = {
  ["dbid-chest"] = { ITEM_MOD_CRIT_RATING_SHORT = 612 },
}

-- Scripted per case: the activities GetActivities returns, the example links,
-- the generated hyperlinks by itemDBID, and whether the server holds offers.
local ACTIVITIES, EXAMPLES, GENLINKS, HAS_AVAILABLE = {}, {}, {}, false
local NO_HYPERLINK_FN, NO_HASAVAIL_FN = false, false

local CHEST_TYPES = {
  Raid = 3, Activities = 1, MythicPlus = 7, World = 6, RankedPvP = 2,
}

local function setEnum(withCached)
  if withCached then
    _G.Enum = {
      WeeklyRewardChestThresholdType = CHEST_TYPES,
      CachedRewardType = { None = 0, Item = 1, Currency = 2, Quest = 3 },
    }
  else
    _G.Enum = { WeeklyRewardChestThresholdType = CHEST_TYPES }
  end
end

setEnum(true)

_G.C_WeeklyRewards = {
  GetActivities = function() return ACTIVITIES end,
  GetExampleRewardItemHyperlinks = function(id) return EXAMPLES[id] end,
  GetItemHyperlink = function(dbid)
    if NO_HYPERLINK_FN then error("no such API on this client") end
    return GENLINKS[dbid]
  end,
  HasAvailableRewards = function()
    if NO_HASAVAIL_FN then error("no such API on this client") end
    return HAS_AVAILABLE
  end,
}

_G.C_Item = {
  GetDetailedItemLevelInfo = function(ln)
    return ILVL[tonumber((ln:match("item:(%d+)")))]
  end,
  GetItemStats = function(ln)
    for dbid, target in pairs(LINKS) do
      if target == ln then return STATS[dbid] end
    end
    return nil
  end,
  IsItemKeystoneByID = function(id) return id == KEYSTONE end,
}

_G.UnitGUID = function() return "Player-1-TEST" end
_G.tinsert = table.insert

local ns = {
  WIRE_V = 1,
  now = function() return NOW end,
  print = function() end,
  safe = function(fn, a, b, c)
    if type(fn) ~= "function" then return nil end
    local ok, r1, r2, r3 = pcall(fn, a, b, c)
    if ok then return r1, r2, r3 end
    return nil
  end,
  itemInfo = function(id) return ITEMS[id] end,
}

ns.Gear = {
  SlotFor = function(loc)
    if loc == "INVTYPE_CHEST" then return 5 end
    if loc == "INVTYPE_FINGER" then return 11 end
    return nil
  end,
  IsTierSlot = function(slot) return slot == 5 end,
  SetID = function() return 9999 end,
}

_G.WarbandProDB = {}
assert(loadfile("Store.lua"))("WarbandPro", ns)
assert(loadfile("Instances.lua"))("WarbandPro", ns)
local Store, Instances = ns.Store, ns.Instances
Store.Init()

local function resetClient()
  ACTIVITIES, EXAMPLES, GENLINKS, HAS_AVAILABLE = {}, {}, {}, false
  NO_HYPERLINK_FN, NO_HASAVAIL_FN = false, false
  setEnum(true)
  _G.WarbandProDB = {}
  Store.Init()
end

local function act(typename, progress, threshold, id, rewards)
  return {
    type = CHEST_TYPES[typename], progress = progress, threshold = threshold,
    level = 14, id = id, rewards = rewards,
  }
end

local function itemReward(id, dbid)
  return { type = 1, id = id, quantity = 1, itemDBID = dbid }
end

local function char()
  return Store.db.chars["Player-1-TEST"]
end

-- ── the passes ──────────────────────────────────────────────────────────────

do
  -- A vault earned but never opened: progress with no offers behind it.
  resetClient()
  ACTIVITIES = { act("Activities", 8, 8, 11), act("Raid", 2, 4, 21) }
  Instances.Vault()
  local c = char()
  check("an unopened vault stores progress", c.weeklyVault ~= nil)
  check("an unopened vault stores no choices", c.vaultChoices == nil)
  check("an unopened vault stamps no choice read",
    c.seenAt.vaultChoices == nil)
  check("an unopened vault claims nothing", c.vaultClaimedAt == nil)
  check("the pass itself is still stamped", c.seenAt.vault == NOW)
end

do
  -- The refactor guard: the example `r` shapes exactly as before.
  resetClient()
  EXAMPLES[11] = LINKS["dbid-chest"]
  ACTIVITIES = { act("Activities", 8, 8, 11) }
  Instances.Vault()
  local r = char().weeklyVault.mplus.rows[1].r
  check("the example reward still shapes",
    r ~= nil and r.id == CHEST and r.slot == 5 and r.ilvl == 681)
  check("the example carries stats and set",
    r.st ~= nil and r.set == 9999)
end

do
  -- Opening the vault puts the generated offers in the payload, stamped.
  -- Currency and quest rewards are not items and never ride along.
  resetClient()
  GENLINKS = { ["dbid-chest"] = LINKS["dbid-chest"],
               ["dbid-ring"] = LINKS["dbid-ring"] }
  ACTIVITIES = {
    act("Activities", 8, 8, 11, {
      itemReward(CHEST, "dbid-chest"),
      { type = 2, id = 1337, quantity = 5, itemDBID = "dbid-crest" },
      { type = 3, id = 99, quantity = 1, itemDBID = "dbid-quest" },
    }),
    act("Raid", 4, 4, 21, { itemReward(RING, "dbid-ring") }),
  }
  HAS_AVAILABLE = true
  local c = Store.Char()
  c.vaultClaimedAt = NOW - 9999
  Instances.Vault()
  c = char()
  check("two generated offers stored", c.vaultChoices ~= nil
    and #c.vaultChoices == 2, c.vaultChoices and #c.vaultChoices)
  local got = c.vaultChoices or {}
  local a, b = got[1], got[2]
  check("offers name their buckets", a ~= nil and b ~= nil
    and a.b == "mplus" and b.b == "raid")
  check("offers carry the item shape", a ~= nil
    and a.id == CHEST and a.slot == 5 and a.ilvl == 681
    and a.s == "item:250456::::::::80:250" and a.set == 9999)
  check("the ring has no set to carry", b ~= nil
    and b.set == nil and b.id == RING)
  check("an offer is never somewhere", a ~= nil and a.where == nil)
  check("the choice read is stamped", c.seenAt.vaultChoices == NOW)
  check("a new read clears the old claim", c.vaultClaimedAt == nil)
end

do
  -- A keystone, an uncached link and an unrecognised slot are declined, and
  -- a pass that resolves one of three still stores that one.
  resetClient()
  GENLINKS = { ["dbid-ring"] = LINKS["dbid-ring"] }
  ACTIVITIES = {
    act("Activities", 8, 8, 11, {
      itemReward(KEYSTONE, "dbid-key"),
      itemReward(CHEST, "dbid-chest"),
      itemReward(BAUBLE, "dbid-bauble"),
      itemReward(RING, "dbid-ring"),
    }),
  }
  HAS_AVAILABLE = true
  Instances.Vault()
  local c = char()
  local only = c.vaultChoices or {}
  check("only the resolvable ring stores", #only == 1
    and only[1] ~= nil and only[1].id == RING, #only)
  -- A fuller read an hour later repairs the partial one.
  NOW = NOW + 3600
  GENLINKS["dbid-chest"] = LINKS["dbid-chest"]
  Instances.Vault()
  c = char()
  local fuller = c.vaultChoices or {}
  check("the fuller read repairs the partial one", #fuller == 2, #fuller)
  check("the stamp moves with the fuller read",
    c.seenAt.vaultChoices == NOW)
end

do
  -- The claim transition: offers stored, slots still earned, the server no
  -- longer holding anything. The choices go; the moment is stamped.
  resetClient()
  GENLINKS = { ["dbid-ring"] = LINKS["dbid-ring"] }
  ACTIVITIES = { act("Activities", 8, 8, 11,
    { itemReward(RING, "dbid-ring") }) }
  HAS_AVAILABLE = true
  Instances.Vault()
  local readAt = char().seenAt.vaultChoices
  NOW = NOW + 3600
  ACTIVITIES = { act("Activities", 8, 8, 11) }
  HAS_AVAILABLE = false
  Instances.Vault()
  local c = char()
  check("claimed choices leave the payload", c.vaultChoices == nil)
  check("the claim is stamped", c.vaultClaimedAt == NOW)
  check("the old choice read keeps its stamp",
    c.seenAt.vaultChoices == readAt)
  -- A second pass changes nothing: the wipe happens once.
  NOW = NOW + 3600
  Instances.Vault()
  c = char()
  check("the claim stamp is not re-stamped", c.vaultClaimedAt == NOW - 3600)
end

do
  -- Generated but not yet readable: the server still holds offers, so an
  -- empty read keeps what we stored rather than calling it claimed.
  resetClient()
  local c = Store.Char()
  c.vaultChoices = { { b = "mplus", slot = 5, id = CHEST } }
  c.seenAt.vaultChoices = NOW - 100
  ACTIVITIES = { act("Activities", 8, 8, 11) }
  HAS_AVAILABLE = true
  Instances.Vault()
  c = char()
  check("held offers are kept, not wiped", c.vaultChoices ~= nil
    and #c.vaultChoices == 1)
  check("no claim is stamped for held offers", c.vaultClaimedAt == nil)
end

do
  -- A fresh week with nothing earned: the old value stays for the site's
  -- reset gate to age out. The addon does not destroy what it cannot date.
  resetClient()
  local c = Store.Char()
  c.vaultChoices = { { b = "mplus", slot = 5, id = CHEST } }
  c.seenAt.vaultChoices = NOW - 604800
  ACTIVITIES = { act("Activities", 0, 8, 11) }
  HAS_AVAILABLE = false
  Instances.Vault()
  c = char()
  check("a fresh week keeps last week's choices", c.vaultChoices ~= nil)
  check("a fresh week claims nothing", c.vaultClaimedAt == nil)
end

do
  -- An API too old to answer HasAvailableRewards: keep, never destroy.
  resetClient()
  local c = Store.Char()
  c.vaultChoices = { { b = "mplus", slot = 5, id = CHEST } }
  ACTIVITIES = { act("Activities", 8, 8, 11) }
  NO_HASAVAIL_FN = true
  Instances.Vault()
  c = char()
  check("an unanswerable server keeps the choices", c.vaultChoices ~= nil)
  check("an unanswerable server claims nothing", c.vaultClaimedAt == nil)
end

do
  -- A client without the CachedRewardType names: the numbers still work.
  resetClient()
  setEnum(false)
  GENLINKS = { ["dbid-chest"] = LINKS["dbid-chest"] }
  ACTIVITIES = { act("Activities", 8, 8, 11, {
    itemReward(CHEST, "dbid-chest"),
    { type = 2, id = 1337, quantity = 5, itemDBID = "dbid-crest" },
  }) }
  HAS_AVAILABLE = true
  Instances.Vault()
  local c = char()
  check("the numeric item type still stores", c.vaultChoices ~= nil
    and #c.vaultChoices == 1)
end

do
  -- No weekly-rewards API at all: the previous answer stands untouched.
  resetClient()
  ACTIVITIES = { act("Activities", 8, 8, 11) }
  Instances.Vault()
  local before = char().weeklyVault
  _G.C_WeeklyRewards = nil
  Instances.Vault()
  check("a silent client keeps the previous vault",
    char().weeklyVault == before)
  _G.C_WeeklyRewards = {
    GetActivities = function() return ACTIVITIES end,
    GetExampleRewardItemHyperlinks = function(id) return EXAMPLES[id] end,
    GetItemHyperlink = function(dbid) return GENLINKS[dbid] end,
    HasAvailableRewards = function() return HAS_AVAILABLE end,
  }
end

if fail > 0 then
  print(pass .. " passed, " .. fail .. " failed")
  os.exit(1)
else
  print(pass .. " passed, " .. fail .. " failed")
end
