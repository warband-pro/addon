-- WarbandPro / UI.lua
-- One panel. Blizzard widgets only, no XML, no templates beyond the three
-- Blizzard has shipped for a decade, no tooltip hooks, no minimap button.
--
-- The whole job is: show what the bundle contains and how stale it is, then put
-- the string somewhere Ctrl+C can reach it. WoW has no SetClipboard, so an
-- auto-highlighted multiline EditBox is the only path that works.

local _, ns = ...

local UI = {}
ns.UI = UI

local DOT = {
  green  = "|cff50fa7b*|r",
  yellow = "|cfff1fa8c*|r",
  red    = "|cffff5555*|r",
  never  = "|cff6272a4*|r",
}

local MAX_ROWS = 10
local frame, editBox, scroll, header, footer, rows

-- The junk panel's own widgets. A second frame rather than a mode on the first:
-- the export panel exists to be copied FROM and reverts anything typed into it,
-- and this one exists to be pasted INTO. One frame doing both would need that
-- rule to be conditional, which is the kind of conditional that eventually
-- eats a paste.
local JUNK_ROWS = 12
local junkFrame, junkPaste, junkHeader, junkFooter, junkRows, junkScroll, junkChild

local function backdrop(f)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.043, 0.047, 0.071, 0.96)
  for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local line = f:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.27, 0.28, 0.35, 1)
    if edge == "TOP" or edge == "BOTTOM" then
      line:SetHeight(1)
      line:SetPoint(edge .. "LEFT")
      line:SetPoint(edge .. "RIGHT")
    else
      line:SetWidth(1)
      line:SetPoint("TOP" .. edge)
      line:SetPoint("BOTTOM" .. edge)
    end
  end
end

local function build()
  if frame then return frame end

  frame = CreateFrame("Frame", "WarbandProExportFrame", UIParent)
  frame:SetSize(520, 460)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  backdrop(frame)
  tinsert(UISpecialFrames, "WarbandProExportFrame")   -- Esc closes

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("warband.pro")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  header:SetPoint("TOPLEFT", 16, -36)
  header:SetPoint("TOPRIGHT", -16, -36)
  header:SetJustifyH("LEFT")

  rows = {}
  for i = 1, MAX_ROWS do
    local row = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row:SetPoint("TOPLEFT", 16, -54 - (i - 1) * 14)
    row:SetPoint("TOPRIGHT", -16, -54 - (i - 1) * 14)
    row:SetJustifyH("LEFT")
    rows[i] = row
  end

  -- The well is created before the scroll frame on purpose: siblings get their
  -- frame level from creation order, and a backdrop made afterwards would paint
  -- over the very string this panel exists to show.
  local well = CreateFrame("Frame", nil, frame)
  well:SetPoint("TOPLEFT", 10, -200)
  well:SetPoint("BOTTOMRIGHT", -28, 86)
  backdrop(well)

  scroll = CreateFrame("ScrollFrame", "WarbandProExportScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 6)

  editBox = CreateFrame("EditBox", nil, scroll)
  editBox:SetMultiLine(true)
  editBox:SetMaxLetters(0)          -- Blizzard's default cap would truncate us
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetWidth(452)
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
  scroll:SetScrollChild(editBox)

  local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("BOTTOMLEFT", 16, 48)
  help:SetPoint("BOTTOMRIGHT", -16, 48)
  help:SetJustifyH("LEFT")
  help:SetText("1. Ctrl+C copies (already selected)   2. warband.pro > Import, or Ctrl+V   3. Esc closes")

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 16, 18)
  footer:SetJustifyH("LEFT")

  local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectAll:SetSize(110, 22)
  selectAll:SetPoint("BOTTOMRIGHT", -16, 12)
  selectAll:SetText("Select all")
  selectAll:SetScript("OnClick", function()
    editBox:SetFocus()
    editBox:HighlightText()
  end)

  frame:SetScript("OnShow", function()
    -- Highlighting only sticks once the frame has actually drawn.
    C_Timer.After(0, function()
      if frame:IsShown() then
        editBox:SetFocus()
        editBox:HighlightText()
      end
    end)
  end)

  return frame
end

