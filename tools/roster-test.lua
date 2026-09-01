-- Off-client tests for Roster.lua — the grid model.
--
-- Roster.lua is pure by construction (a DB table in, a display model out), so
-- the whole of it is testable here and none of it needs a QA pass. What that
-- buys is the rule the display exists to protect and the one a hand check is
-- worst at seeing: **absent is not zero.** A blank cell and a `0` look almost
-- the same on screen and mean opposite things — "nobody has looked in there"
-- against "we looked, and it was empty" — so the cases below are mostly about
-- which of the two a missing field produces.
--
-- Loads the shipped Init.lua rather than restating the namespace, for the
-- reason import-test.lua does: a fixture that restates the contract cannot
-- catch the shipped file failing to meet it. `ns.dot` and `ns.ago` are real
-- here, driven by a fake clock.
--
--   lua5.1 tools/roster-test.lua

package.path = "./?.lua;" .. package.path

local pass, fail = 0, 0
local function check(label, cond, extra)
  if cond then
    pass = pass + 1
    print("PASS " .. label)
  else
    fail = fail + 1
    print("FAIL " .. label .. (extra ~= nil and ("  " .. tostring(extra)) or ""))
  end
end

-- ── a fake clock ────────────────────────────────────────────────────────────

local NOW = 1724000000
_G.GetServerTime = function() return NOW end
_G.format = string.format
_G.tinsert = table.insert

-- ── the addon ───────────────────────────────────────────────────────────────

local ns = {}
assert(loadfile("Init.lua"))("WarbandPro", ns)
assert(loadfile("Roster.lua"))("WarbandPro", ns)

local Roster = ns.Roster

-- ── fixtures ────────────────────────────────────────────────────────────────

local function char(over)
  local c = {
    name = "Voctesa", realm = "Wyrmrest Accord", class = "DRUID", level = 80,
    seenAt = { lastSeen = NOW - 60 },
  }
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

local function db(chars)
  return { chars = chars or {} }
end

--- The row with this label, from anywhere in the model.
local function row(model, label)
  for _, g in ipairs(model.groups) do
    for _, r in ipairs(g.rows) do
      if r.label == label then return r, g end
    end
  end
  return nil
end

local function textAt(model, label, i)
  local r = row(model, label)
  if not r then return nil end
  return r.cells[i] and r.cells[i].text
end

-- ── columns ─────────────────────────────────────────────────────────────────

do
  local model = Roster.Build(db({
    ["g-zed"] = char({ name = "Zed", realm = "Moon Guard" }),
    ["g-abe"] = char({ name = "Abe", realm = "Wyrmrest Accord" }),
    ["g-me"] = char({ name = "Voctara", realm = "Wyrmrest Accord" }),
  }), "g-me")

  check("the character at the keyboard is the first column",
    model.columns[1] and model.columns[1].name == "Voctara",
    model.columns[1] and model.columns[1].name)

  -- SavedInstances' ServerSort, and the reason it is worth porting: realms are
  -- how an alt player groups their own roster in their head.
  check("the rest group by realm, then by name",
    model.columns[2].name == "Zed" and model.columns[3].name == "Abe",
    (model.columns[2].name or "?") .. "," .. (model.columns[3].name or "?"))

  check("a column carries the freshness the export tab draws",
    model.columns[1].dot == "green" and model.columns[1].ago == "60s ago",
    model.columns[1].dot .. " " .. model.columns[1].ago)

  -- The dot is `ns.dot`'s, not a second opinion: a character last seen four
  -- days ago is red in this grid because it is red in the export tab.
  local stale = Roster.Columns(db({ a = char({ seenAt = { lastSeen = NOW - 4 * 86400 } }) }), nil)
  check("a stale character is red here because it is red there",
    stale[1].dot == "red" and stale[1].ago == "4d ago", stale[1].dot .. " " .. stale[1].ago)

  check("item level prefers the equipped figure over the average",
    Roster.Columns(db({ a = char({ itemLevelAvg = 623, itemLevelEquipped = 621 }) }), nil)[1].ilvl == 621)
end

