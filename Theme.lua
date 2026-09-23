-- WarbandPro / Theme.lua
-- One reusable theme for the window chrome: frame ground, tab row, section
-- plaques and the divider under the tabs. Every visual choice lives here as a
-- builder; UI.lua calls the builders and carries no one-off styling of its own.
--
-- The look is Blizzard-native throughout: the only texture named is the
-- client's own WHITE8X8 quad, tinted in code, and every FontString starts from
-- a game font object. No artwork ships and nothing is copied from anywhere.
--
-- UI scale is preserved by construction — every size below is in UI units, so
-- the client's scale multiplies the whole window including this chrome — and
-- the plaque labels keep their game font object rather than a hardcoded file.
-- The tab labels step to 16 but keep the client's own font file, because that
-- is Friz Quadrata on Latin clients and the locale face everywhere else; the
-- points still scale with the window. Selected state is never color-only: the
-- active tab also carries an underline bar, so a player who cannot tell white
-- from gold still knows where they are.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- ── palette ─────────────────────────────────────────────────────────────────
--
-- Hex first, because that is how the brief states them; the triple beside each
-- is what the client actually takes.

Theme.GROUND_HEX = "110A06"                                  -- window ground
Theme.GROUND = { r = 0x11 / 255, g = 0x0A / 255, b = 0x06 / 255 }

Theme.BRONZE_HEX = "9C7A4A"                                  -- thin frame border
Theme.BRONZE = { r = 0x9C / 255, g = 0x7A / 255, b = 0x4A / 255 }

Theme.GOLD = { r = 1, g = 0.82, b = 0 }                       -- inactive tabs, divider
Theme.PLAQUE_TEXT_HEX = "CDAA7F"                             -- plaque headers
Theme.PLAQUE_TEXT = { r = 0xCD / 255, g = 0xAA / 255, b = 0x7F / 255 }

Theme.PALETTE = {
  normal        = "D7C0A3",   -- plain text at rest
  selected      = "FFFFFF",   -- the value you came for; also the active tab
  body          = "A39D93",   -- secondary copy
  nonInteractive = "947C66",  -- chrome that is neither value nor tone
  disabled      = "808080",   -- standard client gray for what cannot be used
}

Theme.TAB_SIZE = 16                -- tab label points, Friz Quadrata
Theme.TAB_FONT = "Fonts\\FRIZQT__.TTF"

-- ── frame ───────────────────────────────────────────────────────────────────

