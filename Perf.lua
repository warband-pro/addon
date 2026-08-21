-- WarbandPro / Perf.lua
-- /warband perf. Wraps the scan entry points in place, after they are
-- defined, so this file is purely additive: delete it and drop its line from
-- the .toc and every other file is unchanged.
--
-- Two profiler reads per scan, never per slot — the overhead has to be noise
-- against a several-hundred-slot walk or the numbers it produces are lying.
-- debugprofilestop() read twice and subtracted is the standard WoW addon
-- microbenchmark idiom; debugprofilestart() is a different, session-wide
-- profiler switch and is not what this needs.

local _, ns = ...

local Perf = {}
ns.Perf = Perf

local timers = {}                          -- label -> {calls, totalMs, maxMs, lastMs}
local walks = { containers = 0, slots = 0 }
local deferred = 0

local function timer(label)
  local t = timers[label]
  if not t then
    t = { calls = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
    timers[label] = t
  end
  return t
end

-- Wraps tbl[name] in place under display name `label` (defaults to name).
local function wrap(tbl, name, label)
  local fn = tbl and tbl[name]
  if type(fn) ~= "function" then return end
  local t = timer(label or name)
  tbl[name] = function(...)
    local start = debugprofilestop()
    local r1, r2, r3, r4 = fn(...)
    local ms = debugprofilestop() - start
    t.calls = t.calls + 1
    t.totalMs = t.totalMs + ms
    t.lastMs = ms
    if ms > t.maxMs then t.maxMs = ms end
    return r1, r2, r3, r4
  end
end

for _, name in ipairs({ "Bags", "Bank", "WarbandBank", "Currencies", "Consumables", "All" }) do
  wrap(ns.Scan, name, "Scan." .. name)
end
for _, name in ipairs({ "All", "Equipped", "Talents" }) do
  wrap(ns.Gear, name, "Gear." .. name)
end

-- Scan.Walk is the one place every container read passes through (bags,
-- bank, warband tabs, all of it), so counting there gives a true per-flush
-- slot count without instrumenting Scan.lua itself.
local rawWalk = ns.Scan.Walk
ns.Scan.Walk = function(bagID, visit)
  walks.containers = walks.containers + 1
  return rawWalk(bagID, function(bID, slot, info)
    walks.slots = walks.slots + 1
    return visit(bID, slot, info)
  end)
end

-- Bumped from Init.lua's dirty-set flush whenever InCombatLockdown() holds a
-- flush back — this file just reads that counter, it does not own it.
function Perf.Reset()
  for _, t in pairs(timers) do
    t.calls, t.totalMs, t.maxMs, t.lastMs = 0, 0, 0, 0
  end
  walks.containers, walks.slots = 0, 0
  deferred = ns.combatDeferred or 0
end

local function fmtMs(n)
  return format("%.2fms", n)
end

function Perf.Report()
  local nowDeferred = (ns.combatDeferred or 0) - deferred
  ns.print(format("containers walked %d, slots visited %d, combat-deferred flushes %d, dirty scopes pending %d",
    walks.containers, walks.slots, nowDeferred, ns.dirtyCount and ns.dirtyCount() or 0))

  local names = {}
  for name in pairs(timers) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local t = timers[name]
    if t.calls > 0 then
      ns.print(format("  %s: %d call%s, last %s, max %s, total %s",
        name, t.calls, t.calls == 1 and "" or "s", fmtMs(t.lastMs), fmtMs(t.maxMs), fmtMs(t.totalMs)))
    end
  end

  local cacheN = ns.itemInfoCount and ns.itemInfoCount() or 0
  local stats = ns.itemInfoStats or { hits = 0, misses = 0 }
  local total = stats.hits + stats.misses
  local hitPct = total > 0 and format("%.0f%%", stats.hits / total * 100) or "n/a"
  ns.print(format("item-info cache: %d entr%s, %d hit%s / %d miss%s (%s hit rate)",
    cacheN, cacheN == 1 and "y" or "ies",
    stats.hits, stats.hits == 1 and "" or "s", stats.misses, stats.misses == 1 and "" or "es", hitPct))

  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    ns.print(format("memory: %.1f KB", GetAddOnMemoryUsage(ns.ADDON)))
  end
  if GetCVar and GetCVar("scriptProfile") == "1" and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
    UpdateAddOnCPUUsage()
    ns.print(format("CPU (scriptProfile on): %.2fms", GetAddOnCPUUsage(ns.ADDON)))
  else
    ns.print("CPU: scriptProfile is off — SetCVar(\"scriptProfile\",\"1\") and /reload for a real figure")
  end
end
