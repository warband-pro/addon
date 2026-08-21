-- WarbandPro / Init.lua
-- Namespace, constants, and the handful of helpers every other file uses.
-- Owns no data and registers no events — that is Store.lua and Core.lua.

local ADDON, ns = ...

_G.WarbandPro = ns          -- one deliberate global, for /dump and QA macros

ns.ADDON      = ADDON
ns.WIRE       = "wb1!"      -- wb0! is Camp DNA. Gear and talents also live on wb1!, additively; wb2! stays reserved.
ns.WIRE_V     = 1
ns.MAX_CHARS  = 20          -- CONTRACT.md rejects a bundle larger than this
ns.SOFT_BYTES = 20480       -- past this the panel warns instead of pretending

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

-- Trailing-edge throttle. One timer per key, no OnUpdate anywhere in this addon.
local pending = {}
function ns.throttle(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    ns.safe(fn)
  end)
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