-- ── the junk panel ──────────────────────────────────────────────────────────

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
  row.label:SetPoint("RIGHT", row, "RIGHT", -150, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)

  row.sell = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.sell:SetSize(52, 16)
  row.sell:SetPoint("RIGHT", -76, 0)
  row.sell:SetText("Sell")

  row.de = CreateFrame("Button", "WarbandProJunkDE" .. i, row, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  row.de:SetSize(72, 16)
  row.de:SetPoint("RIGHT", -2, 0)
  row.de:SetText("Disenchant")
  row.de:RegisterForClicks("AnyUp", "AnyDown")

  return row
end

local function buildJunk()
  if junkFrame then return junkFrame end

  junkFrame = CreateFrame("Frame", "WarbandProJunkFrame", UIParent)
  junkFrame:SetSize(520, 420)
  junkFrame:SetPoint("CENTER", 60, -30)
  junkFrame:SetFrameStrata("DIALOG")
  junkFrame:SetToplevel(true)
  junkFrame:EnableMouse(true)
  junkFrame:SetMovable(true)
  junkFrame:RegisterForDrag("LeftButton")
  junkFrame:SetScript("OnDragStart", junkFrame.StartMoving)
  junkFrame:SetScript("OnDragStop", junkFrame.StopMovingOrSizing)
  junkFrame:Hide()
  backdrop(junkFrame)
  tinsert(UISpecialFrames, "WarbandProJunkFrame")

  local title = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("warband.pro  ·  clear out")

  local close = CreateFrame("Button", nil, junkFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  -- The paste box. No OnTextChanged revert here — that rule belongs to the
  -- export panel, whose text is ours. This one's text is the player's.
  local well = CreateFrame("Frame", nil, junkFrame)
  well:SetPoint("TOPLEFT", 12, -38)
  well:SetPoint("TOPRIGHT", -12, -38)
  well:SetHeight(26)
  backdrop(well)

  junkPaste = CreateFrame("EditBox", nil, well)
  junkPaste:SetPoint("TOPLEFT", 6, -5)
  junkPaste:SetPoint("BOTTOMRIGHT", -6, 5)
  junkPaste:SetAutoFocus(false)
  junkPaste:SetMaxLetters(0)
  junkPaste:SetFontObject(ChatFontNormal)
  junkPaste:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    junkFrame:Hide()
  end)
  junkPaste:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = self:GetText()
    if text == "" or #text < 6 then return end
    local decoded, code = ns.Import.DecodeCleanup(text)
    if not decoded then
      -- Only complain once the paste looks finished. A prefix typed one
      -- character at a time would otherwise scold on every keystroke.
      if text:sub(1, #ns.CLEANUP_WIRE) == ns.CLEANUP_WIRE or #text > 24 then
        junkHeader:SetText("|cffff5555" .. ns.Import.Message(code) .. "|r")
      end
      return
    end
    local kept = ns.Junk.Save(decoded)
    self:SetText("")
    self:ClearFocus()
    if kept == 0 then
      junkHeader:SetText("|cfff1fa8cthat list is for characters this account has not scanned yet|r")
      return
    end
    UI.RenderJunk()
  end)

  junkHeader = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  junkHeader:SetPoint("TOPLEFT", 16, -72)
  junkHeader:SetPoint("TOPRIGHT", -16, -72)
  junkHeader:SetJustifyH("LEFT")

  local list = CreateFrame("Frame", nil, junkFrame)
  list:SetPoint("TOPLEFT", 10, -90)
  list:SetPoint("BOTTOMRIGHT", -28, 40)
  backdrop(list)

  junkScroll = CreateFrame("ScrollFrame", "WarbandProJunkScroll", junkFrame, "UIPanelScrollFrameTemplate")
  junkScroll:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6)
  junkScroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -6, 6)

  junkChild = CreateFrame("Frame", nil, junkScroll)
  junkChild:SetSize(452, JUNK_ROWS * 18)
  junkScroll:SetScrollChild(junkChild)

  junkRows = {}
  for i = 1, JUNK_ROWS do
    junkRows[i] = buildJunkRow(junkChild, i)
  end

  junkFooter = junkFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  junkFooter:SetPoint("BOTTOMLEFT", 16, 16)
  junkFooter:SetPoint("BOTTOMRIGHT", -16, 16)
  junkFooter:SetJustifyH("LEFT")

  return junkFrame
end

