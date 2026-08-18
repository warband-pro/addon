-- WarbandPro / Scan.lua
-- Reads the current character only. Never touches another character's data,
-- never calls a protected API, never reads a field off a combat-log or aura
-- result. Every API call goes through ns.safe, because a section that cannot be
-- read must go missing, not throw.

local _, ns = ...

local Scan = {}
ns.Scan = Scan

local Store = ns.Store
local C = C_Container or {}
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Bag ids: read from Enum where the client offers it, fall back to the numbers,
-- so a Midnight rename costs us one section rather than the whole scan.
local function bagID(name, fallback)
  local e = Enum and Enum.BagIndex
  local v = e and e[name]
  if type(v) == "number" then return v end
  return fallback
end

local CARRIED = { bagID("Backpack", 0), bagID("Bag_1", 1), bagID("Bag_2", 2),
                  bagID("Bag_3", 3), bagID("Bag_4", 4), bagID("ReagentBag", 5) }
local BANK    = { bagID("Bank", -1), bagID("BankBag_1", 6), bagID("BankBag_2", 7),
                  bagID("BankBag_3", 8), bagID("BankBag_4", 9), bagID("BankBag_5", 10),
                  bagID("BankBag_6", 11), bagID("BankBag_7", 12) }
local REAGENT_BANK = bagID("Reagentbank", -3)