-- Lay the dark ground and the thin bronze border over the frame. Idempotent:
-- a second call re-tints rather than stacking, so build() can call it freely.
function Theme.ApplyFrame(frame)
  if not frame or not frame.CreateTexture then return nil end
  local g, b = Theme.GROUND, Theme.BRONZE
  if frame.ThemeChrome then
    frame.ThemeChrome.ground:SetVertexColor(g.r, g.g, g.b, 1)
    for _, edge in ipairs(frame.ThemeChrome.edges) do
      edge:SetVertexColor(b.r, b.g, b.b, 1)
    end
    return frame.ThemeChrome
  end
  local chrome = { edges = {} }
  frame.ThemeChrome = chrome
  local ground = frame:CreateTexture(nil, "BACKGROUND")
  ground:SetTexture("Interface\\Buttons\\WHITE8X8")
  ground:SetVertexColor(g.r, g.g, g.b, 1)
  ground:SetAllPoints(frame)
  chrome.ground = ground
  local function edge(height, width, point, x, y)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(b.r, b.g, b.b, 1)
    if height then t:SetHeight(height) end
    if width then t:SetWidth(width) end
    if point == "TOP" or point == "BOTTOM" then
      t:SetPoint(point .. "LEFT", frame, point .. "LEFT", 0, y or 0)
      t:SetPoint(point .. "RIGHT", frame, point .. "RIGHT", 0, y or 0)
    else
      t:SetPoint("TOP" .. point, frame, "TOP" .. point, x or 0, 0)
      t:SetPoint("BOTTOM" .. point, frame, "BOTTOM" .. point, x or 0, 0)
    end
    chrome.edges[#chrome.edges + 1] = t
    return t
  end
  edge(1, nil, "TOP", 0, 0)
  edge(1, nil, "BOTTOM", 0, 0)
  edge(nil, 1, "LEFT", 0, 0)
  edge(nil, 1, "RIGHT", 0, 0)
  return chrome
end

-- ── tabs ────────────────────────────────────────────────────────────────────
--
-- The tabs keep their PanelTabButtonTemplate birth — the click sound, the
-- OnClick into UI.SelectTab, the PanelTemplates_SetNumTabs/SetTab selection
-- model — and lose only the boxes: every static box texture is hidden and the
-- label is restyled as plain serif text. RefreshTabs runs after each
-- PanelTemplates_SetTab because selecting re-shows the box textures; hiding
-- them again there is what keeps behavior and look from drifting apart. The
-- hover highlight is deliberately left alone: it is transient native feedback,
-- not a box the tab wears at rest.

local BOX_KEYS = {
  "Left", "Middle", "Right",
  "LeftDisabled", "MiddleDisabled", "RightDisabled",
  "ActiveLeft", "ActiveMiddle", "ActiveRight",
}

function Theme.HideTabBoxes(tab)
  if not tab then return end
  for _, key in ipairs(BOX_KEYS) do
    local tex = tab[key]
    if tex and tex.Hide then tex:Hide() end
  end
end

function Theme.SizeTab(tab, padding)
  if not tab then return end
  if PanelTemplates_TabResize then
    PanelTemplates_TabResize(tab, padding or 0)
  end
end

-- Plain-text restyle for one tab: 16px serif, 1px black shadow, auto width,
-- a native 1px press nudge, an underline bar reserved for the active tab, and
-- the inactive gold as the resting color (RefreshTabs corrects the selected
-- one once the tab row knows which that is).
function Theme.StyleTab(tab)
  if not tab then return end
  local fs
  if tab.GetFontString then fs = tab:GetFontString() end
  if fs then
    -- Keep the client's own font file and only step the size: on Latin
    -- clients that file already is Friz Quadrata, and on a client whose
    -- locale swapped it a hardcoded FRIZQT__.TTF would print tofu. TAB_FONT
    -- is the fallback for a tab with no font yet, not the answer.
    if fs.SetFont and fs.GetFont then
      local path, _, flags = fs:GetFont()
      fs:SetFont(path or Theme.TAB_FONT, Theme.TAB_SIZE, flags or "")
    end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    if fs.SetTextColor then fs:SetTextColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b) end
  end
  if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, -1) end
  if not tab.ThemeUnderline and tab.CreateTexture then
    local u = tab:CreateTexture(nil, "OVERLAY")
    u:SetTexture("Interface\\Buttons\\WHITE8X8")
    u:SetVertexColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b, 1)
    u:SetHeight(1)
    u:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 4, 1)
    u:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 1)
    u:Hide()
    tab.ThemeUnderline = u
  end
  Theme.HideTabBoxes(tab)
  Theme.SizeTab(tab, 0)
end

-- Repaint the row after PanelTemplates_SetTab: boxes back off, active tab
-- white with its underline bar, the rest gold. The bar is the non-color half
-- of the selected state.
function Theme.RefreshTabs(tabs, selected)
  if not tabs then return end
  for i, tab in ipairs(tabs) do
    if tab then
      Theme.HideTabBoxes(tab)
      local fs
      if tab.GetFontString then fs = tab:GetFontString() end
      if fs and fs.SetTextColor then
        if i == selected then
          fs:SetTextColor(1, 1, 1)
        else
          fs:SetTextColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b)
        end
      end
      if tab.ThemeUnderline and tab.ThemeUnderline.Show and tab.ThemeUnderline.Hide then
        if i == selected then
          tab.ThemeUnderline:Show()
        else
          tab.ThemeUnderline:Hide()
        end
      end
    end
  end
end

-- ── divider ─────────────────────────────────────────────────────────────────
--
-- The thin gold rule with a center ornament that sits under the tab row. The
-- ornament is a diamond — a client quad rotated square — with a ground-colored
-- center, so it reads as a ring rather than a blob. SetRotation is guarded:
-- a client without it gets the square, which still reads as an ornament.

function Theme.MakeDivider(parent)
  local d = CreateFrame("Frame", nil, parent)
  if not d then return nil end
  d:SetHeight(9)
  local gold = Theme.GOLD
  local left = d:CreateTexture(nil, "ARTWORK")
  left:SetTexture("Interface\\Buttons\\WHITE8X8")
  left:SetVertexColor(gold.r, gold.g, gold.b, 0.75)
  left:SetHeight(1)
  left:SetPoint("LEFT", d, "LEFT", 0, 0)
  left:SetPoint("RIGHT", d, "CENTER", -9, 0)
  local right = d:CreateTexture(nil, "ARTWORK")
  right:SetTexture("Interface\\Buttons\\WHITE8X8")
  right:SetVertexColor(gold.r, gold.g, gold.b, 0.75)
  right:SetHeight(1)
  right:SetPoint("LEFT", d, "CENTER", 9, 0)
  right:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  local diamond = d:CreateTexture(nil, "OVERLAY")
  diamond:SetTexture("Interface\\Buttons\\WHITE8X8")
  diamond:SetVertexColor(gold.r, gold.g, gold.b, 1)
  diamond:SetSize(7, 7)
  diamond:SetPoint("CENTER", d, "CENTER", 0, 0)
  if diamond.SetRotation then diamond:SetRotation(math.pi / 4) end
  local core = d:CreateTexture(nil, "OVERLAY")
  core:SetTexture("Interface\\Buttons\\WHITE8X8")
  core:SetVertexColor(Theme.GROUND.r, Theme.GROUND.g, Theme.GROUND.b, 1)
  core:SetSize(3, 3)
  core:SetPoint("CENTER", d, "CENTER", 0, 0)
  if core.SetRotation then core:SetRotation(math.pi / 4) end
  d.ThemeSpans = { left = left, right = right }
  return d
