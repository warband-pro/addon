-- WarbandPro / UI.lua
-- One window, four tabs: Roster, Export, Import, Options. Built entirely from
-- the templates Blizzard's own panels use — ButtonFrameTemplate for the chrome,
-- PanelTabButtonTemplate for the tabs, InputBoxTemplate and InsetFrameTemplate
-- inside — so the window looks like the game and inherits whatever the player
-- has set: UI scale, font scale, colorblind text. No hand-rolled backdrop, no
-- pixel skin of our own.
--
-- The jobs, in the order the tabs sit in. Roster: the grid — every character
-- across the top, everything the addon knows about them down the side, which
-- is the SavedInstances arrangement and is the only tab you READ rather than
-- act on. Export: show what the bundle contains and how stale it is, then put
-- the string somewhere Ctrl+C can reach it — WoW has no SetClipboard, so an
-- auto-highlighted multiline EditBox is the only path that works. Import: take
-- the string warband.pro sends back and turn it into a clear-out list with live
-- Sell and Disenchant buttons.
--
-- **The roster reads the same DB the export encodes**, so it is not a second
-- source of truth and cannot drift from the bundle: what the grid shows is what
-- the paste will carry, which is the whole reason it is worth having in a
-- window whose other job is producing that paste.
--
-- The two paste rules survive the merge into one window because they belong to
-- widgets, not frames. The export box is copied FROM and reverts anything
-- typed into it, so a broken paste never reaches the website; the import box
-- is pasted INTO and its text is the player's. Two widgets on two tabs, each
-- carrying its own rule unconditionally.

local _, ns = ...

local UI = {}
ns.UI = UI

-- Native text colors, not the website's: this window lives inside the game's
-- own chrome now, so the freshness dots use the client's traffic-light palette
-- and the muted lines use its gray.
--
-- **Two inks, and the split is what turns the grid into a glance.** A LABEL is
-- chrome — a group's name, a row's name, the words around a count — and it is
-- drawn in the client's grey. A VALUE is the thing you came for and it is
-- drawn in its plain white, the brightest ink this window has. Everything that
-- is neither is a TONE, and the tones are the whole attention system: green
-- earned, gold close, red gone, and a class colour for whose it is.
--
-- **This used to be one weight.** Labels, headings and values all arrived in
-- `GameFontHighlightSmall`, so a wall of same-brightness text is what the tab
-- and the hover opened onto and the number you were after had to be found
-- rather than seen. Dimming the chrome is the whole of the fix — no tone
-- changed, no colour was added, and nothing about a value changed except what
-- is around it.
local DOT = {
  green  = "|cff00ff00*|r",
  yellow = "|cffffd100*|r",
  red    = "|cffff2020*|r",
  never  = "|cff808080*|r",
}
local MUTED, WARN, BAD, GOOD = "808080", "ffd100", "ff2020", "00ff00"
-- The section line inside a per-cell tooltip: which row the cell under the
-- mouse belongs to, over its detail. SavedInstances marks a sub-header — an
-- LFR wing, a group of rows — in orange, one step off the gold it marks a
-- title with. It stays here and nowhere else: a GameTooltip has no texture to
-- rule a section off with, so colour is the only structure available to it.
-- Both grids used to take it for their group headings and gave it up to the
-- ink ramp above — they have a stripe, which is a line doing a line's job.
local ORANGE = "ff8000"

local TAB_ROSTER, TAB_EXPORT, TAB_IMPORT, TAB_OPTIONS = 1, 2, 3, 4
local MAX_ROWS = 8
local JUNK_ROWS = 12
-- The gear-set list: one row per item on the wire. Sixteen is every real slot,
-- so the pool never has to grow, and the well below anchors under whatever is
-- drawn rather than under a fixed height.
local GS_ROWS, GS_LINE = 16, 16

-- The grid's geometry. Two numbers are fixed because the text decides them: a
-- label column has to hold "Nerub-ar Palace (Heroic)", and a cell has to hold
-- `4,500/20,000`. Everything else follows from the size of the window, which
-- the player now sets by dragging its corner.
--
-- **This was a constant six columns and a constant 24 rows, and both were wrong
-- in the same way** — a warband is not a fixed size. Six columns meant an
-- eight-alt player read six of them and paged for the rest, which is precisely
-- what the read-across arrangement exists to avoid. Twenty-four rows was worse
-- than a limit and closer to a lie: the model builds every row and the scroll
-- child was sized for all of them, but only the first 24 were ever painted, so
-- a real warband (16 currencies, 9 professions, the vault, pockets — 38 lines
-- measured) scrolled off the bottom of its own grid into blank space. Both
-- pools now grow to whatever the model and the window between them ask for.
local LABEL_W, CELL_W, LINE_H = 152, 56, 14

-- The v2 sidebar takes the left of the roster panel; the grid starts past it.
local SIDEBAR_W, SIDE_ROW_H = 184, 16
local SLOT_SHORT = { raid = "raid", mplus = "mythic+", world = "world" }
-- The icon a row may carry, and the room the label gives up for it. Sized off
-- the line so the two stay in step if the grid ever changes row height.
local ROW_ICON = LINE_H - 2
local ROW_ICON_GAP = 3

-- The gutter left of the first cell. The well is already anchored 20px clear of
-- UIPanelScrollFrameTemplate's bar, so the bar is NOT subtracted again here —
-- doing so is how a 560px window that has always held six columns quietly
-- starts holding five.
local ROSTER_GUTTER = 6

-- Window bounds, and the default is the one worth explaining. It is derived
-- rather than chosen: eight columns is 152 + 8x56, the gutter is 6, and the
-- chrome between the frame's edge and the scroll frame's costs about 72 across
-- the inset, the panel, the well and the scrollbar gutter — so 680 is the width
-- at which a warband of eight is on screen the moment the window opens.
--
-- **Eight, not the six this window used to fit, because opening on a partial
-- warband is the complaint.** The minimum stays at the old 560 so a player who
-- wants it narrow can still have it; below that the label column and a usable
-- cell stop fitting together.
--
-- **The minimum height is set by the Options tab, not the grid.** Its controls
-- are laid out top-down at a fixed pitch against a version line pinned to the
-- panel's bottom, so the tallest tab decides how short the window may get. The
-- fifth checkbox arrived with the currency filter and 420 no longer cleared the
-- footer; 460 does, with room for a description that wraps to three lines at
-- the minimum width.
local WIN_DEF_W, WIN_DEF_H = 680, 520
local WIN_MIN_W, WIN_MIN_H = 560, 460
local WIN_MAX_W, WIN_MAX_H = 1600, 1000

local frame, panels, tabs
local editBox, header, footer, rows, help
-- The slice row on the export tab: which characters the string covers, and
-- which page of a warband too large for one bundle. Declared up here because
-- buildExport creates them and refreshExport repaints them.
local scopeAll, scopeOne, slimButton, pageLabel, pagePrev, pageNext
local junkPaste, junkHeader, junkFooter, junkRows, junkChild
local gsHeader, gsButton, gsList, gsRows
local rosterHead, rosterFoot, rosterCols, rosterLines, rosterChild, rosterPrev, rosterNext
local rosterScroll
local sideFrame, sideRows, vaultStrip, vaultSlots, rosterWell
-- Forward-declared: buildRoster calls these before their definitions read.
local buildSidebar, buildVaultStrip
local optionChecks = {}

-- Which characters the export covers: "bundle" is the whole warband and
-- "current" is the character at the keyboard. It is a panel control now rather
-- than only a slash command, and it does NOT survive a close — every open
-- starts on the whole warband, because that is the scope the camp flow relies
-- on and the gear flows are one click from it either way. See UI.Open.
UI.mode = "bundle"
-- Which six characters the grid is showing. Same idiom as UI.page below and
-- for the same reason: a warband can be larger than the surface that draws it.
UI.rosterPage = 1
-- Which page of a warband too large for one bundle is in the box. Always 1
-- unless `/warband copy 2` asked for another, and reset by any plain open so
-- the panel cannot sit on page 3 days after the player went looking for it.
UI.page = 1

-- Which roster character the sidebar narrowed the grid to: a guid, or nil
-- for the whole warband. Survives a close; a reading position, not a copy.
UI.rosterSelect = nil

-- ── window chrome ───────────────────────────────────────────────────────────

local function makeTab(i, text)
  local tab = CreateFrame("Button", "WarbandProFrameTab" .. i, frame, "PanelTabButtonTemplate")
  tab:SetID(i)
  tab:SetText(text)
  if i == 1 then
    tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
  else
    tab:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", 3, 0)
  end
  tab:SetScript("OnClick", function(self)
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    UI.SelectTab(self:GetID())
  end)
  PanelTemplates_TabResize(tab, 0)
  return tab
end

local function makePanel()
  local p = CreateFrame("Frame", nil, frame)
  p:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 10, -8)
  p:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -10, 8)
  p:Hide()
  return p
end

-- A recessed well for text, the same InsetFrameTemplate the character pane
-- nests for its stats block.
local function makeWell(parent)
  local well = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  return well
end

-- ── export tab ──────────────────────────────────────────────────────────────

-- Step 2 read "warband.pro > Import", and the site has no such destination:
-- import is a field in the rail, reached with `i`, on every route. The README
-- said `/settings/import` (a route that has been deleted) and docs/UI.md said
-- the Camp page's top bar — three stale names for one field, none of them
-- right, in the one instruction a player follows every night. What ships is
-- what the site actually does.
--
-- Button labels stay capitalized ("Select all", "Sell", "Disenchant") while
-- every line of panel prose is lowercase: the buttons are Blizzard's chrome
-- and match "Accept" and "Cancel" beside them, and the prose is ours and
-- matches the chat lines it shares a voice with.
local HELP_STEPS = "1. Ctrl+C copies (already selected)   2. on warband.pro press i, paste, Enter   3. Esc closes"

-- Repaint the instruction line for whether the string has been copied yet.
-- `UI.copied` is per-render rather than persisted: it answers "did you copy
-- *this* string", and a fresh build is a fresh string.
local function refreshHelp()
  if not help then return end
  if UI.copied then
    help:SetText(format("|cff%scopied|r  ·  on warband.pro press i, paste, Enter", GOOD))
  else
    help:SetText(HELP_STEPS)
  end
end

-- The slice buttons rebuild the string, and refreshExport is defined below
-- them because it needs renderRows. Forward-declared rather than reordered:
-- the tab's builder reading before its painter is the shape every other tab
-- in this file has.
local refreshExport

local function buildExport()
  local p = panels[TAB_EXPORT]

  header = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetJustifyH("LEFT")

  rows = {}
  for i = 1, MAX_ROWS do
    local row = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row:SetPoint("TOPLEFT", 0, -18 - (i - 1) * 14)
    row:SetPoint("TOPRIGHT", 0, -18 - (i - 1) * 14)
    row:SetJustifyH("LEFT")
    rows[i] = row
  end

  -- ── the slice row ─────────────────────────────────────────────────────────
  --
  -- The scope was always in the wire switches and never on the screen: the
  -- whole warband opened by default and the smaller slice lived behind
  -- `/warband copy current`, a command a player mid-dungeon will not type. Both
  -- mid-session gear flows (best-in-bags, the clear-out list) want this
  -- character and the camp flow wants the warband, so the choice is one click
  -- either way and neither one is a command any more.
  --
  -- Blizzard's own "you are here" idiom for a two-way choice: the button for
  -- the scope the panel is already on is disabled. Same SetEnabled call the
  -- roster's pager uses for an edge it cannot cross, so a player who has used
  -- one has read the other.
  local SLICE_Y = -(18 + MAX_ROWS * 14 + 4)

  scopeAll = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  scopeAll:SetSize(104, 20)
  scopeAll:SetPoint("TOPLEFT", 0, SLICE_Y)
  scopeAll:SetText("Whole warband")
  scopeAll:SetScript("OnClick", function() UI.SetScope("bundle") end)

  scopeOne = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  scopeOne:SetSize(104, 20)
  scopeOne:SetPoint("LEFT", scopeAll, "RIGHT", 4, 0)
  scopeOne:SetText("This character")
  scopeOne:SetScript("OnClick", function() UI.SetScope("current") end)

  -- Paging, for the warband larger than one bundle holds. The header used to
  -- name `/warband copy 2` here; the arrows are the same walk without the
  -- command, and they only exist when there is somewhere to walk to.
  pageNext = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  pageNext:SetSize(24, 20)
  pageNext:SetPoint("TOPRIGHT", -20, SLICE_Y)
  pageNext:SetText(">")
  pageNext:SetScript("OnClick", function() UI.SetPage(UI.page + 1) end)

  pagePrev = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  pagePrev:SetSize(24, 20)
  pagePrev:SetPoint("RIGHT", pageNext, "LEFT", -2, 0)
  pagePrev:SetText("<")
  pagePrev:SetScript("OnClick", function() UI.SetPage(UI.page - 1) end)

  pageLabel = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pageLabel:SetPoint("RIGHT", pagePrev, "LEFT", -6, 0)
  pageLabel:SetJustifyH("RIGHT")

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", 0, SLICE_Y - 24)
  well:SetPoint("BOTTOMRIGHT", -20, 36)

  local scroll = CreateFrame("ScrollFrame", "WarbandProExportScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", well, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, 8)

  editBox = CreateFrame("EditBox", nil, scroll)
  editBox:SetMultiLine(true)
  editBox:SetMaxLetters(0)          -- Blizzard's default cap would truncate us
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetWidth(470)
  -- The box wraps at its own width, so a window the player widened for the
  -- roster has to widen the string too — otherwise the export tab keeps a
  -- 470px column of text in the middle of a 1200px window.
  scroll:SetScript("OnSizeChanged", function(self, w)
    if w and w > 0 then editBox:SetWidth(w) end
  end)
  editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- The string is not editable in any useful sense; if the user types into it,
  -- put it back rather than let a broken paste reach the website. SetText from
  -- code passes userInput false, so this cannot loop.
  editBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput and UI.current then
      self:SetText(UI.current)
      self:HighlightText()
    end
  end)
  -- The one moment this addon exists for, and nothing acknowledged it.
  --
  -- The player's whole job here is Ctrl+C. WoW gives an addon no way to read
  -- the clipboard, so the copy itself cannot be confirmed — but the keystroke
  -- can be seen, and seeing it is enough to say "that landed, here is what to
  -- do next". Before this the window gave no flash, no state change, no sound:
  -- the only evidence was /warband status's "last copied", which was stamped
  -- when the panel *rendered* (below) and so reset itself every time the window
  -- was opened and closed without a keypress. A readout answering the wrong
  -- question is worse than no readout.
  editBox:SetScript("OnKeyDown", function(_, key)
    if key ~= "C" or not IsControlKeyDown() then return end
    if not UI.current or UI.current == "" then return end
    if ns.Store.Ready() then ns.Store.db.lastExport = ns.now() end
    UI.copied = true
    refreshHelp()
  end)
  scroll:SetScrollChild(editBox)

  help = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("BOTTOMLEFT", 0, 18)
  help:SetPoint("BOTTOMRIGHT", 0, 18)
  help:SetJustifyH("LEFT")
  help:SetText(HELP_STEPS)

  footer = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 0, 2)
  footer:SetJustifyH("LEFT")

  local selectAll = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  selectAll:SetSize(96, 22)
  selectAll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
  selectAll:SetText("Select all")
  selectAll:SetScript("OnClick", function()
    editBox:SetFocus()
    editBox:HighlightText()
  end)

  -- The soft cap, as the offer it always was rather than the sentence it used
  -- to be. Past ns.SOFT_BYTES the footer read "(large — try /warband copy
  -- current)": a warning whose remedy was a command, printed at the one moment
  -- the player is least likely to go and learn one. The remedy is now the
  -- button beside the warning, and it is deliberately the second door onto the
  -- same scope the slice row already offers — the row is where the choice
  -- lives, this is where the warning is, and a warning you can act on without
  -- moving your eyes is worth one extra widget.
  slimButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  slimButton:SetSize(136, 22)
  slimButton:SetPoint("BOTTOMRIGHT", selectAll, "BOTTOMLEFT", -4, 0)
  slimButton:SetText("Just this character")
  slimButton:SetScript("OnClick", function() UI.SetScope("current") end)
  slimButton:Hide()
