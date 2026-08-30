-- WarbandPro / UI.lua
-- One window, three tabs: Export, Import, Options. Built entirely from the
-- templates Blizzard's own panels use — ButtonFrameTemplate for the chrome,
-- PanelTabButtonTemplate for the tabs, InputBoxTemplate and InsetFrameTemplate
-- inside — so the window looks like the game and inherits whatever the player
-- has set: UI scale, font scale, colorblind text. No hand-rolled backdrop, no
-- pixel skin of our own.
--
-- The two jobs have not changed. Export: show what the bundle contains and how
-- stale it is, then put the string somewhere Ctrl+C can reach it — WoW has no
-- SetClipboard, so an auto-highlighted multiline EditBox is the only path that
-- works. Import: take the string warband.pro sends back and turn it into a
-- clear-out list with live Sell and Disenchant buttons.
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

local TAB_EXPORT, TAB_IMPORT, TAB_OPTIONS = 1, 2, 3
local MAX_ROWS = 8
local JUNK_ROWS = 12

local frame, panels, tabs
local editBox, header, footer, rows, help
local junkPaste, junkHeader, junkFooter, junkRows, junkChild
local gsHeader, gsButton
local optionChecks = {}

UI.mode = "bundle"
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
    -- One box, two inbound wires: the prefix says which decoder the paste
    -- belongs to, and each decoder still refuses the other's string by name
    -- so a misrouted call fails toward a sentence rather than "invalid".
    local trimmed = text:gsub("^%s+", "")
    if trimmed:sub(1, #ns.GEARSET_WIRE) == ns.GEARSET_WIRE then
      local gs, gsCode = ns.Import.DecodeGearSet(text)
      if not gs then
        junkHeader:SetText("|cff" .. BAD .. ns.Import.GearSetMessage(gsCode) .. "|r")
        return
      end
      local kept = ns.GearSet.Save(gs)
      self:SetText("")
      self:ClearFocus()
      if kept == 0 then
        junkHeader:SetText("|cff" .. WARN .. "that set is for characters this account has not scanned yet|r")
        return
      end
      UI.RenderGearSet()
      junkHeader:SetText(format("|cff%sread a gear set for %d character%s — equip is below|r", GOOD, kept,
        kept == 1 and "" or "s"))
      return
    end
    local decoded, code = ns.Import.DecodeCleanup(text)
    if not decoded then
      -- Only complain once the paste looks finished. A prefix typed one
      -- character at a time would otherwise scold on every keystroke.
      --
      -- The floor was `#text < 6` plus this test, which together swallowed
      -- anything 1-24 characters that did not start with the prefix: no
      -- decode, no message, no clear — the box simply sat there having done
      -- nothing, which is indistinguishable from a broken addon. A paste is
      -- one event, so anything arriving at once is finished by definition.
      if #text >= #ns.CLEANUP_WIRE or #text > 24 then
        junkHeader:SetText("|cff" .. BAD .. ns.Import.Message(code) .. "|r")
      end
      return
    end
    -- What was there before, so the receipt can say this replaced something.
    -- Pasting a second list over a first was silent, and the two lists are
    -- usually for different characters — "nothing happened" and "your previous
    -- list is gone" looked identical.
    local had = ns.Junk.Count()
    local kept = ns.Junk.Save(decoded)
    self:SetText("")
    self:ClearFocus()
    if kept == 0 then
      junkHeader:SetText("|cff" .. WARN .. "that list is for characters this account has not scanned yet|r")
      return
    end
    UI.RenderJunk()
    -- After RenderJunk, which writes this same line from the resolved list —
    -- the receipt is about the paste and has to win.
    -- `kept` is characters, not items: Save stores one list per GUID and skips
    -- any this account has never scanned. Saying "items" here would report the
    -- wrong unit for the one number the paste produced.
    junkHeader:SetText(format("|cff%sread a list for %d character%s%s|r", GOOD, kept,
      kept == 1 and "" or "s", had > 0 and ", replacing the last one" or ""))
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

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", 0, -84)
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
    -- 1.10.0 a paste stores a setup per spec, so having sets and having none
    -- for the spec you are standing in is the common case after a respec —
    -- and "nothing here" would send that player back to the website for a
    -- string they already pasted.
    local stored = ns.GearSet.Summary()
    gsHeader:SetText(stored > 0
      and format("|cff%sgear set: none for this spec — %d stored for others|r", MUTED, stored)
      or "")
    gsButton:Hide()
    return
  end
  local parts = {}
  if #r.ready > 0 then parts[#parts + 1] = format("%d to equip", #r.ready) end
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

  local version = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", 0, 2)
  version:SetPoint("BOTTOMRIGHT", 0, 2)
  version:SetJustifyH("LEFT")
  version:SetText(format("Warband.pro Companion v%s  ·  no network calls — the export moves only when you copy it",
    ns.VERSION))
end

local function refreshOptions()
  for _, o in ipairs(optionChecks) do
    o.check:SetChecked(o.get() and true or false)
  end
end

-- ── the window ──────────────────────────────────────────────────────────────

local function build()
  if frame then return frame end

  frame = CreateFrame("Frame", "WarbandProFrame", UIParent, "ButtonFrameTemplate")
  frame:SetSize(560, 520)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  tinsert(UISpecialFrames, "WarbandProFrame")   -- Esc closes

  -- Mixin methods, guarded: a client where PortraitFrame lost one of these
  -- should cost the title or the icon, never the window.
  if frame.SetTitle then
    frame:SetTitle("Warband.pro Companion")
  elseif frame.TitleContainer and frame.TitleContainer.TitleText then
    frame.TitleContainer.TitleText:SetText("Warband.pro Companion")
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

  panels = { makePanel(), makePanel(), makePanel() }

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
  tabs[TAB_EXPORT]  = makeTab(TAB_EXPORT, "To warband.pro")
  tabs[TAB_IMPORT]  = makeTab(TAB_IMPORT, "From warband.pro")
  tabs[TAB_OPTIONS] = makeTab(TAB_OPTIONS, "Options")
  frame.Tabs = tabs
  PanelTemplates_SetNumTabs(frame, #tabs)

  buildExport()
  buildImport()
  buildOptions()

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
  if id == TAB_EXPORT then
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

--- What the window's header says, said before you open the window.
---
--- Read straight off the store rather than out of `Export.Build`: the header
--- gets its number from a built bundle because it is about to show you that
--- bundle, and a hover is not worth an encode and a deflate.
local function minimapFreshest()
  local db = ns.Store.db
  if not db or not db.chars then return nil end
  local best
  for _, c in pairs(db.chars) do
    local seen = c.seenAt and c.seenAt.lastSeen
    if seen and (not best or seen > best) then best = seen end
  end
  return best
end

local function minimapTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Warband.pro Companion")
  local n = ns.Store.Count()
  GameTooltip:AddLine(format("%d character%s  ·  freshest %s",
    n, n == 1 and "" or "s", ns.ago(minimapFreshest())), 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click  ·  the export string", 1, 0.82, 0)
  GameTooltip:AddLine("Right-click  ·  options", 1, 0.82, 0)
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
_G.BINDING_HEADER_WARBANDPRO = "Warband.pro Companion"
_G.BINDING_NAME_WARBANDPRO_TOGGLE = "Open the export window"
