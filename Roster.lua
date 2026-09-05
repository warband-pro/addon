-- WarbandPro / Roster.lua
-- The grid: every character this account has scanned, beside every saved thing
-- the addon already knows about them. Pure — a table in, a model out, no WoW
-- API and no frames — so tools/roster-test.lua can hold the rules and UI.lua
-- only has to draw what it is handed.
--
-- **The shape is SavedInstances', deliberately.** That addon solved this
-- display years ago, and the reason it reads well is one decision: characters
-- are COLUMNS and the things you track are ROWS, so the question an alt player
-- actually asks — *which of them still has this* — is a line you read across
-- rather than six panes you hold in your head. Its column header is a
-- class-coloured name over a level, its cells are two or three characters
-- (`3/8`), and its rows come in labelled groups with a rule between them. All
-- of that is ported here.
--
-- What could NOT be ported is how it draws. SavedInstances builds its grid with
-- LibQTip on top of Ace3, and this addon ships neither and is not going to —
-- docs/RESEARCH-REFERENCE.md is the standing answer and this is not the change
-- that reopens it. So the MODEL is ported and the rendering is ours, out of the
-- client's own widgets. That split is also why this file is testable and
-- SavedInstances' equivalent is not.
--
-- Three rules keep the grid honest. None of them is new — each is this addon's
-- existing doctrine pointed at a display:
--
-- 1. **Absent is not zero.** A section a character has never had read shows an
--    EMPTY cell, never a `0`. That is the distinction `seenAt` exists to carry
--    and the website's dots already draw, and it is the one a grid is most
--    likely to destroy: a blank column reads as "nothing there" when it means
--    "nobody looked". `0/8` means we looked and nothing had died.
-- 2. **A row nobody has a value for is not drawn.** SavedInstances gives every
--    instance a per-row `always | saved | never`; the useful half of that with
--    no config attached is "show it if somebody is saved to it". A grid whose
--    rows are mostly blank is a grid nobody reads, and an alt player's list of
--    possible lockouts is far longer than their list of real ones.
-- 3. **Nothing here reads the game.** Every number already went through
--    `ns.safe` on the way into the DB. Reading it back out is table work, and
--    a display that could throw in the middle of a raid would be a new way to
--    break the one promise this addon makes about crashing.

local _, ns = ...

local Roster = {}
ns.Roster = Roster

local floor, sort, format = math.floor, table.sort, string.format

-- ── cells ───────────────────────────────────────────────────────────────────

-- A cell is text plus a tone, and the tone is a NAME rather than a colour:
-- UI.lua owns the palette (it uses the client's own, not the website's), and a
-- model that carried hex would have to know which window it was drawn in.
--
--   good   something is done, banked, or full
--   warn   something is close to a cap or about to be lost
--   bad    something is wrong or expired
--   plain  a number with no opinion attached
--
-- There is no "muted" tone. An unknown is an ABSENT cell, not a grey one —
-- rule 1 above, expressed in the type rather than in a convention.
--
-- `tip` is the cell's own detail, as a list of lines, and it is where this grid
-- earns the comparison to SavedInstances rather than merely borrowing its
-- shape. A cell is two or three characters because that is what makes a row
-- readable ACROSS; everything the two characters are a summary of — which
-- bosses are dead, when the lockout resets, how much of a weekly cap is spent —
-- lives here and costs nothing until the mouse asks. SavedInstances calls it a
-- secondary tooltip and it is the feature people actually name when they say
-- that addon reads well.
--
-- Lines are plain strings, or `{left, right}` pairs where a value should sit
-- against the far edge. Nothing here carries colour: UI.lua owns the palette,
-- for the reason the tone names exist.
local function cell(text, tone, tip)
  if text == nil then return nil end
  return { text = text, tone = tone or "plain", tip = tip }
end

--- `12,345` — thousands separated, the way every WoW UI writes a big number.
local function commas(n)
  local s = tostring(floor(n))
  local out, count = "", 0
  for i = #s, 1, -1 do
    out = s:sub(i, i) .. out
    count = count + 1
    if count % 3 == 0 and i > 1 then out = "," .. out end
  end
  return out
