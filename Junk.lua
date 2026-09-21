-- WarbandPro / Junk.lua
-- The stored cleanup list, resolved against the bags that exist right now.
--
-- The whole design turns on one decision, recorded in docs/CONTRACT.md: the
-- wire carries **no bag coordinates**. A position captured when the export was
-- made is stale by the time the cleanup string comes back — the player looted,
-- sold, sorted, ran a dungeon — and `UseContainerItem` on a slot that moved
-- sells whatever is sitting there now. That is the one failure this feature
-- must never have, and the only way to be certain of it is to never carry a
-- coordinate anyone could believe.
--
-- So a verdict names an item by its item string, and this file walks the live
-- bags to find it. A verdict finds the item it was written about, or it finds
-- nothing and the panel says how many went missing. Every coordinate handed to
-- an action comes from the walk that just happened.
--
-- A verdict applies to EVERY live match of its string. Two items with the same
-- item string are the same item in every respect the game exposes — the string
-- carries uniqueID — so there is no copy to choose between.

local _, ns = ...

local Junk = {}
ns.Junk = Junk

local Store = ns.Store
local C = C_Container

-- Enchanting's skill line, as GetProfessionInfo reports it. Matches
-- ENCHANTING_SKILL_LINE in the website's cleanup.ts.
local ENCHANTING = 333

Junk.merchantOpen = false

--- The stored list for the character at the keyboard, or nil.
function Junk.Stored()
  local db = Store.db
  if not db or not db.junk then return nil end
  local guid = ns.safe(UnitGUID, "player")
  if not guid then return nil end
  return db.junk[guid]
end

