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