end

--- Copper to a whole gold figure. Silver and copper are noise at warband scale.
local function money(copper)
  if type(copper) ~= "number" then return nil end
  return commas(floor(copper / 10000)) .. "g"
end

local function num(v)
  if type(v) ~= "number" then return nil end
  return v
end

local function unlockedN(v)
  if v == true then return 1 end
  if type(v) == "number" then return v end
  return nil
end

-- ── columns ─────────────────────────────────────────────────────────────────

-- SavedInstances' `cpairs_sort`, ported: the character at the keyboard first,
-- then grouped by realm, then by name. The first clause is the one that earns
-- its keep — you are the column you check against, so it belongs where the eye
-- lands, not wherever the alphabet puts it.
local function order(a, b)
  if a.isSelf ~= b.isSelf then return a.isSelf end
  local ar, br = a.realm or "", b.realm or ""
  if ar ~= br then return ar < br end
  return (a.name or "") < (b.name or "")
end

--- Every scanned character, sorted, as the grid's columns.
---
--- `dot` and `ago` come from the same `ns.dot`/`ns.ago` the export tab draws,
--- so a character that reads green here reads green there. One freshness rule
--- in this addon, not two.
function Roster.Columns(db, selfGuid)
  local cols = {}
  if type(db) ~= "table" or type(db.chars) ~= "table" then return cols end
  for guid, c in pairs(db.chars) do
    if type(c) == "table" then
      local seen = c.seenAt or {}
      cols[#cols + 1] = {
        guid = guid,
        char = c,
        name = c.name or "?",
        realm = c.realm,
        class = c.class,
        level = num(c.level),
        ilvl = num(c.itemLevelEquipped) or num(c.itemLevelAvg),
        isSelf = guid == selfGuid,
        dot = ns.dot(seen.lastSeen),
        ago = ns.ago(seen.lastSeen),
        zone = c.lastZone,
        guild = c.guild and c.guild.name or nil,
        gold = money(c.gold),
      }
    end
  end
  sort(cols, order)
  return cols
end

-- ── row building ────────────────────────────────────────────────────────────

-- A group under construction. `add` takes a label and a function that answers
-- for one character, which is what keeps every row below to one line: the
-- "is anybody home" test (rule 2) lives here once rather than in each row.
local function group(label)
  return { label = label, rows = {}, _n = 0 }
end

local function addRow(g, cols, label, fn)
  local cells, any = {}, false
  for i = 1, #cols do
    local c = fn(cols[i].char, cols[i])
    cells[i] = c
    if c then any = true end
  end
  if not any then return end
  g._n = g._n + 1
  g.rows[g._n] = { label = label, cells = cells }
end

