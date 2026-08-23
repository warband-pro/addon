-- WarbandPro / Core.lua
-- The dispatcher: one frame, one event table, one slash command. Loads last so
-- everything it wires up already exists.
--
-- Nothing here polls. Every scan hangs off an event the game already fires, and
-- the noisy ones are throttled so a full-bag loot does not cost twenty scans.

local _, ns = ...

local Store, Scan, Instances, Gear, UI = ns.Store, ns.Scan, ns.Instances, ns.Gear, ns.UI

local frame = CreateFrame("Frame", "WarbandProEventFrame")

-- Some of these names moved in Midnight. Registering an unknown event throws,
-- so ask for each one on its own and let the ones that exist stick.
local EVENTS = {
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
  "PLAYER_REGEN_DISABLED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
  "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED",
  "PLAYER_MONEY", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
  "CURRENCY_DISPLAY_UPDATE", "CURRENCY_TRANSFER_LOG_UPDATE",
  "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
  "ACCOUNT_BANK_TAB_DATA_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED",
  "UPDATE_INSTANCE_INFO", "BOSS_KILL", "ENCOUNTER_END",
  "WEEKLY_REWARDS_UPDATE", "CHALLENGE_MODE_COMPLETED",
  "MAIL_INBOX_UPDATE", "OWNED_AUCTIONS_UPDATED",
  "SKILL_LINES_CHANGED",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE",
  "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
}

local registered = {}
for _, event in ipairs(EVENTS) do
  if pcall(frame.RegisterEvent, frame, event) then registered[event] = true end
end

-- ── handlers ────────────────────────────────────────────────────────────────

local handlers = {}

handlers.ADDON_LOADED = function(addon)
  if addon ~= ns.ADDON then return end
  Store.Init()
end

handlers.PLAYER_LOGIN = function()
  Store.Init()
  Gear.Seed()   -- before any scan: rebuilds this session's scope tables from storage
  Scan.All()
  Instances.Request()
  Instances.Vault()
end

handlers.PLAYER_ENTERING_WORLD = function()
  ns.throttle("identity", 2, function()
    Scan.Identity()
    Scan.Money()
    Instances.Request()
  end)
end

-- A ding is the one identity fact that used to need a loading screen to be
-- noticed. `Scan.Identity` was reachable only from PLAYER_LOGIN and
-- PLAYER_ENTERING_WORLD, so levelling in the open world left the stored level
-- one behind until the next zone or relog — and `/warband copy` in between
-- exported the old number as if it were current.
--
-- Its own throttle key rather than "identity": sharing PLAYER_ENTERING_WORLD's
-- would let a ding taken a second before a loading screen swallow that
-- handler's Money and Instances.Request too.
--
-- One second, because UnitLevel("player") is what Scan.Identity reads and both
-- events can arrive a frame before the unit itself reports the new value.
-- Registered as a pair: PLAYER_LEVEL_UP is the ding, PLAYER_LEVEL_CHANGED also
-- covers the level moving for any other reason, and the loop above drops
-- whichever name this client does not have.
local function dinged()
  ns.throttle("levelup", 1, Scan.Identity)
end
handlers.PLAYER_LEVEL_UP = dinged
handlers.PLAYER_LEVEL_CHANGED = dinged

handlers.PLAYER_MONEY = function()
  ns.throttle("money", 1, Scan.Money)
end

-- Container and gear/talent work is coalesced through the dirty-set scheduler
-- (ns.dirty / ns.onDirty, Init.lua) instead of a throttle key per scope: a
-- loot mid-equip-swap used to schedule a bag walk and a gear walk separately
-- even though Scan.lua now reads bag gear during the same pass it reads bag
-- items. It also fails closed in combat, same as the export panel below —
-- a full-bag loot mid-pull must not cost a container walk mid-frame.
ns.onDirty("bag", function()
  Scan.Bags()
  Instances.Keystone()   -- the key is an item; it moves when bags move
end)
handlers.BAG_UPDATE = function() ns.dirty("bag") end
handlers.BAG_UPDATE_DELAYED = function()
  ns.dirty("bag")
  -- Only while the panel is up: this is a re-render of something on screen,
  -- not a scan, and it must not become a fourth walk that runs all session.
  if UI.JunkIsShown() then ns.throttle("junk", 0.3, UI.RenderJunk) end
