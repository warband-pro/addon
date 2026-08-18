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
local SECTIONS = { "bag", "bank", "warbank", "currency", "instance", "vault", "mail", "auctions", "profession" }

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
  db.opts = db.opts or {}
  if db.opts.includeLinks == nil then db.opts.includeLinks = false end

  _G.WarbandProDB = db
  Store.db = db
  return db
end

function Store.Ready()
  return type(Store.db) == "table" and not Store.readOnly
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
  local now = ns.now()
  c.seenAt.lastSeen = now
  if section then c.seenAt[section] = now end
end

-- The warband bank is one shared vault seen through whichever character
-- happened to open it, so it is stored once at the root of the DB with the name
-- of whoever last looked. Each character keeps only its own warbank stamp, so
-- the dots can still say "Vocnar saw it an hour ago, you have not."
function Store.PutWarbandBank(tabs, gold)
  if not Store.Ready() or tabs == nil then return end
  local wb = Store.db.warbandBank
  wb.tabs = tabs
  if gold ~= nil then wb.gold = gold end
  wb.seenAt = ns.now()
  wb.seenByGuid = UnitGUID("player")
  wb.seenByName = UnitName("player")
  local c = Store.Char()
  if c then c.seenAt.warbank = wb.seenAt end
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
function Store.Forget(name)
  if not Store.Ready() or type(name) ~= "string" or name == "" then return 0 end
  local want, removed = name:lower(), 0
  for guid, c in pairs(Store.db.chars) do
    if type(c.name) == "string" and c.name:lower() == want then
      Store.db.chars[guid] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- /warband optimize — drop characters not logged in 90 days.
function Store.Prune()
  if not Store.Ready() then return 0 end
  local cutoff, removed = ns.now() - ns.STALE_PRUNE, 0
  local mine = UnitGUID("player")
  for guid, c in pairs(Store.db.chars) do
    local last = c.seenAt and c.seenAt.lastSeen or 0
    if guid ~= mine and last < cutoff then
      Store.db.chars[guid] = nil
      removed = removed + 1
    end
  end
  return removed
end

Store.SECTIONS = SECTIONS
