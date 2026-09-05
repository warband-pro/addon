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

-- Exposed so Gear.lua walks the same containers rather than re-deriving the
-- Midnight Enum.BagIndex hedging above.
Scan.CARRIED = CARRIED
Scan.BANK = BANK
Scan.WarbandTabs = warbandTabs

-- One pass over a container, handing each occupied slot to `visit(bagID, slot,
-- info)`. Bags, gear and the consumables rollup all used to walk the same
-- slots separately — a bag move cost three full passes over the same six
-- containers. Returns size, free; both 0 for an empty or unusable container
-- so callers never need a nil check on the numbers.
function Scan.Walk(id, visit)
  if id == nil then return 0, 0 end
  local size = ns.safe(C.GetContainerNumSlots, id) or 0
  if size <= 0 then return 0, 0 end
  for slot = 1, size do
    local info = ns.safe(C.GetContainerItemInfo, id, slot)
    if info and info.itemID then
      visit(id, slot, info)
    end
  end
  return size, ns.safe(C.GetContainerNumFreeSlots, id) or 0
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

local function newCounts()
  return { phial = 0, potion = 0, foodFeast = 0, weaponRune = 0 }
end

local function addCounts(into, id, count)
  local named = POTION_IDS[id]
  if named then into[named] = (into[named] or 0) + count end
  local info = ns.itemInfo(id)
  if info and info.classID == 0 then
    local bucket = SUBCLASS[info.subclassID]
    if bucket then into[bucket] = into[bucket] + count end
  end
end

