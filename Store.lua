-- WarbandPro / Store.lua
-- The account-wide SavedVariables table, and the only code allowed to write it.
--
-- Shape note: a character entry in the DB *is* a wire CharacterObject, minus the
-- warband bank, which is account-wide and lives at the root. Bundle.lua reads
-- these straight out and never reshapes them, so there is one schema in this
-- addon, not two.

local _, ns = ...

local Store = {}
ns.Store = Store

-- Sections that carry their own freshness stamp. The website turns each into a
-- dot, so a section that is scanned must stamp and a section that is stamped
-- must be scanned.
--
-- `bank` and `reagentBank` are two stamps because they are two reads. The
-- reagent bank is its own container and can come back while the bank bags do
-- not (or the reverse), and until 1.8.0 either one landing moved a single
-- shared `bank` stamp — so a reagent-bank-only read drew a green dot on bank
-- contents that had not been looked at since the last banker visit.
--
-- `profession` and `professionCooldown` are two stamps for the same reason.
-- Skill levels come back from SKILL_LINES_CHANGED at every login; cooldowns are
-- readable only while the profession window is open, which most players do
-- twice a week. Sharing one stamp would draw a fresh dot on a transmute timer
-- nobody has looked at since Tuesday — the reagent bank's bug with a different
-- window in front of it.
local SECTIONS = {
  "bag", "bank", "reagentBank", "warbank", "currency", "instance", "vault", "mail", "auctions",
  "profession", "professionCooldown", "gear", "talents",
}

function Store.Init()
  local db = _G.WarbandProDB
  if type(db) ~= "table" then db = {} end

  -- No migrations yet. A DB from a future wire version is left alone rather
  -- than downgraded — the user reinstalls or we ship a migration, we never
  -- silently rewrite their history.
  if db.v and db.v > ns.WIRE_V then
    ns.print("saved data is from a newer version — not touching it")
    _G.WarbandProDB = db
    Store.db = db
    Store.readOnly = true
    return db
  end

  db.v = ns.WIRE_V
  db.chars = db.chars or {}
  db.warbandBank = db.warbandBank or { seenAt = nil, seenByGuid = nil, seenByName = nil, tabs = {} }
  db.lastExport = db.lastExport or 0
  -- Whether this install has ever told the player it is here. One line, once,
  -- on the first login after install — see Core.lua's PLAYER_LOGIN.
  db.greeted = db.greeted or false
  db.opts = db.opts or {}
  if db.opts.includeLinks == nil then db.opts.includeLinks = false end
  if db.opts.includeGear == nil then db.opts.includeGear = true end
  if db.opts.autoJunk == nil then db.opts.autoJunk = false end
  -- The minimap button is on by default. Its angle is deliberately not
  -- defaulted here: UI.lua owns the number it falls back to, so there is one
  -- home for it, and a DB written before the button existed does not have to be
  -- rewritten to gain one.
  if db.opts.minimap == nil then db.opts.minimap = true end
  -- Off, so the grid shows the currencies the game is still metering and says
  -- how many it left out. Roster.lua carries the rule and why it is a rule
  -- rather than SavedInstances' per-currency checklist.
  if db.opts.allCurrencies == nil then db.opts.allCurrencies = false end

  _G.WarbandProDB = db
  Store.db = db
  return db
end

function Store.Ready()
  return type(Store.db) == "table" and not Store.readOnly
end

-- Bumped on every write below, so Export.Build (Export.lua) can skip
-- re-encoding and re-deflating the whole bundle when nothing has moved since
-- the last call — status() used to pay that cost just to print a byte count.
Store.rev = 0
function Store.Touch()
  Store.rev = Store.rev + 1
end

-- The current character's entry, created on first touch.
function Store.Char()
  if not Store.Ready() then return nil end
  local guid = UnitGUID("player")
  if not guid then return nil end
  local c = Store.db.chars[guid]
  if not c then
    c = { guid = guid, seenAt = {} }
    Store.db.chars[guid] = c
  end
  c.seenAt = c.seenAt or {}
  return c
end

-- Write one section of the current character and stamp it. `value` nil means
-- the scan could not read that section right now (bank closed, API returned
-- nothing) — we keep whatever we knew before rather than blanking it, and we do
-- not move the stamp, because the stamp is what tells the website how much to
-- trust the old value.
function Store.Put(section, key, value)
  if value == nil then return end
  local c = Store.Char()
  if not c then return end
  c[key] = value
  Store.Stamp(section, c)
end

-- Stamp a section the caller wrote itself, and register the write.
--
-- Store.Put covers "one section, one field". Scan.Identity spreads a dozen
-- loose fields across the character and Scan.Bank writes two containers under
-- two different stamps, so both built their fields by hand — and by hand meant
-- neither called Store.Touch. Export.Build caches on Store.rev, so a bank walk
-- that moved nothing else left the next `/warband copy` serving a bundle
-- assembled before the bank was read: the contents were in the DB and absent
-- from the string.
--
-- `section` nil stamps lastSeen alone, which is what identity is — it says the
-- character was at the keyboard, not that any one section was re-read. `c` is
-- the character when the caller already holds it, so a scan that stamps two
-- sections does not resolve the same GUID three times. Returns the character so
-- a caller can keep writing to it.
function Store.Stamp(section, c)
  c = c or Store.Char()
  if not c or not c.seenAt then return nil end
  local now = ns.now()
  c.seenAt.lastSeen = now
  if section then c.seenAt[section] = now end
  Store.Touch()
  return c