local function push(groups, g)
  if g._n > 0 then
    g._n = nil
    groups[#groups + 1] = g
  end
end

-- ── the groups ──────────────────────────────────────────────────────────────

-- The vault buckets in the order a player thinks about them, with the label
-- each one gets. `world` is last because it is the one that fills itself.
local VAULT = {
  { key = "raid", label = "vault · raid" },
  { key = "mplus", label = "vault · mythic+" },
  { key = "world", label = "vault · world" },
}

local function thisWeek(groups, cols)
  local g = group("this week")

  for _, v in ipairs(VAULT) do
    addRow(g, cols, v.label, function(c)
      local b = c.weeklyVault and c.weeklyVault[v.key]
      if not b then return nil end
      local unlocked = unlockedN(b.unlocked) or 0
      -- The per-slot detail the two-character summary is a summary OF. A bucket
      -- carries only the NEXT threshold, so "one more boss raises the slot you
      -- already have" cannot be said from the summary at all — `rows` is the
      -- field Instances.lua added for exactly that sentence, and until now
      -- nothing in this addon read it.
      local tip
      if type(b.rows) == "table" and #b.rows > 0 then
        tip = {}
        local ordered = {}
        for _, r in ipairs(b.rows) do ordered[#ordered + 1] = r end
        sort(ordered, function(x, y) return (x.t or 0) < (y.t or 0) end)
        for _, r in ipairs(ordered) do
          local got = (num(r.p) or 0) >= (num(r.t) or 0)
          tip[#tip + 1] = { format("%d needed", num(r.t) or 0),
            got and (r.l and ("earned · " .. r.l) or "earned") or format("%d so far", num(r.p) or 0) }
        end
      end
      -- Progress against the next threshold you can still reach. Once all
      -- three are earned the bucket carries no threshold at all, and there is
      -- nothing left to chase — so it says so rather than printing `4/nil`.
      local t = num(b.threshold)
      if not t then return cell(unlocked .. " slots", "good", tip) end
      local text = format("%d/%d", num(b.progress) or 0, t)
      if unlocked > 0 then text = text .. format(" (%d)", unlocked) end
      return cell(text, unlocked > 0 and "good" or "plain", tip)
    end)
  end

  addRow(g, cols, "keystone", function(c)
    local k = c.keystone
    if not k or not num(k.level) then return nil end
    return cell("+" .. k.level, "plain")
  end)

  addRow(g, cols, "m+ score", function(c)
    local s = num(c.mythicPlusScore)
    if not s then return nil end
    return cell(commas(s), "plain")
  end)

  push(groups, g)
end

-- One row per instance-and-difficulty anybody is saved to, which is the whole
-- of SavedInstances' own row set minus the ones it draws from a static table of
-- every instance in the game. We have no such table and want none: what the
-- client told us somebody is locked to is exactly the set worth a row.
local function lockouts(groups, cols)
  local g = group("lockouts")

  local keys, seen = {}, {}
  for i = 1, #cols do
    for _, inst in ipairs(cols[i].char.instances or {}) do
      if inst.name then
        local diff = inst.difficultyName
        local key = inst.name .. "|" .. (diff or "")
        if not seen[key] then
          seen[key] = true
          keys[#keys + 1] = {
            key = key,
            name = inst.name,
            label = diff and (inst.name .. " (" .. diff .. ")") or inst.name,
            isRaid = inst.isRaid and true or false,
          }
        end
      end
    end
  end
  -- Raids above dungeons, then alphabetical — SavedInstances' `RaidsFirst`,
  -- which is its default and the right one: a raid lockout is the one that
  -- decides a night.
  sort(keys, function(a, b)
    if a.isRaid ~= b.isRaid then return a.isRaid end
    return a.label < b.label
  end)

  for _, k in ipairs(keys) do
    addRow(g, cols, k.label, function(c)
      for _, inst in ipairs(c.instances or {}) do
        if inst.name and (inst.name .. "|" .. (inst.difficultyName or "")) == k.key then
          -- **An expired lockout is not a lockout.** `resetTime` is absolute
          -- unix seconds (Instances.lua converts the client's seconds-remaining
          -- once, on the way in), so a character last played before the reset
          -- carries a saved instance that has certainly gone. Drawing it would
          -- be the grid stating something known to be false — worse than the
          -- blank it becomes, which correctly says we have not looked since.
          -- Whether they re-locked is a different question and an unread one.
          if inst.resetTime and not ns.hence(inst.resetTime) then return nil end

          local killed, total, dead, alive = 0, 0, {}, {}
          for _, boss in ipairs(inst.bosses or {}) do
            total = total + 1
            if boss.killed then
              killed = killed + 1
              if boss.name then dead[#dead + 1] = boss.name end
            elseif boss.name then
              alive[#alive + 1] = boss.name
            end
          end

          -- SavedInstances' secondary tooltip, which is the half of that addon
          -- people actually praise: the cell says how many, the hover says
          -- which. We already store every boss name and never showed one.
          local tip = {}
          local left = ns.hence(inst.resetTime)
          if left then tip[#tip + 1] = { "resets in", left } end
          if inst.extended then tip[#tip + 1] = "extended" end
          for _, n2 in ipairs(alive) do tip[#tip + 1] = { n2, "alive" } end
          for _, n2 in ipairs(dead) do tip[#tip + 1] = { n2, "dead" } end
          if #tip == 0 then tip = nil end

          -- A lockout with no encounter list is still a lockout. `saved` is
          -- the honest cell for it; `0/0` would read as a clear.
          if total == 0 then return cell("saved", "warn", tip) end
          return cell(format("%d/%d", killed, total), killed >= total and "good" or "warn", tip)
        end
      end
      return nil
    end)
  end

  addRow(g, cols, "world bosses", function(c)
    local w = c.worldBosses
    if type(w) ~= "table" then return nil end
    local live, tip = 0, {}
    for _, boss in ipairs(w) do
      -- Same rule as the instance rows above: a world boss whose week has
      -- rolled over is not still killed.
      local left = boss.resetTime and ns.hence(boss.resetTime)
      if left or not boss.resetTime then
        live = live + 1
        if boss.name then tip[#tip + 1] = { boss.name, left or "killed" } end
      end
    end
    if live == 0 then return nil end
    return cell(tostring(live), "warn", #tip > 0 and tip or nil)
  end)

  push(groups, g)
end

-- **Which currencies get a row.** SavedInstances answers this with a checklist
-- of every currency in the game and asks the player to tick the interesting
-- ones. That list is the single biggest thing in its options, and it is
-- maintenance the player does on the addon's behalf every time an expansion
-- retires a currency and mints four more.
--
-- The signal is already on the wire, so this is decided rather than configured,
-- the way the expired lockout is: **a currency is LIVE when the game is still
-- metering it for somebody.** It has a total cap, or a weekly cap, or a
-- character earned some of it this week. Everything else is a pile left over
-- from an expansion nobody in this warband is playing — Timewarped Badges, the
-- marks of three seasons ago — padding a currency group that docs/UI.md
-- measured at sixteen rows, between the two rows the tab was opened for.
--
-- The test runs across the WHOLE warband, not per character, so one alt still
-- earning a currency keeps its row for the nine who are not. That is the point
-- of a grid.
local function liveCurrency(cur)
  local max, weekly, earned = num(cur.maxQuantity), num(cur.weeklyMax), num(cur.earnedThisWeek)
  if max and max > 0 then return true end
  if weekly and weekly > 0 then return true end
  if earned and earned > 0 then return true end
  return false
end

local function currencies(groups, cols, showAll)
  local g = group("currencies")

  local keys, seen = {}, {}
  for i = 1, #cols do
    for _, cur in ipairs(cols[i].char.currencies or {}) do
      if cur.id and cur.name then
        local k = seen[cur.id]
        if not k then
          k = { id = cur.id, name = cur.name, live = false }
          seen[cur.id] = k
          keys[#keys + 1] = k
        end
        if liveCurrency(cur) then k.live = true end
      end
    end
  end
  sort(keys, function(a, b) return a.name < b.name end)

  local hidden = 0
  for _, k in ipairs(keys) do
    if not (showAll or k.live) then
      hidden = hidden + 1
    else
      addRow(g, cols, k.name, function(c)
        for _, cur in ipairs(c.currencies or {}) do
          if cur.id == k.id then
            local q = num(cur.quantity)
            if not q then return nil end
            local max = num(cur.maxQuantity)
            local weekly, earned = num(cur.weeklyMax), num(cur.earnedThisWeek)
            -- `maxQuantity` 0 is uncapped per CONTRACT.md, not a cap of nothing.
            local capped = max and max > 0 and q >= max
            local weeklyDone = weekly and weekly > 0 and (earned or 0) >= weekly

            -- The weekly cap is a different question from the total cap and the
            -- more urgent one — a weekly that resets unspent is gone, where a
            -- total cap merely stops accruing. Both ride the wire and neither
            -- was being read.
            local tip = {}
            if capped then tip[#tip + 1] = "at cap — anything more is lost" end
            if weekly and weekly > 0 then
              tip[#tip + 1] = { "this week", commas(earned or 0) .. "/" .. commas(weekly) }
            end
            if cur.isAccountWide then tip[#tip + 1] = "shared across the warband" end
            if #tip == 0 then tip = nil end

            -- SavedInstances' three currency colours, translated rather than
            -- copied. Its green for "under the cap" is decoration here — this
            -- grid's rule is that colour is state, and sixteen green rows state
            -- nothing — so `plain` is what "fine" looks like, and the two
            -- colours left are the two things you can act on:
            --
            --   bad   at the cap. Everything earned from here is thrown away.
            --   warn  close enough to that to go spend it, or this week's
            --         allowance is already earned and running more pays nothing.
            --
            -- The 90% warning is the one that arrives while it is still worth
            -- something. `bad` used to be `warn` too, which made "go spend
            -- this" and "too late" the same colour — and the minimap glance has
            -- called the second one red since 1.9.0, so the two surfaces
            -- disagreed about the same currency.
            local tone = "plain"
            if capped then
              tone = "bad"
            elseif (max and max > 0 and q >= max * 0.9) or weeklyDone then
              tone = "warn"
            end

            -- A cap is only worth drawing when there is one: `4500/0` is not a
            -- fraction.
            if max and max > 0 then
              return cell(commas(q) .. "/" .. commas(max), tone, tip)
            end
            return cell(commas(q), tone, tip)
          end
        end
        return nil
      end)
    end
  end

  -- Honest about the omission, the way the glance's `+2` is. A group header
  -- that silently drops four rows is a bug report waiting to be filed; one that
  -- says how many were dropped sends the player to the switch that shows them.
  if hidden > 0 then
    g.label = format("currencies · %d hidden", hidden)
  end

  push(groups, g)
end

local function professions(groups, cols)
  local g = group("professions")

  local keys, seen = {}, {}
  for i = 1, #cols do
    for _, p in ipairs(cols[i].char.professions or {}) do
      if p.name and not seen[p.name] then
        seen[p.name] = true
        keys[#keys + 1] = p.name
      end
    end
  end
  sort(keys)

  for _, name in ipairs(keys) do
    addRow(g, cols, name, function(c)
      for _, p in ipairs(c.professions or {}) do
        if p.name == name then
          local skill = num(p.skill)
          if not skill then return nil end
          local max = num(p.maxLevel)
          if max and max > 0 then
            return cell(skill .. "/" .. max, skill >= max and "good" or "plain")
          end
          return cell(tostring(skill), "plain")
        end
      end
      return nil
    end)
  end

  push(groups, g)
end

-- The consumable keys the scanner actually writes, with what a player calls
-- them. Not every key is worth a row on its own — a rune and a potion are one
-- decision at raid time — but they are counted separately in the DB and
-- collapsing them here would hide which one you are short of.
local CONSUMABLES = {
  { key = "phial", label = "phials" },
  { key = "healthPotion", label = "health potions" },
  { key = "tempPotion", label = "combat potions" },
  { key = "foodFeast", label = "food" },
  { key = "weaponRune", label = "weapon runes" },
}

local function pockets(groups, cols)
  local g = group("pockets")

  addRow(g, cols, "gold", function(c) return cell(money(c.gold), "plain") end)

  addRow(g, cols, "bag space", function(c)
    local bags = c.bags
    if type(bags) ~= "table" or #bags == 0 then return nil end
    local free, size = 0, 0
    for _, bag in ipairs(bags) do
      -- `free` nil is a container that was not read (CONTRACT.md), and adding
      -- it as zero would report a full bag as roomy.
      if type(bag.free) ~= "number" then return nil end
      free = free + bag.free
      size = size + (num(bag.size) or 0)
    end
    return cell(free .. "/" .. size, free <= 4 and "warn" or "plain")
  end)

  for _, con in ipairs(CONSUMABLES) do
    addRow(g, cols, con.label, function(c)
      local n = c.consumables and num(c.consumables[con.key])
      if not n then return nil end
      return cell(tostring(n), n == 0 and "bad" or "plain")
    end)
  end

  addRow(g, cols, "mail", function(c)
    local m = c.mail
    local n = m and num(m.countItems)
    if not n or n == 0 then return nil end
    local soon = m and num(m.soonestExpiryHours)
    return cell(tostring(n), (soon and soon < 72) and "bad" or "plain")
  end)

  push(groups, g)
end

-- ── what warband.pro sent back ──────────────────────────────────────────────

-- **The group SavedInstances structurally cannot have**, because it has no
-- other side: what the website last told this account to do, per character.
--
-- Everything above is the game reporting itself. This is the addon reporting
-- its own inbox — `db.junk[guid]` and `db.gearset[guid]`, both written by a
-- `wbc1!` paste and both keyed by the same guid the columns already sort on.
--
-- **It draws the plan's EXISTENCE and AGE, never its reasoning.** How many
-- items are on the clear-out list, whether a setup is stored, how old the paste
-- is — all facts about what is in this database. Not which item is better, not
-- how far behind a slot is, not who to play tonight: those need the loot table,
-- the item stats and the weights, none of which are here, and a second surface
-- guessing at them would be a second surface being wrong. The website decides;
-- this says whether its answer arrived and how stale it has gone.
--
-- Why it belongs in the grid rather than on the Import tab: the Import tab is
-- the character at the keyboard, and the question this answers is a warband
-- question. Before this, finding out which of nine alts had an unapplied plan
-- meant logging into nine alts.
local function fromSite(groups, cols)
  local g = group("from warband.pro")

  addRow(g, cols, "gear set", function(_, col)
    local rec = col.plan and col.plan.gearset
    if not rec then return nil end
    local items = type(rec.items) == "table" and #rec.items or 0
    local specs = 0
    if type(rec.bySpec) == "table" then
      for _ in pairs(rec.bySpec) do specs = specs + 1 end
    end
    local tip = {}
    if rec.set then tip[#tip + 1] = { "set", tostring(rec.set) } end
    if specs > 0 then tip[#tip + 1] = { "specs solved", tostring(specs) } end
    tip[#tip + 1] = { "pasted", ns.ago(rec.generatedAt) }
    tip[#tip + 1] = "/warband equip applies it"
    if items == 0 then return cell("stored", "plain", tip) end
    return cell(items .. " to wear", "good", tip)
  end)

  addRow(g, cols, "clear-out", function(_, col)
    local rec = col.plan and col.plan.junk
    if not rec then return nil end
    local n2 = type(rec.items) == "table" and #rec.items or 0
    -- **By verdict and reason, never by name.** The wire carries `k`, `id`,
    -- `s`, `r` and `ilvl` and no display name at all — Junk.lua resolves names
    -- live from the item string, against the bags as they are now, because a
    -- name stored from an hour ago is a name for an item that may have moved.
    -- A pure model has no client to ask, so it counts what it actually has.
    local byVerdict, byReason = {}, {}
    for _, it in ipairs(rec.items or {}) do
      local k = it.k or "sell"
      byVerdict[k] = (byVerdict[k] or 0) + 1
      if it.r then byReason[it.r] = (byReason[it.r] or 0) + 1 end
    end
    local tip = {}
    local VERDICT = { sell = "to sell", de = "to disenchant", del = "to destroy" }
    for _, k in ipairs({ "sell", "de", "del" }) do
      if byVerdict[k] then tip[#tip + 1] = { VERDICT[k], tostring(byVerdict[k]) } end
    end
    for _, r in ipairs({ "gap", "unusable", "dupe", "dominated" }) do
      if byReason[r] then tip[#tip + 1] = { r, tostring(byReason[r]) } end
    end
    tip[#tip + 1] = { "pasted", ns.ago(rec.generatedAt) }
    if n2 == 0 then return cell("none", "good", tip) end
    return cell(tostring(n2), "warn", tip)
  end)

  addRow(g, cols, "builds", function(_, col)
    local rec = col.plan and col.plan.gearset
    local builds = rec and rec.builds
    if type(builds) ~= "table" then return nil end
    local n2 = 0
    for _ in pairs(builds) do n2 = n2 + 1 end
    if n2 == 0 then return nil end
    return cell(tostring(n2), "plain", { { "specs assigned", tostring(n2) },
      "which saved build is for raid, m+, delves" })
  end)

  -- The age of the plan itself, as its own row, because it is the number that
  -- decides whether to trust any of the three above. A plan from before the
  -- last raid night is describing bags that have since changed.
  addRow(g, cols, "plan age", function(_, col)
    local plan = col.plan
    if not plan then return nil end
    local at = plan.gearset and plan.gearset.generatedAt or (plan.junk and plan.junk.generatedAt)
    if not at then return nil end
    -- `ns.dot`'s thresholds, reused rather than re-guessed: a plan and a scan
    -- go stale at the same rate because they describe the same bags.
    local d = ns.dot(at)
    return cell(ns.ago(at), d == "green" and "good" or (d == "red" and "bad" or "warn"),
      { "the site's answer, as pasted", "paste again after a night's play" })
  end)

  push(groups, g)
end

-- ── the model ───────────────────────────────────────────────────────────────

--- The whole grid: sorted columns, and the groups of rows worth drawing.
---
--- `warbandBank` rides along because it is the one thing in this DB that is
--- account-wide rather than per-character, so it has no column to live in and
--- would otherwise be the only stored fact the roster could not show.
function Roster.Build(db, selfGuid)
  local cols = Roster.Columns(db, selfGuid)
  -- The inbox, attached per column. Kept off `Roster.Columns` because a caller
  -- that only wants the header row should not pay for it, and kept out of
  -- `char` because `db.chars[guid]` is a wire CharacterObject and the plan is
  -- emphatically not part of the wire going out.
  local junk = type(db) == "table" and type(db.junk) == "table" and db.junk or {}
  local gearset = type(db) == "table" and type(db.gearset) == "table" and db.gearset or {}
  for i = 1, #cols do
    local j, gs = junk[cols[i].guid], gearset[cols[i].guid]
    if j or gs then cols[i].plan = { junk = j, gearset = gs } end
  end

  -- The only option the grid reads. It arrives on `db` rather than as an
  -- argument because `db.opts` is where every other switch in this addon lives
  -- and the model already has the whole DB in its hand.
  local opts = type(db) == "table" and type(db.opts) == "table" and db.opts or {}

  local groups = {}
  if #cols > 0 then
    thisWeek(groups, cols)
    lockouts(groups, cols)
    currencies(groups, cols, opts.allCurrencies and true or false)
    professions(groups, cols)
    pockets(groups, cols)
    fromSite(groups, cols)
  end

  local wb = type(db) == "table" and db.warbandBank or nil
  return {
    columns = cols,
    groups = groups,
    warbandBank = wb and {
      ago = ns.ago(wb.seenAt),
      by = wb.seenByName,
      tabs = type(wb.tabs) == "table" and #wb.tabs or 0,
      tabsOwned = num(wb.tabsOwned),
      gold = wb.gold and money(wb.gold) or nil,
    } or nil,
  }
end

-- ── the glance ──────────────────────────────────────────────────────────────

-- **SavedInstances' primary tooltip — the half of its interface that is not the
-- grid.** Hovering its icon is not how you reach the answer there, it *is* the
-- answer, and opening a window is the follow-up question. Ours has said "6
-- characters · freshest 4m ago" and then listed slash commands since 1.5.0,
-- which tells a player the addon is installed and nothing about the warband it
-- has been watching.
--
-- A hover can carry four lines before it stops being a glance, so it carries
-- the four that decide a night: a vault slot already earned, the keystone in
-- the bag, what is locked, and what has stopped accruing. The grid answers each
-- of those per character; this answers them ACROSS the warband, which is the
-- only shape in which four lines can cover twenty alts.
--
-- The grid's rules survive the compression, and the first is again the one the
-- format is most likely to destroy:
--
-- 1. **Absent is not zero.** A character whose vault has never been read is not
--    counted as having no slots — it is not counted at all. Every test below is
--    "did this character have an answer", never "was the answer zero", so an
--    unscanned alt is silent rather than reassuring.
-- 2. **A line nobody has a value for is not drawn.** A row's rule, at line
--    scale: an account with no keystone anywhere gets no keystone line, not an
--    empty one.
-- 3. **Names where a name is what you act on.** "2 characters have a keystone"
--    sends you to the grid to find out which; `Vocnar +12 · Voctara +9` does
--    not. The column sort already puts the character at the keyboard first, so
--    the name you check against leads the line for free.
--
-- Shrink-to-fit is SavedInstances' fit-to-screen, decided rather than
-- configured: a line names at most `GLANCE_NAMES` characters and reports how
-- many it did not name. A tooltip that grows with the warband ends up covering
-- the minimap it is anchored to, which is the one thing a minimap tooltip must
-- not do.
--
-- Like everything else in this file it reads only the stored DB, so the glance
-- and the grid cannot disagree — what the hover claims is what the tab shows.

local GLANCE_NAMES = 3

--- One glance line, or nil when nobody could answer.
---
--- `fn` returns the short note drawn after a character's name — `+12`, `3
--- slots` — or nil for "no answer", which is the absent case rule 1 is about.
--- Not "" and not `0`: the two are the same pixels on screen and the opposite
--- fact, which is the whole reason this is a separate return value.
local function glance(cols, label, tone, fn)
  local parts, more = {}, 0
  for i = 1, #cols do
    local note = fn(cols[i].char, cols[i])
    if note ~= nil then
      if #parts < GLANCE_NAMES then
        parts[#parts + 1] = { name = cols[i].name, class = cols[i].class, note = note }
      else
        more = more + 1
      end
    end
  end
  if #parts == 0 then return nil end
  return { label = label, tone = tone, parts = parts, more = more }
end

--- What the minimap hover says, before the window is opened.
---
--- Colours are absent here for the reason cell tones are: UI.lua owns the
--- palette, including the class colour a name is drawn in, and a model carrying
--- hex would have to know which surface it was painted on.
function Roster.Glance(db, selfGuid)
  local cols = Roster.Columns(db, selfGuid)
  local lines = {}
  local function add(line) if line then lines[#lines + 1] = line end end

  -- A slot already earned leads, because it is the only thing on this list that
  -- can be lost by not logging in before Tuesday.
  add(glance(cols, "vault ready", "good", function(c)
    local v = c.weeklyVault
    if type(v) ~= "table" then return nil end
    local unlocked = 0
    for _, b in ipairs(VAULT) do
      local bucket = v[b.key]
      if type(bucket) == "table" then unlocked = unlocked + (unlockedN(bucket.unlocked) or 0) end
    end
    if unlocked == 0 then return nil end
    return unlocked .. (unlocked == 1 and " slot" or " slots")
  end))

  add(glance(cols, "keystone", "plain", function(c)
    local k = c.keystone
    if type(k) ~= "table" or not num(k.level) then return nil end
    return "+" .. k.level
  end))

  -- Live lockouts only, by the same absolute-`resetTime` rule the grid's rows
  -- use. A glance is the worst surface on which to state something known to be
  -- false: there is no cell to hover for the detail that would correct it.
  add(glance(cols, "saved", "warn", function(c)
    local n = 0
    for _, inst in ipairs(c.instances or {}) do
      if not inst.resetTime or ns.hence(inst.resetTime) then n = n + 1 end
    end
    if n == 0 then return nil end
    return tostring(n)
  end))

  -- A currency at its total cap has stopped accruing, and everything earned
  -- towards it from here is thrown away — the one currency state worth
  -- interrupting a glance for. Reaching a WEEKLY cap is the opposite news, and
  -- stays in the grid's currency hover where it already is.
  add(glance(cols, "at cap", "bad", function(c)
    local hit
    for _, cur in ipairs(c.currencies or {}) do
      local q, max = num(cur.quantity), num(cur.maxQuantity)
      -- `maxQuantity` 0 is uncapped per CONTRACT.md, not a cap of nothing.
      if q and max and max > 0 and q >= max and cur.name then
        hit = hit or {}
        hit[#hit + 1] = cur.name
      end
    end
    if not hit then return nil end
    if #hit == 1 then return hit[1] end
    return #hit .. " currencies"
  end))

  local freshest
  for i = 1, #cols do
    local seen = cols[i].char.seenAt and cols[i].char.seenAt.lastSeen
    if type(seen) == "number" and (not freshest or seen > freshest) then freshest = seen end
  end

  return {
    characters = #cols,
    ago = ns.ago(freshest),
    dot = ns.dot(freshest),
    lines = lines,
  }
end