end

local function renderRows(summary)
  for i = 1, MAX_ROWS do rows[i]:SetText("") end
  if #summary == 0 then
    rows[1]:SetText("|cff" .. MUTED .. "no characters scanned yet — log in on a character and it lands here|r")
    return
  end
  local shown = math.min(#summary, MAX_ROWS)
  for i = 1, shown do
    local r = summary[i]
    local line = format("%s %s|cff%s-%s|r  %s", DOT[r.dot] or DOT.never, r.name, MUTED, r.realm or "?", r.ago)
    if r.bankAgo ~= "never" then line = line .. format("  |cff%sbank %s|r", MUTED, r.bankAgo) end
    rows[i]:SetText(line)
  end
  if #summary > MAX_ROWS then
    rows[MAX_ROWS]:SetText(format("|cff%s+%d more in the bundle|r", MUTED, #summary - MAX_ROWS + 1))
  end
end

-- Repaint the slice row for the scope the panel is on and the bundle it just
-- built. Everything here is derived from that bundle rather than remembered:
-- `pages` is absent on a warband that fits in one, so the arrows exist exactly
-- when there is a second page to reach.
local function refreshScope(payload, bytes)
  if not scopeAll then return end
  local current = UI.mode == "current"
  scopeAll:SetEnabled(current)
  scopeOne:SetEnabled(not current)

  local b = payload and payload.bundle
  local pages = b and b.pages
  local page = (b and b.page) or 1
  -- Adopt the page that was actually built. Bundle.Build clamps, so `/warband
  -- copy 99` on a three-page warband hands back page 3 while UI.page still says
  -- 99 — and an arrow stepping from 99 would clamp to 3 again and look dead.
  -- The panel's idea of where it is has to be the bundle's.
  if b then UI.page = page end
  -- One character never pages, so the arrows belong to the warband scope only.
  local paged = (not current and pages and pages > 1) and true or false
  pagePrev:SetShown(paged)
  pageNext:SetShown(paged)
  pageLabel:SetShown(paged)
  if paged then
    pageLabel:SetText(format("page %d of %d", page, pages))
    pagePrev:SetEnabled(page > 1)
    pageNext:SetEnabled(page < pages)
  end

  slimButton:SetShown((not current and bytes and bytes > ns.SOFT_BYTES) and true or false)
end

function refreshExport()
  local str, bytes, payload, rawBytes =
    ns.Export.Build({ currentOnly = UI.mode == "current", page = UI.page })
  UI.current = str or ""
  editBox:SetText(UI.current)
  -- A new string has not been copied yet, whatever happened to the last one.
  UI.copied = false
  refreshHelp()

  local summary = ns.Bundle.Summary(payload)
  renderRows(summary)
  refreshScope(payload, bytes)

  if not str then
    -- One plain sentence before the diagnostics. `/warband status` is what the
    -- README itself calls a debug dump — event counts, per-section stamps, a raw
    -- Lua error — and this was the one path that sent an ordinary player to it.
    header:SetText("|cff" .. BAD .. "could not build the bundle|r — nothing to copy yet"
      .. "; /warband status has the detail")
    footer:SetText("")
  elseif #summary == 0 then
    -- An empty bundle is not a bundle. `Bundle.Build` has no empty guard, so
    -- with nothing scanned the string still built, the footer still reported a
    -- byte count, and the box still auto-highlighted — a perfectly copyable
    -- payload carrying `characters: []`, which the site rejects out of hand.
    -- The row above already says why; this stops the panel contradicting it.
    header:SetText(format("|cff%snothing to send yet|r — log in on a character and it lands here", WARN))
    footer:SetText("")
    UI.current = ""
    editBox:SetText("")
  else
    -- A vault with a tab missing reads as a vault that small, so the header
    -- names the gap rather than letting the age stand for completeness: the
    -- stamp is honest about when we looked and says nothing about how much of
    -- it we saw.
    local wb = ns.Store.db and ns.Store.db.warbandBank
    local bank = (wb and wb.seenAt)
      and format("  ·  warband bank %s (by %s)%s", ns.ago(wb.seenAt), wb.seenByName or "?",
        wb.partial and format(", %d of %d tabs", #(wb.tabs or {}), wb.tabsOwned) or "")
      or "  ·  warband bank never seen"
    -- Two warnings the panel used to leave for the far side of the copy.
    --
    -- A bundle where every character is red is worth knowing about *before*
    -- alt-tabbing to paste it, not after: the site says "half stale" once it
    -- has the string, by which point the effort is spent. The dots already
    -- carry the per-character answer; this is the one about the bundle.
    local allStale = true
    for i = 1, #summary do
      if summary[i].dot ~= "red" and summary[i].dot ~= "never" then allStale = false break end
    end
    -- And the cap. One bundle holds MAX_CHARS characters, so a larger warband
    -- goes out a page at a time and the header has to say how much is waiting —
    -- the count alone reads as a loss, and the old line made that literal by
    -- offering `/warband clear <name>` as the remedy. Deleting an alt is the
    -- wrong answer for the player who has twenty-one of them; the site merges
    -- pages rather than replacing what it holds, so all of them fit if they are
    -- all sent.
    --
    -- Which page this is, and the walk to the next one, moved to the arrows on
    -- the slice row — this line said "/warband copy 2 for the next 20" and was
    -- the last instruction on the tab that was a command rather than a control.
    local dropped = payload.bundle.droppedOverCap
    local pages = payload.bundle.pages
    local warnLine = ""
    if dropped and pages then
      warnLine = format("  |cff%s·  %d of %d — the rest go out a page at a time|r",
        WARN, payload.bundle.count, payload.bundle.count + dropped)
    elseif allStale then
      warnLine = format("  |cff%s·  all stale — log those alts in again for fresher numbers|r", WARN)
    end
    -- The scope in words as well as in the buttons. "1 character" is not an
    -- answer for the player who has one: it reads the same whether the panel
    -- sliced the warband or the warband is that small.
    local scope = UI.mode == "current" and "this character only  ·  " or ""
    header:SetText(format("%s%d character%s  ·  freshest %s%s%s",
      scope, #summary, #summary == 1 and "" or "s",
      #summary > 0 and ns.ago(payload.bundle.freshestSeenAt) or "never", bank, warnLine))
    -- The "(large — try /warband copy current)" note is gone from here: past the
    -- soft cap the offer is the [Just this character] button beside this line,
    -- which refreshScope shows. The byte count stays, because it is a fact.
    local note = bytes > ns.SOFT_BYTES and format("  |cff%s·  large|r", WARN) or ""
    footer:SetText(format("|cff%s%s  ·  %d bytes from %d of JSON|r%s", MUTED, ns.WIRE, bytes, rawBytes or 0, note))
    -- `lastExport` is NOT stamped here any more — 2026-08-24.
    --
    -- It was, and /warband status reported it as "last copied", so opening this
    -- window and closing it again without touching the keyboard reset the
    -- answer to "just now". The stamp belongs to the copy, and the copy is a
    -- keystroke this panel can see; it is written in the editBox's OnKeyDown.
  end

  -- Highlighting only sticks once the frame has actually drawn.
  C_Timer.After(0, function()
    if frame:IsShown() and panels[TAB_EXPORT]:IsShown() then
      editBox:SetFocus()
      editBox:HighlightText()
    end
  end)
end

-- ── import tab ──────────────────────────────────────────────────────────────

local QUALITY_HEX = {
  [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
  [4] = "a335ee", [5] = "ff8000",
}

--- One row: a label, a [sell] button, and a secure disenchant button.
---
--- The secure button is created ONCE, here, and never again. Its attributes are
--- re-baked out of combat on every resolve; creating or reparenting a secure
--- frame during combat is the taint this addon has spent its whole life
--- avoiding, and a pool built up front never has to.
local function buildJunkRow(parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(18)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
  row:SetPoint("TOPRIGHT", 0, -(i - 1) * 18)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", 2, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -140, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)

  row.sell = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.sell:SetSize(52, 16)
  row.sell:SetPoint("RIGHT", -80, 0)
  row.sell:SetText("Sell")

  row.de = CreateFrame("Button", "WarbandProJunkDE" .. i, row, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  row.de:SetSize(76, 16)
  row.de:SetPoint("RIGHT", -2, 0)
  row.de:SetText("Disenchant")
  row.de:RegisterForClicks("AnyUp", "AnyDown")

  return row
end

--- One gear-set row: the item's icon, the slot it is for, the item's name in
--- its quality colour with its item level, and where it is right now.
---
--- A Frame with the mouse enabled rather than a Button: nothing here is
--- pressed. The hover is the client's own item tooltip off the wire's item
--- string — `SetHyperlink` takes an `item:` string directly — so a player
--- can read the stats of the thing the site picked without leaving the tab,
--- which is the other half of what the AMR screen does with its icons.
local function buildGearRow(parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(GS_LINE)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * GS_LINE)
  row:SetPoint("TOPRIGHT", 0, -(i - 1) * GS_LINE)
  row:EnableMouse(true)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(GS_LINE - 2, GS_LINE - 2)
  row.icon:SetPoint("LEFT", 2, 0)
  -- The stock icon border is baked into the texture's outer 6%; cropping it
  -- is what every action bar does, and it is why a 14px icon still reads.
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.slot:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.slot:SetWidth(64)
  row.slot:SetJustifyH("LEFT")
  row.slot:SetWordWrap(false)

  row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.state:SetPoint("RIGHT", -4, 0)
  row.state:SetJustifyH("RIGHT")
  row.state:SetWordWrap(false)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row.slot, "RIGHT", 4, 0)
  row.label:SetPoint("RIGHT", row.state, "LEFT", -8, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)

  row:SetScript("OnEnter", function(self)
    if not self.s and not self.buyID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.s then
      -- The client's own item tooltip for the wire's item string. A string the
      -- client cannot resolve leaves the tooltip empty rather than raising.
      ns.safe(GameTooltip.SetHyperlink, GameTooltip, self.s)
    else
      -- A shopping row names something that is not in a bag, so there is no
      -- item string to hang a tooltip on — only an id.
      ns.safe(GameTooltip.SetItemByID, GameTooltip, self.buyID)
      if ns.GearSet.ahOpen then
        GameTooltip:AddLine("Click to search the auction house", 0.6, 0.6, 0.6)
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- The one thing a shopping row can do. Every other row in this list is inert
  -- by design — the gear set is applied by its button, never by clicking a
  -- line — and this stays inert too unless the auction house is open, which
  -- `SearchAuction` checks for itself rather than trusting the caller.
  -- `OnMouseUp`, not `OnClick`: this row is a Frame with EnableMouse, and a
  -- Frame has no OnClick at all — the handler would simply never fire, which
  -- is the quiet kind of wrong.
  row:SetScript("OnMouseUp", function(self, button)
    if not self.buyID or button ~= "LeftButton" then return end
    ns.GearSet.SearchAuction({ state = "buy", id = self.buyID })
  end)
  return row
end

--- Name, quality and icon for an item string, from the client's item cache.
---
--- `C_Item.GetItemInfo` answers nil for an item this session has never seen —
--- the one in your bank — and GET_ITEM_INFO_RECEIVED (Core.lua) redraws when
--- it arrives; until then the row says `item <id>` in plain text. The icon
--- is asked for by id when the info is not there yet, because
--- `GetItemIconByID` is instant for any id the client has art for.
local function itemLook(row)
  local name, quality, icon = ns.safe(function(s)
    local n, _, q, _, _, _, _, _, _, tex = C_Item.GetItemInfo(s)
    return n, q, tex
  end, row.s)
  if not icon and row.id then icon = ns.safe(C_Item.GetItemIconByID, row.id) end
  local ilvl = ns.safe(C_Item.GetDetailedItemLevelInfo, row.s)
  return name, quality, icon, ilvl
end

local GS_TONE = { good = GOOD, warn = WARN, muted = MUTED }

--- Lay the set out, one row per item, and size the list to what it drew.
local function renderGearRows(r)
  local rowsData = ns.GearSet.Rows(r)
  local shown = math.min(#rowsData, GS_ROWS)
  for i = 1, GS_ROWS do
    local w = gsRows[i]
    local d = rowsData[i]
    if not d or i > shown then
      w.s = nil
      w:Hide()
    else
      local name, quality, icon, ilvl = itemLook(d)
      local hex = QUALITY_HEX[quality or 1] or "ffffff"
      w.s = d.s
      -- Only a shopping row carries this, and it is what makes the row's
      -- tooltip and its click possible at all — there is no item string for
      -- something that is not in a bag yet.
      w.buyID = d.state == "buy" and d.id or nil
      w.icon:SetTexture(icon or ns.ICON)
      w.slot:SetText(d.name)
      -- Name, then the client's item level, then — when the site sent one —
      -- its estimated gain, in the good tone because a row here is a swap
      -- the site is proposing and the figure is why.
      local gain = ns.GearSet.GainText(d)
      -- A shopping row's best label is what the site called it — `+300
      -- Critical Strike` — because that is what the player is choosing
      -- between, and the item's own name ("Elusive Blasphemite") says less.
      -- The client's name wins when it has one, since that is what the auction
      -- house is going to show.
      local label = name or d.d or (d.id and ("item " .. d.id)) or "?"
      w.label:SetText(format("|cff%s%s|r%s%s",
        name and hex or MUTED,
        label,
        ilvl and format("  |cff%s%d|r", MUTED, ilvl) or "",
        gain ~= "" and format("  |cff%s%s|r", GOOD, gain) or ""))
      local text, tone = ns.GearSet.StateText(d)
      w.state:SetText(format("|cff%s%s|r", GS_TONE[tone] or MUTED, text))
      w:Show()
    end
  end
  -- A hidden list still needs a height, or the well anchored under it sits on
  -- the header. 1 rather than 0: some clients treat a zero-height frame as
  -- unanchored and the well jumps.
  gsList:SetHeight(shown > 0 and shown * GS_LINE + 6 or 1)
end

local function buildImport()
  local p = panels[TAB_IMPORT]

  local intro = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT")
  intro:SetPoint("TOPRIGHT")
  intro:SetJustifyH("LEFT")
  intro:SetText("paste a string from warband.pro/gear — cleanup or equip, the box reads either")

  -- The native single-line input, not a bare EditBox: InputBoxTemplate carries
  -- the recessed border every stock text field wears.
  junkPaste = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  junkPaste:SetPoint("TOPLEFT", 6, -18)
  junkPaste:SetPoint("TOPRIGHT", -2, -18)
  junkPaste:SetHeight(20)
  junkPaste:SetAutoFocus(false)
  junkPaste:SetMaxLetters(0)
  junkPaste:SetFontObject(ChatFontNormal)
  junkPaste:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    frame:Hide()
  end)
  -- No revert here — that rule belongs to the export box, whose text is ours.
  -- This one's text is the player's.
  junkPaste:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = self:GetText()
    if text == "" then return end
    -- **One decode, whichever string this is.** Two wires still reach this box
    -- — `wbc1!`, which carries everything since 1.8.0, and the equip-only
    -- `wbg1!` the site sent before it — but the prefix dispatch and the two
    -- receipts collapsed into `DecodeInbound`, which normalises both into one
    -- plan. The panel below used to be two code paths that had to agree about
    -- what "kept" counted.
    local plan, code, kind = ns.Import.DecodeInbound(text)
    if not plan then
      -- Only complain once the paste looks finished. A prefix typed one
      -- character at a time would otherwise scold on every keystroke.
      --
      -- The floor was `#text < 6` plus this test, which together swallowed
      -- anything 1-24 characters that did not start with the prefix: no
      -- decode, no message, no clear — the box simply sat there having done
      -- nothing, which is indistinguishable from a broken addon. A paste is
      -- one event, so anything arriving at once is finished by definition.
      if #text >= #ns.CLEANUP_WIRE or #text > 24 then
        junkHeader:SetText("|cff" .. BAD .. ns.Import.InboundMessage(code, kind) .. "|r")
      end
      return
    end

    -- What was there before, so the receipt can say this replaced something.
    -- Pasting a second list over a first was silent, and the two lists are
    -- usually for different characters — "nothing happened" and "your previous
    -- list is gone" looked identical.
    local had = ns.Junk.Count()
    local keptJunk = ns.Junk.Save(plan)
    local keptSets = ns.GearSet.Save(plan)
    local keptBuilds = ns.GearSet.SaveBuilds(plan)
    local keptShop = ns.GearSet.SaveShop(plan)
    self:SetText("")
    self:ClearFocus()

    if keptJunk + keptSets + keptBuilds + keptShop == 0 then
      junkHeader:SetText("|cff" .. WARN .. "that string is for characters this account has not scanned yet|r")
      return
    end

    UI.RenderJunk()
    UI.RenderGearSet()
    -- After both renders, which write this same line from the resolved state —
    -- the receipt is about the paste and has to win.
    --
    -- One sentence naming what actually arrived, rather than one of two
    -- fixed sentences. Every count is CHARACTERS, not items: each Save stores
    -- one section per GUID and skips any this account has never scanned, so
    -- "12 items" would report the wrong unit for the number the paste
    -- produced. A section that arrived for nobody is left out entirely — a
    -- zero would read as a failure rather than as a string that was never
    -- about that.
    local parts, counts = {}, {}
    local function part(n, clause)
      if n > 0 then
        parts[#parts + 1] = clause
        counts[#counts + 1] = n
      end
    end
    part(keptJunk, "a clear-out list for %d")
    part(keptSets, "gear for %d")
    part(keptBuilds, "talent builds for %d")
    part(keptShop, "a shopping list for %d")
    -- The unit rides the FIRST clause and the rest inherit it, which is how
    -- the sentence is said out loud: "gear for 2" after "a list for 3
    -- characters" is unambiguous, and repeating the noun three times is not
    -- how anyone writes a receipt.
    parts[1] = format(parts[1] .. " character%s", counts[1], counts[1] == 1 and "" or "s")
    for i = 2, #parts do
      parts[i] = format(parts[i], counts[i])
    end
    junkHeader:SetText(format("|cff%sread %s%s|r", GOOD, table.concat(parts, ", "),
      (had > 0 and keptJunk > 0) and ", replacing the last list" or ""))
  end)

  junkHeader = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  junkHeader:SetPoint("TOPLEFT", 0, -46)
  junkHeader:SetPoint("TOPRIGHT", 0, -46)
  junkHeader:SetJustifyH("LEFT")

  -- The gear-set row: one status line and one button, above the junk list —
  -- both halves of the same paste box, so they share the tab. The button is
  -- an ordinary button, not a secure one: equipping out of combat is not
  -- protected, and the tab is already gone before combat can make it so.
  gsButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  gsButton:SetSize(150, 18)
  gsButton:SetPoint("TOPRIGHT", -2, -62)
  gsButton:SetScript("OnClick", function()
    if ns.GearSet.Apply() then UI.RenderGearSet() end
  end)
  gsButton:Hide()

  gsHeader = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gsHeader:SetPoint("TOPLEFT", 0, -64)
  gsHeader:SetPoint("RIGHT", gsButton, "LEFT", -6, 0)
  gsHeader:SetJustifyH("LEFT")
  gsHeader:SetWordWrap(false)

  -- The set itself, slot by slot, under the line of counts. The counts say
  -- what the button will do; these say to WHICH items — the piece AMR's
  -- import screen has and this tab did not (app#71). Sized at render to the
  -- rows it draws, and the junk well hangs off its bottom edge, so a set of
  -- three costs three lines and no set costs none.
  gsList = CreateFrame("Frame", nil, p)
  gsList:SetPoint("TOPLEFT", 0, -84)
  gsList:SetPoint("TOPRIGHT", -20, -84)
  gsList:SetHeight(1)
  gsRows = {}
  for i = 1, GS_ROWS do
    gsRows[i] = buildGearRow(gsList, i)
  end

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", gsList, "BOTTOMLEFT", 0, 0)
  well:SetPoint("BOTTOMRIGHT", -20, 18)

  local scroll = CreateFrame("ScrollFrame", "WarbandProJunkScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 6)

  junkChild = CreateFrame("Frame", nil, scroll)
  junkChild:SetSize(470, JUNK_ROWS * 18)
  scroll:SetScrollChild(junkChild)

  junkRows = {}
  for i = 1, JUNK_ROWS do
    junkRows[i] = buildJunkRow(junkChild, i)
  end

  junkFooter = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  junkFooter:SetPoint("BOTTOMLEFT", 0, 2)
  junkFooter:SetPoint("BOTTOMRIGHT", 0, 2)
  junkFooter:SetJustifyH("LEFT")
end

--- Redraw the gear-set row from the live paperdoll and bags.
---
--- Same freshness rule as the junk list below: every count comes from the
--- resolve this call just made. The line reads as a receipt of what pressing
--- the button would do, and the button carries the number so the click is
--- never a surprise.
function UI.RenderGearSet()
  if not frame or not gsHeader then return end
  if InCombatLockdown() then return end
  local r = ns.GearSet.Resolve()
  if not r then
    -- Two silences, and they are different things to tell somebody. Since
    -- 1.8.0 a paste stores a setup per spec, so having sets and having none
    -- for the spec you are standing in is the common case after a respec —
    -- and "nothing here" would send that player back to the website for a
    -- string they already pasted.
    local stored = ns.GearSet.Summary()
    gsHeader:SetText(stored > 0
      and format("|cff%sgear set: none for this spec — %d stored for others|r", MUTED, stored)
      or "")
    gsButton:Hide()
    renderGearRows(nil)
    return
  end
  renderGearRows(r)
  local parts = {}
  if #r.ready > 0 then
    -- What the button is worth, when the site priced it: the same figure the
    -- rows carry, summed over the ones the button will actually equip.
    local gain = ns.GearSet.Gain(r)
    parts[#parts + 1] = format("%d to equip%s", #r.ready,
      gain and format("  |cff%s%s|r", GOOD, ns.GearSet.GainText({ g = gain })) or "")
  end
  if #r.already > 0 then parts[#parts + 1] = format("|cff%s%d already worn|r", MUTED, #r.already) end
  if #r.missing > 0 then
    local bank = 0
    for _, it in ipairs(r.missing) do
      if it.w == "bank" or it.w == "warbank" then bank = bank + 1 end
    end
    parts[#parts + 1] = format("|cff%s%d missing%s|r", WARN, #r.missing,
      bank > 0 and format(" (%d in your bank)", bank) or "")
  end
  if r.generatedAt then parts[#parts + 1] = format("|cff%sset from %s|r", MUTED, ns.ago(r.generatedAt)) end
  -- The set's own name leads, because with a setup per spec it is the thing
  -- that says WHICH set this row is about — and it is the same name the
  -- Equipment Manager will show.
  gsHeader:SetText(format("%s:  ", r.set or "gear set") .. table.concat(parts, "  ·  "))
  if #r.ready > 0 then
    gsButton:SetText(format("Equip %d & save set", #r.ready))
    gsButton:Enable()
    gsButton:Show()
  elseif #r.already > 0 then
    -- Everything wearable is worn; the button's remaining job is the save.
    gsButton:SetText("Save set")
    gsButton:Enable()
    gsButton:Show()
  else
    gsButton:Hide()
  end
end

--- Redraw the junk list from the live bags.
---
--- Every coordinate a button carries comes from the walk this function just
--- made, never from storage — see Junk.lua's header for why that is the whole
--- design. Called on tab select, on a bag change while shown, and when a
--- merchant opens or closes.
function UI.RenderJunk()
  if not frame then return end
  -- Secure attributes may not be written in combat. The tab hides itself on
  -- PLAYER_REGEN_DISABLED, so this is the belt to that braces.
  if InCombatLockdown() then return end
  UI.RenderGearSet()

  local rowsData, missing, generatedAt = ns.Junk.Resolve()
  local canDE = ns.Junk.CanDisenchant()
  local shown = math.min(#rowsData, JUNK_ROWS)

  junkChild:SetHeight(math.max(shown, 1) * 18)

  for i = 1, JUNK_ROWS do
    local w = junkRows[i]
    local r = rowsData[i]
    if not r or i > shown then
      w:Hide()
    else
      local hex = QUALITY_HEX[r.quality or 1] or "ffffff"
      local reason = ns.Junk.ReasonText(r)
      -- What the site said to DO with this, not only why it is on the list.
      --
      -- `Junk.VerdictLabel` has existed since the panel was written, is
      -- covered by four cases in tools/junk-test.lua — including "delete is
      -- advice, and says so" — and was never called. So a `del` row, an item
      -- warband.pro judged should be deleted by hand, rendered as an ordinary
      -- row with a live [Sell] button: the reason column explained why it was
      -- junk while the button contradicted the recommendation beside it.
      local verdict = ns.Junk.VerdictLabel(r, canDE)
      w.label:SetText(format(
        "|cff%s%s|r%s%s%s",
        hex,
        r.name or "?",
        r.ilvl and format("  |cff%s%d|r", MUTED, r.ilvl) or "",
        reason ~= "" and format("  |cff%s%s|r", MUTED, reason) or "",
        format("  |cff%s%s|r", MUTED, verdict)
      ))

      -- Sell is only ever live at a merchant. Off it, the button says why
      -- rather than disappearing — a row that changes shape when you walk up
      -- to a vendor is harder to read than one that lights up.
      --
      -- `del` is the exception, and it is why the verdict had to reach the row
      -- at all: nothing here deletes an item and the game would not allow it,
      -- so the button is not merely disabled by position — there is no sell
      -- for this row to do, and offering one was advice the site did not give.
      --
      -- Since the sell-price check it is also drawn for an item the vendor
      -- will not buy at any price, which is the same shape of problem: the
      -- click could only ever have printed "the vendor doesn't want this".
      -- `Junk.Sellable` is the one place that answers this, so the vendor
      -- window's sell-all cannot count a row the panel does not offer.
      local sellable = ns.Junk.Sellable(r)
      w.sell:SetShown(sellable)
      w.sell:SetEnabled(sellable and ns.Junk.merchantOpen)
      w.sell:SetScript("OnClick", function()
        if ns.Junk.Sell(r.bag, r.slot) then
          UI.RenderJunk()
          -- The vendor window's button counts the same rows, so a sale made
          -- from the panel has to move its label too.
          UI.RefreshMerchantButton()
        end
      end)

      -- Read off the verdict rather than recomputed from `k`, so the button and
      -- the word beside it cannot disagree — including on the fallback, where
      -- an unsellable item the site only said to sell now reads "disenchant"
      -- and has to grow the button that word promises.
      local wantsDE = verdict == "disenchant"
      if wantsDE then
        w.de:Show()
        w.de:SetAttribute("type", "macro")
        w.de:SetAttribute("macrotext", ns.Junk.DisenchantMacro(r.bag, r.slot))
      else
        w.de:Hide()
        -- Cleared rather than left stale: a hidden button holding a bag slot
        -- from two resolves ago is one Show() away from being wrong.
        w.de:SetAttribute("macrotext", nil)
      end

      w:Show()
    end
  end

  local parts = {}
  if #rowsData == 0 then
    parts[#parts + 1] = generatedAt and "nothing on the list is in your bags" or "no cleanup list yet"
  else
    parts[#parts + 1] = format("%d item%s to clear", #rowsData, #rowsData == 1 and "" or "s")
  end
  if missing and missing > 0 then
    parts[#parts + 1] = format("|cff%s%d no longer in your bags|r", MUTED, missing)
  end
  if generatedAt then
    parts[#parts + 1] = format("|cff%slist from %s|r", MUTED, ns.ago(generatedAt))
  end
  junkHeader:SetText(table.concat(parts, "  ·  "))

  if #rowsData > JUNK_ROWS then
    junkFooter:SetText(format("|cff%sshowing %d of %d|r", MUTED, JUNK_ROWS, #rowsData))
  elseif not ns.Junk.merchantOpen then
    junkFooter:SetText(format("|cff%sopen a merchant to sell  ·  paste a new list any time|r", MUTED))
  else
    junkFooter:SetText(format("|cff%sat a merchant — Sell is live|r", MUTED))
  end
end

-- ── roster tab ──────────────────────────────────────────────────────────────

-- The grid. Roster.lua decides WHAT is in it and this decides how it looks, so
-- everything below is layout — no rule about the data lives here, and the file
-- that owns the rules is the one with tests.
--
-- **Characters across, things down.** That is SavedInstances' arrangement and
-- the reason it is worth copying: the question this window exists to answer is
-- "which of them still has this", and that is a line you read across. A
-- per-character pane would answer a question nobody with nine alts is asking.
--
-- Widgets are pooled and reused rather than created per render. The grid
-- redraws on every tab switch and a warband is twenty characters deep, so
-- creating FontStrings per row would leak a few hundred frames across an
-- evening of opening and closing the window.

local TONE = { good = GOOD, warn = WARN, bad = BAD }

--- The class colour escape for a character, or plain white.
---
--- `colorStr` already carries the alpha byte, so it follows `|c` directly
--- rather than the `|cff` the rest of this file writes by hand.
local function classText(class, text)
  local c = class and ns.safe(function() return RAID_CLASS_COLORS[class] end)
  if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
  return text
end

--- A cell's FontString: the client's own number face, at this window's size.
---
--- Right-aligned AND tabular, which are two halves of one job. The alignment
--- gives a column an edge to read down — a centred value drifts with its own
--- width, so `0/2` and `43,418g` would start in different places — and the
--- face is what lines the digits up INSIDE that edge. The game font the rest
--- of this window is built from is proportional: its `1` is narrower than its
--- `8`, so a column of `3/8`, `11/8`, `6/8` wanders either side of its own
--- slashes even when every value ends flush against the same pixel.
---
--- `NumberFontNormalSmall` is the face the client draws its own numbers in,
--- and it is taken as a TEMPLATE NAME rather than as a font object because a
--- non-Latin client swaps the file behind that name — taking the name is how
--- the swap comes with us. Cells are ASCII by construction (`3/8`, `+12`,
--- `4,500/20,000`, `ready`), so nothing in one asks that font for a glyph it
--- does not have; the names, which do, are in the headers and stay in the
--- game font.
---
--- The size comes off a sibling FontString rather than from a constant: the
--- number face is two points taller than this window's small game font, and a
--- cell standing taller than the label beside it is the thing the alignment
--- was supposed to fix.
local function numberText(parent, sibling)
  -- A client without that font object costs the tabular digits, not the grid.
  local fs = ns.safe(function()
    return parent:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  end) or parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local path, _, flags = fs:GetFont()
  local size = select(2, sibling:GetFont())
  if path and size then fs:SetFont(path, size, flags or "") end
  fs:SetJustifyH("RIGHT")
  fs:SetWordWrap(false)
  return fs
end

--- Everything about a character that does not fit in a column header.
---
--- A header is 56px and a name plus a realm plus a level plus an item level
--- plus a last-seen is not, so the header identifies and the hover carries the
--- rest. Extracted from the header widget when the minimap hover grew columns
--- of its own: two grids asking the same question of a column have to get the
--- same answer, and the second copy is how they stop doing.
local function columnTip(c)
  local tip = {}
  if c.realm then tip[#tip + 1] = { "realm", c.realm } end
  if c.guild then tip[#tip + 1] = { "guild", c.guild } end
  if c.level then tip[#tip + 1] = { "level", tostring(c.level) } end
  if c.ilvl then tip[#tip + 1] = { "item level", tostring(c.ilvl) } end
  if c.gold then tip[#tip + 1] = { "gold", c.gold } end
  if c.zone then tip[#tip + 1] = { "last seen in", c.zone } end
  tip[#tip + 1] = { "scanned", c.ago }
  return tip
end

--- Paint one of Roster.lua's tips into GameTooltip and show it.
---
--- The model hands back plain strings and `{left, right}` pairs and no colour
--- at all, so the palette decision lives here with the rest of it. Two columns
--- for a pair is what makes `Ulgrax   dead` scan as a table rather than as
--- prose — the same reason the grid itself has columns.
--- `beside` is a frame the tooltip should sit alongside rather than an anchor
--- on the widget that was hovered. The grid in a window can hang its detail off
--- the cell, because there is room to the right of the window; the grid in the
--- minimap hover cannot — a tooltip anchored to a cell would open on top of the
--- rows either side of it. Passing the panel puts the second tooltip beside the
--- first, which is where SavedInstances puts it.
local function showTip(owner, title, tip, beside)
  if not tip or #tip == 0 then return end
  if beside then
    GameTooltip:SetOwner(beside, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", beside, "TOPLEFT", -4, 0)
  else
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  end
  if title then GameTooltip:AddLine(title) end
  for _, line in ipairs(tip) do
    if type(line) == "table" then
      GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.6, 0.6, 0.6)
    else
      GameTooltip:AddLine(line, 0.5, 0.5, 0.5)
    end
  end
  GameTooltip:Show()
end

--- Build one column header, on demand.
---
--- Headers sit OUTSIDE the scroll frame so scrolling the rows never scrolls
--- away the names they belong to. A grid whose header leaves the screen is a
--- grid of anonymous numbers.
---
--- Each is a mouse-enabled frame rather than a bare FontString, because a name
--- plus a realm plus a level plus an item level plus a last-seen does not fit
--- in 56px: the header shows what identifies the character and the hover
--- carries the rest.
local function makeRosterCol(i)
  local p = panels[TAB_ROSTER]
  local hit = CreateFrame("Frame", nil, p)
  -- +8 because the cells below are children of the scroll frame, which starts
  -- 8px inside the well, and these are children of the panel. Without it every
  -- name in the grid sits 8px left of the column it labels.
  hit:SetPoint("TOPLEFT", 8 + LABEL_W + (i - 1) * CELL_W, -18)
  hit:SetSize(CELL_W, 30)
  hit:EnableMouse(true)
  local name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("TOPLEFT", 0, -2)
  name:SetWidth(CELL_W)
  name:SetJustifyH("CENTER")
  name:SetWordWrap(false)
  local meta = hit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  meta:SetPoint("TOPLEFT", 0, -16)
  meta:SetWidth(CELL_W)
  meta:SetJustifyH("CENTER")
  meta:SetWordWrap(false)
  hit:SetScript("OnEnter", function(self)
    if not self.col then return end
    showTip(self, self.col.name, columnTip(self.col))
  end)
  hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rosterCols[i] = { hit = hit, name = name, meta = meta }
  return rosterCols[i]
end

--- Build one grid line, on demand: a label and as many cells as columns exist.
---
--- A line owns its own cells, so growing the column count has to reach into
--- every line already built. `growLine` below is that reach, and it is why the
--- cell pool is per-line rather than a flat grid — a line is the unit that
--- appears and disappears as the model changes.
local function makeRosterLine(i)
  local y = -(i - 1) * LINE_H

  -- The stripe under the whole line, drawn first so text sits on top of it. It
  -- does two jobs SavedInstances does with LibQTip: it separates a group from
  -- the one above, and it follows the mouse across a row. Reading a 14px row
  -- across twelve columns is exactly where an eye loses its place.
  local stripe = rosterChild:CreateTexture(nil, "BACKGROUND")
  stripe:SetPoint("TOPLEFT", 0, y)
  stripe:SetHeight(LINE_H)
  stripe:Hide()

  -- One icon per line, pooled with the line and hidden when the row it lands on
  -- has none. SavedInstances draws a currency's own icon before its name, and
  -- that is what makes a column of sixteen currencies scannable — the icon
  -- arrives before the word does. Created here rather than per render: a
  -- texture made while drawing is a texture leaked on every draw.
  local icon = rosterChild:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ROW_ICON, ROW_ICON)
  icon:SetPoint("TOPLEFT", 0, y - (LINE_H - ROW_ICON) / 2)
  -- The stock icon border is baked into the texture's outer 6%, the same crop
  -- buildGearRow takes and for the same reason: at 12px the border is most of
  -- what you would see.
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:Hide()

  -- Grey, because a row's name is chrome: you are here for the cells to the
  -- right of it, and `Nerub-ar Palace (Heroic)` is only how you know which row
  -- they belong to. `GameFontDisableSmall` is the client's own grey rather
  -- than a hex of ours, so this tracks the player's font settings the way the
  -- rest of the window does.
  local label = rosterChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", 0, y)
  label:SetWidth(LABEL_W)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)

  -- The hover area spans the whole line, under the cells, so the highlight
  -- tracks a row rather than a cell. It is behind them in frame level, so a
  -- cell's own tooltip still wins where there is one.
  local rowHit = CreateFrame("Frame", nil, rosterChild)
  rowHit:SetPoint("TOPLEFT", 0, y)
  rowHit:SetHeight(LINE_H)
  -- Explicitly below the cells. They are siblings, and a tie on frame level is
  -- settled by creation order — which would make the row highlight swallow the
  -- cell tooltips that are the whole point of the grid.
  rowHit:SetFrameLevel(rosterChild:GetFrameLevel())
  rowHit:EnableMouse(false)
  rowHit:SetScript("OnEnter", function(self)
    if self.hi then self.hi:Show() end
    -- Only a group header says anything on hover, and what it says is the one
    -- thing a `+` in front of a word does not: which way the click goes.
    if self.group then showTip(self, self.group, { self.hint }) end
  end)
  rowHit:SetScript("OnLeave", function(self)
    if self.hi then self.hi:Hide() end
    GameTooltip:Hide()
  end)
  -- A group header is the only clickable line, and `group` is both the flag and
  -- the key: a data row clears it on every render, so a pooled widget that used
  -- to be a header cannot keep shutting somebody else's group.
  rowHit:SetScript("OnMouseUp", function(self, button)
    if self.group and button == "LeftButton" then UI.ToggleRosterGroup(self.group) end
  end)

  local hi = rosterChild:CreateTexture(nil, "ARTWORK")
  hi:SetPoint("TOPLEFT", 0, y)
  hi:SetHeight(LINE_H)
  hi:SetColorTexture(1, 1, 1, 0.06)
  hi:Hide()
  rowHit.hi = hi

  rosterLines[i] = {
    label = label, icon = icon, stripe = stripe, hi = hi, rowHit = rowHit,
    cells = {}, hits = {}, y = y,
  }
  return rosterLines[i]
end

--- Give a line cells up to `n`, creating the ones it does not have.
---
--- A cell is a frame wrapping its FontString for one reason: a FontString takes
--- no mouse input, and the hover detail is the whole of what makes `2/8` worth
--- reading. This is the widget cost of SavedInstances' secondary tooltip, and
--- it is paid once per cell for the life of the session.
local function growLine(w, n)
  for j = #w.cells + 1, n do
    local hit = CreateFrame("Frame", nil, rosterChild)
    hit:SetPoint("TOPLEFT", LABEL_W + (j - 1) * CELL_W, w.y)
    hit:SetSize(CELL_W, LINE_H)
    hit:SetFrameLevel(rosterChild:GetFrameLevel() + 2)
    hit:EnableMouse(true)
    -- The number face, flushed right. `numberText` above carries the whole of
    -- why. The name headers stay centred in the game font — they are labels,
    -- not a series, and a name is the one thing in this grid that is not a
    -- number.
    local fs = numberText(hit, w.label)
    fs:SetAllPoints(hit)
    hit:SetScript("OnEnter", function(self)
      if w.hi then w.hi:Show() end
      showTip(self, self.tipTitle, self.tip)
    end)
    hit:SetScript("OnLeave", function()
      if w.hi then w.hi:Hide() end
      GameTooltip:Hide()
    end)
    w.cells[j] = fs
    w.hits[j] = hit
  end
end

--- The pools, grown to what this render needs and no further.
local function ensureRoster(nCols, nLines)
  for i = #rosterCols + 1, nCols do makeRosterCol(i) end
  for i = #rosterLines + 1, nLines do makeRosterLine(i) end
  for i = 1, #rosterLines do growLine(rosterLines[i], nCols) end
end

local function buildRoster()
  local p = panels[TAB_ROSTER]

  rosterHead = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rosterHead:SetPoint("TOPLEFT")
  rosterHead:SetPoint("TOPRIGHT", -104, 0)
  rosterHead:SetJustifyH("LEFT")

  -- The season the detail answers for. One entry today â€” the wire carries this
  -- season only â€” so it sits disabled; Roster.Seasons gaining a second entry
  -- is what enables it, and nothing here has to move then.
  local seasonBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  seasonBtn:SetSize(96, 18)
  seasonBtn:SetPoint("TOPRIGHT", 0, -2)
  seasonBtn:SetText(ns.Roster.SEASON_LABEL or "Season")
  seasonBtn:Disable()

  rosterCols = {}
  -- The sidebar owns the panel left edge (buildSidebar below); the strip
  -- and grid start past it.
  buildSidebar(p)
  buildVaultStrip(p)

  rosterWell = makeWell(p)
  rosterWell:SetPoint("TOPLEFT", SIDEBAR_W + 8, -50)
  rosterWell:SetPoint("BOTTOMRIGHT", -20, 34)

  local scroll = CreateFrame("ScrollFrame", "WarbandProRosterScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", rosterWell, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", rosterWell, "BOTTOMRIGHT", -8, 8)
  rosterScroll = scroll

  rosterChild = CreateFrame("Frame", nil, scroll)
  rosterChild:SetSize(LABEL_W + CELL_W, LINE_H)
  scroll:SetScrollChild(rosterChild)

  rosterLines = {}

  rosterFoot = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  rosterFoot:SetPoint("BOTTOMLEFT", 0, 2)
  rosterFoot:SetJustifyH("LEFT")

  rosterPrev = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  rosterPrev:SetSize(24, 20)
  rosterPrev:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -46, 0)
  rosterPrev:SetText("<")
  rosterPrev:SetScript("OnClick", function()
    UI.rosterPage = UI.rosterPage - 1
    UI.RenderRoster()
  end)

  rosterNext = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  rosterNext:SetSize(24, 20)
  rosterNext:SetPoint("LEFT", rosterPrev, "RIGHT", 2, 0)
  rosterNext:SetText(">")
  rosterNext:SetScript("OnClick", function()
    UI.rosterPage = UI.rosterPage + 1
    UI.RenderRoster()
  end)

  -- Widening the window is only worth doing because it buys columns, so the
  -- grid redraws when it happens. Watch the SCROLL frame rather than the panel,
  -- because that is what fittingCols measures â€” and because an anchored frame
  -- reads 0 wide until the first layout pass, so this is also what turns the
  -- opening render's fallback single column into the real one.
  --
  -- A render only resizes the scroll CHILD, so this cannot feed itself; the
  -- guard is for the layout pass a resize can schedule inside one.
  scroll:SetScript("OnSizeChanged", function()
    if UI.rendering or not scroll:IsVisible() then return end
    UI.rendering = true
    UI.RenderRoster()
    UI.rendering = false
  end)
end

--- How many character columns fit in the grid as it is currently sized.
---
--- **This is the shrink-to-fit SavedInstances does, spent the other way.** SI
--- scales its tooltip down until the whole warband fits the screen; a window
--- with an EditBox and buttons on its other tabs cannot be scaled without
--- taking them with it, so the player sizes the window and the column count
--- follows. The result is the same one that matters: your warband is on screen
--- at once, and `<` `>` appear only when it genuinely does not fit.
local function fittingCols()
  -- The scroll frame is what the cells actually live in, so it is what decides
  -- how many fit. Measuring the panel instead would be measuring the well, the
  -- scrollbar gutter and the page buttons along with them.
  local w = rosterScroll and rosterScroll:GetWidth() or 0
  local n = math.floor((w - LABEL_W - ROSTER_GUTTER) / CELL_W)
  -- Before the first layout pass a frame measures 0, and one column is a better
  -- wrong answer than none: the OnSizeChanged that follows corrects it.
  if n < 1 then n = 1 end
  return n
end

--- Draw the grid.
---
--- Flattens the model's groups into one list of lines — a group header is a
--- line with no cells — because a scroll child of uniform 14px rows is what
--- makes the label column and the cells stay aligned without a layout pass.
-- ── roster sidebar ──────────────────────────────────────────────────────────
--
-- The v2 sidebar: All plus one row per character, then the account section. A
-- row is a plain button — name on the left, compact status on the right — and
-- clicking one narrows the grid to that character (All restores the whole
-- warband). The selected row carries a bronze bar as well as bright text, so
-- selection is never color alone. Rows are pooled like every other widget
-- here and grow to whatever the warband asks for.

local function makeSideRow(i)
  local b = CreateFrame("Button", nil, sideFrame)
  b:SetSize(SIDEBAR_W, SIDE_ROW_H)
  b:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 0, -(i - 1) * SIDE_ROW_H)
  b.bar = b:CreateTexture(nil, "OVERLAY")
  b.bar:SetColorTexture(0.55, 0.42, 0.28, 1)
  b.bar:SetSize(2, 12)
  b.bar:SetPoint("LEFT", 3, 0)
  b.bar:Hide()
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.name:SetPoint("LEFT", 10, 0)
  b.name:SetWidth(112)
  b.name:SetJustifyH("LEFT")
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(12, 12)
  b.icon:SetPoint("RIGHT", -4, 0)
  b.icon:Hide()
  b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.status:SetPoint("RIGHT", -4, 0)
  b.status:SetJustifyH("RIGHT")
  b:SetScript("OnClick", function(self)
    UI.rosterSelect = self.selGuid
    UI.RenderRoster()
  end)
  sideRows[i] = b
  return b
end

local function ensureSide(n)
  if not sideRows then sideRows = {} end
  for i = 1, n do if not sideRows[i] then makeSideRow(i) end end
end

function buildSidebar(p)
  sideFrame = CreateFrame("Frame", nil, p)
  sideFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -50)
  sideFrame:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 30)
  sideFrame:SetWidth(SIDEBAR_W)
  sideRows = {}
end

-- The vault-slot strip above the grid: one small button per Great Vault
-- bucket of the selected character, Plumber's GreatVault.lua pattern (n/m
-- text; locked dimmed gray, unlocked full brightness white). Shown only for
-- a single-character selection; the whole warband keeps the vault rows it
-- already has. The strip costs the well its top rows only while shown.
function buildVaultStrip(p)
  vaultStrip = CreateFrame("Frame", nil, p)
  vaultStrip:SetPoint("TOPLEFT", p, "TOPLEFT", SIDEBAR_W + 8, -28)
  vaultStrip:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -28)
  vaultStrip:SetHeight(20)
  vaultStrip:Hide()
  vaultSlots = {}
  for i = 1, 3 do
    local s
    if ns.Theme and ns.Theme.MakeSlot then
      s = ns.Theme.MakeSlot(vaultStrip, 118)
    end
    if not s then
      s = CreateFrame("Frame", nil, vaultStrip)
      s:SetSize(118, 20)
      s.SlotText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      s.SlotText:SetPoint("CENTER", s, "CENTER", 0, 0)
    end
    s:SetPoint("LEFT", vaultStrip, "LEFT", (i - 1) * 124, 0)
    s:Hide()
    vaultSlots[i] = s
  end
end

local function renderSidebar(side, sel)
  if not sideFrame then return end
  local n = #side.rows
  local entries = {
    { head = "Warband" },
    { kind = "all", name = "All",
      status = n == 1 and "1 alt" or format("%d alts", n) },
  }
  for _, r in ipairs(side.rows) do
    entries[#entries + 1] = { kind = "char", guid = r.col.guid,
      class = r.col.class, name = r.col.name,
      status = r.vault and r.vault.text or (r.keystone and r.keystone.text or "") }
  end
  entries[#entries + 1] = { head = "Account" }
  for _, a in ipairs(side.account) do
    entries[#entries + 1] = { kind = "account", name = a.name,
      status = a.text, icon = a.icon }
  end
  ensureSide(#entries)
  for i, b in ipairs(sideRows) do
    local e = entries[i]
    if not e then
      b:Hide()
    else
      b:Show()
      if e.head then
        b.name:SetText(format("|cff947C66%s|r", e.head))
        b.status:SetText("")
        b.icon:Hide()
        b.bar:Hide()
        b:EnableMouse(false)
      else
        b:EnableMouse(true)
        b.selGuid = e.guid
        local selected = (e.guid == sel)
        if e.kind == "char" then
          b.name:SetText(classText(e.class, e.name))
        elseif e.kind == "account" then
          b.name:SetText(format("|cffEBDEC2%s|r", e.name))
        else
          b.name:SetText(selected
            and "|cffffffffAll|r" or format("|cffD7C0A3%s|r", e.name))
        end
        local sc = selected and "FFFFFF" or "D7C0A3"
        b.status:SetText(e.status ~= "" and format("|cff%s%s|r", sc, e.status) or "")
        if e.icon then
          b.icon:SetTexture(e.icon)
          b.icon:Show()
          b.status:SetPoint("RIGHT", -20, 0)
        else
          b.icon:Hide()
          b.status:SetPoint("RIGHT", -4, 0)
        end
        if selected then b.bar:Show() else b.bar:Hide() end
      end
    end
  end
end

local function renderSlots(selRow, single)
  local slots = selRow and selRow.vault and selRow.vault.slots or nil
  local show = single and slots and #slots > 0
  if not vaultStrip then return show end
  if not show then
    vaultStrip:Hide()
  else
    vaultStrip:Show()
    for i, s in ipairs(vaultSlots) do
      local sl = slots[i]
      if not sl then
        s:Hide()
      else
        s:Show()
        local label = format("%s  %s", SLOT_SHORT[sl.key] or sl.key, sl.text)
        local unlocked = (sl.unlocked or 0) > 0
        if ns.Theme and ns.Theme.SetSlot then
          ns.Theme.SetSlot(s, label, unlocked)
        elseif s.SlotText then
          s.SlotText:SetText(label)
          if unlocked then
            s.SlotText:SetTextColor(1, 1, 1)
            s:SetAlpha(1)
          else
            s.SlotText:SetTextColor(0.5, 0.5, 0.5)
            s:SetAlpha(0.6)
          end
        end
      end
    end
  end
  if rosterWell then
    local parent = rosterWell:GetParent()
    rosterWell:ClearAllPoints()
    rosterWell:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDEBAR_W + 8, show and -74 or -50)
    rosterWell:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 34)
  end
  return show
end

function UI.RenderRoster()
  if not rosterLines then return end
  local db = ns.Store.db
  local selfGuid = ns.safe(UnitGUID, "player")
  -- Sidebar selection: a guid narrows the grid to that character, nil shows
  -- the whole warband. A guid the DB no longer has (forgotten alt) falls back
  -- to All rather than drawing an empty grid.
  local sel = UI.rosterSelect
  if sel and not (db and db.chars and db.chars[sel]) then
    sel = nil
    UI.rosterSelect = nil
  end
  local view = db
  if sel and db then
    view = { chars = { [sel] = db.chars[sel] },
      junk = db.junk, gearset = db.gearset, opts = db.opts, warbank = db.warbank }
  end
  local model = ns.Roster.Build(view, selfGuid)
  local all = model.columns
  -- The sidebar always sees the whole warband, whatever the grid is showing.
  local side = db and ns.Roster.Sidebar(db, selfGuid) or { rows = {}, account = {} }

  -- Columns first, because the page arithmetic depends on how many fit.
  local nCols = fittingCols()
  local pages = math.max(math.ceil(#all / nCols), 1)

  UI.rosterPage = math.min(math.max(UI.rosterPage, 1), pages)
  local first = (UI.rosterPage - 1) * nCols
  local shown = {}
  for i = 1, nCols do
    shown[i] = all[first + i]
  end

  -- The model is per-column already, so the page has to pull the same slice out
  -- of every row that it pulled out of the column list. `Roster.Lines` owns
  -- that arithmetic and the shut-group rule together, because they are the same
  -- question asked of a row and of the header above it.
  local opts = view and view.opts
  local lines = ns.Roster.Lines(model.groups, first, nCols,
    type(opts) == "table" and type(opts.rosterShut) == "table" and opts.rosterShut or nil)
  local n = #lines

  -- Grow to exactly what this render needs. Every line the model produced gets
  -- a widget, which is the whole of the fix for the old 24-row ceiling.
  ensureRoster(nCols, n)

  local gridW = LABEL_W + nCols * CELL_W

  for i = 1, #rosterCols do
    local col, head = shown[i], rosterCols[i]
    head.hit.col = col
    head.hit:SetShown(i <= nCols and col ~= nil)
    if col then
      head.name:SetText((DOT[col.dot] or DOT.never) .. classText(col.class, col.name))
      head.meta:SetText(format("|cff%s%s%s|r", MUTED,
        col.level and tostring(col.level) or "?",
        col.ilvl and (" · " .. col.ilvl) or ""))
    else
      head.name:SetText("")
      head.meta:SetText("")
    end
  end

  -- The label column, with or without its icon. A row that has one gives up
  -- the icon's width from the left of the label rather than drawing over it,
  -- so a long currency name still stops short of the first value column.
  local function setLabel(w, text, icon)
    w.label:ClearAllPoints()
    if icon then
      w.icon:SetTexture(icon)
      w.icon:Show()
      w.label:SetPoint("TOPLEFT", ROW_ICON + ROW_ICON_GAP, w.y)
      w.label:SetWidth(LABEL_W - ROW_ICON - ROW_ICON_GAP)
    else
      w.icon:Hide()
      w.label:SetPoint("TOPLEFT", 0, w.y)
      w.label:SetWidth(LABEL_W)
    end
    w.label:SetText(text)
  end

  local function blank(w)
    for j = 1, #w.cells do
      w.cells[j]:SetText("")
      -- A hit area with no cell under it must not keep the previous render's
      -- tooltip: an empty cell that still explains somebody else's lockout is
      -- the exact failure a pooled widget invites.
      w.hits[j].tip, w.hits[j].tipTitle = nil, nil
      w.hits[j]:Hide()
    end
  end

  for i = 1, #rosterLines do
    local line, w = lines[i], rosterLines[i]
    w.stripe:SetWidth(gridW)
    w.hi:SetWidth(gridW)
    w.rowHit:SetWidth(gridW)
    w.hi:Hide()
    if not line then
      setLabel(w, "", nil)
      w.stripe:Hide()
      w.rowHit:EnableMouse(false)
      w.rowHit.group, w.rowHit.hint = nil, nil
      blank(w)
    elseif line.head then
      -- A group header is the rule between groups as well as its name: the
      -- stripe under it is what stops `currencies` reading as one more row of
      -- the block above it.
      --
      -- **Grey after all, and the stripe carries the separation.** This was
      -- gold, for a reason that stopped being true one line above: grey read
      -- as disabled while the data rows were WHITE, which left the heading at
      -- less weight than the rows under it. The labels are grey now and only
      -- the values are bright, so a heading no longer has to out-shout the
      -- block it names — it has to step out of the way, and the one thing on
      -- the line that is not text does the separating. The stripe went from 5%
      -- to 10% to take that on.
      --
      -- The `+`/`-` in front of it is the whole of the affordance. A shut group
      -- names the count it is holding, because `lockouts` with a rule under it
      -- and nothing else looks like a group that had nothing to say.
      setLabel(w, format("%s %s%s", line.closed and "+" or "-", line.head,
        line.closed and format("  (%d)", line.hidden) or ""), nil)
      w.stripe:SetColorTexture(1, 1, 1, 0.10)
      w.stripe:Show()
      w.rowHit:EnableMouse(true)
      w.rowHit.group = line.head
      w.rowHit.hint = line.closed and "click to open" or "click to close"
      blank(w)
    else
      setLabel(w, line.label, line.icon)
      w.stripe:Hide()
      w.rowHit:EnableMouse(true)
      w.rowHit.group, w.rowHit.hint = nil, nil
      for j = 1, #w.cells do
        local c = j <= nCols and line.cells[j] or nil
        local hit = w.hits[j]
        if not c then
          -- An empty cell, never a zero. Roster.lua's rule 1, drawn.
          w.cells[j]:SetText("")
          hit.tip, hit.tipTitle = nil, nil
          hit:Hide()
        else
          if TONE[c.tone] then
            w.cells[j]:SetText(format("|cff%s%s|r", TONE[c.tone], c.text))
          else
            w.cells[j]:SetText(c.text)
          end
          hit.tip = c.tip
          -- The title names WHOSE cell this is, because a grid read across
          -- loses track of the column by the time the mouse arrives.
          hit.tipTitle = shown[j] and (line.label .. "  —  " .. shown[j].name) or line.label
          hit:Show()
        end
      end
    end
  end
  rosterChild:SetSize(gridW, math.max(n, 1) * LINE_H)

  if #all == 0 then
    rosterHead:SetText(format("|cff%sno characters scanned yet — log in on a character and it lands here|r",
      MUTED))
  -- The MODEL's groups, not the lines drawn. A group exists only because some
  -- character has a value in it, so an empty model is the one honest "nothing
  -- read yet" — whereas no lines can now also mean the player shut every group,
  -- and telling them to go and play one would be the grid stating something it
  -- can see is false.
  elseif #model.groups == 0 then
    rosterHead:SetText(format("|cff%s%d character%s, and nothing read yet — play one and it fills in|r",
      MUTED, #all, #all == 1 and "" or "s"))
  else
    -- The count is the value and everything after it is the sentence it sits
    -- in, so the count keeps the bright ink and the words take the grey.
    rosterHead:SetText(format("%d|cff%s character%s%s|r", #all, MUTED, #all == 1 and "" or "s",
      pages > 1 and format("  ·  showing %d-%d · drag the corner to widen", first + 1,
        math.min(first + nCols, #all)) or ""))
  end

  local wb = model.warbandBank
  rosterFoot:SetText(wb
    and format("|cff%swarband bank %s%s%s%s|r", MUTED, wb.ago,
      wb.by and (" (by " .. wb.by .. ")") or "",
      wb.gold and ("  ·  " .. wb.gold) or "",
      (wb.tabsOwned and wb.tabs < wb.tabsOwned)
        and format(", %d of %d tabs", wb.tabs, wb.tabsOwned) or "")
    or format("|cff%swarband bank never seen|r", MUTED))

  rosterPrev:SetShown(pages > 1)
  rosterNext:SetShown(pages > 1)
  rosterPrev:SetEnabled(UI.rosterPage > 1)
  rosterNext:SetEnabled(UI.rosterPage < pages)
  renderSidebar(side, sel)
  local selRow
  if sel then
    for _, r in ipairs(side.rows) do
      if r.col.guid == sel then selRow = r break end
    end
  end
  renderSlots(selRow, sel ~= nil)
end

--- Shut a group, or open it again, and remember which.
---
--- The set is keyed by the group's LABEL rather than by its position, because
--- which groups a warband has depends on what has been scanned — an index would
--- move under the player the first time a lockout appeared and shut whatever
--- landed in that slot instead.
---
--- Only the shut ones are stored, and a group that is opened drops out of the
--- table rather than storing `false`. The default is every group open, so an
--- addon that has never had this clicked carries no key at all.
function UI.ToggleRosterGroup(label)
  local o = ns.Store.db and ns.Store.db.opts
  if not o or not label then return end
  if type(o.rosterShut) ~= "table" then o.rosterShut = {} end
  o.rosterShut[label] = (not o.rosterShut[label]) or nil
  ns.Store.Touch()
  UI.RenderRoster()
end

-- ── options tab ─────────────────────────────────────────────────────────────

--- One native checkbox with a label beside it and a muted description under
--- it. The label and description are our own FontStrings rather than the
--- template's, so a template rename cannot silently drop the text.
-- ── options tab: three panes ──────────────────────────────────────────────
--
-- Plumber's settings shape (LeftSection / CentralSection / RightSection): the
-- left nav names the three categories, the center lists that category's
-- options, the right shows the selected option's checkbox and description.
-- Every control keeps working and persists the same saved variables — the six
-- get/set pairs below are the old flat tab's, moved verbatim — so this is
-- presentation only. The selected nav and list rows are disabled, the same
-- "you are here" idiom the export slice row and the roster pager use.

local OPT_CATS = { "Data", "Automation", "Display" }
local OPT_DEFS = {}
local optNavBtns, optListBtns, optGroups, optDetailAnchor

local function makeOption(parent, label, desc, get, set)
  local g = CreateFrame("Frame", nil, parent)
  g:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  g:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  g:SetHeight(140)
  local check = CreateFrame("CheckButton", nil, g, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", 0, 0)
  check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)

  local text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", check, "RIGHT", 4, 0)
  text:SetText(label)
  if ns.Theme and ns.Theme.Ink then ns.Theme.Ink(text, "normal") end

  local sub = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 4)
  sub:SetPoint("RIGHT", g, "RIGHT", 0, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText(desc)
  if ns.Theme and ns.Theme.Ink then ns.Theme.Ink(sub, "body") end

  optionChecks[#optionChecks + 1] = { check = check, get = get }
  g:Hide()
  return g
end

local function optButton(parent, x, w, y)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 20)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b.bar = b:CreateTexture(nil, "OVERLAY")
  b.bar:SetColorTexture(0.55, 0.42, 0.28, 1)
  b.bar:SetSize(2, 12)
  b.bar:SetPoint("LEFT", 2, 0)
  b.bar:Hide()
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 10, 0)
  b.text:SetJustifyH("LEFT")
  return b
end

local function firstOfCat(cat)
  for idx, d in ipairs(OPT_DEFS) do
    if d.cat == cat then return idx end
  end
  return 1
end

local function renderOptions()
  if not optNavBtns then return end
  for i, b in ipairs(optNavBtns) do
    local selected = (i == UI.optCat)
    b.text:SetText(selected
      and format("|cffffffff%s|r", OPT_CATS[i])
      or format("|cffD7C0A3%s|r", OPT_CATS[i]))
    b:SetEnabled(not selected)
    if selected then b.bar:Show() else b.bar:Hide() end
  end
  local shown = {}
  for idx, d in ipairs(OPT_DEFS) do
    if d.cat == UI.optCat then shown[#shown + 1] = idx end
  end
  for i, b in ipairs(optListBtns) do
    local idx = shown[i]
    if not idx then
      b:Hide()
    else
      b:Show()
      b.optIdx = idx
      local selected = (idx == UI.optItem)
      b.text:SetText(selected
        and format("|cffffffff%s|r", OPT_DEFS[idx].label)
        or format("|cffD7C0A3%s|r", OPT_DEFS[idx].label))
      b:SetEnabled(not selected)
      if selected then b.bar:Show() else b.bar:Hide() end
    end
  end
  for idx, g in ipairs(optGroups) do g:SetShown(idx == UI.optItem) end
  for _, o in ipairs(optionChecks) do
    o.check:SetChecked(o.get() and true or false)
  end
end

local function buildOptions()
  local p = panels[TAB_OPTIONS]
  local opts = function() return ns.Store.db and ns.Store.db.opts end

  OPT_DEFS = {
    { cat = 1, label = "Capture gear",
      desc = "Equipped, bag, bank and warband-bank gear - and talents - ride the export string. "
        .. "Turning this off keeps what is already stored; it is just left out of the next bundle.",
      get = function() local o = opts() return o and o.includeGear end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.includeGear = v
        ns.Store.Touch()
        if v then
          ns.Scan.Bags()   -- current bag contents; equipped and the rest follow
          ns.Gear.All()
        end
      end },
    { cat = 1, label = "Include item links",
      desc = "Full hyperlinks for every bag stack, for debugging a specific item. "
        .. "Costs about a third more wire.",
      get = function() local o = opts() return o and o.includeLinks end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.includeLinks = v
        ns.Store.Touch()
      end },
    { cat = 2, label = "Open the clear-out list at merchants",
      desc = "When a merchant window opens and the cleanup list has something in your bags, "
        .. "the Import tab opens by itself and closes when you leave the merchant.",
      get = function() local o = opts() return o and o.autoJunk end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.autoJunk = v
        ns.Store.Touch()
      end },
    { cat = 2, label = "Turn combat logging on in raids",
      desc = "Starts /combatlog when you zone into a raid and stops it when you leave, so an upload to "
        .. "Warcraft Logs has the pulls in it. Raids only, and off by default - it writes a file "
        .. "that grows with every pull, which is not a cost to hand somebody who did not ask.",
      get = function() local o = opts() return o and o.autoLog end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.autoLog = v
        ns.Store.Touch()
        -- Applied now rather than at the next loading screen: turning it on
        -- while already standing in the raid is exactly when somebody turns it
        -- on, and waiting would look broken.
        ns.syncCombatLog()
      end },
    { cat = 3, label = "Show the minimap button",
      desc = "The icon on the minimap ring - click it for the export string, right-click it for options, "
        .. "drag it anywhere round the ring. Turning it off leaves /warband and the addon compartment.",
      get = function() local o = opts() return o and o.minimap end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.minimap = v
        ns.Store.Touch()
        UI.RefreshMinimap()
      end },
    { cat = 3, label = "Show every currency in the Roster grid",
      desc = "The grid lists the currencies the game is still metering - one with a cap, a weekly cap, "
        .. "or something earned towards it this week - and its header says how many it left out. "
        .. "Turn this on to list every currency any character is carrying.",
      get = function() local o = opts() return o and o.allCurrencies end,
      set = function(v)
        local o = opts()
        if not o then return end
        o.allCurrencies = v
        ns.Store.Touch()
        UI.RenderRoster()
      end },
  }

  optNavBtns = {}
  for i = 1, #OPT_CATS do
    local b = optButton(p, 0, 124, -(i - 1) * 22)
    b.navIdx = i
    b:SetScript("OnClick", function(self)
      UI.optCat = self.navIdx
      UI.optItem = firstOfCat(self.navIdx)
      renderOptions()
    end)
    optNavBtns[i] = b
  end

  optListBtns = {}
  for i = 1, #OPT_DEFS do
    local b = optButton(p, 134, 180, -(i - 1) * 22)
    b:SetScript("OnClick", function(self)
      UI.optItem = self.optIdx
      renderOptions()
    end)
    optListBtns[i] = b
  end

  optDetailAnchor = CreateFrame("Frame", nil, p)
  optDetailAnchor:SetPoint("TOPLEFT", p, "TOPLEFT", 324, 0)
  optDetailAnchor:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 24)
  optGroups = {}
  for idx, d in ipairs(OPT_DEFS) do
    optGroups[idx] = makeOption(optDetailAnchor, d.label, d.desc, d.get, d.set)
  end

  UI.optCat, UI.optItem = 1, 1

  local version = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", 0, 2)
  version:SetPoint("BOTTOMRIGHT", 0, 2)
  version:SetJustifyH("LEFT")
  version:SetText(format("Warband.pro v%s  ·  no network calls - the export moves only when you copy it",
    ns.VERSION))
end

local function refreshOptions()
  renderOptions()
end

-- ── the window ──────────────────────────────────────────────────────────────

--- Remember where the window is and how big it was left.
---
--- Same idiom and same home as the minimap button's angle: an `opts` field,
--- written when the drag stops rather than on every frame of it. A window the
--- player widened for their warband that comes back at 560 next session has
--- not really been made resizable.
local function saveGeometry()
  local o = ns.Store.db and ns.Store.db.opts
  if not o or not frame then return end
  local point, _, rel, x, y = frame:GetPoint(1)
  if not point then return end
  o.window = {
    w = math.floor(frame:GetWidth() + 0.5),
    h = math.floor(frame:GetHeight() + 0.5),
    point = point, rel = rel, x = math.floor(x + 0.5), y = math.floor(y + 0.5),
  }
end

--- Put it back, clamped to the bounds this version allows.
---
--- Clamping on the way IN as well as on the way out is what makes a bound
--- change safe: a size stored by an older build, or by a player on a monitor
--- they no longer have, must not be able to produce a window that cannot be
--- reached or resized back.
local function restoreGeometry()
  local o = ns.Store.db and ns.Store.db.opts
  local g = o and o.window
  if not g or not frame then return end
  local w = math.min(math.max(tonumber(g.w) or WIN_DEF_W, WIN_MIN_W), WIN_MAX_W)
  local h = math.min(math.max(tonumber(g.h) or WIN_DEF_H, WIN_MIN_H), WIN_MAX_H)
  frame:SetSize(w, h)
  if g.point and g.x and g.y then
    frame:ClearAllPoints()
    frame:SetPoint(g.point, UIParent, g.rel or g.point, g.x, g.y)
  end
end

--- The corner grab. Hand-rolled from the size-grabber textures rather than a
--- template, for the reason the portrait calls are guarded: these three
--- textures have shipped since Wrath and cannot be renamed out from under us,
--- where a resize *template* is a name that has moved more than once.
local function makeGrip(parent)
  local grip = CreateFrame("Button", nil, parent)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetFrameLevel(parent:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() parent:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    parent:StopMovingOrSizing()
    saveGeometry()
  end)
  return grip
end

local function build()
  if frame then return frame end

  frame = CreateFrame("Frame", "WarbandProFrame", UIParent, "ButtonFrameTemplate")
  frame:SetSize(WIN_DEF_W, WIN_DEF_H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveGeometry()
  end)

  -- Resizable, because the roster is a grid and a grid's useful width is the
  -- size of the player's warband. Guarded like the portrait mixins above: a
  -- client missing SetResizeBounds should cost the resizing, never the window.
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H)
  end
  makeGrip(frame)
  frame:Hide()
  tinsert(UISpecialFrames, "WarbandProFrame")   -- Esc closes

  -- Mixin methods, guarded: a client where PortraitFrame lost one of these
  -- should cost the title or the icon, never the window.
  if frame.SetTitle then
    frame:SetTitle("Warband.pro")
  elseif frame.TitleContainer and frame.TitleContainer.TitleText then
    frame.TitleContainer.TitleText:SetText("Warband.pro")
  end
  if frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(ns.ICON)
  end



  -- Every panel anchors to the inset. ButtonFrameTemplate has shipped one for
  -- a decade; if the parentKey ever moves, build our own rather than error.
  if not frame.Inset then
    frame.Inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    frame.Inset:SetPoint("TOPLEFT", 8, -60)
    frame.Inset:SetPoint("BOTTOMRIGHT", -8, 30)
  end

  panels = { makePanel(), makePanel(), makePanel(), makePanel() }

  tabs = {}
  -- Named by direction, with the site as the fixed reference — 2026-08-24.
  --
  -- They read "Export" and "Import", and the pair was inverted against the
  -- only mental model a player has: warband.pro's own control for receiving
  -- this string is called import, so the addon's *Export* feeds the web's
  -- import and the addon's *Import* consumes what the web's /gear page hands
  -- back. Someone who has just pressed import in the browser and typed
  -- /warband landed on a tab called Import and was looking at the wrong one.
  --
  -- Nothing in the window said which way either tab flowed except one sentence
  -- buried inside the second panel. A direction is what these tabs actually
  -- differ by, so it is what they are named by.
  -- Roster is first because it is the only tab you READ. The other three act —
  -- copy a string, apply one, change a setting — and reading precedes acting.
  -- It is not what the window OPENS on, though: `/warband` has always landed
  -- on a highlighted export box and FLOW.md counts that at under two seconds,
  -- so every existing door still opens the tab it always opened. This one is
  -- reached by its tab, by `/warband roster`, and by the minimap tooltip
  -- saying so.
  tabs[TAB_ROSTER]  = makeTab(TAB_ROSTER, "Roster")
  tabs[TAB_EXPORT]  = makeTab(TAB_EXPORT, "To warband.pro")
  tabs[TAB_IMPORT]  = makeTab(TAB_IMPORT, "From warband.pro")
  tabs[TAB_OPTIONS] = makeTab(TAB_OPTIONS, "Options")
  frame.Tabs = tabs
  PanelTemplates_SetNumTabs(frame, #tabs)

  -- The gold divider with its center ornament under the tab row. The ground
  -- and bronze edge landed earlier through ApplyFrame; everything here goes
  -- through a Theme builder, never a one-off.
  if ns.Theme and ns.Theme.MakeDivider then
    local divider = ns.Theme.MakeDivider(frame)
    if divider then
      divider:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", 0, -3)
      divider:SetPoint("TOPRIGHT", tabs[#tabs], "BOTTOMRIGHT", 0, -3)
      frame.ThemeDivider = divider
    end
  end

  buildRoster()
  buildExport()
  buildImport()
  buildOptions()

  -- Last, because it has to overrule the SetSize and SetPoint above and every
  -- panel inside is anchored rather than placed, so one resize at the end lays
  -- the whole window out correctly.
  restoreGeometry()

  return frame
end

function UI.SelectTab(id)
  if not frame then return end
  -- The import tab holds the secure disenchant rows, and secure attributes
  -- cannot be written in combat — so the tab cannot be entered there either.
  if id == TAB_IMPORT and InCombatLockdown() then
    ns.print("in combat — the clear-out list opens when you drop out")
    return
  end
  PanelTemplates_SetTab(frame, id)
  -- Selecting re-shows the template boxes; the theme hides them again and
  -- repaints the row so behavior and look cannot drift apart.
  if ns.Theme and ns.Theme.RefreshTabs then ns.Theme.RefreshTabs(tabs, id) end
  for i, p in ipairs(panels) do p:SetShown(i == id) end
  if id == TAB_ROSTER then
    UI.RenderRoster()
  elseif id == TAB_EXPORT then
    refreshExport()
  elseif id == TAB_IMPORT then
    UI.RenderJunk()
    if not ns.Junk.Stored() then
      junkHeader:SetText(format("|cff%spaste the cleanup string from warband.pro/gear above|r", MUTED))
    end
  else
    refreshOptions()
  end
end

--- Switch which characters the export covers and rebuild the string.
---
--- `UI.page` resets, deliberately: page 2 of a warband means nothing to a
--- bundle holding the one character at the keyboard, and coming back the other
--- way should land on the first twenty rather than wherever the player had
--- walked to before.
function UI.SetScope(mode)
  if UI.mode == mode then return end
  UI.mode = mode
  UI.page = 1
  refreshExport()
end

--- Walk to another page of a warband too large for one bundle. Clamped here so
--- the arrows can be plain +1/-1; Bundle.Build clamps again on its own account.
function UI.SetPage(page)
  page = math.max(math.floor(tonumber(page) or 1), 1)
  if page == UI.page then return end
  UI.page = page
  refreshExport()
end

--- Open the window on a tab. Fails closed in combat: the request is queued and
--- honored when the fight ends, rather than fighting the taint rules mid-pull.
function UI.Open(tab, mode, page)
  if InCombatLockdown() then
    UI.pendingOpen = { tab = tab, mode = mode, page = page }
    ns.print("in combat — the window will open when you drop out")
    return
  end
  UI.pendingOpen = nil
  -- Every open starts on the whole warband unless the caller names a scope.
  -- It used to keep whatever the last open left behind, which mattered little
  -- while the only way to set it was `/warband copy current` and matters a lot
  -- now that it is one click: a gear-flow export must not silently hand the
  -- camp flow a one-character bundle the next time the window opens. The slice
  -- is one click away in either direction, so there is nothing to remember.
  UI.mode = mode or "bundle"
  UI.page = math.max(math.floor(tonumber(page) or 1), 1)
  UI.rosterPage = 1
  build()
  frame:Show()
  UI.SelectTab(tab)
end

-- mode: "bundle" (default) or "current"; page: which twenty, for a warband
-- larger than one bundle holds.
function UI.Show(mode, page)
  UI.Open(TAB_EXPORT, mode or "bundle", page)
end

function UI.ShowJunk()
  UI.Open(TAB_IMPORT)
end

function UI.ShowRoster()
  UI.Open(TAB_ROSTER)
end

--- Same shape as ToggleJunk: a second press on the same tab closes.
function UI.ToggleRoster()
  if frame and frame:IsShown() then
    if frame.selectedTab == TAB_ROSTER then
      frame:Hide()
    else
      UI.SelectTab(TAB_ROSTER)
    end
    return
  end
  UI.ShowRoster()
end

function UI.ShowOptions()
  UI.Open(TAB_OPTIONS)
end

function UI.Toggle(mode)
  if frame and frame:IsShown() then
    frame:Hide()
    return
  end
  UI.Show(mode)
end

function UI.ToggleJunk()
  if frame and frame:IsShown() then
    if frame.selectedTab == TAB_IMPORT then
      frame:Hide()
    else
      UI.SelectTab(TAB_IMPORT)
    end
    return
  end
  UI.ShowJunk()
end

--- Same shape as ToggleJunk, for the minimap button's right click: a second
--- press on the same tab closes, a press from another tab switches.
function UI.ToggleOptions()
  if frame and frame:IsShown() then
    if frame.selectedTab == TAB_OPTIONS then
      frame:Hide()
    else
      UI.SelectTab(TAB_OPTIONS)
    end
    return
  end
  UI.ShowOptions()
end

function UI.Hide()
  if frame then frame:Hide() end
end

function UI.JunkIsShown()
  return frame and frame:IsShown() and frame.selectedTab == TAB_IMPORT
end

--- Combat starting. Only the import tab has to go — its rows are secure and
--- cannot be re-baked until the fight ends — so the export string a player had
--- open mid-ready-check stays where it was. Remembered and brought back by
--- UI.AfterCombat.
function UI.CombatLockdown()
  if UI.JunkIsShown() then
    UI.reopenTab = TAB_IMPORT
    frame:Hide()
  end
end

--- Combat over: reopen whatever combat closed or queued, exactly once.
function UI.AfterCombat()
  local p = UI.pendingOpen
  UI.pendingOpen = nil
  if p then
    UI.Open(p.tab, p.mode, p.page)
    return
  end
  if UI.reopenTab then
    local tab = UI.reopenTab
    UI.reopenTab = nil
    UI.Open(tab)
  end
end

--- A merchant opened or closed. Rendering keeps the Sell buttons honest; the
--- auto-open half is the Options tab's "open the clear-out list at merchants",
--- which only fires when the resolved list actually has rows — an empty panel
--- popping over every vendor visit would train people to turn it off.
function UI.MerchantChanged(open)
  UI.RefreshMerchantButton()
  if UI.JunkIsShown() then UI.RenderJunk() end
  local opts = ns.Store.db and ns.Store.db.opts
  if open then
    if opts and opts.autoJunk and not (frame and frame:IsShown()) and not InCombatLockdown() then
      local rowsData = ns.Junk.Resolve()
      if #rowsData > 0 then
        UI.autoOpened = true
        UI.ShowJunk()
      end
    end
  elseif UI.autoOpened then
    UI.autoOpened = nil
    -- Only if it is still the auto-opened panel: a player who switched tabs
    -- has made the window theirs, and it stays.
    if UI.JunkIsShown() then frame:Hide() end
  end
end

-- ── the vendor window's sell-all ────────────────────────────────────────────
--
-- The clear-out panel lists every verdict with a Sell button beside it, and the
-- job it is actually for is selling the whole list — one click at a time, in a
-- panel that only does anything at a vendor anyway. So the sell-all goes where
-- the selling happens: on MerchantFrame itself, the way Zygor has put "Sell
-- Grays" there for fifteen years.
--
-- **It is not the panel's button moved.** The panel stays exactly as it is, for
-- the item you want to keep; this is for the other eleven. Nothing here decides
-- what sells — `Junk.SellPlan` does, and it is tested — so the button and the
-- rows a player can see can never disagree about the list.
--
-- The confirm is not optional and it is not a nicety. Greys are greys, but this
-- list is gear the website judged, and the only way back from a mistake is the
-- vendor's twelve-slot buyback tab. One dialog stating the count and the take
-- is cheap against an item sold in a click the player did not mean to make.

local merchantButton

local SELL_ALL_POPUP = "WARBANDPRO_SELL_LIST"

--- What the confirm says. A floor rather than a guess when the client has not
--- cached every price — see `Junk.SellPlan`.
local function sellAllPrompt(plan)
  return format(
    "Sell %d item%s from your clear-out list for %s%s?\n\nThe vendor's buyback tab holds the last 12.",
    plan.count,
    plan.count == 1 and "" or "s",
    plan.unpriced > 0 and "at least " or "",
    ns.Junk.Money(plan.total)
  )
end

--- Sell the list, from the confirm's OnAccept and nowhere else.
---
--- **Resolved here, not when the button was drawn.** The label's count comes
--- from a walk made at MERCHANT_SHOW; the bags may have moved since, and a
--- bag/slot from that walk is exactly the stale coordinate Junk.lua's header
--- forbids. Rows that left the bags are simply not in this plan, which is the
--- same thing the panel's missing count already reports.
function UI.SellList()
  local plan = ns.Junk.SellPlanNow()
  local sold, copper = ns.Junk.SellAll(plan)
  if sold > 0 then
    ns.print(format("sold %d item%s for %s (buyback available)",
      sold, sold == 1 and "" or "s", ns.Junk.Money(copper)))
  else
    ns.print("nothing on the clear-out list is still in your bags")
  end
  UI.RefreshMerchantButton()
  if UI.JunkIsShown() then UI.RenderJunk() end
end

--- The button, built once against MerchantFrame.
---
--- Below the frame on the right, which is the one edge with nothing on it: the
--- Merchant and Buyback tabs hang off the bottom-left, the money frame sits
--- inside the bottom-right, and anchoring over either would cost the player a
--- control the game gave them.
---
--- Returns nil rather than erroring on a client with no MerchantFrame. Nothing
--- here is secure, so there is no combat rule to obey — a merchant window does
--- not open in combat in the first place.
local function buildMerchantButton()
  if merchantButton then return merchantButton end
  if not MerchantFrame then return nil end

  local b = CreateFrame("Button", "WarbandProSellListButton", MerchantFrame, "UIPanelButtonTemplate")
  b:SetSize(124, 22)
  b:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -6, 1)
  b:SetScript("OnClick", function()
    local plan = ns.Junk.SellPlanNow()
    if plan.count == 0 then
      UI.RefreshMerchantButton()
      return
    end
    if type(StaticPopup_Show) ~= "function" then return end
    StaticPopup_Show(SELL_ALL_POPUP, sellAllPrompt(plan))
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Warband.pro clear-out list")
    GameTooltip:AddLine("Sells everything the list says to sell. Asks first.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()

  -- `preferredIndex = 3` is the standard guard against tainting Blizzard's own
  -- popup slots, and `text = "%s"` is what lets the caller build the sentence:
  -- the count and the price are only known at click time.
  if StaticPopupDialogs then
    StaticPopupDialogs[SELL_ALL_POPUP] = {
      text = "%s",
      button1 = "Sell",
      button2 = "Cancel",
      OnAccept = function() UI.SellList() end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      showAlert = true,
      preferredIndex = 3,
    }
  end

  merchantButton = b
  return b
end

--- Show the button with a live count, or hide it. Safe to call at any time.
---
--- Hidden rather than disabled at zero, which is the opposite of the panel's
--- own rule and for the opposite reason: a disabled row explains why a sale is
--- not on offer for an item you are looking at, while a disabled button on
--- Blizzard's vendor frame would be this addon leaving furniture in a window
--- that is not its own.
function UI.RefreshMerchantButton()
  if not ns.Junk.merchantOpen then
    if merchantButton then merchantButton:Hide() end
    return
  end
  local b = buildMerchantButton()
  if not b then return end
  local plan = ns.Junk.SellPlanNow()
  if plan.count == 0 then
    b:Hide()
    return
  end
  b:SetText(format("Sell list (%d)", plan.count))
  b:Show()
end

-- ── minimap button ──────────────────────────────────────────────────────────

-- The third door to the same window, and the only one that is visible without
-- being gone looking for.
--
-- docs/FLOW.md ruled a minimap button out on purpose and the reasoning was
-- compatibility: a button meant LibDBIcon, LibDBIcon meant LibStub, and this
-- addon ships neither. That argument was always against the library rather
-- than against the button — the ring is a texture the client already has and
-- the maths is one cosine, so there is no dependency here to weigh.
--
-- What decided it is the loop the addon exists for. docs/FLOW.md counts four
-- to ten exports in a play night, each one an alt-tab out of a fight. The
-- compartment is a list of every addon installed, so each of those is a click,
-- a read and a second click; this is one click at a spot that never moves.
-- The compartment entry stays — it costs a .toc line and it is where a player
-- who hid this button goes looking.
--
-- Still no artwork of our own (docs/POLICY.md): Blizzard's own tracking-ring
-- border, and a face already in the player's client.

local MINIMAP_ANGLE = 216   -- lower-left, the emptiest arc of the stock ring
local minimapButton

local function minimapOpts()
  return ns.Store.db and ns.Store.db.opts
end

--- Park the button on the ring, `deg` degrees anticlockwise from due east.
local function placeMinimap(deg)
  if not minimapButton then return end
  local rad = math.rad(deg)
  local radius = (Minimap:GetWidth() / 2) + 5
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

--- Follow the cursor round the ring while the button is held.
---
--- This is the addon's only OnUpdate, and it exists only between the press and
--- the release: OnDragStart installs it and OnDragStop takes it away again. It
--- polls nothing — the thing it is reading is the player's own hand, and it
--- stops when the hand does. Everything that watches the *game* still hangs off
--- an event (Init.lua's throttle and dirty-set helpers).
local function dragMinimap()
  local scale = Minimap:GetEffectiveScale()
  local mx, my = Minimap:GetCenter()
  if not mx or not my then return end   -- an unanchored minimap costs the drag, not the session
  local cx, cy = GetCursorPosition()
  local deg = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
  local o = minimapOpts()
  if o then o.minimapAngle = deg end
  placeMinimap(deg)
end

--- One glance line: who it applies to, joined, with the names class-coloured.
---
--- The label carries the TONE and the names carry their CLASS colour, which is
--- the split the rest of this window already uses — a colour is either a status
--- or an identity, never both at once. That is also SavedInstances' rule and
--- the reason its tooltip stays readable at twenty characters: colour for
--- state, and nothing else coloured for decoration.
local function glanceLine(line)
  local parts = {}
  for _, p in ipairs(line.parts) do
    parts[#parts + 1] = classText(p.class, p.name) .. " " .. p.note
  end
  local right = table.concat(parts, "  ")
  -- The names the model dropped to keep the tooltip off the minimap. `+2` is
  -- honest about the omission where simply stopping at three would not be.
  if line.more > 0 then right = right .. format("  |cff%s+%d|r", MUTED, line.more) end
  -- A label with a tone keeps it: the tone IS the attention system and this
  -- band is where it does the most work. A label with none is chrome and reads
  -- grey — that is the `keystone` line, which used to arrive in the same white
  -- as the level beside it and so said "look here" about nothing at all.
  local label = format("|cff%s%s|r", TONE[line.tone] or MUTED, line.label)
  return label, right
end

--- What the window says, said before you open the window.
---
--- **This is SavedInstances' primary tooltip, and that is the point of it.**
--- Hovering its icon is not the route to the answer there, it IS the answer,
--- and opening a window is the follow-up question. Until now this hover said
--- how many characters were stored and then listed slash commands — enough to
--- tell you the addon was installed, and nothing about the warband it had been
--- watching.
---
--- `Roster.Glance` decides what earns a line and this paints it, the same split
--- the grid already has: the file with the rules is the file with tests, and
--- this one only knows about colour.
---
--- Read straight off the store rather than out of `Export.Build`: the export
--- tab's header gets its number from a built bundle because it is about to show
--- you that bundle, and a hover is not worth an encode and a deflate.
local function minimapTooltip(self)
  local g = ns.Roster.Glance(ns.Store.db, ns.safe(UnitGUID, "player"))

  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Warband.pro")
  GameTooltip:AddLine(format("%s %d character%s  ·  freshest %s", DOT[g.dot] or DOT.never,
    g.characters, g.characters == 1 and "" or "s", g.ago), 1, 1, 1)

  if #g.lines > 0 then
    GameTooltip:AddLine(" ")
    for _, line in ipairs(g.lines) do
      GameTooltip:AddDoubleLine(glanceLine(line))
    end
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click  ·  the export string", 1, 0.82, 0)
  GameTooltip:AddLine("Right-click  ·  options", 1, 0.82, 0)
  -- The grid has no click of its own left on this button, so the tooltip is
  -- where it gets discovered: the roster is a tab and a slash command, and a
  -- feature nobody is told about is one nobody uses.
  GameTooltip:AddLine("/warband roster  ·  every alt at once", 0.5, 0.5, 0.5)
  GameTooltip:AddLine("Drag  ·  move it round the ring", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

-- ── the minimap hover grid ──────────────────────────────────────────────────

-- **The hover IS the interface.** That is the SavedInstances habit this is
-- built for: a player parks on the minimap icon between queues and the whole
-- warband picture is right there — which alt is saved to which raid and how
-- far, who has done their weeklies, how much of each currency each of them
-- holds — with no window to open. The glance above answered four questions
-- across the warband and then sent you to a tab for the fifth, which is a
-- summary where a decade of muscle memory expects a grid.
--
-- So the grid moved into the hover, and the tab stays as the surface you ACT
-- on: it scrolls, it shuts groups, it pages, and it is next to the export and
-- import boxes that are the reason the window exists at all. The hover reads.
--
-- Three things this is not allowed to be, and each decided a line of it:
--
-- 1. **Not a second source of truth.** `Roster.Hover` is `Roster.Build` and
--    `Roster.Lines` — the two calls `UI.RenderRoster` makes — so what the hover
--    says is what the tab shows and what the paste will carry. Nothing here
--    encodes or deflates: a hover is not worth a bundle build.
-- 2. **Not a skin.** `TooltipBackdropTemplate` is the client's own tooltip
--    chrome, the same nine-slice GameTooltip wears, so this panel inherits the
--    player's tooltip settings and scale rather than imitating them. If the
--    template is not there to build on, `makeHoverGrid` returns nil and the
--    button falls back to the four-line glance — a missing frame costs the
--    grid, never the session.
-- 3. **Not a window.** It has no scrollbar and no click, because a tooltip you
--    have to operate is a window that forgot to have a title bar. What does not
--    fit is trimmed by the model and counted out loud in the footer, and the
--    footer names the tab that has the rest.
--
-- GameTooltip itself cannot be the panel: it is two columns (`AddDoubleLine`)
-- and a warband is twenty. So the panel is ours and the SECOND tooltip — the
-- per-cell detail, which is the half of SavedInstances people actually name —
-- is the real GameTooltip, hung off the panel's left edge.

local HOVER_LABEL_W, HOVER_CELL_W, HOVER_LINE_H = 150, 52, 12
local HOVER_ICON = HOVER_LINE_H - 1
local HOVER_ICON_GAP = 3
local HOVER_PAD, HOVER_GAP, HOVER_TEXT_H = 12, 5, 13
-- The lines of chrome the grid does not get: title, freshness, the glance band,
-- the column header and the footer. Subtracted from the screen before the rows
-- are counted, because a tooltip is measured against the monitor and not
-- against the warband.
local HOVER_CHROME = 14
-- Narrow enough for a one-character account, wide enough for the two footer
-- lines: below this the hints wrap out of the panel they are inside.
local HOVER_MIN_W = 360

local hoverFrame, hoverTitle, hoverMeta, hoverNote, hoverHint, hoverHint2
local hoverGlance, hoverHeads, hoverRows = {}, {}, {}

--- Is the mouse still somewhere that wants this panel open?
---
--- The button and the panel are two frames with a shared border, so leaving one
--- for the other fires an OnLeave that means nothing. Asking where the cursor
--- actually is — rather than trusting the event — is what lets the panel be
--- hovered at all, and it is why the rows can carry a tooltip of their own.
local function hoverWanted()
  if minimapButton and minimapButton:IsShown() and minimapButton:IsMouseOver() then return true end
  if hoverFrame and hoverFrame:IsShown() and hoverFrame:IsMouseOver() then return true end
  return false
end

local function hoverDismiss()
  if hoverWanted() then return end
  if hoverFrame then hoverFrame:Hide() end
  GameTooltip:Hide()
end

--- A leave is a question, asked once the cursor has had time to land.
---
--- One `C_Timer.After` and not an OnUpdate: the addon's only OnUpdate is the
--- drag handler, which exists between a press and a release, and a panel that
--- polled the cursor every frame while it was open would be the thing
--- `Init.lua` says this addon does not do.
local function hoverLeave()
  C_Timer.After(0.1, hoverDismiss)
end

--- Hide the panel now, whatever the cursor is doing. The click that opens the
--- window and the drag that moves the button both take the hover with them.
function UI.HideHover()
  if hoverFrame then hoverFrame:Hide() end
end

--- How much of the grid this screen can hold, in columns and in lines.
---
--- Decided here and passed to the model, which has no idea how wide UIParent
--- is. Both numbers are floors on purpose: a partial column would be a name cut
--- in half, and a partial row would be a lockout you could not read.
local function hoverFit()
  local w = ns.safe(function() return UIParent:GetWidth() end) or 1024
  local h = ns.safe(function() return UIParent:GetHeight() end) or 768
  -- Just over half the screen's width, because the panel hangs off a minimap
  -- that is itself in a corner: a grid wider than this reaches the far edge and
  -- gets clamped back over the button it belongs to.
  local cols = math.floor((w * 0.55 - HOVER_PAD * 2 - HOVER_LABEL_W) / HOVER_CELL_W)
  local lines = math.floor((h * 0.8 - HOVER_CHROME * HOVER_LINE_H) / HOVER_LINE_H)
  return math.max(cols, 1), math.max(lines, 6)
end

local function hoverText(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

--- One column header: the freshness dot, the name in its class colour, and
--- everything that did not fit on the hover.
local function makeHoverHead(i)
  local hit = CreateFrame("Frame", nil, hoverFrame)
  hit:SetSize(HOVER_CELL_W, HOVER_TEXT_H)
  hit:EnableMouse(true)
  hit:SetFrameLevel(hoverFrame:GetFrameLevel() + 2)
  local name = hoverText(hit, "GameFontHighlightSmall", "CENTER")
  name:SetAllPoints(hit)
  hit:SetScript("OnEnter", function(self)
    if not self.col then return end
    showTip(self, self.col.name, columnTip(self.col), hoverFrame)
  end)
  hit:SetScript("OnLeave", function()
    GameTooltip:Hide()
    hoverLeave()
  end)
  hoverHeads[i] = { hit = hit, name = name }
  return hoverHeads[i]
end

--- One grid line: a label, the icon it may carry, and its cells.
---
--- Every part of a line is anchored inside a container frame, so a render that
--- puts the rows two lines further down — because the glance band grew a line —
--- moves one frame per row rather than four widgets.
local function makeHoverRow(i)
  local row = CreateFrame("Frame", nil, hoverFrame)
  row:SetHeight(HOVER_LINE_H)
  row:EnableMouse(true)

  local hi = row:CreateTexture(nil, "BACKGROUND")
  hi:SetAllPoints(row)
  hi:SetColorTexture(1, 1, 1, 0.06)
  hi:Hide()

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(HOVER_ICON, HOVER_ICON)
  icon:SetPoint("LEFT")
  -- The stock icon border is baked into the texture's outer 6%, and at 11px it
  -- would be most of what you saw. Same crop as the grid's rows.
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:Hide()

  -- The rule under a group heading, and the whole of what separates one group
  -- from the next now that the heading is grey. The tab has had this since the
  -- grid arrived — its `stripe`, at the same 10% — and the hover was doing the
  -- same job with an orange word, which is a colour standing in for a line.
  local rule = row:CreateTexture(nil, "BACKGROUND")
  rule:SetAllPoints(row)
  rule:SetColorTexture(1, 1, 1, 0.10)
  rule:Hide()

  -- Grey for the same reason the tab's row labels are: the label says which
  -- row, and the cells to the right of it are what you came to read.
  local label = hoverText(row, "GameFontDisableSmall", "LEFT")
  label:SetPoint("LEFT")

  row:SetScript("OnEnter", function(self) self.hi:Show() end)
  row:SetScript("OnLeave", function(self)
    self.hi:Hide()
    hoverLeave()
  end)

  -- On the FRAME as well as in the pool entry: the handlers above are given the
  -- frame, not the table, and a highlight the row cannot reach is a nil call in
  -- the middle of a hover.
  row.hi = hi

  hoverRows[i] = { row = row, hi = hi, rule = rule, icon = icon, label = label, cells = {}, hits = {} }
  return hoverRows[i]
end

--- Give a line cells up to `n`. A cell is a frame around its FontString because
--- a FontString takes no mouse input, and the detail under the mouse is the
--- whole reason a two-character cell is worth reading.
local function growHoverRow(w, n)
  for j = #w.cells + 1, n do
    local hit = CreateFrame("Frame", nil, w.row)
    hit:SetPoint("LEFT", HOVER_LABEL_W + (j - 1) * HOVER_CELL_W, 0)
    hit:SetSize(HOVER_CELL_W, HOVER_LINE_H)
    -- Above the row's own hit area, which is a sibling by creation order: a
    -- tie on frame level would let the highlight swallow the tooltips.
    hit:SetFrameLevel(w.row:GetFrameLevel() + 2)
    hit:EnableMouse(true)
    -- The same number face the tab's cells use, for the same reason: this is
    -- the surface where a column of digits has the least room to be ragged in.
    local fs = numberText(hit, w.label)
    fs:SetAllPoints(hit)
    hit:SetScript("OnEnter", function(self)
      w.hi:Show()
      if not self.tip then return end
      showTip(self, self.tipTitle, self.tip, hoverFrame)
    end)
    hit:SetScript("OnLeave", function()
      w.hi:Hide()
      GameTooltip:Hide()
      hoverLeave()
    end)
    w.cells[j] = fs
    w.hits[j] = hit
  end
end

--- The panel, built once. Nil means this client had no tooltip chrome to build
--- on and the caller should fall back to the glance.
local function makeHoverGrid()
  if hoverFrame then return hoverFrame end
  local f = ns.safe(function()
    return CreateFrame("Frame", "WarbandProHoverGrid", UIParent, "TooltipBackdropTemplate")
  end)
  if not f then return nil end

  -- DIALOG rather than TOOLTIP, deliberately: the per-cell detail is the real
  -- GameTooltip and it has to open ON TOP of this panel, not behind it.
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetScript("OnLeave", hoverLeave)
  f:Hide()

  hoverFrame = f
  hoverTitle = hoverText(f, "GameFontNormal", "LEFT")
  hoverMeta = hoverText(f, "GameFontHighlightSmall", "LEFT")
  hoverNote = hoverText(f, "GameFontDisableSmall", "LEFT")
  hoverHint = hoverText(f, "GameFontNormalSmall", "LEFT")
  hoverHint2 = hoverText(f, "GameFontDisableSmall", "LEFT")
  return f
end

--- Paint the grid and show it beside the button.
---
--- Returns false when there is no panel to paint, which is the caller's cue to
--- show the glance instead.
local function showHoverGrid(owner)
  if not makeHoverGrid() then return false end
  local f = hoverFrame

  local maxCols, maxLines = hoverFit()
  local g = ns.Roster.Hover(ns.Store.db, ns.safe(UnitGUID, "player"), maxCols, maxLines)
  local nCols = #g.columns
  local gridW = HOVER_LABEL_W + nCols * HOVER_CELL_W

  for i = #hoverHeads + 1, nCols do makeHoverHead(i) end
  for i = #hoverRows + 1, #g.lines do makeHoverRow(i) end
  for i = 1, #hoverRows do growHoverRow(hoverRows[i], nCols) end

  local y = -HOVER_PAD
  local function place(fs, text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", HOVER_PAD, y)
    fs:SetText(text)
    fs:Show()
  end

  place(hoverTitle, "Warband.pro")
  y = y - 16

  -- Two values and the words between them: the count and the age are what
  -- this line is for, so they keep the bright ink and the rest takes the grey.
  place(hoverMeta, format("%s %d|cff%s character%s  ·  freshest |r%s", DOT[g.dot] or DOT.never,
    g.characters, MUTED, g.characters == 1 and "" or "s", g.ago))
  y = y - HOVER_TEXT_H

  -- The summary band: the four cross-warband lines this hover already carried,
  -- kept because the grid under them cannot say what they say — a grid answers
  -- per character and these answer per warband, which is the only shape in
  -- which four lines cover twenty alts.
  if #g.glance > 0 then y = y - HOVER_GAP end
  for i = 1, math.max(#g.glance, #hoverGlance) do
    local gl = g.glance[i]
    local w = hoverGlance[i]
    if gl and not w then
      w = { left = hoverText(f, "GameFontHighlightSmall", "LEFT"),
            right = hoverText(f, "GameFontHighlightSmall", "RIGHT") }
      hoverGlance[i] = w
    end
    if w and not gl then
      w.left:Hide()
      w.right:Hide()
    elseif w then
      local label, right = glanceLine(gl)
      w.left:ClearAllPoints()
      w.left:SetPoint("TOPLEFT", HOVER_PAD, y)
      w.left:SetText(label)
      w.left:Show()
      w.right:ClearAllPoints()
      w.right:SetPoint("TOPRIGHT", -HOVER_PAD, y)
      w.right:SetText(right)
      w.right:Show()
      y = y - HOVER_TEXT_H
    end
  end

  y = y - HOVER_GAP
  for i = 1, #hoverHeads do
    local col, head = g.columns[i], hoverHeads[i]
    head.hit.col = col
    head.hit:SetShown(col ~= nil)
    if col then
      head.hit:ClearAllPoints()
      head.hit:SetPoint("TOPLEFT", HOVER_PAD + HOVER_LABEL_W + (i - 1) * HOVER_CELL_W, y)
      head.name:SetText((DOT[col.dot] or DOT.never) .. classText(col.class, col.name))
    end
  end
  if nCols > 0 then y = y - HOVER_TEXT_H - 2 end

  for i = 1, #hoverRows do
    local line, w = g.lines[i], hoverRows[i]
    if not line then
      w.row:Hide()
    else
      w.row:ClearAllPoints()
      w.row:SetPoint("TOPLEFT", HOVER_PAD, y)
      w.row:SetWidth(gridW)
      w.hi:Hide()
      w.row:Show()
      y = y - HOVER_LINE_H

      -- A group heading is a grey label over its own rule — the tab's stripe,
      -- at the tab's weight. It was an orange word and no rule at all, which
      -- is colour doing a line's job on the one surface that most needs to
      -- stay quiet behind its values. It has no `+` because there is nothing
      -- to click: shutting a group is a decision you make in the tab.
      local head = line.head
      w.rule:SetShown(head ~= nil)
      w.icon:SetShown(line.icon ~= nil and not head)
      if line.icon and not head then w.icon:SetTexture(line.icon) end
      w.label:ClearAllPoints()
      if line.icon and not head then
        w.label:SetPoint("LEFT", HOVER_ICON + HOVER_ICON_GAP, 0)
        w.label:SetWidth(HOVER_LABEL_W - HOVER_ICON - HOVER_ICON_GAP - 4)
      else
        w.label:SetPoint("LEFT")
        w.label:SetWidth(HOVER_LABEL_W - 4)
      end
      w.label:SetText(head or line.label)

      for j = 1, #w.cells do
        local c = not head and j <= nCols and line.cells[j] or nil
        local hit = w.hits[j]
        if not c then
          -- An empty cell, never a zero: Roster.lua's rule 1, drawn in a
          -- tooltip this time.
          w.cells[j]:SetText("")
          hit.tip, hit.tipTitle = nil, nil
          hit:Hide()
        else
          w.cells[j]:SetText(TONE[c.tone] and format("|cff%s%s|r", TONE[c.tone], c.text) or c.text)
          -- The detail names WHOSE cell it is, in that character's class
          -- colour, and what it is a cell OF in the section colour — the two
          -- things a grid read across has lost by the time the mouse arrives.
          hit.tip = c.tip
          hit.tipTitle = g.columns[j] and classText(g.columns[j].class, g.columns[j].name) or nil
          if hit.tipTitle and c.tip then
            local tip = { format("|cff%s%s|r", ORANGE, line.label) }
            for _, l in ipairs(c.tip) do tip[#tip + 1] = l end
            hit.tip = tip
          end
          hit:Show()
        end
      end
    end
  end

  y = y - HOVER_GAP
  local note
  if g.characters == 0 then
    note = "no characters scanned yet — log in on a character and it lands here"
  elseif g.moreColumns > 0 or g.moreRows > 0 then
    -- Counted out loud. A hover that quietly showed nine of twenty alts would
    -- be worse than the summary it replaced.
    local parts = {}
    if g.moreColumns > 0 then parts[#parts + 1] = format("+%d character%s", g.moreColumns,
      g.moreColumns == 1 and "" or "s") end
    if g.moreRows > 0 then parts[#parts + 1] = format("+%d row%s", g.moreRows,
      g.moreRows == 1 and "" or "s") end
    note = table.concat(parts, "  ·  ") .. " did not fit"
  end
  if note then
    place(hoverNote, note)
    y = y - HOVER_TEXT_H
  else
    hoverNote:Hide()
  end

  place(hoverHint, "Click  ·  the export string      Right-click  ·  options")
  y = y - HOVER_TEXT_H
  -- The tab is the follow-up surface and this is where it gets discovered: it
  -- scrolls, it shuts a group and it pages, which is the whole of what a
  -- tooltip cannot do.
  place(hoverHint2, "Drag  ·  move it round the ring      /warband roster  ·  the same grid, scrollable")
  y = y - HOVER_TEXT_H

  f:SetSize(math.max(gridW, HOVER_MIN_W) + HOVER_PAD * 2, -y + HOVER_PAD)
  f:ClearAllPoints()
  -- Shoulder to shoulder with the button, so the cursor can cross into the
  -- panel without passing over the minimap between them.
  f:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
  f:Show()
  return true
end

--- Built once, and only when there is a Minimap to hang it on. Returns nil on a
--- client without one rather than erroring, the same way every other API call
--- in this addon fails a section instead of a session.
local function buildMinimap()
  if minimapButton then return minimapButton end
  if not Minimap then return nil end

  local b = CreateFrame("Button", "WarbandProMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(ns.ICON)
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  -- Stock icon art carries a drawn-on square border of its own, and the ring
  -- above is already this button's border. Trim the edges rather than show two.
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- Left opens the string, right opens the options — and the switch that takes
  -- this button away is on that tab, so the thing a player wants to be rid of
  -- is what hands them the way to do it.
  b:SetScript("OnClick", function(_, button)
    UI.HideHover()
    if button == "RightButton" then
      UI.ToggleOptions()
    else
      UI.Toggle("bundle")
    end
  end)

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", dragMinimap)
    GameTooltip:Hide()
    UI.HideHover()
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    ns.Store.Touch()
  end)

  -- The grid, and the glance only when there is no panel to draw the grid in.
  b:SetScript("OnEnter", function(self)
    if not showHoverGrid(self) then minimapTooltip(self) end
  end)
  -- Leaving the button is not leaving the hover: the panel is next door and the
  -- cursor is probably on its way there. `hoverLeave` asks where the mouse
  -- actually ended up before it closes anything.
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
    hoverLeave()
  end)

  minimapButton = b
  return b
end

--- Build, place, and show or hide the button to match the saved options. Safe
--- to call again at any point — login, the Options checkbox and
--- `/warband minimap` all come through here.
function UI.RefreshMinimap()
  local o = minimapOpts()
  if not o then return end
  if o.minimap == false then
    if minimapButton then minimapButton:Hide() end
    UI.HideHover()
    return
  end
  if not buildMinimap() then return end
  placeMinimap(o.minimapAngle or MINIMAP_ANGLE)
  minimapButton:Show()
end

-- Blizzard's addon compartment entry, declared by the .toc, and the keybinding
-- entry declared by Bindings.xml. These are the last globals the addon defines.
--
-- Both open the same window on the same tab, because both answer the same
-- question — "put the string in front of me" — and a key that landed somewhere
-- else would be a second design of one action.
function _G.WarbandPro_OnAddonCompartmentClick()
  UI.Toggle("bundle")
end

function _G.WarbandPro_ToggleFromBinding()
  UI.Toggle("bundle")
end

-- What the Key Bindings panel reads. `Bindings.xml` names an action and a
-- header; the panel turns each into text by looking up a global, and prints the
-- raw token when there is none. Both were missing, so the binding sat under a
-- heading called WARBANDPRO as a row called WARBANDPRO_TOGGLE — findable, but
-- shouting, and not the "Key Bindings > WarbandPro" docs/FLOW.md promises.
_G.BINDING_HEADER_WARBANDPRO = "Warband.pro"
_G.BINDING_NAME_WARBANDPRO_TOGGLE = "Open the export window"
