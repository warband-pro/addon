-- WarbandPro / Init.lua
-- Namespace, constants, and the handful of helpers every other file uses.
-- Owns no data and registers no events — that is Store.lua and Core.lua.

local ADDON, ns = ...

_G.WarbandPro = ns          -- one deliberate global, for /dump and QA macros

ns.ADDON      = ADDON
ns.WIRE       = "wb1!"      -- wb0! is Camp DNA. Gear and talents also live on wb1!, additively; wb2! stays reserved.
ns.CLEANUP_WIRE = "wbc1!"   -- the return direction: the cleanup list warband.pro sends back
ns.GEARSET_WIRE = "wbg1!"   -- the other return direction: a gear set to equip and save, added in 1.6.0
ns.WIRE_V     = 1
ns.MAX_CHARS  = 20          -- CONTRACT.md rejects a bundle larger than this
ns.SOFT_BYTES = 20480       -- past this the panel warns instead of pretending

-- The addon's face, in one place. It is the window's portrait and the minimap
-- button, and `WarbandPro.toc` names the same texture again for the addon
-- compartment because a .toc cannot read a Lua value. Two copies, and the .toc
-- is the one that will drift, so change this line and grep for the other.
--
-- A texture already in the player's client, never a file we ship — the addon
-- carries no artwork at all, which is docs/POLICY.md's line and also why there
-- is nothing here to keep in sync with a CurseForge avatar.
ns.ICON = "Interface\\Icons\\inv_enchant_voidcrystal"

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "0.0.0-dev"
if ns.VERSION:find("@") then ns.VERSION = "0.0.0-dev" end   -- unbuilt @project-version@

-- LibDeflate hands itself out with `return`, which WoW discards for a file loaded
-- from a .toc, so Vendor/LibDeflate.lua assigns ns.LibDeflate at its foot. That
-- assignment is unreachable on most real clients: when LibStub already holds an
-- equal or newer LibDeflate, upstream returns from the main chunk long before it,
-- and LibStub is a global the moment any addon that bundles it loads first. The
-- vendored copy is still the one we ship and the one that runs on a bare client;
-- this is the fallback for when someone else got there first. The 1.0.x
-- CompressDeflate signature is what we depend on, and it is stable across them.
ns.LibDeflate = ns.LibDeflate or (LibStub and LibStub:GetLibrary("LibDeflate", true))

-- Freshness thresholds, in seconds. The web draws the same dots from the same
-- numbers; if these move, warband.pro's importer moves with them.
ns.FRESH_GREEN  = 6 * 3600
ns.FRESH_YELLOW = 3 * 86400
ns.STALE_PRUNE  = 90 * 86400

-- ── helpers ─────────────────────────────────────────────────────────────────

-- Unix seconds. GetServerTime is the same clock the reset timers use.
function ns.now()
  if GetServerTime then return GetServerTime() end
  return time()
end

-- Every WoW API call goes through here. Midnight renamed and moved enough of
-- the container and bank surface that a nil field must cost us one section of
-- one snapshot, never a Lua error in the middle of the user's raid.
ns.lastError = nil
ns.errorCount = 0
function ns.safe(fn, a, b, c)
  if type(fn) ~= "function" then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if ok then return r1, r2, r3 end
  ns.lastError = tostring(r1)
  ns.errorCount = ns.errorCount + 1
  return nil
end

-- Trailing-edge throttle. One timer per key. Nothing in this addon watches the
-- game on an OnUpdate — the one OnUpdate that exists is installed by the minimap
-- button while it is being dragged and removed when the mouse comes up, and what
-- it reads is the player's hand rather than anything the client is doing.
local pending = {}
function ns.throttle(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    ns.safe(fn)
  end)
end

-- Immutable per-item facts: equip location, item class, item subclass. All
-- three come from GetItemInfoInstant and none of them can change for a given
-- item id in this session, so asking again on every scan is pure waste — the
-- same reasoning as the accountWide memo Scan.lua keeps for currencies.
-- Cached here, not in Gear.lua or Scan.lua, because both read it.
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local itemInfoCache = {}
ns.itemInfoStats = { hits = 0, misses = 0 }

