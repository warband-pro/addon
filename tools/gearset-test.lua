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
_G.C_EquipmentSet = {
  GetEquipmentSetID = function(name) return SETS[name] end,
  CreateEquipmentSet = function(name)
    ORDER[#ORDER + 1] = "create:" .. name
    SETS[name] = nextSetID
    nextSetID = nextSetID + 1
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

local decoded, code = Import.DecodeGearSet(wire)
check("golden vector decodes", decoded ~= nil, code)
check("golden generatedAt is seconds", decoded and decoded.generatedAt == 1724001000)
check("golden is keyed by guid", decoded and decoded.chars["Player-1-TEST"] ~= nil)
local entry = decoded and decoded.chars["Player-1-TEST"]
check("golden carries all three items", entry and #entry.items == 3)
check("golden keeps the real finger-2 slot", entry and entry.items[2].slot == 12)
check("golden carries the set name", entry and entry.set == "warband.pro")
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

local cd, cc = Import.DecodeCleanup("wbg1!AAAA")
check("DecodeCleanup names an equip string", cd == nil and cc == "is_gearset", tostring(cc))

-- ── save: guid gating ───────────────────────────────────────────────────────

inflated = readAll(DIR .. "wbg1-min.json")
decoded = Import.DecodeGearSet(wire)
check("saves the set for a character this account has", GearSet.Save(decoded) == 1)
check("stores it under the guid", ns.Store.db.gearset["Player-1-TEST"] ~= nil)
check("ignores a guid this account has never scanned",
  GearSet.Save({ generatedAt = 1, chars = { ["Player-9-NOPE"] = { items = {} } } }) == 0)

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
check("resolve carries the set name", r and r.set == "warband.pro")

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
check("verify created the set", ORDER[3] == "create:warband.pro")
check("verify saved it after every equip", ORDER[4] == "save:41")
check("verify cleared the pending", GearSet.pending == nil)
check("the receipt names the equip, the worn item and the missing one",
  printed[1] ~= nil
    and printed[1]:find("equipped 1", 1, true) ~= nil
    and printed[1]:find("1 already worn", 1, true) ~= nil
    and printed[1]:find("1 missing (1 in your bank)", 1, true) ~= nil
    and printed[1]:find('saved as "warband.pro"', 1, true) ~= nil,
  printed[1])

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

-- ── verdict ─────────────────────────────────────────────────────────────────

print(string.format("gearset-test: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
