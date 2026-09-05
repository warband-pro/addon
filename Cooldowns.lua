-- WarbandPro / Cooldowns.lua
-- Trade skill cooldowns: which alt can transmute, mill or forge again tonight.
-- SavedInstances' trade skill row, which is one of the two things people name
-- when they say that addon saved them a login.
--
-- **A cooldown is stored as an absolute `readyTime`, and an elapsed one is the
-- answer rather than a stale row.** This is the exact inverse of the lockout
-- rule in Instances.lua, and the two are worth reading together: a lockout past
-- its `resetTime` is known to be GONE, so drawing it would state something
-- false; a cooldown past its ready time is known to be READY, which is the most
-- useful thing this group can say. Same absolute stamp, same arithmetic against
-- the same clock, opposite conclusions — so the timer is converted once, here,
-- and every surface downstream reads a number instead of a countdown that was
-- true when it was written.
--
-- `readyTime` is therefore always a number and never nil: a recipe with no
-- cooldown running is ready NOW, and `now` says that in the same units as
-- everything else. A row with no `readyTime` at all would have to be read as
-- "unknown", which is what an absent row already means.
--
-- **No static table of spell ids.** SavedInstances carries a per-expansion list
-- of trade skill cooldown spells and grows it every patch; we walk what the
-- open profession window actually lists, which is the same move Roster.lua
-- makes about currencies and Instances.lua makes about lockouts. The cost is
-- that a recipe becomes known to have a cooldown the first time we see it on
-- one — and from then on it is remembered and reported ready, which is the
-- state worth knowing anyway.
--
-- **Readable only while the profession window is open**, the same as the bank
-- and the mailbox: `C_TradeSkillUI` answers for the skill line the client
-- currently has loaded and for nothing else. That is why Store.lua merges these
-- by skill line rather than replacing the list — a walk of Alchemy must not
-- erase what we know about Blacksmithing — and why they carry their own
-- `professionCooldown` stamp instead of sharing `profession`, which
-- SKILL_LINES_CHANGED moves at every login.

local _, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

local Store = ns.Store

-- Which profession the window is showing, and what the client calls it.
--
-- Two APIs, because this one moved: `GetBaseProfessionInfo` is the modern
-- answer and `GetTradeSkillLine` is the one that has survived every rename so
-- far. Neither is worth failing the whole read over, so the fallback is a
-- fallback rather than a version check — the same shape as Init.lua's
-- LibDeflate handoff and Core.lua's per-event registration.
local function openLine()
  local api = C_TradeSkillUI
  if type(api) ~= "table" then return nil end

  local info = ns.safe(api.GetBaseProfessionInfo)
  if type(info) == "table" and type(info.professionID) == "number" then
    return { id = info.professionID, name = info.professionName }
  end

  local line = ns.safe(function()
    local id, name = api.GetTradeSkillLine()
    return { id = id, name = name }
  end)
  if type(line) == "table" and type(line.id) == "number" then return line end
  return nil
end

-- One recipe's cooldown as the client reports it right now, or nil when it has
-- none. `charges` rides along because a charge-based cooldown (the alchemy
-- transmutes, which is where most people meet this) is ready while it still has
-- one, whatever the timer says — so a row can be both counting down and usable,
-- and a display that only read the timer would tell you to wait for something
-- you could do immediately.
local function recipeCooldown(api, id)
  return ns.safe(function()
    local seconds, isDay, charges, maxCharges = api.GetRecipeCooldown(id)
    return { seconds = seconds, isDay = isDay, charges = charges, maxCharges = maxCharges }
  end)
end

--- Walk the open profession window and store what it says about cooldowns.
---
--- `GetAllRecipeIDs` rather than `GetFilteredRecipeIDs`: the filtered list is
--- whatever the player last typed into the search box, and a cooldown hidden by
--- a filter would silently leave the grid — an absent cell reading as "nobody
--- looked" when we looked and were shown less than everything.
---
--- The walk is cheap in the way that matters: `GetRecipeCooldown` is asked once
--- per recipe, and only the handful that answer pay for a `GetRecipeInfo` name
--- lookup. It runs only while the window is open, throttled by Core.lua.
function Cooldowns.Scan()
  local api = C_TradeSkillUI
  if type(api) ~= "table" or type(api.GetRecipeCooldown) ~= "function" then return end

  local line = openLine()
  if not line then return end

  local ids = ns.safe(api.GetAllRecipeIDs)
  if type(ids) ~= "table" then return end

  local now = ns.now()
  local rows, listed = {}, {}

  for _, id in ipairs(ids) do
    if type(id) == "number" then
      listed[id] = true
      local cd = recipeCooldown(api, id)
      local maxCharges = (type(cd) == "table" and type(cd.maxCharges) == "number") and cd.maxCharges or 0
      local seconds = (type(cd) == "table" and type(cd.seconds) == "number") and cd.seconds or 0
      -- A recipe is worth a row when the game is metering it — it is counting
      -- down, or it holds charges. Everything else is an ordinary recipe with
      -- nothing to wait for, and there are hundreds of those.
      if seconds > 0 or maxCharges > 0 then
        local name = ns.safe(function()
          local info = api.GetRecipeInfo(id)
          return info and info.name
        end)
        rows[#rows + 1] = {
          spellID = id,
          name = name,
          skillLineID = line.id,
          skillLine = line.name,
          -- Absolute, once, here. See the file header for why an elapsed one is
          -- kept rather than dropped.
          readyTime = seconds > 0 and (now + seconds) or now,
          isDayCooldown = (type(cd) == "table" and cd.isDay) and true or nil,
          charges = (type(cd) == "table" and type(cd.charges) == "number") and cd.charges or nil,
          maxCharges = maxCharges > 0 and maxCharges or nil,
        }
      end
    end
  end

  Store.PutProfessionCooldowns(line.id, rows, listed)
end