do
  local model = Roster.Build(db(), nil)
  check("an empty account has no columns and no groups",
    #model.columns == 0 and #model.groups == 0)
end

-- ── absent is not zero ──────────────────────────────────────────────────────

do
  -- The whole point. A character with nothing scanned but identity must not
  -- gain a single fabricated number.
  local model = Roster.Build(db({ a = char() }), nil)
  check("a character with nothing read draws no rows at all", #model.groups == 0,
    #model.groups)
end

do
  local model = Roster.Build(db({
    a = char({ name = "Has", gold = 12345678 }),
    b = char({ name = "Not" }),
  }), nil)
  -- Both columns exist; only one has a cell. The other is nil, not "0g".
  local r = row(model, "gold")
  check("gold renders for the character that has it", r and r.cells[1].text == "1,234g",
    r and r.cells[1] and r.cells[1].text)
  check("a character with no gold reading gets an empty cell, not 0g",
    r and r.cells[2] == nil)
end

do
  -- A bag whose `free` the client would not answer is not a full bag.
  local model = Roster.Build(db({
    a = char({ bags = { { bagID = 0, size = 30, free = 3 }, { bagID = 1, size = 28 } } }),
  }), nil)
  check("a bag with no free count makes the whole row absent rather than wrong",
    row(model, "bag space") == nil)
end

do
  local model = Roster.Build(db({
    a = char({ bags = { { bagID = 0, size = 30, free = 12 }, { bagID = 1, size = 28, free = 8 } } }),
  }), nil)
  check("bag space sums the containers that were read", textAt(model, "bag space", 1) == "20/58",
    textAt(model, "bag space", 1))
end

do
  -- Zero IS a reading here, and the one worth colouring: the tonight plan
  -- blocks on an empty phial count, so the grid should show it in the tone
  -- that says go and buy some.
  local model = Roster.Build(db({ a = char({ consumables = { phial = 0, foodFeast = 200 } }) }), nil)
  check("a consumable that was counted at zero is drawn as 0", textAt(model, "phials", 1) == "0")
  check("and it is drawn as a problem", row(model, "phials").cells[1].tone == "bad")
  check("a consumable key the scan never wrote has no row",
    row(model, "health potions") == nil)
end

-- ── the vault ───────────────────────────────────────────────────────────────

do
  local model = Roster.Build(db({
    a = char({ weeklyVault = {
      raid = { progress = 1, threshold = 3, unlocked = 0 },
      mplus = { progress = 8, threshold = 8, unlocked = 1 },
      world = { progress = 3, unlocked = 3 },
    } }),
  }), nil)

  check("a vault bucket reads as progress against the next threshold",
    textAt(model, "vault · raid", 1) == "1/3", textAt(model, "vault · raid", 1))
  check("an unlocked slot count rides along in parentheses",
    textAt(model, "vault · mythic+", 1) == "8/8 (1)", textAt(model, "vault · mythic+", 1))
  -- A bucket with everything earned carries no threshold at all, so there is
  -- nothing left to chase and `3/nil` would be the only alternative.
  check("a bucket with nothing left to chase says how many slots it has",
    textAt(model, "vault · world", 1) == "3 slots", textAt(model, "vault · world", 1))
  check("an earned bucket reads as good", row(model, "vault · world").cells[1].tone == "good")
end

-- ── lockouts ────────────────────────────────────────────────────────────────

do
  local model = Roster.Build(db({
    a = char({ name = "Abe", instances = {
      { name = "Nerub-ar Palace", difficultyName = "Heroic", isRaid = true,
        bosses = { { killed = true }, { killed = true }, { killed = false } } },
      { name = "Ara-Kara", difficultyName = "Mythic", isRaid = false,
        bosses = { { killed = true }, { killed = true }, { killed = true } } },
    } }),
    b = char({ name = "Bea", instances = {
      { name = "Nerub-ar Palace", difficultyName = "Heroic", isRaid = true,
        bosses = { { killed = false }, { killed = false }, { killed = false } } },
    } }),
  }), nil)

  check("a lockout cell is killed over total",
    textAt(model, "Nerub-ar Palace (Heroic)", 1) == "2/3",
    textAt(model, "Nerub-ar Palace (Heroic)", 1))
  check("a character not saved to that lockout has an empty cell",
    row(model, "Ara-Kara (Mythic)").cells[2] == nil)
  check("a cleared lockout reads as good",
    row(model, "Ara-Kara (Mythic)").cells[1].tone == "good")
  check("a partial one reads as unfinished",
    row(model, "Nerub-ar Palace (Heroic)").cells[1].tone == "warn")

  -- SavedInstances' RaidsFirst default: a raid lockout decides a night, a
  -- dungeon one rarely does.
  local _, g = row(model, "Nerub-ar Palace (Heroic)")
  check("raids sort above dungeons", g.rows[1].label == "Nerub-ar Palace (Heroic)",
    g.rows[1].label)
end

do
  -- A lockout the client described without an encounter list is still a
  -- lockout, and `0/0` would read as a clear.
  local model = Roster.Build(db({
    a = char({ instances = { { name = "Old Raid", isRaid = true, bosses = {} } } }),
  }), nil)
  check("a lockout with no boss list says saved rather than 0/0",
    textAt(model, "Old Raid", 1) == "saved", textAt(model, "Old Raid", 1))
end

do
  local model = Roster.Build(db({ a = char({ worldBosses = {} }) }), nil)
  check("an empty world boss list is not a row", row(model, "world bosses") == nil)
end

-- ── currencies ──────────────────────────────────────────────────────────────

do
  local model = Roster.Build(db({
    a = char({ currencies = {
      { id = 2815, name = "Resonance Crystals", quantity = 4500, maxQuantity = 20000 },
      { id = 3008, name = "Valorstones", quantity = 1900, maxQuantity = 2000 },
      { id = 1, name = "Gold Dust", quantity = 12000, maxQuantity = 0 },
    } }),
  }), nil)

  check("a capped currency renders as a fraction",
    textAt(model, "Resonance Crystals", 1) == "4,500/20,000",
    textAt(model, "Resonance Crystals", 1))
  check("near the cap it warns", row(model, "Valorstones").cells[1].tone == "warn")
  -- maxQuantity 0 means uncapped, per CONTRACT.md, and `12000/0` is not a
  -- fraction anyone can read.
  check("an uncapped currency renders as a bare number",
    textAt(model, "Gold Dust", 1) == "12,000", textAt(model, "Gold Dust", 1))
  check("currencies sort by name",
    model.groups[1].rows[1].label == "Gold Dust", model.groups[1].rows[1].label)
end

-- ── professions ─────────────────────────────────────────────────────────────

do
  local model = Roster.Build(db({
    a = char({ professions = { { name = "Alchemy", skill = 100, maxLevel = 100 } } }),
    b = char({ professions = { { name = "Alchemy", skill = 42, maxLevel = 100 } } }),
  }), nil)
  check("a profession reads as skill over max", textAt(model, "Alchemy", 1) == "100/100")
  check("a maxed profession reads as good", row(model, "Alchemy").cells[1].tone == "good")
  check("an unmaxed one does not", row(model, "Alchemy").cells[2].tone == "plain")
end

-- ── the warband bank ────────────────────────────────────────────────────────

do
  -- Account-wide, so it has no column to live in — and without this it would
  -- be the only thing in the DB the roster could not show.
  local model = Roster.Build({
    chars = { a = char() },
    warbandBank = { seenAt = NOW - 7200, seenByName = "Vocnar", gold = 50000000,
      tabs = { {}, {} }, tabsOwned = 5 },
  }, nil)
  check("the warband bank reports its age and who saw it",
    model.warbandBank.ago == "2h ago" and model.warbandBank.by == "Vocnar",
    model.warbandBank.ago)
  check("and how much of it was read",
    model.warbandBank.tabs == 2 and model.warbandBank.tabsOwned == 5)
  check("and its gold", model.warbandBank.gold == "5,000g", model.warbandBank.gold)
end

do
  local model = Roster.Build(db({ a = char() }), nil)
  check("no warband bank at all is nil rather than an empty readout",
    model.warbandBank == nil)
end

-- ── result ──────────────────────────────────────────────────────────────────

print(format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