-- One visitor per container walk, feeding the item list, the consumables
-- rollup and (when gear capture is on) Gear.lua's classification from the
-- single pass Scan.Walk already makes. `where` is the wire's gear scope —
-- "bag" | "bank" | "warbank" — or nil for the reagent bank, which never holds
-- gear (Gear.lua skips a lookup that could only ever come back empty).
local function combinedVisitor(where, links, wantGear, items, gearOut, counts)
  return function(id, slot, info)
    local item = { id = info.itemID, count = info.stackCount or 1 }
    if info.quality then item.quality = info.quality end
    if info.isBound then item.isBound = true end
    if links and info.hyperlink then item.link = info.hyperlink end
    items[#items + 1] = item

    if wantGear then ns.Gear.Visit(where, id, slot, info, gearOut) end
    addCounts(counts, info.itemID, item.count)
  end
end

-- Items carry id, count, quality and a bound flag. Name, icon, class and link
-- are all derivable from the id through Game Data on the website, and carrying
-- them would multiply the bundle for nothing. Links stay available behind
-- WarbandProDB.opts.includeLinks for debugging one specific item.
--
-- `where` gates gear classification; pass false explicitly (reagent bank) to
-- skip it. Returns nil for an empty or closed container, else
-- {bag, gear, consumables} from the one walk.
local function scanContainer(id, where, gearEligible)
  if id == nil then return nil end
  if gearEligible == nil then gearEligible = true end
  local links = Store.db and Store.db.opts and Store.db.opts.includeLinks
  local wantGear = gearEligible and not (Store.db and Store.db.opts and Store.db.opts.includeGear == false)
  local items, gearOut, counts = {}, {}, newCounts()
  local visit = combinedVisitor(where, links, wantGear, items, gearOut, counts)
  local size, free = Scan.Walk(id, visit)
  if size <= 0 then return nil end
  return { bag = { bagID = id, size = size, free = free, items = items }, gear = gearOut, consumables = counts }
end

-- Aggregates scanContainer across every bag in one scope (carried, bank, or
-- warband tabs), so Scan.Bags/Bank/WarbandBank each do exactly one walk of
-- their own containers and nobody else's.
local function scanList(ids, where)
  local bags, gearOut, counts = {}, {}, newCounts()
  for i = 1, #ids do
    local result = scanContainer(ids[i], where)
    if result then
      bags[#bags + 1] = result.bag
      for j = 1, #result.gear do gearOut[#gearOut + 1] = result.gear[j] end
      for key, n in pairs(result.consumables) do counts[key] = (counts[key] or 0) + n end
    end
  end
  if #bags == 0 then return nil end
  return { bags = bags, gear = gearOut, consumables = counts }
end

function Scan.Identity()
  local c = Store.Char()
  if not c then return end
  local class, classFile, classID = UnitClass("player")
  local raceName, raceFile = UnitRace("player")
  local realm = GetRealmName()
  c.name = UnitName("player")
  c.realm = realm
  c.realmSlug = ns.slug(realm)
  c.faction = UnitFactionGroup("player")
  c.class = classFile or class
  c.classId = classID
  c.race = raceFile or raceName
  c.level = UnitLevel("player")
  c.xp = UnitXP("player")
  c.restXP = ns.safe(GetXPExhaustion)
  -- The denominator `restXP` is useless without. Rested is a fraction of a
  -- level, and experience per level is not a constant, so the same 400,000
  -- rested is over a level at 81 and a fraction of one at 89 — a consumer
  -- comparing two characters on the raw number compares nothing. No Blizzard
  -- endpoint publishes experience at all, so if this does not send it, it is
  -- not knowable anywhere.
  c.xpMax = UnitXPMax("player")
  c.lastZone = ns.safe(GetZoneText)
  c.hearthZone = ns.safe(GetBindLocation)
  local avg, equipped = ns.safe(GetAverageItemLevel)
  if avg then
    c.itemLevelAvg = math.floor(avg + 0.5)
    c.itemLevelEquipped = equipped and math.floor(equipped + 0.5) or nil
  end
  local guild, rank, rankIndex = ns.safe(GetGuildInfo, "player")
  c.guild = guild and { name = guild, rank = rank, rankIndex = rankIndex } or nil
  -- No section: identity says the character was at the keyboard, not that any
  -- one section was re-read. Store.Stamp rather than a bare stamp write so the
  -- rev Export.Build caches on moves with it.
  Store.Stamp(nil, c)
end

function Scan.Money()
  Store.Put(nil, "gold", ns.safe(GetMoney))
end

-- Consumables are kept per scope and summed at Scan.Consumables() rather than
-- re-walked from stored items on every bag or bank change — a bag move used
-- to re-derive bank and reagent-bank counts too, for nothing.
Scan.consumableParts = { bag = nil, bank = nil, reagentBank = nil }

function Scan.Bags()
  local result = scanList(CARRIED, "bag")
  if not result then return end
  Store.Put("bag", "bags", result.bags)
  ns.Gear.SetScope("bag", result.gear)
  Scan.consumableParts.bag = result.consumables
  Scan.Consumables()
end

-- Bank contents exist only while the frame is open. Until it has been opened
-- once the field stays absent, which the website shows as "open your bank"
-- rather than as an empty bank. Only touches the parts it actually read: a
-- closed reagent bank must not blank out bank gear that was captured earlier,
-- and vice versa.
--
-- Two containers, two stamps. Until 1.8.0 either one landing moved a single
-- shared `bank` stamp, so a pass that read only the reagent bank reported the
-- bank bags as freshly seen — a green dot on contents nobody had looked at
-- since the last banker visit. Each is stamped only if it was actually read;
-- neither being read leaves both stamps where they were, which is what tells
-- the website how much to trust the old value.
function Scan.Bank()
  local bankResult = scanList(BANK, "bank")
  local reagentResult = scanContainer(REAGENT_BANK, "bank", false)  -- reagent bank never holds gear
  if not bankResult and not reagentResult then return end
  local c = Store.Char()
  if not c then return end
  if bankResult then
    c.bank = bankResult.bags
    ns.Gear.SetScope("bank", bankResult.gear)
    Scan.consumableParts.bank = bankResult.consumables
    Store.Stamp("bank", c)
  end
  if reagentResult then
    c.reagentBank = reagentResult.bag
    Scan.consumableParts.reagentBank = reagentResult.consumables
    Store.Stamp("reagentBank", c)
  end
  Scan.Consumables()
end

-- How many warband tabs the account has purchased, or nil when this client will
-- not say. It is the only denominator that separates a partial read from a
-- small vault: an unread tab and an unbought tab both report zero slots, so
-- counting what came back can never tell them apart on its own. Through
-- ns.safe, so a client without the call costs us the completeness claim rather
-- than the scan — absent, not guessed.
function Scan.WarbandTabsOwned()
  local data = ns.safe(function()
    return C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
  end)
  if type(data) ~= "table" then return nil end
  local n = #data
  if n <= 0 then return nil end
  return n
end

-- Not part of the consumables rollup — the original rollup only ever read
-- c.bags/c.bank/c.reagentBank, and this keeps that scope.
--
-- The tabs merge in Store.PutWarbandBank, so a pass that saw three of five
-- updates three and leaves two alone. The gear scope cannot do that: a gear
-- row records the equip slot it would fill, not the container it was found
-- in, so there is no key to merge a partial warbank result on. Replacing the
-- scope from a partial read would drop the gear in every tab that did not
-- load, so a partial read leaves the gear scope untouched and the next
-- complete read replaces it — the last walk of a banker visit is the one with
-- every tab loaded, which is exactly when the replace should happen.
function Scan.WarbandBank()
  local tabs, gearOut, any = {}, {}, false
  for _, id in ipairs(warbandTabs()) do
    local result = scanContainer(id, "warbank")
    if result then
      any = true
      tabs[#tabs + 1] = result.bag
      for j = 1, #result.gear do gearOut[#gearOut + 1] = result.gear[j] end
    end
  end
  if not any then return end
  -- Warband gold is the one number the tabs do not carry, and it is the whole
  -- reason "can this alt afford the crafting order" is answerable at all.
  local gold = ns.safe(function()
    return C_Bank.FetchDepositedMoney(Enum.BankType.Account)
  end)
  local owned = Scan.WarbandTabsOwned()
  Store.PutWarbandBank(tabs, gold, owned)
  if not owned or #tabs >= owned then
    ns.Gear.SetScope("warbank", gearOut)
  end
end

function Scan.Consumables()
  local c = Store.Char()
  if not c then return end
  local parts = Scan.consumableParts
  if not parts.bag and not parts.bank and not parts.reagentBank then return end
  local out = newCounts()
  for _, part in pairs(parts) do
    if part then
      for key, n in pairs(part) do out[key] = (out[key] or 0) + n end
    end
  end
  c.consumables = out
  -- Derived from sections that stamped themselves, so it carries no stamp of
  -- its own — but it does change the bundle, and Export.Build's cache is keyed
  -- on Store.rev.
  Store.Touch()
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
  ns.Gear.All()
  ns.Gear.Talents()
end
