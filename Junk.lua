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

--- Store a decoded cleanup payload. Only the entry for a guid this account
--- actually has is kept: a string is per-warband, and the rest of it belongs to
--- characters that will read it when they log in.
function Junk.Save(decoded)
  local db = Store.db
  if not db or type(decoded) ~= "table" then return 0 end
  db.junk = db.junk or {}
  local kept = 0
  for guid, entry in pairs(decoded.chars) do
    if db.chars[guid] then
      db.junk[guid] = { generatedAt = decoded.generatedAt, items = entry.items }
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
        }
      end
      -- Greys are found here rather than sent over the wire: the website's
      -- copy of your bags is as old as your last paste, and a vendor-trash
      -- list is only useful if it is about what you are carrying now.
      if info.quality == 0 then
        greys[#greys + 1] = {
          bag = bagID,
          slot = slot,
          link = info.hyperlink,
          name = itemName(info.hyperlink),
          quality = 0,
          grey = true,
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
          rows[#rows + 1] = {
            bag = m.bag,
            slot = m.slot,
            link = m.link,
            name = m.name or ("item " .. tostring(v.id or "?")),
            quality = m.quality,
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

--- What the row says it is for. `del` is advice only — nothing in this addon
--- deletes an item, and the game would not let it.
function Junk.VerdictLabel(row, canDisenchant)
  if row.grey then return "sell" end
  if row.k == "de" then return canDisenchant and "disenchant" or "sell" end
  if row.k == "del" then return "delete by hand" end
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
