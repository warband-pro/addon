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

handlers.PLAYER_MONEY = function()
  ns.throttle("money", 1, Scan.Money)
end

local function bags()
  ns.throttle("bags", 0.5, function()
    Scan.Bags()
    Instances.Keystone()   -- the key is an item; it moves when bags move
    Gear.All()              -- bag gear moves when bags move too
  end)
end
handlers.BAG_UPDATE = bags
handlers.BAG_UPDATE_DELAYED = bags

local function currencies()
  ns.throttle("currency", 1, Scan.Currencies)
end
handlers.CURRENCY_DISPLAY_UPDATE = currencies
handlers.CURRENCY_TRANSFER_LOG_UPDATE = currencies

-- Bank contents are readable only while the frame is open, and the warband tabs
-- populate a beat after it opens.
local function banks()
  ns.throttle("bank", 0.5, function()
    Scan.Bank()
    Scan.WarbandBank()
    Gear.All()              -- bank and warband bank gear live in these too
  end)
end
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

local function gear()
  ns.throttle("gear", 1, Gear.All)
end
handlers.PLAYER_EQUIPMENT_CHANGED = gear
handlers.PLAYER_AVG_ITEM_LEVEL_UPDATE = gear

local function talents()
  ns.throttle("talents", 1, Gear.Talents)
end
handlers.TRAIT_CONFIG_UPDATED = talents
handlers.ACTIVE_COMBAT_CONFIG_CHANGED = talents
handlers.PLAYER_SPECIALIZATION_CHANGED = talents

-- The one thing we defer: a panel asked for during a fight.
handlers.PLAYER_REGEN_ENABLED = function()
  if UI.pending then
    local mode = UI.pending
    UI.pending = nil
    UI.Show(mode)
  end
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
      if on then
        Gear.All()
        ns.print("gear capture on — captured now")
      else
        ns.print("gear capture off — stored gear kept, just left out of the next bundle")
      end
    else
      ns.print("saved data not loaded yet")
    end
  else
    ns.print("/warband · /warband copy current · /warband status · /warband optimize · "
      .. "/warband clear <name> · /warband gear on|off")
  end
end