end

-- The warband bank is one shared vault seen through whichever character
-- happened to open it, so it is stored once at the root of the DB with the name
-- of whoever last looked. Each character keeps only its own warbank stamp, so
-- the dots can still say "Vocnar saw it an hour ago, you have not."
--
-- Tabs merge by bagID and each carries its own stamp; they are not replaced
-- wholesale. ACCOUNT_BANK_TAB_DATA_CHANGED fires once per tab as the client
-- streams the data in, so the first walk after a banker opens routinely sees
-- one tab and not the other four — and a wholesale replace stored that one
-- tab, dropped four, and put a fresh stamp on the loss. A tab this pass could
-- not read keeps what we knew and keeps its own older stamp, which is the
-- whole difference between "that tab is empty" and "nobody has looked in that
-- tab since Tuesday".
--
-- `owned` is how many tabs the account has purchased, when the client will say
-- so. It is the only honest denominator for "is this the whole vault": an
-- unread tab and an unbought tab both report zero slots, so without it a
-- partial read and a small vault are the same reading. nil means the client
-- would not answer, and then the previous count stands rather than a guess.
function Store.PutWarbandBank(tabs, gold, owned)
  if not Store.Ready() or tabs == nil then return end
  local wb = Store.db.warbandBank
  local now = ns.now()

  local at, merged = {}, {}
  for _, tab in ipairs(wb.tabs or {}) do
    if tab.bagID and not at[tab.bagID] then
      merged[#merged + 1] = tab
      at[tab.bagID] = #merged
    end
  end
  for _, tab in ipairs(tabs) do
    tab.seenAt = now
    local where = tab.bagID and at[tab.bagID]
    if where then
      merged[where] = tab
    else
      merged[#merged + 1] = tab
      if tab.bagID then at[tab.bagID] = #merged end
    end
  end
  -- Sorted so the wire is byte-stable whatever order the tabs arrived in —
  -- Bundle.JSON sorts keys but cannot sort a list, and a bundle that changes
  -- bytes without changing meaning is one a diff cannot be read against.
  table.sort(merged, function(a, b) return (a.bagID or 0) < (b.bagID or 0) end)

  wb.tabs = merged
  if gold ~= nil then wb.gold = gold end
  if type(owned) == "number" and owned > 0 then wb.tabsOwned = owned end
  wb.partial = (type(wb.tabsOwned) == "number" and #merged < wb.tabsOwned) or nil
  wb.seenAt = now
  wb.seenByGuid = UnitGUID("player")
  wb.seenByName = UnitName("player")
  local c = Store.Char()
  if c then c.seenAt.warbank = wb.seenAt end
  Store.Touch()
end

-- Trade skill cooldowns for one profession, merged into whatever we already
-- know about the others.
--
-- **Merge, never replace** — the warband bank's rule, arrived at from the same
-- constraint. `C_TradeSkillUI` answers for the skill line the client currently
-- has open and for nothing else, so a walk of Alchemy sees Alchemy's recipes
-- and reports nothing at all about the Blacksmithing cooldown stored an hour
-- ago. Replacing the list would delete that, and stamp the loss fresh.
--
-- `listed` is the set of recipe ids the open window actually showed, and it is
-- what separates the two silences. A stored recipe the window listed and said
-- nothing about has come OFF cooldown — so its remembered ready time is pulled
-- back to now if it was still in the future, and the row survives as the "ready"
-- it is. A stored recipe the window did not list belongs to another profession
-- and is left exactly as it was, stamp included.
--
-- Sorted by recipe id on the way out, because Bundle.JSON sorts object keys and
-- cannot sort a list: a bundle whose bytes move without its meaning moving is
-- one no diff can be read against.
function Store.PutProfessionCooldowns(skillLineID, rows, listed)
  if not Store.Ready() then return end
  if type(skillLineID) ~= "number" or type(rows) ~= "table" then return end
  local c = Store.Char()
  if not c then return end

  local now = ns.now()
  local fresh = {}
  for _, row in ipairs(rows) do
    if type(row.spellID) == "number" then fresh[row.spellID] = row end
  end

  local merged = {}
  for _, row in ipairs(c.professionCooldowns or {}) do
    if type(row.spellID) == "number" and not fresh[row.spellID] then
      if row.skillLineID == skillLineID and listed and listed[row.spellID] then
        -- Listed and quiet: the cooldown we remembered has run out.
        if type(row.readyTime) ~= "number" or row.readyTime > now then row.readyTime = now end
        row.charges = nil
      end
      merged[#merged + 1] = row
    end
  end
  for _, row in ipairs(rows) do
    if type(row.spellID) == "number" then merged[#merged + 1] = row end
  end
  table.sort(merged, function(a, b) return (a.spellID or 0) < (b.spellID or 0) end)

  -- An empty answer from a profession with no cooldown recipes at all is still
  -- an answer — it says we looked — so this writes and stamps unconditionally,
  -- the same as an empty lockout list.
  c.professionCooldowns = merged
  Store.Stamp("professionCooldown", c)
end

-- The oldest stamp across the stored tabs, which is how fresh the vault is as
-- a whole — `warbandBank.seenAt` is only how recently somebody stood at the
-- banker. They differ exactly when a tab did not load, which is the case this
-- whole model exists for. nil when no tab carries a stamp, meaning every tab
-- predates per-tab stamping and only the root stamp is known.
function Store.WarbandBankOldestTab()
  local wb = Store.db and Store.db.warbandBank
  if not wb or not wb.tabs then return nil end
  local oldest
  for _, tab in ipairs(wb.tabs) do
    if type(tab.seenAt) == "number" and (not oldest or tab.seenAt < oldest) then
      oldest = tab.seenAt
    end
  end
  return oldest
end

function Store.Count()
  if not Store.Ready() then return 0 end
  local n = 0
  for _ in pairs(Store.db.chars) do n = n + 1 end
  return n
end

-- Characters newest-first, which is also the order a capped bundle keeps.
function Store.Characters()
  local out = {}
  if not Store.Ready() then return out end
  for _, c in pairs(Store.db.chars) do out[#out + 1] = c end
  table.sort(out, function(a, b)
    return (a.seenAt and a.seenAt.lastSeen or 0) > (b.seenAt and b.seenAt.lastSeen or 0)
  end)
  return out
end

-- /warband clear <name> — remove by character name, case-insensitive.
-- Account-wide orphan guard: if the forgotten character was the one who last
-- saw the warbank, clear the attribution — the vault tabs are account-wide
-- and remain, but "by Vocnar" must not point at a deleted GUID.
--- Drop stored cleanup lists for characters that no longer exist.
---
--- A junk list is keyed by guid like everything else, so forgetting a character
--- without this leaves a list nothing can ever render and nothing can ever
--- clear — the same orphan the warband bank's attribution would become, handled
--- in the same two places for the same reason.
function Store.DropJunk(removedGuids)
  local db = Store.db
  local junk = db and db.junk
  if not junk then return end
  if removedGuids then
    for guid in pairs(removedGuids) do
      junk[guid] = nil
    end
  end
  for guid in pairs(junk) do
    if not db.chars[guid] then
      junk[guid] = nil
    end
  end
end

-- One orphan rule, two callers. The warbank tabs are account-wide and survive
-- a Forget or a Prune, but the "seen by <deleted char>" attribution must not —
-- a dangling seenByGuid points at nothing.
local function clearOrphans(removedGuids)
  local wb = Store.db.warbandBank
  if not wb then return false end
  if wb.seenByGuid and (removedGuids[wb.seenByGuid] or not Store.db.chars[wb.seenByGuid]) then
    wb.seenByGuid = nil
    wb.seenByName = nil
    return true
  end
  if not wb.seenByGuid and wb.seenByName then
    wb.seenByName = nil
    return true
  end
  return false
end

function Store.Forget(name)
  if not Store.Ready() or type(name) ~= "string" or name == "" then return 0 end
  local want, removed = name:lower(), 0
  local removedGuids = {}
  for guid, c in pairs(Store.db.chars) do
    if type(c.name) == "string" and c.name:lower() == want then
      Store.db.chars[guid] = nil
      removedGuids[guid] = true
      removed = removed + 1
    end
  end
  local cleared = clearOrphans(removedGuids)
  if removed > 0 or cleared then
    Store.DropJunk(removedGuids)
    Store.Touch()
  end
  return removed
end

-- /warband optimize — drop characters not logged in 90 days.
-- Same orphan rule as Forget: keep the vault, drop the ghost attribution when
-- its owner is pruned or already missing. The orphan check runs even when no
-- characters were pruned this pass, so a dangling seenByGuid from a prior
-- manual edit or a missed Forget does not persist.
function Store.Prune()
  if not Store.Ready() then return 0 end
  local cutoff, removed = ns.now() - ns.STALE_PRUNE, 0
  local mine = UnitGUID("player")
  local removedGuids = {}
  for guid, c in pairs(Store.db.chars) do
    local last = c.seenAt and c.seenAt.lastSeen or 0
    if guid ~= mine and last < cutoff then
      Store.db.chars[guid] = nil
      removedGuids[guid] = true
      removed = removed + 1
    end
  end
  local cleared = clearOrphans(removedGuids)
  Store.DropJunk(removedGuids)
  if removed > 0 or cleared then
    Store.Touch()
  end
  return removed
end

Store.SECTIONS = SECTIONS
