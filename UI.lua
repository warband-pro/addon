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
local MUTED, WARN, BAD = "808080", "ffd100", "ff2020"

local TAB_EXPORT, TAB_IMPORT, TAB_OPTIONS = 1, 2, 3
local MAX_ROWS = 8
local JUNK_ROWS = 12

local frame, panels, tabs
local editBox, header, footer, rows
local junkPaste, junkHeader, junkFooter, junkRows, junkChild
local optionChecks = {}

UI.mode = "bundle"

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
  scroll:SetScrollChild(editBox)

  local help = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("BOTTOMLEFT", 0, 18)
  help:SetPoint("BOTTOMRIGHT", 0, 18)
  help:SetJustifyH("LEFT")
  help:SetText("1. Ctrl+C copies (already selected)   2. warband.pro > Import, or Ctrl+V   3. Esc closes")

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
    rows[1]:SetText("|cff" .. MUTED .. "No characters scanned yet — log in on a character and it lands here.|r")
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
  local str, bytes, payload, rawBytes = ns.Export.Build({ currentOnly = UI.mode == "current" })
  UI.current = str or ""
  editBox:SetText(UI.current)

  local summary = ns.Bundle.Summary(payload)
  renderRows(summary)

  if not str then
    header:SetText("|cff" .. BAD .. "Could not build the bundle|r — /warband status has the detail")
    footer:SetText("")
  else
    local wb = ns.Store.db and ns.Store.db.warbandBank
    local bank = (wb and wb.seenAt)
      and format("  ·  warband bank %s (by %s)", ns.ago(wb.seenAt), wb.seenByName or "?")
      or "  ·  warband bank never seen"
    header:SetText(format("%d character%s  ·  freshest %s%s",
      #summary, #summary == 1 and "" or "s",
      #summary > 0 and ns.ago(payload.bundle.freshestSeenAt) or "never", bank))
    local note = bytes > ns.SOFT_BYTES and format("  |cff%s(large — try /warband copy current)|r", WARN) or ""
    footer:SetText(format("|cff%s%s  ·  %d bytes from %d of JSON|r%s", MUTED, ns.WIRE, bytes, rawBytes or 0, note))
    -- Stamped here rather than in Export.Build, so /warband status can report
    -- when a string was last put in front of the user instead of resetting the
    -- answer every time it is asked.
    if ns.Store.Ready() then ns.Store.db.lastExport = ns.now() end
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
  intro:SetText("Paste the cleanup string from warband.pro/gear — it reads itself.")

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
    if text == "" or #text < 6 then return end
    local decoded, code = ns.Import.DecodeCleanup(text)
    if not decoded then
      -- Only complain once the paste looks finished. A prefix typed one
      -- character at a time would otherwise scold on every keystroke.
      if text:sub(1, #ns.CLEANUP_WIRE) == ns.CLEANUP_WIRE or #text > 24 then
        junkHeader:SetText("|cff" .. BAD .. ns.Import.Message(code) .. "|r")
      end
      return
    end
    local kept = ns.Junk.Save(decoded)
    self:SetText("")
    self:ClearFocus()
    if kept == 0 then
      junkHeader:SetText("|cff" .. WARN .. "that list is for characters this account has not scanned yet|r")
      return
    end
    UI.RenderJunk()
  end)

  junkHeader = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  junkHeader:SetPoint("TOPLEFT", 0, -46)
  junkHeader:SetPoint("TOPRIGHT", 0, -46)
  junkHeader:SetJustifyH("LEFT")

  local well = makeWell(p)
  well:SetPoint("TOPLEFT", 0, -62)
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
        r.ilvl and format("  |cff%s%d|r", MUTED, r.ilvl) or "",
        reason ~= "" and format("  |cff%s%s|r", MUTED, reason) or ""
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
    frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_10")
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
  tabs[TAB_EXPORT]  = makeTab(TAB_EXPORT, "Export")
  tabs[TAB_IMPORT]  = makeTab(TAB_IMPORT, "Import")
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
function UI.Open(tab, mode)
  if InCombatLockdown() then
    UI.pendingOpen = { tab = tab, mode = mode }
    ns.print("in combat — the window will open when you drop out")
    return
  end
  UI.pendingOpen = nil
  if mode then UI.mode = mode end
  build()
  frame:Show()
  UI.SelectTab(tab)
end

-- mode: "bundle" (default) or "current"
function UI.Show(mode)
  UI.Open(TAB_EXPORT, mode or "bundle")
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
    UI.Open(p.tab, p.mode)
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

-- Blizzard's addon compartment entry, declared by the .toc. This is the second
-- and last global the addon defines.
function _G.WarbandPro_OnAddonCompartmentClick()
  UI.Toggle("bundle")
end
