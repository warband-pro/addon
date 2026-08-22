-- WarbandPro / Instances.lua
-- Lockouts, world bosses, keystone, Mythic+ history and the Great Vault.
-- SavedInstances parity, minus the parts the Battle.net API already answers.

local _, ns = ...

local Instances = {}
ns.Instances = Instances

local Store = ns.Store

-- Reset times arrive as seconds remaining. Absolute unix seconds is what the
-- website compares against its own clock, so convert here, once.
local function resetAt(seconds)
  if type(seconds) ~= "number" or seconds <= 0 then return nil end
  return ns.now() + seconds
end

function Instances.Lockouts()
  if not GetNumSavedInstances then return end
  local n = ns.safe(GetNumSavedInstances) or 0
  local out = {}
  for i = 1, n do
    local row = ns.safe(function()
      local name, id, reset, difficultyID, locked, extended, _, isRaid,
            _, difficultyName, numEncounters = GetSavedInstanceInfo(i)
      return { name = name, id = id, reset = reset, difficulty = difficultyID,
               locked = locked, extended = extended, isRaid = isRaid,
               difficultyName = difficultyName, encounters = numEncounters or 0 }
    end)
    if row and row.name and (row.locked or row.extended) then
      local bosses = {}
      for j = 1, row.encounters do
        local boss = ns.safe(function()
          local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
          return { name = bossName, killed = isKilled and true or false }
        end)
        if boss and boss.name then bosses[#bosses + 1] = boss end
      end
      out[#out + 1] = {
        name = row.name,
        instanceID = row.id,
        difficulty = row.difficulty,
        difficultyName = row.difficultyName,
        isRaid = row.isRaid and true or false,
        locked = row.locked and true or false,
        extended = row.extended and true or false,
        resetTime = resetAt(row.reset),
        bosses = bosses,
      }
    end
  end

  local world = {}
  local wn = ns.safe(GetNumSavedWorldBosses) or 0
  for i = 1, wn do
    local boss = ns.safe(function()
      local name, id, reset = GetSavedWorldBossInfo(i)
      return { name = name, worldBossID = id, killed = true, resetTime = resetAt(reset) }
    end)
    if boss and boss.name then world[#world + 1] = boss end
  end

  -- An empty list is a real answer here — it means "no lockouts this week" —
  -- so both write unconditionally once we have talked to the server.
  local c = Store.Char()
  if not c then return end
  c.instances = out
  c.worldBosses = world
  local now = ns.now()
  c.seenAt.instance, c.seenAt.lastSeen = now, now
end

function Instances.Keystone()
  local mp = C_MythicPlus
  if not mp then return end
  local level = ns.safe(mp.GetOwnedKeystoneLevel)
  local mapID = ns.safe(mp.GetOwnedKeystoneChallengeMapID)
  local c = Store.Char()
  if not c then return end
  if level and mapID then
    local name = ns.safe(function() return (C_ChallengeMode.GetMapUIInfo(mapID)) end)
    c.keystone = { level = level, dungeonID = mapID, dungeonName = name }
  else
    -- No key is a fact, and null is how the contract says to state it.
    c.keystone = nil
  end

  local runs = ns.safe(mp.GetRunHistory, false, true)
  if type(runs) == "table" then
    local out = {}
    for _, run in ipairs(runs) do
      out[#out + 1] = {
        mapID = run.mapChallengeModeID,
        level = run.level,
        timed = run.completed and true or false,
        thisWeek = run.thisWeek and true or false,
      }
    end
    c.mythicPlusRuns = out
  end

  local score = ns.safe(function() return (C_ChallengeMode.GetOverallDungeonScore()) end)
  if score then c.mythicPlusScore = score end
end

-- Vault activity types move around between expansions, so the buckets are built
-- from the Enum the client actually shipped rather than from remembered numbers.
local function vaultBuckets()
  local t = (Enum and Enum.WeeklyRewardChestThresholdType) or {}
  local map = {}
  if t.Raid then map[t.Raid] = "raid" end
  if t.Activities then map[t.Activities] = "mplus" end
  if t.MythicPlus then map[t.MythicPlus] = "mplus" end
  if t.World then map[t.World] = "world" end
  if t.RankedPvP then map[t.RankedPvP] = "pvp" end
  return map
end

-- The difficulty a raid vault slot will pay at, or nil when the client will not
-- say. Asked on the raid row and nowhere else: `level` means something different
-- on every row -- a keystone level on mythic+, a difficulty id on raid -- and
-- GetDifficultyInfo(14) answers "Normal" whether that 14 arrived as a difficulty
-- or as a +14 key. A plausible wrong answer is worse here than no answer, and
-- the website reads a missing `d` as the client declining rather than as a
-- difficulty it has to guess at.
local function raidDifficulty(level)
  if type(level) ~= "number" or level <= 0 then return nil end
  local name = ns.safe(GetDifficultyInfo, level)
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

function Instances.Vault()
  local wr = C_WeeklyRewards
  if not wr then return end
  local activities = ns.safe(wr.GetActivities)
  if type(activities) ~= "table" then return end

  local buckets, vault = vaultBuckets(), {}
  for _, a in ipairs(activities) do
    local key = buckets[a.type]
    if key then
      local slot = vault[key]
      if not slot then
        slot = { progress = 0, threshold = nil, unlocked = 0, slots = 0 }
        vault[key] = slot
      end
      slot.slots = slot.slots + 1
      if (a.progress or 0) > slot.progress then slot.progress = a.progress or 0 end
      if (a.progress or 0) >= (a.threshold or 0) then
        slot.unlocked = slot.unlocked + 1
      elseif slot.threshold == nil or (a.threshold or 0) < slot.threshold then
        -- The next reward you can still reach, which is the number worth showing.
        slot.threshold = a.threshold
      end

      -- The rows the fields above are a summary OF. The summary alone cost the
      -- website a sentence it needed: a bucket carries only the NEXT threshold,
      -- so the thresholds of slots already earned were gone, and "one more
      -- heroic boss raises the slot you already have" could not be said from it
      -- at all. Three small tables per bucket, and deflate folds the repeated
      -- keys to nearly nothing across a warband.
      slot.rows = slot.rows or {}
      tinsert(slot.rows, {
        t = a.threshold,
        p = a.progress or 0,
        l = a.level,
        d = (key == "raid") and raidDifficulty(a.level) or nil,
      })

      -- `level` is a max across rows whose ordering it does not own, which is
      -- fine where the field is a keystone level and wrong where it is a
      -- difficulty id: raid ids sort LFR (17) above Mythic (16), so the "best"
      -- slot it named could be the worst one. It is left off the raid bucket
      -- rather than reordered from a remembered table of ids -- `rows[].d` is
      -- the answer anyone reaching for it actually wanted.
      if key ~= "raid" and a.level and a.level > (slot.level or 0) then slot.level = a.level end
    end
  end

  -- Every bucket ends up with progress, the next threshold to chase (absent
  -- once all three are earned), how many of its slots are already unlocked, and
  -- `rows` -- the per-slot detail none of those three can reconstruct.
  -- An empty result means the client had nothing to say yet, not "no vault", so
  -- leave the previous answer and its stamp alone.
  if next(vault) == nil then return end
  local c = Store.Char()
  if not c then return end
  c.weeklyVault = vault
  local now = ns.now()
  c.seenAt.vault, c.seenAt.lastSeen = now, now
end

-- Lockout data arrives asynchronously: ask, then read on UPDATE_INSTANCE_INFO.
function Instances.Request()
  ns.safe(RequestRaidInfo)
end

function Instances.All()
  Instances.Lockouts()
  Instances.Keystone()
  Instances.Vault()
end
