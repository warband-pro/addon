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

-- An item link shaped like a `gear[]` entry on purpose: `slot`, `id`, `ilvl`,
-- `s` and friends, so the website decodes it through the same path an owned
-- item takes rather than growing a second item model for one field. No
-- `where`: a vault reward is not somewhere you own it yet, and calling it a
-- bag item would put it in the solve's candidate pool, which is precisely the
-- mistake this must not make.
--
-- Nil the moment anything declines: a link the item cache has not filled in,
-- an equip slot nothing here recognises. Both callers read absence as
-- "not read".
local function shapeItemReward(link)
  -- The id comes out of the item string rather than from an API that takes a
  -- link. Gear.lua already proves the string is there and already parses ids
  -- this way, and one fewer client call is one fewer thing that can be absent
  -- on a client this addon has not been run against.
  local s = link:match("|H(item[%-%d:]+)|h")
  local id = s and tonumber(s:match("^item:(%d+)"))
  if not id then return nil end

  local itemInfo = ns.itemInfo(id)
  local slot = itemInfo and ns.Gear.SlotFor(itemInfo.equipLoc)
  if not slot then return nil end

  local reward = {
    slot = slot,
    id = id,
    ilvl = ns.safe(C_Item.GetDetailedItemLevelInfo, link),
    s = s,
    n = link:match("|h%[(.-)%]|h"),
    cls = itemInfo.classID,
    sub = itemInfo.subclassID,
  }
  if ns.Gear.IsTierSlot(slot) then reward.set = ns.Gear.SetID(link) end
  local stats = ns.safe(C_Item.GetItemStats, link)
  if type(stats) == "table" then
    local st
    for k, v in pairs(stats) do
      if type(k) == "string" and type(v) == "number" then
        st = st or {}
        st[k] = v
      end
    end
    reward.st = st
  end
  return reward
end

-- The item a vault slot is currently offering, or nil.
--
-- `GetExampleRewardItemHyperlinks` is the client's own answer to "what would
-- this slot give me", and it is the whole reason the website could rank vault
-- progress and never the vault itself: it knew three slots were unlocked and
-- had no idea what was in them. The player sees the items by opening the vault
-- frame; nothing else on the wire carried them.
--
-- Nil the moment anything declines: a locked slot, an API this client does not
-- have. The website reads absence as "not read" and renders vault progress
-- exactly as it did before this existed.
local function vaultReward(wr, activityID)
  if type(wr.GetExampleRewardItemHyperlinks) ~= "function" then return nil end
  local link = ns.safe(wr.GetExampleRewardItemHyperlinks, activityID)
  if type(link) ~= "string" or link == "" then return nil end
  return shapeItemReward(link)
end

-- One generated offer from an activity's `rewards`, or nil.
--
-- `GetActivities` carries these only after the player opens the Great Vault
-- post-reset: generation happens on interact, and before that there is
-- nothing to read. The client's own frame resolves each reward through
-- `C_WeeklyRewards.GetItemHyperlink(reward.itemDBID)` and skips everything
-- that is not an item, so this follows it deliberately rather than inventing
-- a second resolution. Currency and quest rewards never reach the wire, and
-- neither does a keystone. `b` names the bucket whose slot offered it, which
-- is the grouping the character page ranks under.
local function vaultChoice(wr, reward, bucket)
  if type(reward) ~= "table" then return nil end
  local cached = Enum and Enum.CachedRewardType
  if reward.type ~= ((cached and cached.Item) or 1) then return nil end
  local id = reward.id
  if type(id) ~= "number" then return nil end
  local isKeystone = C_Item and C_Item.IsItemKeystoneByID
  if ns.safe(isKeystone, id) then return nil end
  if type(wr.GetItemHyperlink) ~= "function" then return nil end
  local link = ns.safe(wr.GetItemHyperlink, reward.itemDBID)
  if type(link) ~= "string" or link == "" then return nil end
  local shaped = shapeItemReward(link)
  if not shaped then return nil end
  shaped.b = bucket
  return shaped
end

-- What a vault pass may do to the stored generated choices, and the one case
-- it may not. A pass that saw offers overwrites unconditionally: a fuller
-- read an hour later repairs a partial one from an unfilled item cache, and
-- the stamp moves with it. A pass that saw none destroys nothing on its own,
-- because the client is silent about ungenerated weeks and an unopened vault
-- reads exactly like a claimed one. The tell is HasAvailableRewards, which is
-- server state rather than cache: offers we stored while this week's slots
-- are still earned, that the server no longer holds, were claimed. A fresh
-- week with nothing earned yet keeps the old value for the website's reset
-- gate to age out, and an API too old to answer keeps it too.
local function resolveChoices(c, generated, hasAvailable, unlocked, now)
  if #generated > 0 then
    c.vaultChoices = generated
    c.seenAt.vaultChoices = now
    c.vaultClaimedAt = nil
    return
  end
  if c.vaultChoices == nil then return end
  if type(unlocked) ~= "number" or unlocked < 1 then return end
  if hasAvailable ~= false then return end
  c.vaultChoices = nil
  c.vaultClaimedAt = now
end

function Instances.Vault()
  local wr = C_WeeklyRewards
  if not wr then return end
  local activities = ns.safe(wr.GetActivities)
  if type(activities) ~= "table" then return end

  local buckets, vault, generated = vaultBuckets(), {}, {}
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
        -- Asked only of a slot that is actually paying: an activity still
        -- short of its threshold has no reward to example, and the client
        -- answers nil for one anyway. Gating here keeps a full vault to three
        -- GetItemInfo-shaped lookups rather than one per activity row.
        r = ((a.progress or 0) >= (a.threshold or 0)) and a.id and vaultReward(wr, a.id) or nil,
      })

      -- The generated offer, when the player has opened the vault since the
      -- reset and the client has it to give. Collected beside the example
      -- `r` deliberately: same slots, same weeks, and the frame this comes
      -- from is the one `r` can only gesture at.
      local rewards = a.rewards
      if type(rewards) == "table" then
        for _, reward in ipairs(rewards) do
          local choice = vaultChoice(wr, reward, key)
          if choice then generated[#generated + 1] = choice end
        end
      end

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
  local unlocked = 0
  for _, slot in pairs(vault) do
    if type(slot.unlocked) == "number" then unlocked = unlocked + slot.unlocked end
  end
  resolveChoices(c, generated, ns.safe(wr.HasAvailableRewards), unlocked, now)
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