--- Store the cleanup half of a decoded plan. Only the entry for a guid this
--- account actually has is kept: a string is per-warband, and the rest of it
--- belongs to characters that will read it when they log in.
---
--- **A character with no `junk` section is skipped, not cleared.** Since
--- 1.8.0 one string carries the clear-out list, the gear setups and the build
--- assignments together, and a character can legitimately have setups and
--- nothing to sell. Writing an absent section would make pasting a
--- gear-and-talents string silently delete a cleanup list the player still
--- wants — the same "absent means unknown, not empty" rule the whole outbound
--- wire runs on, applied on the way back in.
function Junk.Save(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" or type(decoded.chars) ~= "table" then return 0 end
  db.junk = db.junk or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    if db.chars[guid] and entry.junk then
      db.junk[guid] = { generatedAt = decoded.generatedAt, items = entry.junk }
      kept = kept + 1
    end
  end
  Store.Touch()
  return kept
end

--- How many characters currently hold a stored cleanup list.
---
--- Read before a paste overwrites one, so the receipt can say the new list
--- replaced something rather than leaving the player to notice that their
--- previous list is gone.
function Junk.Count()
  local db = Store.db
  if not db or type(db.junk) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(db.junk) do n = n + 1 end
  return n
end

--- Whether this character can disenchant, checked live rather than trusted from
--- the export. A profession dropped since then would otherwise leave a button
--- that casts nothing.
function Junk.CanDisenchant()
  if not GetProfessions then return false end
  local slots = ns.safe(function()
    local p1, p2 = GetProfessions()
    return { p1, p2 }
  end) or {}
  for i = 1, 2 do
    local index = slots[i]
    if index then
      local line = ns.safe(function()
        local _, _, _, _, _, _, skillLine = GetProfessionInfo(index)
        return skillLine
      end)
      if line == ENCHANTING then return true end
    end
  end
  return false
end

local function itemString(link)
  if type(link) ~= "string" then return nil end
  return link:match("|H(item[^|]+)|h")
end

local function itemName(link)
  if type(link) ~= "string" then return nil end
  local name = link:match("|h%[(.-)%]|h")
  if name == "" then return nil end
  return name
end

--- What one of this item sells to a vendor for, in copper, or nil.
---
--- The sell price is position 11 of `C_Item.GetItemInfo`'s return list, read
--- positionally because that is the only place the client states it — the
--- instant lookup `ns.itemInfo` uses does not carry it. Gear.lua reads position
--- 16 the same way for the same reason.
---
--- **nil and zero are different answers and the difference is the whole point.**
--- `GetItemInfo` answers nothing at all for an item this session has never
--- seen, and a nil read must never take a working Sell button away from a row
--- the vendor would in fact have bought. So nil means "not cached, assume it
--- sells" and only a literal zero means the vendor refuses — a quest item, a
--- token, the things that answer a click with "the vendor doesn't want this"
--- and nothing else. `Junk.Sellable` reads that zero; the vendor window's
--- sell-all totals the positive ones.
---
--- Gear.lua avoids this call on a warband bank scan because it is the slow,
--- cache-dependent one. The same caution does not apply here: the only items
--- asked about are greys and list matches in the **carried** bags, which the
--- client has cached by definition, and the question is only asked while a
--- panel or the vendor button is drawing itself.
local function sellPrice(link)
  if type(link) ~= "string" then return nil end
  local info = C_Item and C_Item.GetItemInfo
  if type(info) ~= "function" then return nil end
  return ns.safe(function()
    return (select(11, info(link)))
  end)
end

--- Everything currently in the carried bags, indexed by item string, plus the
--- grey stacks.
---
--- One pass over the carried bags only. The bank is deliberately not walked:
--- its contents are not reachable from a merchant, and a row for something the
--- player cannot act on right now is a row that cannot be cleared.
local function scanCarried()
  local byString, greys = {}, {}
  for _, bag in ipairs(ns.Scan.CARRIED) do
    ns.Scan.Walk(bag, function(bagID, slot, info)
      local s = itemString(info.hyperlink)
      if s then
        local list = byString[s]
        if not list then
          list = {}
          byString[s] = list
        end
        list[#list + 1] = {
          bag = bagID,
          slot = slot,
          link = info.hyperlink,
          name = itemName(info.hyperlink),
          quality = info.quality,
          -- A stack sells whole, so the vendor button's total is the unit price
          -- times this. The price itself is read in Resolve, for the rows that
          -- turn out to need it rather than for every slot walked.
          count = info.stackCount or 1,
        }
      end
      -- Greys are found here rather than sent over the wire: the website's
      -- copy of your bags is as old as your last paste, and a vendor-trash
      -- list is only useful if it is about what you are carrying now.
      if info.quality == 0 then
        local greyPrice = sellPrice(info.hyperlink)
        greys[#greys + 1] = {
          bag = bagID,
          slot = slot,
          link = info.hyperlink,
          name = itemName(info.hyperlink),
          quality = 0,
          count = info.stackCount or 1,
          grey = true,
          price = greyPrice,
          nosell = greyPrice == 0,
          k = "sell",
          r = "grey",
        }
      end
    end)
  end
  return byString, greys
end

--- The stored verdicts matched against live bags.
---
--- Returns `rows` (one per live item, in stored order then greys), `missing`
--- (verdicts that matched nothing) and `generatedAt`.
function Junk.Resolve()
  local stored = Junk.Stored()
  local byString, greys = scanCarried()
  local rows, missing = {}, 0

  if stored then
    for _, v in ipairs(stored.items) do
      local matches = byString[v.s]
      if matches then
        for _, m in ipairs(matches) do
          -- Asked here rather than in the bag walk: a warband with full bags is
          -- two hundred slots and a handful of verdicts, and this is the slow
          -- cache-dependent call `sellPrice`'s header warns about.
          local price = sellPrice(m.link)
          rows[#rows + 1] = {
            bag = m.bag,
            slot = m.slot,
            link = m.link,
            name = m.name or ("item " .. tostring(v.id or "?")),
            quality = m.quality,
            count = m.count or 1,
            price = price,
            nosell = price == 0,
            k = v.k,
            r = v.r,
            g = v.g,
            ilvl = v.ilvl,
          }
        end
      else
        missing = missing + 1
      end
    end
  end

  for _, g in ipairs(greys) do
    rows[#rows + 1] = g
  end

  return rows, missing, stored and stored.generatedAt or nil
end

--- Sell one row at the open merchant.
---
--- Guarded on the merchant actually being open rather than on the button being
--- enabled: the frame can close between a render and a click, and
--- UseContainerItem outside a merchant window equips or uses the item instead,
--- which is a far worse outcome than doing nothing.
function Junk.Sell(bag, slot)
  if not Junk.merchantOpen then return false end
  if type(bag) ~= "number" or type(slot) ~= "number" then return false end
  ns.safe(C.UseContainerItem, bag, slot)
  return true
end

--- The macro text a secure button runs to disenchant one bag slot.
---
--- Disenchanting is a spell cast at an item, which is protected: an addon may
--- not do it, and may only put a secure button under the player's own click.
--- The button is built once and its attributes are re-baked out of combat —
--- see UI.lua, which hides the whole panel on PLAYER_REGEN_DISABLED.
function Junk.DisenchantMacro(bag, slot)
  if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
  local spell = ns.safe(C_Spell and C_Spell.GetSpellName, 13262) or "Disenchant"
  return "/cast " .. spell .. "\n/use " .. bag .. " " .. slot
end

--- Whether a row is a candidate for the disenchant fallback.
---
--- Quality is the whole test — uncommon or better, and never a grey. It is
--- deliberately not the site's `de` verdict: this answers the question the site
--- was never asked, which is what to offer instead of a sale the vendor will
--- refuse. A wrong yes costs a secure button the game declines to cast; a wrong
--- no costs the player the one action left, so the test errs toward offering.
function Junk.Disenchantable(row)
  if type(row) ~= "table" or row.grey then return false end
  return type(row.quality) == "number" and row.quality >= 2
end

--- Whether this row's `[Sell]` button should exist at all.
---
--- **The one predicate, and the reason it is a function rather than the two
--- lines it replaces.** The panel row asks it and so does the vendor-window
--- sell-all, so the count on that button can never disagree with the buttons
--- the player can see. Two copies of `k ~= "del"` would have drifted the first
--- time either grew a case.
---
--- It answers "is a sale on offer here", not "is a sale what the list
--- recommends": a `de` row on an enchanter still carries a live Sell beside its
--- Disenchant, as it always has. A caller that wants sell-verdict rows only
--- pairs this with `VerdictLabel`.
function Junk.Sellable(row)
  if type(row) ~= "table" then return false end
  -- The vendor's own answer beats the site's: a verdict of sell on an item
  -- with no sell price is a button that can only ever print "the vendor
  -- doesn't want this".
  if row.nosell then return false end
  return row.k ~= "del" or row.grey == true
end

--- What the row says it is for. `del` is advice only — nothing in this addon
--- deletes an item, and the game would not let it.
---
--- **An item the vendor will not buy falls back the same way a `de` row does
--- without the profession**, and that symmetry is the point: the panel already
--- reads "sell" for a disenchant it cannot do, so it reads "disenchant" — or,
--- failing that, "delete by hand" — for a sale it cannot make. The verdict
--- column is the one the player reads before clicking, so it is the column that
--- has to be honest about what is actually on offer.
function Junk.VerdictLabel(row, canDisenchant)
  if row.grey then
    -- A grey with no sell price is the one grey nobody can do anything with.
    return row.nosell and "delete by hand" or "sell"
  end
  if row.k == "del" then return "delete by hand" end
  if row.k == "de" then
    if canDisenchant then return "disenchant" end
    return row.nosell and "delete by hand" or "sell"
  end
  if row.nosell then
    if canDisenchant and Junk.Disenchantable(row) then return "disenchant" end
    return "delete by hand"
  end
  return "sell"
end

--- The one-line reason, built only from what the verdict carried.
---
--- An `r` this build does not know reads "" and the row still offers its
--- action, which is what lets warband.pro add a reason without waiting on an
--- addon release. It is also the whole reason `dupe` could ship on wbc1! v1:
--- a spare-copy verdict is one the website only sends when EVERY live match is
--- surplus — the copy it is measuring against is on the player's body, not in
--- a bag — so "apply to every match" is already correct and an older build
--- offering all of them was never going to sell something it should not.
function Junk.ReasonText(row)
  if row.grey then return "grey" end
  if row.r == "unusable" then return "cannot wear" end
  -- "already wearing one", not "duplicate": the fact the verdict rests on is
  -- that a copy is on the body, and that is what the player can check in a
  -- glance before clicking sell.
  if row.r == "dupe" then return "already wearing one" end
  -- "you own a better one" rather than "worse": the player is about to sell
  -- something, and the fact that makes that safe is the other item, not this
  -- one's shortcoming.
  if row.r == "dominated" then return "you own a better one" end
  if row.r == "gap" and row.g then return row.g .. " behind" end
  return ""
end

-- ── selling the whole list ──────────────────────────────────────────────────
--
-- The panel's per-row Sell buttons are for picking; this is for the job the
-- player actually came to the vendor to do. It lives in Junk.lua rather than
-- in UI.lua for the reason Roster.lua exists: what gets sold and what it is
-- worth is a decision, and a decision that only exists inside a frame is one
-- no test can audit. UI.lua is left with a button and a confirm.

--- Copper as the game writes it — "45g 20s", zero parts left out.
---
--- Not `GetCoinTextureString`: this text goes into a StaticPopup and into a
--- chat line, and the icon form is unreadable at the popup's font size and
--- carries no meaning into a log the player scrolls back through.
function Junk.Money(copper)
  if type(copper) ~= "number" or copper < 0 then return "0c" end
  copper = math.floor(copper)
  local parts = {}
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

--- Which resolved rows a sell-all would sell, how many, and what they are worth.
---
--- **`Sellable` alone is not the test, and that is deliberate.** It answers
--- "is a sale on offer", which is true of a `de` row on an enchanter — that row
--- carries a live Sell beside its Disenchant so the player can overrule the
--- advice one item at a time. Overruling it twelve items at a time under one
--- confirm is not the same act, so the sell-all takes only rows whose verdict
--- *is* sell: the site said sell, or it is a grey. Pairing the two predicates
--- is what `Junk.Sellable`'s own header says a caller wanting sell-verdict rows
--- should do.
---
--- `total` is a floor rather than a guess. A row whose price the client has not
--- cached is still sold — the same asymmetry `sellPrice` is built on — but it
--- contributes nothing to the total and is counted in `unpriced` so the confirm
--- can say "at least" instead of quietly understating the take.
function Junk.SellPlan(rows, canDisenchant)
  local plan = { rows = {}, count = 0, total = 0, unpriced = 0 }
  if type(rows) ~= "table" then return plan end
  for _, row in ipairs(rows) do
    if Junk.Sellable(row) and Junk.VerdictLabel(row, canDisenchant) == "sell" then
      plan.rows[#plan.rows + 1] = row
      plan.count = plan.count + 1
      -- A stack sells whole, so the price is per item and the take is not.
      if type(row.price) == "number" and row.price > 0 then
        plan.total = plan.total + row.price * (row.count or 1)
      else
        plan.unpriced = plan.unpriced + 1
      end
    end
  end
  return plan
end

--- The plan for the bags as they are this instant.
---
--- Thin on purpose: it exists so that neither the button's label nor the
--- confirm can be built from a walk anybody made earlier. Bags change between
--- the paste and the vendor visit, and between opening the vendor and pressing
--- the button — a coordinate from a stale walk sells whatever is sitting in
--- that slot now, which is the one failure this file's header forbids.
function Junk.SellPlanNow()
  local rows = Junk.Resolve()
  return Junk.SellPlan(rows, Junk.CanDisenchant())
end

--- Sell every row in a plan. Returns how many sold and what they came to.
---
--- Merchant-gated twice over — here and inside `Junk.Sell` — because the frame
--- can close between the confirm and the loop, and `UseContainerItem` off a
--- merchant equips or uses the item instead.
---
--- No timer and no batching: the player's click on the confirm is the hardware
--- event that drives this, and a loop that continued on a timer afterwards
--- would be selling without one.
function Junk.SellAll(plan)
  if not Junk.merchantOpen then return 0, 0 end
  if type(plan) ~= "table" or type(plan.rows) ~= "table" then return 0, 0 end
  local sold, copper = 0, 0
  for _, row in ipairs(plan.rows) do
    if Junk.Sell(row.bag, row.slot) then
      sold = sold + 1
      if type(row.price) == "number" and row.price > 0 then
        copper = copper + row.price * (row.count or 1)
      end
    end
  end
  return sold, copper
end