end

local function currencies()
  ns.throttle("currency", 1, Scan.Currencies)
end
handlers.CURRENCY_DISPLAY_UPDATE = currencies
handlers.CURRENCY_TRANSFER_LOG_UPDATE = currencies

-- Bank contents are readable only while the frame is open, and the warband
-- tabs populate a beat after it opens — walked together, same as before.
ns.onDirty("bank", function()
  Scan.Bank()
  Scan.WarbandBank()
end)
local function banks() ns.dirty("bank") end
handlers.BANKFRAME_OPENED = banks
handlers.PLAYERBANKSLOTS_CHANGED = banks
handlers.PLAYERREAGENTBANKSLOTS_CHANGED = banks
handlers.ACCOUNT_BANK_TAB_DATA_CHANGED = banks
handlers.BANK_TABS_CHANGED = banks
handlers.BANK_TAB_SETTINGS_UPDATED = banks

handlers.UPDATE_INSTANCE_INFO = function()
  ns.throttle("instances", 2, function()
    Instances.Lockouts()
    Instances.Keystone()
  end)
end

local function askForLockouts()
  ns.throttle("raidinfo", 3, Instances.Request)
end
handlers.BOSS_KILL = askForLockouts
handlers.ENCOUNTER_END = askForLockouts
handlers.CHALLENGE_MODE_COMPLETED = function()
  ns.throttle("mplus", 3, Instances.Keystone)
end

handlers.WEEKLY_REWARDS_UPDATE = function()
  ns.throttle("vault", 1, Instances.Vault)
end

handlers.MAIL_INBOX_UPDATE = function()
  ns.throttle("mail", 1, Scan.Mail)
end

handlers.OWNED_AUCTIONS_UPDATED = function()
  ns.throttle("auctions", 1, Scan.Auctions)
end

handlers.SKILL_LINES_CHANGED = function()
  ns.throttle("professions", 2, Scan.Professions)
end

ns.onDirty("equipped", Gear.All)
handlers.PLAYER_EQUIPMENT_CHANGED = function() ns.dirty("equipped") end
handlers.PLAYER_AVG_ITEM_LEVEL_UPDATE = function() ns.dirty("equipped") end

ns.onDirty("talents", Gear.Talents)
handlers.TRAIT_CONFIG_UPDATED = function() ns.dirty("talents") end
handlers.ACTIVE_COMBAT_CONFIG_CHANGED = function() ns.dirty("talents") end
handlers.PLAYER_SPECIALIZATION_CHANGED = function() ns.dirty("talents") end

-- The two things we defer: anything the window queued or closed during a
-- fight (UI.AfterCombat reopens it exactly once), and any container/gear/
-- talent scope the dirty scheduler held back for the same reason (ns.dirty in
-- Init.lua).
handlers.PLAYER_REGEN_ENABLED = function()
  ns.flushDirty()
  UI.AfterCombat()
end

-- Secure attributes cannot be written in combat, so the Import tab closes
-- rather than going stale behind the player — a stale row holds a bag slot,
-- and a bag slot that moved is the wrong item. The Export tab holds no secure
-- state and stays put.
handlers.PLAYER_REGEN_DISABLED = function()
  UI.CombatLockdown()
end

-- Selling is the one thing this addon does that changes the game, and it is
-- possible only while a merchant window is open. The flag is set from the
-- event rather than read from a frame, so nothing has to guess. The UI call
-- keeps the Sell buttons honest and carries the "open the clear-out list at
-- merchants" option.
handlers.MERCHANT_SHOW = function()
  ns.Junk.merchantOpen = true
  UI.MerchantChanged(true)
end

handlers.MERCHANT_CLOSED = function()
  ns.Junk.merchantOpen = false
  UI.MerchantChanged(false)
end

frame:SetScript("OnEvent", function(_, event, arg1)
  local handler = handlers[event]
  if handler then ns.safe(handler, arg1) end
end)

-- ── slash ───────────────────────────────────────────────────────────────────

