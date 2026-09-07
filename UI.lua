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
local DOT = {
  green  = "|cff00ff00*|r",
  yellow = "|cffffd100*|r",
  red    = "|cffff2020*|r",
  never  = "|cff808080*|r",
}
local MUTED, WARN, BAD, GOOD = "808080", "ffd100", "ff2020", "00ff00"

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
local junkPaste, junkHeader, junkFooter, junkRows, junkChild
local gsHeader, gsButton, gsList, gsRows
local rosterHead, rosterFoot, rosterCols, rosterLines, rosterChild, rosterPrev, rosterNext
local rosterScroll
local optionChecks = {}

UI.mode = "bundle"
-- Which six characters the grid is showing. Same idiom as UI.page below and
-- for the same reason: a warband can be larger than the surface that draws it.
UI.rosterPage = 1
-- Which page of a warband too large for one bundle is in the box. Always 1
-- unless `/warband copy 2` asked for another, and reset by any plain open so
-- the panel cannot sit on page 3 days after the player went looking for it.
UI.page = 1

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

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", 0, -18 - MAX_ROWS * 14 - 6)
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

local function refreshExport()
  local str, bytes, payload, rawBytes =
    ns.Export.Build({ currentOnly = UI.mode == "current", page = UI.page })
  UI.current = str or ""
  editBox:SetText(UI.current)
  -- A new string has not been copied yet, whatever happened to the last one.
  UI.copied = false
  refreshHelp()

  local summary = ns.Bundle.Summary(payload)
  renderRows(summary)

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
    -- goes out a page at a time and the header has to say which page this is
    -- and how to get the next — the count alone reads as a loss, and the old
    -- line made that literal by offering `/warband clear <name>` as the
    -- remedy. Deleting an alt is the wrong answer for the player who has
    -- twenty-one of them; the site merges pages rather than replacing what it
    -- holds, so all of them fit if they are all sent.
    local dropped = payload.bundle.droppedOverCap
    local pages = payload.bundle.pages
    local warnLine = ""
    if dropped and pages then
      local next_ = (payload.bundle.page or 1) % pages + 1
      warnLine = format("  |cff%s·  page %d of %d — /warband copy %d for the next %d|r",
        WARN, payload.bundle.page or 1, pages, next_, math.min(dropped, ns.MAX_CHARS))
    elseif allStale then
      warnLine = format("  |cff%s·  all stale — log those alts in again for fresher numbers|r", WARN)
    end
    header:SetText(format("%d character%s  ·  freshest %s%s%s",
      #summary, #summary == 1 and "" or "s",
      #summary > 0 and ns.ago(payload.bundle.freshestSeenAt) or "never", bank, warnLine))
    local note = bytes > ns.SOFT_BYTES and format("  |cff%s(large — try /warband copy current)|r", WARN) or ""
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
    if not self.s then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- The client's own item tooltip for the wire's item string. A string the
    -- client cannot resolve leaves the tooltip empty rather than raising.
    ns.safe(GameTooltip.SetHyperlink, GameTooltip, self.s)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
      w.icon:SetTexture(icon or ns.ICON)
      w.slot:SetText(d.name)
      -- Name, then the client's item level, then — when the site sent one —
      -- its estimated gain, in the good tone because a row here is a swap
      -- the site is proposing and the figure is why.
      local gain = ns.GearSet.GainText(d)
      w.label:SetText(format("|cff%s%s|r%s%s",
        name and hex or MUTED,
        name or (d.id and ("item " .. d.id) or "?"),
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
    self:SetText("")
    self:ClearFocus()

    if keptJunk + keptSets + keptBuilds == 0 then
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
      local sellable = r.k ~= "del" or r.grey
      w.sell:SetShown(sellable)
      w.sell:SetEnabled(sellable and ns.Junk.merchantOpen)
      w.sell:SetScript("OnClick", function()
        if ns.Junk.Sell(r.bag, r.slot) then UI.RenderJunk() end
      end)

      local wantsDE = canDE and r.k == "de" and not r.grey
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

--- Paint one of Roster.lua's tips into GameTooltip and show it.
---
--- The model hands back plain strings and `{left, right}` pairs and no colour
--- at all, so the palette decision lives here with the rest of it. Two columns
--- for a pair is what makes `Ulgrax   dead` scan as a table rather than as
--- prose — the same reason the grid itself has columns.
local function showTip(owner, title, tip)
  if not tip or #tip == 0 then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
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
    local c = self.col
    local tip = {}
    if c.realm then tip[#tip + 1] = { "realm", c.realm } end
    if c.guild then tip[#tip + 1] = { "guild", c.guild } end
    if c.level then tip[#tip + 1] = { "level", tostring(c.level) } end
    if c.ilvl then tip[#tip + 1] = { "item level", tostring(c.ilvl) } end
    if c.gold then tip[#tip + 1] = { "gold", c.gold } end
    if c.zone then tip[#tip + 1] = { "last seen in", c.zone } end
    tip[#tip + 1] = { "scanned", c.ago }
    showTip(self, c.name, tip)
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

  local label = rosterChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    label = label, stripe = stripe, hi = hi, rowHit = rowHit,
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
    local fs = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints(hit)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
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
  rosterHead:SetPoint("TOPRIGHT")
  rosterHead:SetJustifyH("LEFT")

  rosterCols = {}

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", 0, -50)
  well:SetPoint("BOTTOMRIGHT", -20, 34)

  local scroll = CreateFrame("ScrollFrame", "WarbandProRosterScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", well, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, 8)
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
  -- because that is what fittingCols measures — and because an anchored frame
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
function UI.RenderRoster()
  if not rosterLines then return end
  local db = ns.Store.db
  local model = ns.Roster.Build(db, ns.safe(UnitGUID, "player"))
  local all = model.columns

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
  local opts = db and db.opts
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
      w.label:SetText("")
      w.stripe:Hide()
      w.rowHit:EnableMouse(false)
      w.rowHit.group, w.rowHit.hint = nil, nil
      blank(w)
    elseif line.head then
      -- A group header is the rule between groups as well as its name: the
      -- stripe under it is what stops `currencies` reading as one more row of
      -- the block above it.
      --
      -- The `+`/`-` in front of it is the whole of the affordance. A shut group
      -- names the count it is holding, because `pockets` with a rule under it
      -- and nothing else looks like a group that had nothing to say.
      w.label:SetText(format("|cff%s%s %s%s|r", MUTED, line.closed and "+" or "-", line.head,
        line.closed and format("  (%d)", line.hidden) or ""))
      w.stripe:SetColorTexture(1, 1, 1, 0.05)
      w.stripe:Show()
      w.rowHit:EnableMouse(true)
      w.rowHit.group = line.head
      w.rowHit.hint = line.closed and "click to open" or "click to close"
      blank(w)
    else
      w.label:SetText(line.label)
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
    rosterHead:SetText(format("%d character%s%s", #all, #all == 1 and "" or "s",
      pages > 1 and format("  ·  |cff%sshowing %d-%d · drag the corner to widen|r", MUTED, first + 1,
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
local function makeOption(p, y, label, desc, get, set)
  local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", 0, y)
  check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)

  local text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", check, "RIGHT", 4, 0)
  text:SetText(label)

  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 4)
  sub:SetPoint("RIGHT", p, "RIGHT", -8, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText(desc)

  optionChecks[#optionChecks + 1] = { check = check, get = get }
  return check
end

local function buildOptions()
  local p = panels[TAB_OPTIONS]
  local opts = function() return ns.Store.db and ns.Store.db.opts end

  makeOption(p, 0,
    "Capture gear",
    "Equipped, bag, bank and warband-bank gear — and talents — ride the export string. "
      .. "Turning this off keeps what is already stored; it is just left out of the next bundle.",
    function() local o = opts() return o and o.includeGear end,
    function(v)
      local o = opts()
      if not o then return end
      o.includeGear = v
      ns.Store.Touch()
      if v then
        ns.Scan.Bags()   -- current bag contents; equipped and the rest follow
        ns.Gear.All()
      end
    end)

  makeOption(p, -66,
    "Include item links",
    "Full hyperlinks for every bag stack, for debugging a specific item. "
      .. "Costs about a third more wire.",
    function() local o = opts() return o and o.includeLinks end,
    function(v)
      local o = opts()
      if not o then return end
      o.includeLinks = v
      ns.Store.Touch()
    end)

  makeOption(p, -132,
    "Open the clear-out list at merchants",
    "When a merchant window opens and the cleanup list has something in your bags, "
      .. "the Import tab opens by itself and closes when you leave the merchant.",
    function() local o = opts() return o and o.autoJunk end,
    function(v)
      local o = opts()
      if not o then return end
      o.autoJunk = v
      ns.Store.Touch()
    end)

  makeOption(p, -198,
    "Show the minimap button",
    "The icon on the minimap ring — click it for the export string, right-click it for this tab, "
      .. "drag it anywhere round the ring. Turning it off leaves /warband and the addon compartment.",
    function() local o = opts() return o and o.minimap end,
    function(v)
      local o = opts()
      if not o then return end
      o.minimap = v
      ns.Store.Touch()
      UI.RefreshMinimap()
    end)

  makeOption(p, -264,
    "Show every currency in the Roster grid",
    "The grid lists the currencies the game is still metering — one with a cap, a weekly cap, "
      .. "or something earned towards it this week — and its header says how many it left out. "
      .. "Turn this on to list every currency any character is carrying.",
    function() local o = opts() return o and o.allCurrencies end,
    function(v)
      local o = opts()
      if not o then return end
      o.allCurrencies = v
      ns.Store.Touch()
      UI.RenderRoster()
    end)

  local version = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", 0, 2)
  version:SetPoint("BOTTOMRIGHT", 0, 2)
  version:SetJustifyH("LEFT")
  version:SetText(format("Warband.pro v%s  ·  no network calls — the export moves only when you copy it",
    ns.VERSION))
end

local function refreshOptions()
  for _, o in ipairs(optionChecks) do
    o.check:SetChecked(o.get() and true or false)
  end
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

--- Open the window on a tab. Fails closed in combat: the request is queued and
--- honored when the fight ends, rather than fighting the taint rules mid-pull.
function UI.Open(tab, mode, page)
  if InCombatLockdown() then
    UI.pendingOpen = { tab = tab, mode = mode, page = page }
    ns.print("in combat — the window will open when you drop out")
    return
  end
  UI.pendingOpen = nil
  if mode then UI.mode = mode end
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
  local label = line.label
  if TONE[line.tone] then label = format("|cff%s%s|r", TONE[line.tone], label) end
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
    if button == "RightButton" then
      UI.ToggleOptions()
    else
      UI.Toggle("bundle")
    end
  end)

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", dragMinimap)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    ns.Store.Touch()
  end)

  b:SetScript("OnEnter", minimapTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