--- Redraw the junk list from the live bags.
---
--- Every coordinate a button carries comes from the walk this function just
--- made, never from storage — see Junk.lua's header for why that is the whole
--- design. Called on open, on a bag change while open, and when a merchant
--- opens or closes.
function UI.RenderJunk()
  if not junkFrame then return end
  -- Secure attributes may not be written in combat. The panel hides itself on
  -- PLAYER_REGEN_DISABLED, so this is the belt to that braces.
  if InCombatLockdown() then return end

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
      w.label:SetText(format(
        "|cff%s%s|r%s%s",
        hex,
        r.name or "?",
        r.ilvl and ("  |cff6272a4" .. r.ilvl .. "|r") or "",
        reason ~= "" and ("  |cff6272a4" .. reason .. "|r") or ""
      ))

      -- Sell is only ever live at a merchant. Off it, the button says why
      -- rather than disappearing — a row that changes shape when you walk up
      -- to a vendor is harder to read than one that lights up.
      w.sell:SetEnabled(ns.Junk.merchantOpen)
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
    parts[#parts + 1] = format("|cff6272a4%d no longer in your bags|r", missing)
  end
  if generatedAt then
    parts[#parts + 1] = "|cff6272a4list from " .. ns.ago(generatedAt) .. "|r"
  end
  junkHeader:SetText(table.concat(parts, "  ·  "))

  if #rowsData > JUNK_ROWS then
    junkFooter:SetText(format("|cff6272a4showing %d of %d|r", JUNK_ROWS, #rowsData))
  elseif not ns.Junk.merchantOpen then
    junkFooter:SetText("|cff6272a4open a merchant to sell  ·  paste a new list any time|r")
  else
    junkFooter:SetText("|cff6272a4at a merchant — Sell is live|r")
  end
end

function UI.ShowJunk()
  if InCombatLockdown() then
    UI.pendingJunk = true
    ns.print("in combat — the clear-out panel will open when you drop out")
    return
  end
  UI.pendingJunk = nil
  buildJunk()
  UI.RenderJunk()
  if not ns.Junk.Stored() then
    junkHeader:SetText("|cff6272a4paste the cleanup string from warband.pro/gear above|r")
  end
  junkFrame:Show()
end

function UI.ToggleJunk()
  if junkFrame and junkFrame:IsShown() then
    junkFrame:Hide()
    return
  end
  UI.ShowJunk()
end

--- Hide on the way into combat. Secure attributes cannot be rewritten there, so
--- a panel left open would go stale behind the player's back and hand a click
--- to a bag slot that has since moved. Failing closed is the same posture
--- UI.Show already takes.
function UI.JunkCombatLockdown()
  if junkFrame and junkFrame:IsShown() then
    UI.reopenJunk = true
    junkFrame:Hide()
  end
end

function UI.JunkIsShown()
  return junkFrame and junkFrame:IsShown()
end

local function renderRows(summary)
  for i = 1, MAX_ROWS do rows[i]:SetText("") end
  if #summary == 0 then
    rows[1]:SetText("|cff6272a4No characters scanned yet — log in on a character and it lands here.|r")
    return
  end
  local shown = math.min(#summary, MAX_ROWS)
  for i = 1, shown do
    local r = summary[i]
    local line = format("%s %s|cff6272a4-%s|r  %s", DOT[r.dot] or DOT.never, r.name, r.realm or "?", r.ago)
    if r.bankAgo ~= "never" then line = line .. "  |cff6272a4bank " .. r.bankAgo .. "|r" end
    rows[i]:SetText(line)
  end
  if #summary > MAX_ROWS then
    rows[MAX_ROWS]:SetText(format("|cff6272a4+%d more in the bundle|r", #summary - MAX_ROWS + 1))
  end
end

-- mode: "bundle" (default) or "current"
function UI.Show(mode)
  -- Fail closed in combat: queue the panel and open it when the fight ends,
  -- rather than fighting the taint rules mid-pull.
  if InCombatLockdown() then
    UI.pending = mode or "bundle"
    ns.print("in combat — the export panel will open when you drop out")
    return
  end
  UI.pending = nil
  build()

  local str, bytes, payload, rawBytes = ns.Export.Build({ currentOnly = mode == "current" })
  UI.current = str or ""
  editBox:SetText(UI.current)

  local summary = ns.Bundle.Summary(payload)
  renderRows(summary)

  if not str then
    header:SetText("|cffff5555Could not build the bundle|r — /warband status has the detail")
    footer:SetText("")
  else
    local wb = ns.Store.db and ns.Store.db.warbandBank
    local bank = (wb and wb.seenAt)
      and format("  ·  warband bank %s (by %s)", ns.ago(wb.seenAt), wb.seenByName or "?")
      or "  ·  warband bank never seen"
    header:SetText(format("%d character%s  ·  freshest %s%s",
      #summary, #summary == 1 and "" or "s",
      #summary > 0 and ns.ago(payload.bundle.freshestSeenAt) or "never", bank))
    local note = bytes > ns.SOFT_BYTES and "  |cfff1fa8c(large — try /warband copy current)|r" or ""
    footer:SetText(format("|cff6272a4%s  ·  %d bytes from %d of JSON|r%s", ns.WIRE, bytes, rawBytes or 0, note))
    -- Stamped here rather than in Export.Build, so /warband status can report
    -- when a string was last put in front of the user instead of resetting the
    -- answer every time it is asked.
    if ns.Store.Ready() then ns.Store.db.lastExport = ns.now() end
  end

  frame:Show()
end

function UI.Toggle(mode)
  if frame and frame:IsShown() then
    frame:Hide()
    return
  end
  UI.Show(mode)
end

function UI.Hide()
  if frame then frame:Hide() end
end

-- Blizzard's addon compartment entry, declared by the .toc. This is the second
-- and last global the addon defines.
function _G.WarbandPro_OnAddonCompartmentClick()
  UI.Toggle("bundle")
end