local eventCount = 0
for _ in pairs(registered) do eventCount = eventCount + 1 end

local function status()
  local db = Store.db
  if not db then
    ns.print("saved data not loaded yet")
    return
  end
  local lastExport = db.lastExport
  local str, bytes, _, rawBytes = ns.Export.Build()
  ns.print(format("%d character%s stored, %d of %d events registered, addon v%s",
    Store.Count(), Store.Count() == 1 and "" or "s", eventCount, #EVENTS, ns.VERSION))
  ns.print(format("bundle: %s %d bytes from %d of JSON%s",
    str and ns.WIRE or "|cffff5555failed|r", bytes or 0, rawBytes or 0,
    lastExport > 0 and (", last copied " .. ns.ago(lastExport)) or ""))
  -- The panel sends people here with "status has the detail", so a failed build
  -- has to say why. Not every reason is a failed API call, and the errorCount
  -- line below only fires for those, so this one is separate on purpose.
  if not str and ns.lastError then
    ns.print("|cffff5555bundle error|r: " .. tostring(ns.lastError))
  end
  local c = Store.Char()
  if c then
    local parts = {}
    for _, section in ipairs(Store.SECTIONS) do
      parts[#parts + 1] = section .. " " .. ns.ago(c.seenAt[section])
    end
    ns.print((c.name or "this character") .. ": " .. table.concat(parts, ", "))
    local gearCount = c.gear and #c.gear or 0
    local specNames = {}
    if c.talents and c.talents.specs then
      for _, sp in ipairs(c.talents.specs) do
        specNames[#specNames + 1] = sp.name or ("spec " .. tostring(sp.specID))
      end
    end
    ns.print(format("gear: %d piece%s%s%s", gearCount, gearCount == 1 and "" or "s",
      db.opts.includeGear and "" or "  |cfff1fa8c(off — /warband gear on)|r",
      #specNames > 0 and ("  ·  talents known: " .. table.concat(specNames, ", ")) or ""))
  end
  local wb = db.warbandBank
  ns.print(format("warband bank: %s%s", ns.ago(wb.seenAt),
    wb.seenByName and (" (by " .. wb.seenByName .. ")") or ""))
  if ns.errorCount > 0 then
    ns.print(format("|cfff1fa8c%d API call%s failed|r, last: %s",
      ns.errorCount, ns.errorCount == 1 and "" or "s", tostring(ns.lastError)))
  end
end

SLASH_WARBANDPRO1 = "/warband"
SlashCmdList.WARBANDPRO = function(msg)
  local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if cmd == "" or cmd == "copy" then
    UI.Show("bundle")
  elseif cmd == "copy current" or cmd == "current" then
    UI.Show("current")
  elseif cmd == "status" then
    status()
  elseif cmd == "optimize" then
    local n = Store.Prune()
    ns.print(format("pruned %d character%s not seen in 90 days", n, n == 1 and "" or "s"))
  elseif cmd:match("^clear ") then
    local name = cmd:match("^clear%s+(.+)$")
    local n = Store.Forget(name)
    ns.print(n > 0 and format("removed %s", name) or format("no stored character called %s", name))
  elseif cmd == "gear on" or cmd == "gear off" then
    local on = cmd == "gear on"
    if Store.Ready() then
      Store.db.opts.includeGear = on
      Store.Touch()
      if on then
        Scan.Bags()   -- current bag contents; equipped and the rest follow
        Gear.All()
        ns.print("gear capture on — captured now")
      else
        ns.print("gear capture off — stored gear kept, just left out of the next bundle")
      end
    else
      ns.print("saved data not loaded yet")
    end
  elseif cmd == "junk" or cmd == "clean" then
    UI.ToggleJunk()
  elseif cmd == "options" then
    UI.ShowOptions()
  elseif cmd == "perf" then
    ns.Perf.Report()
  elseif cmd == "perf reset" then
    ns.Perf.Reset()
    ns.print("perf counters reset")
  else
    ns.print("/warband · /warband copy current · /warband junk · /warband options · /warband status · "
      .. "/warband optimize · /warband clear <name> · /warband gear on|off · /warband perf")
  end
end