-- The warband bank is five purchasable tabs today and Blizzard has added tabs
-- before, so probe by name rather than trusting a count.
local function warbandTabs()
  local ids = {}
  for i = 1, 8 do
    local id = bagID("AccountBankTab_" .. i, nil)
    if id then ids[#ids + 1] = id end
  end
  if #ids == 0 then
    for id = 13, 17 do ids[#ids + 1] = id end
  end
  return ids
end

-- Items carry id, count, quality and a bound flag. Name, icon, class and link
-- are all derivable from the id through Game Data on the website, and carrying
-- them would multiply the bundle for nothing. Links stay available behind
-- WarbandProDB.opts.includeLinks for debugging one specific item.
local function scanContainer(id)
  if id == nil then return nil end
  local size = ns.safe(C.GetContainerNumSlots, id) or 0
  if size <= 0 then return nil end
  local links = Store.db and Store.db.opts and Store.db.opts.includeLinks
  local items = {}
  for slot = 1, size do
    local info = ns.safe(C.GetContainerItemInfo, id, slot)
    if info and info.itemID then
      local item = { id = info.itemID, count = info.stackCount or 1 }
      if info.quality then item.quality = info.quality end
      if info.isBound then item.isBound = true end
      if links and info.hyperlink then item.link = info.hyperlink end
      items[#items + 1] = item
    end
  end
  return { bagID = id, size = size, free = ns.safe(C.GetContainerNumFreeSlots, id) or 0, items = items }
end

local function scanList(ids)
  local out = {}
  for i = 1, #ids do
    local bag = scanContainer(ids[i])
    if bag then out[#out + 1] = bag end
  end
  if #out == 0 then return nil end
  return out
end

-- Consumables rollup, derived so the Tonight Plan does not walk every bag on the
-- website. Bucketed by item class rather than by a table of item ids that goes
-- stale every patch: the consumable subclasses (flask, potion, food,
-- enhancement) have been stable for twenty years and Midnight phials are still
-- flasks.
--
-- healthPotion and tempPotion cannot be told apart from each other by class, so
-- they are emitted only for ids listed in POTION_IDS. Until that table is
-- filled they are absent rather than zero, which the contract reads as
-- "unknown" instead of "you have none".
local SUBCLASS = { [1] = "potion", [3] = "phial", [5] = "foodFeast", [6] = "weaponRune" }
local POTION_IDS = {}   -- [itemID] = "healthPotion" | "tempPotion"

local function rollup(bagLists)
  local out = { phial = 0, potion = 0, foodFeast = 0, weaponRune = 0 }
  -- Checked once rather than per item: this runs over every slot the character
  -- owns, and ns.safe on each lookup would cost more than the rollup is worth.
  if type(GetInstant) ~= "function" then return out end
  for _, list in ipairs(bagLists) do
    for _, bag in ipairs(list) do
      for _, item in ipairs(bag.items) do
        local named = POTION_IDS[item.id]
        if named then out[named] = (out[named] or 0) + item.count end
        local _, _, _, _, _, classID, subclassID = GetInstant(item.id)
        if classID == 0 then
          local bucket = SUBCLASS[subclassID]
          if bucket then out[bucket] = out[bucket] + item.count end
        end
      end
    end
  end
  return out
end

function Scan.Identity()
  local c = Store.Char()
  if not c then return end
  local class, classFile, classID = UnitClass("player")
  local realm = GetRealmName()
  c.name = UnitName("player")
  c.realm = realm
  c.realmSlug = ns.slug(realm)
  c.faction = UnitFactionGroup("player")
  c.class = classFile or class
  c.classId = classID
  c.level = UnitLevel("player")
  c.xp = UnitXP("player")
  c.restXP = ns.safe(GetXPExhaustion)
  c.lastZone = ns.safe(GetZoneText)
  c.hearthZone = ns.safe(GetBindLocation)
  local avg, equipped = ns.safe(GetAverageItemLevel)
  if avg then
    c.itemLevelAvg = math.floor(avg + 0.5)
    c.itemLevelEquipped = equipped and math.floor(equipped + 0.5) or nil
  end
  local guild, rank, rankIndex = ns.safe(GetGuildInfo, "player")
  c.guild = guild and { name = guild, rank = rank, rankIndex = rankIndex } or nil
  c.seenAt.lastSeen = ns.now()
end

function Scan.Money()
  Store.Put(nil, "gold", ns.safe(GetMoney))
end

function Scan.Bags()
  local bags = scanList(CARRIED)
  if not bags then return end
  Store.Put("bag", "bags", bags)
  Scan.Consumables()
end

-- Bank contents exist only while the frame is open. Until it has been opened
-- once the field stays absent, which the website shows as "open your bank"
-- rather than as an empty bank.
function Scan.Bank()
  local bank = scanList(BANK)
  local reagent = scanContainer(REAGENT_BANK)
  if not bank and not reagent then return end
  local c = Store.Char()
  if not c then return end
  if bank then c.bank = bank end
  if reagent then c.reagentBank = reagent end
  local now = ns.now()
  c.seenAt.bank, c.seenAt.lastSeen = now, now
  Scan.Consumables()
end

function Scan.WarbandBank()
  local tabs, any = {}, false
  for _, id in ipairs(warbandTabs()) do
    local tab = scanContainer(id)
    if tab then
      any = true
      tabs[#tabs + 1] = tab
    end
  end
  if not any then return end
  -- Warband gold is the one number the tabs do not carry, and it is the whole
  -- reason "can this alt afford the crafting order" is answerable at all.
  local gold = ns.safe(function()
    return C_Bank.FetchDepositedMoney(Enum.BankType.Account)
  end)
  Store.PutWarbandBank(tabs, gold)
end

function Scan.Consumables()
  local c = Store.Char()
  if not c then return end
  local lists = {}
  if c.bags then lists[#lists + 1] = c.bags end
  if c.bank then lists[#lists + 1] = c.bank end
  if c.reagentBank then lists[#lists + 1] = { c.reagentBank } end
  if #lists == 0 then return end
  c.consumables = rollup(lists)
end

-- isAccountWide never changes for a currency and the list is walked on every
-- currency update, so remember it for the session instead of re-asking.
local accountWide = {}

function Scan.Currencies()
  local ci = C_CurrencyInfo
  if not ci then return end
  local size = ns.safe(ci.GetCurrencyListSize) or 0
  if size <= 0 then return end
  local out = {}
  for i = 1, size do
    local info = ns.safe(ci.GetCurrencyListInfo, i)
    if info and not info.isHeader then
      local link = ns.safe(ci.GetCurrencyListLink, i)
      local id = link and tonumber(link:match("currency:(%d+)"))
      if id then
        local wide = info.isAccountWide
        if wide == nil then
          if accountWide[id] == nil then
            local full = ns.safe(ci.GetCurrencyInfo, id)
            accountWide[id] = (full and full.isAccountWide) or false
          end
          wide = accountWide[id]
        end
        out[#out + 1] = {
          id = id,
          name = info.name,
          quantity = info.quantity or 0,
          maxQuantity = info.maxQuantity or 0,
          weeklyMax = info.maxWeeklyQuantity or 0,
          earnedThisWeek = info.quantityEarnedThisWeek,
          isAccountWide = wide or false,
          discovered = info.discovered,
        }
      end
    end
  end
  if #out == 0 then return end
  Store.Put("currency", "currencies", out)
end

-- Skill level and cap only. Recipe counts need the profession window open and a
-- full C_TradeSkillUI walk, which is the most expensive thing this addon could
-- do; the contract already treats knownRecipes as optional.
function Scan.Professions()
  if not GetProfessions then return end
  -- Five slots, any of which may be nil, so collect them by name rather than
  -- through ns.safe's three return values.
  local slots = ns.safe(function()
    local p1, p2, arch, fish, cook = GetProfessions()
    return { p1, p2, arch, fish, cook }
  end) or {}
  local out = {}
  for i = 1, 5 do
    local index = slots[i]
    if index then
      local info = ns.safe(function()
        local name, _, skill, maxSkill, _, _, skillLine = GetProfessionInfo(index)
        return { id = skillLine, name = name, skill = skill, maxLevel = maxSkill }
      end)
      if info and info.name then out[#out + 1] = info end
    end
  end
  if #out == 0 then return end
  Store.Put("profession", "professions", out)
end

-- Mailbox and auction house are readable only while their frame is open, same
-- rule as the bank.
function Scan.Mail()
  if not GetInboxNumItems then return end
  local count = ns.safe(GetInboxNumItems)
  if count == nil then return end
  local gold, items, soonest = 0, 0, nil
  for i = 1, count do
    local mail = ns.safe(function()
      local _, _, _, _, money, _, days, itemCount = GetInboxHeaderInfo(i)
      return { money = money or 0, days = days, items = itemCount or 0 }
    end)
    if mail then
      gold = gold + mail.money
      items = items + mail.items
      if mail.days and (soonest == nil or mail.days < soonest) then soonest = mail.days end
    end
  end
  Store.Put("mail", "mail", {
    countMails = count,
    countItems = items,
    goldPending = gold,
    soonestExpiryHours = soonest and math.floor(soonest * 24) or nil,
  })
end

function Scan.Auctions()
  local ah = C_AuctionHouse
  if not ah then return end
  local n = ns.safe(ah.GetNumOwnedAuctions)
  if n == nil then return end
  Store.Put("auctions", "auctions", { countActive = n })
end

-- Everything readable anywhere, for login and for an explicit /warband copy.
function Scan.All()
  Scan.Identity()
  Scan.Money()
  Scan.Bags()
  Scan.Currencies()
  Scan.Professions()
end