end

-- ── plaque ──────────────────────────────────────────────────────────────────
--
-- Section headers: centered #CDAA7F serif on an inset dark plaque with angled
-- end caps (two client quads rotated square, the same diamond idiom as the
-- divider's ornament). The label keeps a game font object so it follows the
-- player's font settings; only the tint is ours. Exposed for the section
-- headers; the frame and tab row do not use it.

function Theme.MakePlaque(parent, text, width)
  local f = CreateFrame("Frame", nil, parent)
  if not f then return nil end
  f:SetSize(width or 220, 18)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0, 0, 0, 0.55)
  bg:SetAllPoints(f)
  local bronze = Theme.BRONZE
  local top = f:CreateTexture(nil, "BORDER")
  top:SetTexture("Interface\\Buttons\\WHITE8X8")
  top:SetVertexColor(bronze.r, bronze.g, bronze.b, 0.8)
  top:SetHeight(1)
  top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  local bottom = f:CreateTexture(nil, "BORDER")
  bottom:SetTexture("Interface\\Buttons\\WHITE8X8")
  bottom:SetVertexColor(bronze.r, bronze.g, bronze.b, 0.8)
  bottom:SetHeight(1)
  bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local function cap(point, x)
    local c = f:CreateTexture(nil, "ARTWORK")
    c:SetTexture("Interface\\Buttons\\WHITE8X8")
    c:SetVertexColor(bronze.r, bronze.g, bronze.b, 1)
    c:SetSize(8, 8)
    c:SetPoint(point, f, point, x, 0)
    if c.SetRotation then c:SetRotation(math.pi / 4) end
    return c
  end
  cap("LEFT", 4)
  cap("RIGHT", -4)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", f, "CENTER", 0, 0)
  label:SetText(text or "")
  label:SetTextColor(Theme.PLAQUE_TEXT.r, Theme.PLAQUE_TEXT.g, Theme.PLAQUE_TEXT.b)
  label:SetShadowColor(0, 0, 0, 1)
  label:SetShadowOffset(1, -1)
  f.Label = label
  return f
end

function Theme.SetPlaqueText(plaque, text)
  if plaque and plaque.Label and plaque.Label.SetText then
    plaque.Label:SetText(text or "")
  end
end

-- ── vault slots ─────────────────────────────────────────────────────────────
--
-- Small vault-slot buttons in the GreatVault.lua pattern: dark ground, thin
-- bronze border, centered n/m text. Locked and unlocked differ twice — dim
-- gray at reduced alpha when locked, full-bright white when unlocked — never
-- color alone.

function Theme.MakeSlot(parent, width)
  local s = CreateFrame("Frame", nil, parent)
  if not s then return nil end
  s:SetSize(width or 118, 20)
  local bg = s:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0, 0, 0, 0.55)
  bg:SetAllPoints(s)
  local bronze = Theme.BRONZE
  local function edge(point, w, h, x, y)
    local t = s:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(bronze.r, bronze.g, bronze.b, 0.8)
    t:SetSize(w, h)
    t:SetPoint(point, s, point, x or 0, y or 0)
    return t
  end
  edge("TOP", 0, 1, 0, 0)
  edge("BOTTOM", 0, 1, 0, 0)
  edge("LEFT", 1, 0, 0, 0)
  edge("RIGHT", 1, 0, 0, 0)
  local label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", s, "CENTER", 0, 0)
  s.SlotText = label
  return s
end

function Theme.SetSlot(s, text, unlocked)
  if not (s and s.SlotText and s.SlotText.SetText) then return end
  s.SlotText:SetText(text or "")
  if unlocked then
    s.SlotText:SetTextColor(1, 1, 1)
    if s.SetAlpha then s:SetAlpha(1) end
  else
    s.SlotText:SetTextColor(0.5, 0.5, 0.5)
    if s.SetAlpha then s:SetAlpha(0.6) end
  end
end
