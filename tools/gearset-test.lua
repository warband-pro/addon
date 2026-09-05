-- Off-client tests for the gear-set path: Import.DecodeGearSet and GearSet.lua.
--
-- The junk-test/import-test split, applied to the second inbound wire. What is
-- pure runs against the golden fixture (`node tools/vector.mjs --write` must
-- have run first); what touches the client runs against a fake paperdoll and
-- fake bags that record every call, because the property under test is an
-- ORDER — every equip lands before the set is saved — and order is exactly
-- what a hand QA pass is worst at checking.
--
--   lua5.1 tools/gearset-test.lua

package.path = "./?.lua;" .. package.path

local DIR = "docs/contract/vectors/"

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

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ── a fake game ─────────────────────────────────────────────────────────────

local function link(s, name)
  return "|cffa335ee|H" .. s .. "|h[" .. name .. "]|h|r"
end

local PAPERDOLL = {}   -- [invSlot] = hyperlink
local BAGS = {}        -- [bagID] = { [slot] = { itemID, hyperlink } }
local CURSOR = nil
local ORDER = {}       -- every game-changing call, in sequence
local TIMERS = {}      -- C_Timer.After callbacks, fired by hand
local SETS = {}        -- [name] = id
local inCombat = false
local nextSetID = 41

_G.UnitGUID = function() return "Player-1-TEST" end
_G.GetInventoryItemLink = function(_, slot) return PAPERDOLL[slot] end
_G.InCombatLockdown = function() return inCombat end
_G.ClearCursor = function() CURSOR = nil end
_G.EquipCursorItem = function(invSlot)
  ORDER[#ORDER + 1] = "equip:" .. invSlot
  if CURSOR and not CURSOR.stuck then PAPERDOLL[invSlot] = CURSOR.hyperlink end
  CURSOR = nil
end
_G.C_Container = {
  GetContainerNumSlots = function(id) return BAGS[id] and 8 or 0 end,
  GetContainerNumFreeSlots = function() return 0 end,
  GetContainerItemInfo = function(id, slot)
    local b = BAGS[id]
    return b and b[slot] or nil
  end,
  PickupContainerItem = function(id, slot)
    ORDER[#ORDER + 1] = "pickup:" .. id .. ":" .. slot
    CURSOR = BAGS[id] and BAGS[id][slot] or nil
  end,
}
_G.C_Timer = {
  After = function(_, fn) TIMERS[#TIMERS + 1] = fn end,
}
-- The spec at the keyboard. `GearSet.Stored` picks the setup matching it, so
-- every resolve below is implicitly "as Feral" until SPEC is moved.
local SPEC = 103
-- What the client says about each spec: the name the set is called and the
-- icon it wears, both read here and never off the wire.
local SPEC_INFO = {
  [102] = { name = "Balance", icon = 136096 },
  [103] = { name = "Feral", icon = 132115 },
  [105] = { name = "Restoration", icon = 136041 },
}
_G.GetSpecialization = function() return SPEC and 1 or nil end
_G.GetSpecializationInfo = function()
  local info = SPEC_INFO[SPEC] or {}
  return SPEC, info.name, nil, info.icon
end
local ICONS = {}       -- [id] = icon the set was created or renamed with
_G.C_EquipmentSet = {
  GetEquipmentSetID = function(name) return SETS[name] end,
  CreateEquipmentSet = function(name, icon)
    ORDER[#ORDER + 1] = "create:" .. name
    SETS[name] = nextSetID
    ICONS[nextSetID] = icon
    nextSetID = nextSetID + 1
  end,
  ModifyEquipmentSet = function(id, name, icon)
    ORDER[#ORDER + 1] = "rename:" .. id .. ":" .. name
    for old, oldID in pairs(SETS) do
      if oldID == id then SETS[old] = nil end
    end
    SETS[name] = id
    ICONS[id] = icon
  end,
  SaveEquipmentSet = function(id) ORDER[#ORDER + 1] = "save:" .. id end,
}

-- ── load the real code ──────────────────────────────────────────────────────

local ns = {}
local inflated = nil
ns.LibDeflate = {
  DecompressDeflate = function(_, _) return inflated end,
}
assert(loadfile("Init.lua"))("WarbandPro", ns)
ns.Store = {
  db = { chars = { ["Player-1-TEST"] = { name = "Vocnar" } } },
  Touch = function() end,
}
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
local printed = {}
ns.print = function(msg) printed[#printed + 1] = msg end
assert(loadfile("Import.lua"))("WarbandPro", ns)
assert(loadfile("GearSet.lua"))("WarbandPro", ns)
local Import, GearSet = ns.Import, ns.GearSet

-- ── decode: the golden vector ───────────────────────────────────────────────

local wire = readAll(DIR .. "wbg1-min.wbg1")
check("fixture exists — run node tools/vector.mjs --write first", wire ~= nil)
wire = wire and wire:gsub("%s+$", "")
inflated = readAll(DIR .. "wbg1-min.json")
-- The stub hands back the pretty JSON; what is under test is our base64url
-- acceptance, our JSON decoder and our validation, same as import-test.
inflated = inflated

-- DecodeGearSet directly, not through DecodeInbound: this block is about the
-- wbg1! decoder's own shape, and the normalisation into a plan is tested where
-- it lives, in import-test.
local decoded, code = Import.DecodeGearSet(wire)
check("golden vector decodes", decoded ~= nil, code)
check("golden generatedAt is seconds", decoded and decoded.generatedAt == 1724001000)
check("golden is keyed by guid", decoded and decoded.chars["Player-1-TEST"] ~= nil)
local entry = decoded and decoded.chars["Player-1-TEST"]
check("golden carries all three items", entry and #entry.items == 3)
check("golden keeps the real finger-2 slot", entry and entry.items[2].slot == 12)
check("golden carries the proposed set name", entry and entry.set == "Feral")
check("golden carries a setup per spec", entry and entry.bySpec ~= nil
  and entry.bySpec[103] ~= nil and entry.bySpec[105] ~= nil)
check("each setup carries its own items", entry and #entry.bySpec[105].items == 1)
check("each setup carries its own name", entry and entry.bySpec[105].set == "Restoration")
check("golden carries the spec", entry and entry.spec == 103)
check("golden keeps w for the missing line", entry and entry.items[3].w == "bank")

-- ── decode: refusals ────────────────────────────────────────────────────────

local function refusal(label, input, want)
  local d, c = Import.DecodeGearSet(input)
  check(label, d == nil and c == want, tostring(c))
end
refusal("names an export string rather than calling it broken", "wb1!AAAA", "is_export")
refusal("names a cleanup string rather than calling it broken", "wbc1!AAAA", "is_cleanup")
refusal("rejects a foreign prefix", "hello there", "wrong_prefix")
refusal("rejects empty", "", "empty")
refusal("rejects an oversize input before inflating it", "wbg1!" .. string.rep("A", 41 * 1024), "too_large")
refusal("rejects a body that is not base64url", "wbg1!!!!!", "not_base64")

inflated = '{"v":2,"generatedAt":1,"chars":[]}'
refusal("rejects a future version", "wbg1!AAAA", "wrong_version")
inflated = '{"v":1,"generatedAt":1,"chars":[]}'
refusal("rejects an empty list", "wbg1!AAAA", "no_items")
inflated = '{"v":1,"generatedAt":1,"chars":[{"guid":"g","items":[{"slot":4,"s":"item:1"},{"slot":18,"s":"item:2"},'
  .. '{"slot":11,"s":""}]}]}'
refusal("drops a cosmetic slot, an unknown slot and an s-less item", "wbg1!AAAA", "no_items")
inflated = '{"v":1,"generatedAt":1,"chars":[{"guid":"g","items":[{"slot":11,"s":"item:1"},{"slot":4,"s":"item:2"}]}]}'
local partial = Import.DecodeGearSet("wbg1!AAAA")
check("keeps the good item beside a malformed one", partial and #partial.chars["g"].items == 1)
check("every gear-set code has a message", Import.GearSetMessage("is_cleanup") ~= Import.GearSetMessage("nonsense"))

-- ── the cleanup decoder refuses the new prefix by name ──────────────────────

local cd, cc = Import.DecodePlan("wbg1!AAAA")
check("DecodePlan names an equip string", cd == nil and cc == "is_gearset", tostring(cc))

-- ── save: guid gating ───────────────────────────────────────────────────────

inflated = readAll(DIR .. "wbg1-min.json")
decoded = Import.DecodeInbound(wire)
check("saves the set for a character this account has", GearSet.Save(decoded) == 1)
check("stores it under the guid", ns.Store.db.gearset["Player-1-TEST"] ~= nil)
check("ignores a guid this account has never scanned",
  GearSet.Save({ generatedAt = 1, chars = { ["Player-9-NOPE"] = { gear = { items = {} } } } }) == 0)

-- Junk.Save's guard, the other way round: one string carries three sections
-- since 1.8.0, and a character can have a clear-out list and no setups.
check("a paste carrying no setups leaves the stored ones alone", (function()
  local before = ns.Store.db.gearset["Player-1-TEST"]
  GearSet.Save({
    generatedAt = 500,
    chars = { ["Player-1-TEST"] = { name = "Vocnar", junk = { { k = "sell", s = "item:1" } } } },
  })
  return ns.Store.db.gearset["Player-1-TEST"] == before
end)())

-- ── builds: which saved talent build is for which night ─────────────────────

check("stores the build assignments", (function()
  local kept = GearSet.SaveBuilds({
    generatedAt = 600,
    chars = { ["Player-1-TEST"] = { builds = { [103] = { raid = 7, mplus = 8 } } } },
  })
  return kept == 1 and ns.Store.db.gearset["Player-1-TEST"].builds[103].raid == 7
end)())

check("answers for the spec being played", GearSet.BuildFor("raid") == 7)
check("and says nothing for a content type with no assignment", GearSet.BuildFor("delve") == nil)

check("never answers with another spec's build", (function()
  SPEC = 105
  local out = GearSet.BuildFor("raid")
  SPEC = 103
  return out == nil
end)())

-- Saving setups must not drop assignments, and saving assignments must not
-- drop setups: an equip string from before 1.8.0 carries no builds at all.
check("a legacy equip string does not erase the assignments", (function()
  inflated = readAll(DIR .. "wbg1-min.json")
  GearSet.Save(Import.DecodeInbound(wire))
  return GearSet.BuildFor("raid") == 7
end)())

check("and saving assignments does not erase the setups", (function()
  GearSet.SaveBuilds({
    generatedAt = 700,
    chars = { ["Player-1-TEST"] = { builds = { [103] = { delve = 9 } } } },
  })
  return GearSet.Stored() ~= nil and GearSet.BuildFor("delve") == 9
end)())

-- The name comes out of the addon's own capture, never the wire: the site
-- sends three numbers, not three talent strings, because the addon already
-- holds the loadouts it exported.
check("names the build out of this character's own loadouts", (function()
  local c = ns.Store.db.chars["Player-1-TEST"]
  c.talents = { specs = { { specID = 103, loadouts = { { id = 9, name = "Delve", s = "CODE" } } } } }
  local name, str = GearSet.BuildName("delve")
  return name == "Delve" and str == "CODE"
end)())

check("says nothing when the assigned build is not one this character has saved", (function()
  local c = ns.Store.db.chars["Player-1-TEST"]
  c.talents = { specs = { { specID = 103, loadouts = { { id = 1, name = "Other" } } } } }
  return GearSet.BuildName("delve") == nil
end)())

-- ── resolve: already / ready / missing ──────────────────────────────────────

-- The stored set wants: helm (slot 1) — in bag 0:2; ring (slot 12) — already
-- worn there; cleaver (slot 16) — nowhere, wire says bank.
local HELM = "item:221151::::::::80:250::4:6:12053:1:28:::"
local RING = "item:215135::::::::80:250::4:6:12053:1:28:::"
PAPERDOLL = {
  [12] = link(RING, "Seal of the Poisoned Pact"),
  [16] = link("item:212050:7228::::::80:251::7:1:28:::", "Old Staff"),
}
BAGS = { [0] = { [2] = { itemID = 221151, hyperlink = link(HELM, "Ironclaw Warhelm") } } }

local r = GearSet.Resolve()
check("resolve finds the worn ring", r and #r.already == 1 and r.already[1].slot == 12)
check("resolve finds the bagged helm with live coordinates",
  r and #r.ready == 1 and r.ready[1].bag == 0 and r.ready[1].bagSlot == 2)
check("resolve aims the helm at its real slot", r and r.ready[1].slot == 1)
check("resolve names the missing cleaver", r and #r.missing == 1 and r.missing[1].w == "bank")
check("resolve names the set after the spec at the keyboard, not the wire", r and r.set == "Feral")
check("and carries the spec's icon for it", r and r.icon == 132115)
check("and knows the names an older build used",
  r and r.legacy[1] == "warband.pro Feral" and r.legacy[2] == "warband.pro" and #r.legacy == 2)
check("an older website's branded proposal is a name to migrate from, looked up first", (function()
  local _, _, legacy = GearSet.SetName({ set = "warband.pro Feral" })
  return legacy[1] == "warband.pro Feral" and #legacy == 3
end)())

-- ── rows: the set as a list a person reads ──────────────────────────────────
-- The Import tab draws one row per item on the wire, in slot order, each with
-- the state Resolve found it in. The model is here so the layout has nothing
-- to decide.

local rows = GearSet.Rows(r)
check("one row per item on the wire", #rows == 3)
check("rows come in slot order, not state order",
  rows[1].slot == 1 and rows[2].slot == 12 and rows[3].slot == 16)
check("a row names its slot as a player would", rows[1].name == "head" and rows[2].name == "ring 2"
  and rows[3].name == "main hand")
check("the bagged helm is ready", rows[1].state == "ready")
check("the worn ring is worn", rows[2].state == "worn")
check("the absent cleaver is missing", rows[3].state == "missing")
check("a row keeps the wire's identity for the tooltip", rows[1].s == HELM and rows[1].id == 221151)
check("no resolve, no rows", #GearSet.Rows(nil) == 0)

local function stateOf(row) local t, tone = GearSet.StateText(row) return t .. "/" .. tone end
check("worn is the quiet mark — AMR's E", stateOf(rows[2]) == "worn/muted")
check("in bags is the good news", stateOf(rows[1]) == "in bags/good")
check("missing from a bank is a walk", stateOf(rows[3]) == "in your bank/warn")
check("missing with no bank hint says the bags", stateOf({ state = "missing" }) == "not in your bags/warn")
check("a slot the table does not know still gets a name", GearSet.Rows({ already = { { slot = 99, s = "x" } } })[1].name
  == "slot 99")

-- ── apply: equips land before the save, and the save snapshots after ────────

ORDER = {}
printed = {}
local applied = GearSet.Apply()
check("apply acts on the resolve", applied ~= nil)
check("apply picked the helm up from the walk's coordinates", ORDER[1] == "pickup:0:2")
check("apply equips into the wire's slot", ORDER[2] == "equip:1")
check("apply saves nothing yet — the server has not answered", #ORDER == 2)
check("apply armed a pending verify", GearSet.pending ~= nil)

-- The fake client equipped instantly, so the event-driven verify confirms.
GearSet.Verify(false)
check("verify created the set, named after the spec", ORDER[3] == "create:Feral")
check("with the spec's icon", ICONS[41] == 132115)
check("verify saved it after every equip", ORDER[4] == "save:41")
check("verify cleared the pending", GearSet.pending == nil)
check("the receipt names the equip, the worn item and the missing one",
  printed[1] ~= nil
    and printed[1]:find("equipped 1", 1, true) ~= nil
    and printed[1]:find("1 already worn", 1, true) ~= nil
    and printed[1]:find("1 missing (1 in your bank)", 1, true) ~= nil
    and printed[1]:find('saved as "Feral"', 1, true) ~= nil,
  printed[1])

-- ── the set an older build saved is renamed, not left beside a new one ──────
-- Until 1.11.0 the set was `warband.pro Feral`. A player updating has one of
-- those already; saving must carry it forward under the new name and icon
-- rather than leave two sets holding the same kit.

SETS, ORDER, printed, ICONS = { ["warband.pro Feral"] = 7 }, {}, {}, {}
GearSet.pending = { set = "Feral", icon = 132115, legacy = { "warband.pro Feral", "warband.pro" },
  items = {}, readyCount = 0, alreadyCount = 0, missingCount = 0, bankCount = 0 }
GearSet.Verify(true)
check("an older build's set is renamed to the spec", ORDER[1] == "rename:7:Feral", tostring(ORDER[1]))
check("and given the spec's icon", ICONS[7] == 132115)
check("and saved — no second set created", ORDER[2] == "save:7" and #ORDER == 2, tostring(ORDER[2]))
check("the receipt names the set as it is now", printed[1] and printed[1]:find('saved as "Feral"', 1, true) ~= nil)

-- A set the player already has under the spec's name is theirs: updated in
-- place, its icon untouched.
SETS, ORDER, printed, ICONS = { ["Feral"] = 3, ["warband.pro Feral"] = 7 }, {}, {}, { [3] = 999 }
GearSet.pending = { set = "Feral", icon = 132115, legacy = { "warband.pro Feral", "warband.pro" },
  items = {}, readyCount = 0, alreadyCount = 0, missingCount = 0, bankCount = 0 }
GearSet.Verify(true)
check("a set the player already calls Feral is the one updated", ORDER[1] == "save:3" and #ORDER == 1,
  tostring(ORDER[1]))
check("and its icon is left alone", ICONS[3] == 999)

-- No spec readable: the wire's proposal is all there is to call it.
SPEC_INFO[103] = nil
local fallback, fallbackIcon, fallbackLegacy = GearSet.SetName({ set = "warband.pro Feral" })
check("with no spec name the wire's proposal names the set", fallback == "warband.pro Feral")
check("under the addon's own icon", fallbackIcon == ns.ICON)
check("and nothing is migrated", #fallbackLegacy == 0)
SPEC_INFO[103] = { name = "Feral", icon = 132115 }

-- ── apply: an equip the server never confirms ───────────────────────────────

PAPERDOLL = {}
BAGS = { [0] = { [1] = { itemID = 221151, hyperlink = link(HELM, "Ironclaw Warhelm"), stuck = true } } }
ORDER, TIMERS, printed = {}, {}, {}
GearSet.Apply()
GearSet.Verify(false)
check("an unconfirmed equip holds the save", #printed == 0 and GearSet.pending ~= nil)
check("the deadline was armed", #TIMERS == 1)
TIMERS[1]()
check("the deadline saves what actually verified", GearSet.pending == nil and printed[1] ~= nil)
check("and says which equip never landed",
  printed[1] and printed[1]:find("1 did not equip", 1, true) ~= nil, printed[1])

-- ── combat: fail closed, never a queue ──────────────────────────────────────

BAGS = { [0] = { [1] = { itemID = 221151, hyperlink = link(HELM, "Ironclaw Warhelm") } } }
inCombat = true
ORDER, printed = {}, {}
check("apply refuses in combat", GearSet.Apply() == nil)
check("and touched nothing", #ORDER == 0)

GearSet.pending = { set = "warband.pro", items = {}, readyCount = 0, alreadyCount = 0, missingCount = 0, bankCount = 0 }
GearSet.Verify(false)
check("combat mid-apply drops the pending save", GearSet.pending == nil)
check("and says to press the button again", printed[1] ~= nil and printed[1]:find("combat", 1, true) ~= nil, printed[1])
inCombat = false

-- ── a setup per spec (1.8.0) ───────────────────────────────────────────────
-- The website can solve any spec since it learned to, so one set per character
-- became wrong: a stored Feral set is not an answer to a Restoration
-- paperdoll. A record that names specs answers only for the one being played.

SPEC = 105
local resto = GearSet.Stored()
check("standing in another spec finds that spec's setup", resto ~= nil and resto.spec == 105)
check("and it is that setup's items, not the primary's", resto and #resto.items == 1)
check("and the wire's own proposal for it rides along", resto and resto.set == "Restoration")
check("but the set is called what the client calls the spec", GearSet.Resolve().set == "Restoration")

SPEC = 102   -- Balance: nothing was ever solved for it
check("a spec with no setup gets nothing rather than another spec's gear", GearSet.Stored() == nil)
local n, mine = GearSet.Summary()
check("but the panel still knows setups exist", n == 2 and mine == false)

SPEC = 103
local _, ferMine = GearSet.Summary()
check("and knows when one is for the spec being played", ferMine == true)

-- An older website sends no `sets`, so the record names no spec per setup and
-- applies to whoever is standing there — which is also the downgrade path.
inflated = '{"v":1,"generatedAt":1,"chars":[{"guid":"Player-1-TEST","items":[{"slot":1,"s":"item:1"}]}]}'
GearSet.Save(Import.DecodeInbound("wbg1!AAAA"))
SPEC = 102
check("an unkeyed record applies to any spec", GearSet.Stored() ~= nil)
SPEC = 103

-- ── the set name is discovered, never assumed ───────────────────────────────
-- C_EquipmentSet enforces a length this addon cannot read, so the full name is
-- tried and shorter ones after it. Here the stub refuses anything over 16.

local LIMIT = 16
_G.C_EquipmentSet.CreateEquipmentSet = function(name)
  ORDER[#ORDER + 1] = "create:" .. name
  if #name > LIMIT then return end
  SETS[name] = nextSetID
  nextSetID = nextSetID + 1
end

-- Spec names are short, so a name this long only reaches the client from a
-- wire proposal on a character whose spec could not be read.
SETS, ORDER, printed = {}, {}, {}
GearSet.pending = { set = "warband.pro Restoration", items = {}, readyCount = 0,
  alreadyCount = 0, missingCount = 0, bankCount = 0 }
GearSet.Verify(true)
check("tries the full name first", ORDER[1] == "create:warband.pro Restoration", tostring(ORDER[1]))
check("falls back until the client accepts one", SETS["warband.pro Rest"] ~= nil)
check("the receipt names the set that actually exists",
  printed[1] ~= nil and printed[1]:find('saved as "warband.pro Rest"', 1, true) ~= nil, printed[1])

-- ── verdict ─────────────────────────────────────────────────────────────────

print(string.format("gearset-test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