-- Field order is GetItemInfoInstant's actual return list — itemID, itemType,
-- itemSubType, itemEquipLoc, icon, classID, subClassID — so equipLoc is
-- position 4. This line used to read it at position 5, which is the icon file
-- id: EQUIPLOC_SLOT is keyed by INVTYPE_* strings, so every bag, bank and
-- warband-tab item missed the lookup and Gear.Visit dropped every one, from
-- 1.1.0 until this fix. Equipped gear walks fixed slot numbers and never
-- consults equipLoc, which is why the wire looked populated the whole time.
-- tools/gear-test.lua stands a fake client in front of this and fails loudly
-- if the destructuring ever drifts again. Routed through ns.safe, not a bare
-- pcall: a bad id must cost this one lookup, not (as Scan.lua's old
-- unprotected rollup could) the whole scan it is part of.
local function rawItemInfo(id)
  local _, _, _, equipLoc, _, classID, subclassID = GetInstant(id)
  return { equipLoc = equipLoc, classID = classID, subclassID = subclassID }
end

function ns.itemInfo(id)
  if type(id) ~= "number" or type(GetInstant) ~= "function" then return nil end
  local cached = itemInfoCache[id]
  if cached then
    ns.itemInfoStats.hits = ns.itemInfoStats.hits + 1
    return cached
  end
  ns.itemInfoStats.misses = ns.itemInfoStats.misses + 1
  local info = ns.safe(rawItemInfo, id)
  if not info then return nil end
  itemInfoCache[id] = info
  return info
end

function ns.itemInfoCount()
  local n = 0
  for _ in pairs(itemInfoCache) do n = n + 1 end
  return n
end

-- Coalesced dirty-set flush for container/gear/talent work: an event marks a
-- scope dirty, one timer flushes every scope marked since the last flush in
-- one pass. A loot mid-equip-swap used to schedule a bag walk and a gear walk
-- as two unrelated throttle keys even though they read the same slots; this
-- collapses that to one flush, and fails closed in combat the same way the
-- export panel already does (see Core.lua's PLAYER_REGEN_ENABLED handler) —
-- a full-bag loot mid-pull must not cost a container walk mid-frame.
local dirtyScopes = {}
local dirtyPending = false
local dirtyHandlers = {}
local DIRTY_DELAY = 0.5
ns.combatDeferred = 0

function ns.onDirty(scope, fn)
  dirtyHandlers[scope] = fn
end

local function flushDirty()
  dirtyPending = false
  if next(dirtyScopes) == nil then return end
  if InCombatLockdown and InCombatLockdown() then
    -- Leave the scopes marked; PLAYER_REGEN_ENABLED flushes them once the
    -- fight ends.
    ns.combatDeferred = ns.combatDeferred + 1
    return
  end
  local scopes = dirtyScopes
  dirtyScopes = {}
  for scope in pairs(scopes) do
    local fn = dirtyHandlers[scope]
    if fn then ns.safe(fn) end
  end
end

function ns.dirty(scope)
  dirtyScopes[scope] = true
  if dirtyPending then return end
  dirtyPending = true
  C_Timer.After(DIRTY_DELAY, flushDirty)
end

-- Exposed so PLAYER_REGEN_ENABLED can drain anything combat deferred the
-- moment the fight ends, without waiting another DIRTY_DELAY. A no-op call
-- when nothing is pending.
ns.flushDirty = flushDirty

function ns.dirtyCount()
  local n = 0
  for _ in pairs(dirtyScopes) do n = n + 1 end
  return n
end

function ns.print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff8be9fdwarband.pro|r " .. tostring(msg))
end

-- "Wyrmrest Accord" -> "wyrmrest-accord", matching the slug warband.pro keys on.
function ns.slug(realm)
  if type(realm) ~= "string" or realm == "" then return nil end
  local s = realm:lower():gsub("'", ""):gsub("%s+", "-"):gsub("[^%w%-]", "")
  return s
end

-- Seconds since a stamp, or nil if never seen. Shared by the panel header.
function ns.age(stamp)
  if type(stamp) ~= "number" or stamp <= 0 then return nil end
  local d = ns.now() - stamp
  if d < 0 then return 0 end
  return d
end

function ns.ago(stamp)
  local d = ns.age(stamp)
  if not d then return "never" end
  if d < 90 then return d .. "s ago" end
  if d < 5400 then return math.floor(d / 60) .. "m ago" end
  if d < 172800 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- The dot the panel and the website both draw from one stamp.
function ns.dot(stamp)
  local d = ns.age(stamp)
  if not d then return "never" end
  if d < ns.FRESH_GREEN then return "green" end
  if d < ns.FRESH_YELLOW then return "yellow" end
  return "red"
end
