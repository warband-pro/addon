-- WarbandPro / Theme.lua
-- One reusable theme for the window: frame ground and edge, title band, tab
-- row, section plaques, wells, buttons, checkboxes, list rows, scrollbars and
-- the paste field. Every visual choice lives here as a builder; UI.lua calls
-- the builders and carries no one-off styling of its own.
--
-- The look is Plumber's — near-black warm ground, thin bronze hairlines,
-- text-only tabs, flat buttons that light up under the mouse — built from
-- nothing but the client's own WHITE8X8 quad tinted in code, its stock check
-- mark, and its game font objects. No artwork ships and nothing is copied
-- from anywhere; the MIT/GPL boundary is that only the idea crossed.
--
-- **The templates stay for their behavior and lose their paint.** The window
-- is still a ButtonFrameTemplate (title, close button, Esc, the inset every
-- panel anchors to), the tabs are still PanelTabButtonTemplate (click sound,
-- the PanelTemplates_* selection model), the paste field is still an
-- InputBoxTemplate. Each keeps every script and parentKey it was born with;
-- the skin hides the box art and draws its own, so a template rename costs
-- the paint and never the widget. Every hide below is guarded for the same
-- reason: a parentKey that moved is a texture we do not hide, not an error.
--
-- **Fonts are Font objects, not SetFont calls.** A Button re-applies its
-- state font object to its label on every Enable/Disable, and the client's
-- own PanelTemplates_SelectTab disables the selected tab — so a size set
-- straight on the FontString lasts until the first click. Theme.Font builds
-- named Font objects once, copied from a game font so the locale face comes
-- with them, and hands those to the buttons; the state machine then re-applies
-- OUR font rather than the template's.
--
-- **Hairlines are one physical pixel.** A 1px texture at a UI scale below one
-- is drawn at a fraction of a pixel and can vanish or double; PixelUtil, when
-- the client has it, snaps the size to a whole pixel with a floor of one.
-- Without it the line is 1 UI unit, which is what it was.
--
-- UI scale is preserved by construction — every size below is in UI units, so
-- the client's scale multiplies the whole window including this chrome. State
-- is never color alone: the active tab carries an underline bar, a selected
-- row carries a bar and a ground, a locked vault slot is dim as well as grey.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

-- ── palette ─────────────────────────────────────────────────────────────────
--
-- Hex first, because that is how the brief states them; the triple beside each
-- is what the client actually takes.

local function rgb(hex)
  return {
    r = tonumber(hex:sub(1, 2), 16) / 255,
    g = tonumber(hex:sub(3, 4), 16) / 255,
    b = tonumber(hex:sub(5, 6), 16) / 255,
  }
end

Theme.GROUND_HEX = "110A06"                                  -- window ground
Theme.GROUND = rgb(Theme.GROUND_HEX)

Theme.BRONZE_HEX = "9C7A4A"                                  -- hairlines, bars
Theme.BRONZE = rgb(Theme.BRONZE_HEX)

Theme.GOLD = { r = 1, g = 0.82, b = 0 }                       -- title, idle tabs, divider
Theme.PLAQUE_TEXT_HEX = "CDAA7F"                             -- plaque headers
Theme.PLAQUE_TEXT = rgb(Theme.PLAQUE_TEXT_HEX)

Theme.WHITE = { r = 1, g = 1, b = 1 }
Theme.BLACK = { r = 0, g = 0, b = 0 }

-- The inks, by role. `PALETTE` is the hex form for inline colour codes and
-- `INK` the triple form for SetTextColor; they are the same five colours.
Theme.PALETTE = {
  normal         = "D7C0A3",   -- plain text at rest
  selected       = "FFFFFF",   -- the value you came for; also the active tab
  body           = "A39D93",   -- secondary copy
  nonInteractive = "947C66",   -- chrome that is neither value nor tone
  disabled       = "808080",   -- standard client gray for what cannot be used
}
Theme.INK = {}
for key, hex in pairs(Theme.PALETTE) do Theme.INK[key] = rgb(hex) end

Theme.TAB_SIZE = 16                -- tab label points
Theme.TITLE_SIZE = 18              -- window title points
Theme.TAB_FONT = "Fonts\\FRIZQT__.TTF"

-- The window's header: the title band, the tab row under it, the divider
-- under that. UI.lua anchors the inset below these, so they are stated once.
Theme.TITLE_H = 30
Theme.TAB_ROW_Y = -28              -- where the 32px tab buttons hang from
Theme.DIVIDER_Y = -60
Theme.INSET_Y = -68

-- ── primitives ──────────────────────────────────────────────────────────────

--- One physical pixel, or one UI unit on a client without PixelUtil.
local function hairline(tex, axis)
  local ok = PixelUtil and PixelUtil.SetHeight and PixelUtil.SetWidth
  if axis == "h" then
    if ok then PixelUtil.SetHeight(tex, 1, 1) else tex:SetHeight(1) end
  else
    if ok then PixelUtil.SetWidth(tex, 1, 1) else tex:SetWidth(1) end
  end
end

--- A tinted quad on `parent`, in `layer`.
local function quad(parent, layer, c, a, sublevel)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
  t:SetTexture(WHITE8X8)
  t:SetVertexColor(c.r, c.g, c.b, a == nil and 1 or a)
  return t
end
Theme.Quad = quad

--- Four hairlines round `frame`, inset by `inset`. Returns the table so a
--- caller can re-tint them (Theme.SetSelected does).
local function edges(frame, c, a, layer, inset)
  local i = inset or 0
  local e = {}
  local function one(side, axis)
    local t = quad(frame, layer or "BORDER", c, a)
    hairline(t, axis)
    if axis == "h" then
      local y = side == "TOP" and -i or i
      t:SetPoint(side .. "LEFT", frame, side .. "LEFT", i, y)
      t:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -i, y)
    else
      local x = side == "LEFT" and i or -i
      t:SetPoint("TOP" .. side, frame, "TOP" .. side, x, -i)
      t:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, x, i)
    end
    e[#e + 1] = t
    return t
  end
  one("TOP", "h")
  one("BOTTOM", "h")
  one("LEFT", "w")
  one("RIGHT", "w")
  return e
end
Theme.Edges = edges

local function tintAll(list, c, a)
  for _, t in ipairs(list) do t:SetVertexColor(c.r, c.g, c.b, a) end
end

--- Hide a template region whichever kind it is. Guarded: a parentKey that is
--- not there is a region we do not hide, never an error.
local function hideRegion(r)
  if not r then return end
  if r.SetAlpha then r:SetAlpha(0) end
  if r.Hide then r:Hide() end
end
Theme.HideRegion = hideRegion

--- Re-tint a FontString to one of the palette inks.
function Theme.Ink(fs, key)
  local c = fs and Theme.INK[key or "normal"]
  if c and fs.SetTextColor then fs:SetTextColor(c.r, c.g, c.b) end
  return fs
end

--- The client's own click, so a themed button sounds like a stock one.
function Theme.ClickSound(checked)
  if not (PlaySound and SOUNDKIT) then return end
  if checked == false then
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  else
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end
end

-- ── fonts ───────────────────────────────────────────────────────────────────
--
-- Named Font objects, built once and copied from a game font so the file is
-- the client's own — Friz Quadrata on Latin clients, the locale face
-- everywhere else. Only the size and the tint are ours. TAB_FONT is the
-- fallback for a copy that came back with no file, not the answer.

local FONT_SPEC = {
  title          = { base = "GameFontNormal", size = Theme.TITLE_SIZE, ink = Theme.GOLD, shadow = true },
  tab            = { base = "GameFontNormal", size = Theme.TAB_SIZE, ink = Theme.GOLD, shadow = true },
  tabActive      = { base = "GameFontNormal", size = Theme.TAB_SIZE, ink = Theme.WHITE, shadow = true },
  tabHover       = { base = "GameFontNormal", size = Theme.TAB_SIZE, ink = Theme.WHITE, shadow = true },
  button         = { base = "GameFontHighlightSmall", ink = Theme.INK.normal },
  buttonHover    = { base = "GameFontHighlightSmall", ink = Theme.WHITE },
  buttonSelected = { base = "GameFontHighlightSmall", ink = Theme.WHITE },
  buttonDisabled = { base = "GameFontHighlightSmall", ink = Theme.INK.disabled },
  heading        = { base = "GameFontNormal", ink = Theme.PLAQUE_TEXT, shadow = true },
  section        = { base = "GameFontNormalSmall", ink = Theme.INK.nonInteractive },
}
local fonts = {}

--- A Font object by role, or nil on a client without CreateFont. Callers
--- fall back to the template name they would have used anyway.
function Theme.Font(key)
  if fonts[key] then return fonts[key] end
  local spec = FONT_SPEC[key]
  if not spec or type(CreateFont) ~= "function" then return nil end
  local name = "WarbandProFont_" .. key
  local f = _G[name] or ns.safe(CreateFont, name)
  if not f then return nil end
  ns.safe(f.CopyFontObject, f, spec.base)
  if spec.size and f.GetFont and f.SetFont then
    local path, _, flags = f:GetFont()
    f:SetFont(path or Theme.TAB_FONT, spec.size, flags or "")
  end
  f:SetTextColor(spec.ink.r, spec.ink.g, spec.ink.b)
  if spec.shadow then
    f:SetShadowColor(0, 0, 0, 1)
    f:SetShadowOffset(1, -1)
  else
    f:SetShadowColor(0, 0, 0, 0)
  end
  fonts[key] = f
  return f
end

--- The Font object, or the template name to use in its place.
local function fontOr(key, fallback)
  return Theme.Font(key) or fallback
end

-- ── frame ───────────────────────────────────────────────────────────────────

--- Lay the dark ground and the thin bronze border over the frame. Idempotent:
--- a second call re-tints rather than stacking, so build() can call it freely.
function Theme.ApplyFrame(frame)
  if not frame or not frame.CreateTexture then return nil end
  local g, b = Theme.GROUND, Theme.BRONZE
  if frame.ThemeChrome then
    frame.ThemeChrome.ground:SetVertexColor(g.r, g.g, g.b, 1)
    tintAll(frame.ThemeChrome.edges, b, 1)
    return frame.ThemeChrome
  end
  local chrome = {}
  frame.ThemeChrome = chrome
  -- One sublevel above the template's own Bg, so on a client whose
  -- parentKey for that texture has moved and cannot be hidden, ours still
  -- draws over it rather than under.
  local ground = quad(frame, "BACKGROUND", g, 1, 1)
  ground:SetAllPoints(frame)
  chrome.ground = ground
  chrome.edges = edges(frame, b, 1, "BORDER")
  return chrome
end

--- The close X: two hairlines crossed, in the resting ink, with a white pair
--- in the HIGHLIGHT layer so the client draws the hover for us. The button
--- keeps its template scripts (the click, the close sound); only its atlas
--- art goes.
local function skinClose(btn, frame)
  if not btn or btn.ThemeSkinned then return btn end
  btn.ThemeSkinned = true
  for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
    local t = btn[get] and btn[get](btn)
    if t and t.SetAlpha then t:SetAlpha(0) end
  end
  btn:SetSize(22, 22)
  btn:ClearAllPoints()
  btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -4)
  local function cross(layer, c, a)
    for _, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
      local t = quad(btn, layer, c, a)
      t:SetSize(13, 2)
      t:SetPoint("CENTER", btn, "CENTER", 0, 0)
      if t.SetRotation then t:SetRotation(angle) end
    end
  end
  cross("ARTWORK", Theme.INK.normal, 1)
  cross("HIGHLIGHT", Theme.WHITE, 1)
  return btn
end

--- Take a ButtonFrameTemplate window and leave only its behavior: the nine-
--- slice, the parchment, the portrait and the stock title all go, and the
--- title band is redrawn as Plumber draws one — icon, title in gold serif,
--- close X at the right, hairline under. Idempotent. Returns the chrome table
--- with `title` (a FontString) so the caller can retitle.
function Theme.SkinWindow(frame, title, icon)
  if not frame then return nil end
  local chrome = Theme.ApplyFrame(frame)
  if not chrome then return nil end
  if chrome.title then
    chrome.title:SetText(title or "")
    return chrome
  end
  -- PortraitFrameTemplate parentKeys across the last several expansions. A
  -- name that is not there is skipped, never assumed.
  hideRegion(frame.Bg)
  hideRegion(frame.NineSlice)
  hideRegion(frame.TopTileStreaks)
  hideRegion(frame.TitleBg)
  hideRegion(frame.TitleText)
  hideRegion(frame.TitleContainer)
  hideRegion(frame.PortraitContainer)
  hideRegion(frame.PortraitOverlay)
  hideRegion(frame.portrait)
  if frame.Inset then
    hideRegion(frame.Inset.Bg)
    hideRegion(frame.Inset.NineSlice)
  end
  skinClose(frame.CloseButton, frame)

  local x = 14
  if icon then
    local ic = frame:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(icon)
    ic:SetSize(16, 16)
    ic:SetPoint("LEFT", frame, "TOPLEFT", 12, -Theme.TITLE_H / 2)
    -- Stock icon art carries a drawn-on border; at 16px it is most of what
    -- you would see.
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    chrome.icon = ic
    x = 34
  end
  local t = frame:CreateFontString(nil, "OVERLAY")
  t:SetFontObject(fontOr("title", "GameFontNormal"))
  if not Theme.Font("title") then t:SetTextColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b) end
  t:SetPoint("LEFT", frame, "TOPLEFT", x, -Theme.TITLE_H / 2)
  t:SetPoint("RIGHT", frame, "TOPRIGHT", -34, -Theme.TITLE_H / 2)
  t:SetJustifyH("LEFT")
  t:SetWordWrap(false)
  t:SetText(title or "")
  chrome.title = t

  local rule = quad(frame, "BORDER", Theme.BRONZE, 0.35)
  hairline(rule, "h")
  rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -Theme.TITLE_H)
  rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -Theme.TITLE_H)
  chrome.titleRule = rule
  return chrome
end

--- A bronze hairline, horizontal by default, vertical with `vertical`.
--- Anchoring is the caller's; the thickness is the theme's.
function Theme.MakeRule(parent, vertical, alpha)
  if not parent or not parent.CreateTexture then return nil end
  local t = quad(parent, "ARTWORK", Theme.BRONZE, alpha or 0.35)
  hairline(t, vertical and "w" or "h")
  return t
end

-- ── wells ───────────────────────────────────────────────────────────────────
--
-- The recessed area a scroll frame or a list sits in: a shade darker than the
-- ground with a hairline round it. Replaces InsetFrameTemplate, whose nine-
-- slice is the parchment-and-gold the rest of this window no longer wears.

function Theme.MakeWell(parent)
  local f = CreateFrame("Frame", nil, parent)
  if not f then return nil end
  local bg = quad(f, "BACKGROUND", Theme.BLACK, 0.35)
  bg:SetAllPoints(f)
  f.ThemeBg = bg
  f.ThemeEdges = edges(f, Theme.BRONZE, 0.45, "BORDER")
  return f
end

-- ── buttons ─────────────────────────────────────────────────────────────────
--
-- Flat: a dark ground, a bronze hairline, the label in the resting ink. The
-- mouse brightens the label and lays a faint white sheet over it (HIGHLIGHT
-- layer, so the client draws and clears it). Disabled dims the ground and the
-- edges and greys the label — that is "cannot"; **selected is "you are
-- here"** and looks the opposite way, bright edges over a bronze ground with
-- a white label, because a control the panel is already on is not a control
-- that is broken. The export's slice row and the options navigation use it.

local function refreshButton(btn)
  local s = btn.ThemeButton
  if not s then return end
  local enabled = not btn.IsEnabled or btn:IsEnabled()
  if s.selected then
    s.bg:SetVertexColor(Theme.BRONZE.r, Theme.BRONZE.g, Theme.BRONZE.b, 0.28)
    tintAll(s.edges, Theme.BRONZE, 1)
    btn:SetNormalFontObject(fontOr("buttonSelected", "GameFontHighlightSmall"))
  elseif enabled then
    s.bg:SetVertexColor(0, 0, 0, 0.45)
    tintAll(s.edges, Theme.BRONZE, 0.7)
    btn:SetNormalFontObject(fontOr("button", "GameFontNormalSmall"))
  else
    s.bg:SetVertexColor(0, 0, 0, 0.25)
    tintAll(s.edges, Theme.BRONZE, 0.3)
  end
end

--- Skin an existing Button — one born from a template this theme cannot
--- replace, such as the secure disenchant button. Idempotent.
function Theme.SkinButton(btn)
  if not btn or btn.ThemeButton then return btn end
  local s = {}
  btn.ThemeButton = s
  s.bg = quad(btn, "BACKGROUND", Theme.BLACK, 0.45)
  s.bg:SetAllPoints(btn)
  s.edges = edges(btn, Theme.BRONZE, 0.7, "BORDER")
  s.hl = quad(btn, "HIGHLIGHT", Theme.WHITE, 0.08)
  s.hl:SetAllPoints(btn)
  btn:SetNormalFontObject(fontOr("button", "GameFontNormalSmall"))
  btn:SetHighlightFontObject(fontOr("buttonHover", "GameFontHighlightSmall"))
  btn:SetDisabledFontObject(fontOr("buttonDisabled", "GameFontDisableSmall"))
  if btn.SetPushedTextOffset then btn:SetPushedTextOffset(0, -1) end
  btn:SetScript("OnEnable", refreshButton)
  btn:SetScript("OnDisable", refreshButton)
  -- On the press rather than the click: OnClick is the caller's and a
  -- SetScript there would replace the sound.
  btn:SetScript("OnMouseDown", function() Theme.ClickSound() end)
  refreshButton(btn)
  return btn
end

function Theme.MakeButton(parent, text, w, h, name)
  local b = CreateFrame("Button", name, parent)
  if not b then return nil end
  Theme.SkinButton(b)
  b:SetSize(w or 96, h or 20)
  b:SetText(text or "")
  return b
end

--- "You are here" for a themed button. Stays enabled — a click on the place
--- you already are is a no-op the caller owns — and reads the bright way.
function Theme.SetSelected(btn, on)
  local s = btn and btn.ThemeButton
  if not s then
    -- A stock button: the client's own idiom for the same state.
    if btn and btn.SetEnabled then btn:SetEnabled(not on) end
    return
  end
  s.selected = on and true or false
  refreshButton(btn)
end

-- ── checkboxes ──────────────────────────────────────────────────────────────
--
-- A square well with the client's own check mark in it. The mark is the one
-- texture the stock template draws that survives on this ground; the box
-- round it is ours. The label the caller hangs beside it becomes part of the
-- click through Theme.LabelCheck, because a checkbox whose word is not a
-- target is a 20px target.

function Theme.MakeCheck(parent, size)
  local c = CreateFrame("CheckButton", nil, parent)
  if not c then return nil end
  local n = size or 20
  c:SetSize(n, n)
  local bg = quad(c, "BACKGROUND", Theme.BLACK, 0.45)
  bg:SetPoint("TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", -2, 2)
  c.ThemeEdges = edges(c, Theme.BRONZE, 0.8, "BORDER", 2)
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  c:SetHighlightTexture(WHITE8X8)
  local hl = c:GetHighlightTexture()
  if hl then
    hl:SetVertexColor(1, 1, 1, 0.1)
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
  end
  return c
end

--- Make the label part of the checkbox's hit area, and paint it.
function Theme.LabelCheck(check, fs, ink)
  if not (check and fs) then return end
  Theme.Ink(fs, ink or "normal")
  local w = fs.GetStringWidth and fs:GetStringWidth() or 0
  if check.SetHitRectInsets and w > 0 then
    check:SetHitRectInsets(0, -(w + 8), 0, 0)
  end
end

-- ── list rows ───────────────────────────────────────────────────────────────
--
-- The sidebar and the options navigation: a full-width row that lights under
-- the mouse and, when selected, carries a bronze ground and a bar at its left
-- edge. The text is the caller's — a class-coloured name has to stay its
-- colour when the row is selected — so selection changes the ground and the
-- bar and nothing about the words.

function Theme.MakeListRow(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  if not b then return nil end
  b:SetSize(w or 180, h or 20)
  b.selBg = quad(b, "BACKGROUND", Theme.BRONZE, 0.16)
  b.selBg:SetAllPoints(b)
  b.selBg:Hide()
  b.bar = quad(b, "ARTWORK", Theme.BRONZE, 1)
  b.bar:SetSize(2, (h or 20) - 6)
  b.bar:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.bar:Hide()
  b.hl = quad(b, "HIGHLIGHT", Theme.WHITE, 0.06)
  b.hl:SetAllPoints(b)
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.name:SetPoint("LEFT", b, "LEFT", 10, 0)
  b.name:SetJustifyH("LEFT")
  b.name:SetWordWrap(false)
  b:SetScript("OnMouseDown", function() Theme.ClickSound() end)
  return b
end

function Theme.SetRowSelected(b, on)
  if not (b and b.selBg and b.bar) then return end
  b.selBg:SetShown(on and true or false)
  b.bar:SetShown(on and true or false)
end

--- A section label over its own hairline: the sidebar's "Warband" and
--- "Account", the options' category names.
function Theme.MakeSection(parent, text, w)
  local f = CreateFrame("Frame", nil, parent)
  if not f then return nil end
  f:SetSize(w or 180, 18)
  local label = f:CreateFontString(nil, "OVERLAY")
  label:SetFontObject(fontOr("section", "GameFontNormalSmall"))
  if not Theme.Font("section") then Theme.Ink(label, "nonInteractive") end
  label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
  label:SetText(text or "")
  local rule = quad(f, "ARTWORK", Theme.BRONZE, 0.35)
  hairline(rule, "h")
  rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
  rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 1)
  f.Label = label
  f.Rule = rule
  return f
end

-- ── scroll frames and the paste field ───────────────────────────────────────
--
-- UIPanelScrollFrameTemplate's bar is two arrow buttons and a knob; on this
-- ground it is a bronze thumb on a faint track, and the arrows are still
-- there to press — they are transparent, not gone, so the template's own
-- range handling keeps working. The paste field keeps InputBoxTemplate's
-- focus, paste and cursor behavior and loses its three box textures.

function Theme.SkinScroll(scroll)
  local bar = scroll and scroll.ScrollBar
  if not bar or bar.ThemeSkinned then return end
  bar.ThemeSkinned = true
  for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local b = bar[key]
    if b and b.SetAlpha then b:SetAlpha(0) end
  end
  local track = quad(bar, "BACKGROUND", Theme.WHITE, 0.05)
  track:SetWidth(6)
  track:SetPoint("TOP", bar, "TOP", 0, 0)
  track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
  local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
  if thumb then
    thumb:SetTexture(WHITE8X8)
    thumb:SetVertexColor(Theme.BRONZE.r, Theme.BRONZE.g, Theme.BRONZE.b, 0.8)
    thumb:SetSize(6, 28)
  end
end

function Theme.SkinInput(eb)
  if not eb or eb.ThemeSkinned then return eb end
  eb.ThemeSkinned = true
  hideRegion(eb.Left)
  hideRegion(eb.Middle)
  hideRegion(eb.Right)
  local bg = quad(eb, "BACKGROUND", Theme.BLACK, 0.45)
  bg:SetAllPoints(eb)
  local e = edges(eb, Theme.BRONZE, 0.55, "BORDER")
  eb.ThemeEdges = e
  if eb.SetTextInsets then eb:SetTextInsets(8, 8, 0, 0) end
  -- The focused field is the one with the bright edge, which is the whole of
  -- how a paste box says "type here" without a caret the eye can find.
  eb:HookScript("OnEditFocusGained", function() tintAll(e, Theme.BRONZE, 1) end)
  eb:HookScript("OnEditFocusLost", function() tintAll(e, Theme.BRONZE, 0.55) end)
  return eb
end

-- ── tabs ────────────────────────────────────────────────────────────────────
--
-- The tabs keep their PanelTabButtonTemplate birth — the click sound, the
-- OnClick into UI.SelectTab, the PanelTemplates_SetNumTabs/SetTab selection
-- model — and lose only the boxes: every box texture the template has shipped
-- under, across its renames, is hidden, and the label is restyled through
-- Font objects so the selection model's own Enable/Disable re-applies ours.
-- RefreshTabs runs after each PanelTemplates_SetTab because selecting
-- re-shows the boxes and resets the disabled font; putting both back there is
-- what keeps behavior and look from drifting apart.

local BOX_KEYS = {
  "Left", "Middle", "Right",
  "LeftDisabled", "MiddleDisabled", "RightDisabled",
  "LeftActive", "MiddleActive", "RightActive",
  "ActiveLeft", "ActiveMiddle", "ActiveRight",
  "LeftHighlight", "MiddleHighlight", "RightHighlight",
}

function Theme.HideTabBoxes(tab)
  if not tab then return end
  for _, key in ipairs(BOX_KEYS) do hideRegion(tab[key]) end
end

function Theme.SizeTab(tab, padding)
  if not tab then return end
  if PanelTemplates_TabResize then
    PanelTemplates_TabResize(tab, padding or 0)
  end
end

--- Plain-text restyle for one tab: the gold serif at rest, white under the
--- mouse and when active, a native 1px press nudge, and an underline bar
--- reserved for the active tab (RefreshTabs shows it once the row knows
--- which that is). The bar hangs off the label rather than the button, so it
--- is as wide as the word and not as wide as the hidden box.
function Theme.StyleTab(tab)
  if not tab then return end
  tab:SetNormalFontObject(fontOr("tab", "GameFontNormalSmall"))
  tab:SetHighlightFontObject(fontOr("tabHover", "GameFontHighlightSmall"))
  tab:SetDisabledFontObject(fontOr("tabActive", "GameFontHighlightSmall"))
  local fs
  if tab.GetFontString then fs = tab:GetFontString() end
  if fs and not Theme.Font("tab") then
    -- No Font objects on this client: size the label directly and accept
    -- that a select resets it. The tab still works.
    if fs.SetFont and fs.GetFont then
      local path, _, flags = fs:GetFont()
      fs:SetFont(path or Theme.TAB_FONT, Theme.TAB_SIZE, flags or "")
    end
    if fs.SetTextColor then fs:SetTextColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b) end
  end
  if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, -1) end
  if not tab.ThemeUnderline and tab.CreateTexture then
    local u = quad(tab, "OVERLAY", Theme.GOLD, 1)
    hairline(u, "h")
    local anchor = fs or tab
    u:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    u:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    u:Hide()
    tab.ThemeUnderline = u
  end
  Theme.HideTabBoxes(tab)
  Theme.SizeTab(tab, 0)
end

--- Repaint the row after PanelTemplates_SetTab: boxes back off, our fonts
--- back on (the client's select swaps the disabled font for its own), the
--- underline under the active tab and nowhere else. The bar is the non-color
--- half of the selected state.
function Theme.RefreshTabs(tabs, selected)
  if not tabs then return end
  for i, tab in ipairs(tabs) do
    if tab then
      Theme.HideTabBoxes(tab)
      tab:SetNormalFontObject(fontOr("tab", "GameFontNormalSmall"))
      tab:SetDisabledFontObject(fontOr("tabActive", "GameFontHighlightSmall"))
      local fs
      if tab.GetFontString then fs = tab:GetFontString() end
      if fs and fs.SetTextColor and not Theme.Font("tab") then
        if i == selected then
          fs:SetTextColor(1, 1, 1)
        else
          fs:SetTextColor(Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b)
        end
      end
      if tab.ThemeUnderline then tab.ThemeUnderline:SetShown(i == selected) end
      Theme.SizeTab(tab, 0)
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
  local left = quad(d, "ARTWORK", gold, 0.75)
  hairline(left, "h")
  left:SetPoint("LEFT", d, "LEFT", 0, 0)
  left:SetPoint("RIGHT", d, "CENTER", -9, 0)
  local right = quad(d, "ARTWORK", gold, 0.75)
  hairline(right, "h")
  right:SetPoint("LEFT", d, "CENTER", 9, 0)
  right:SetPoint("RIGHT", d, "RIGHT", 0, 0)
  local diamond = quad(d, "OVERLAY", gold, 1)
  diamond:SetSize(7, 7)
  diamond:SetPoint("CENTER", d, "CENTER", 0, 0)
  if diamond.SetRotation then diamond:SetRotation(math.pi / 4) end
  local core = quad(d, "OVERLAY", Theme.GROUND, 1)
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
-- player's font settings; only the tint is ours.

function Theme.MakePlaque(parent, text, width)
  local f = CreateFrame("Frame", nil, parent)
  if not f then return nil end
  f:SetSize(width or 220, 18)
  local bg = quad(f, "BACKGROUND", Theme.BLACK, 0.55)
  bg:SetAllPoints(f)
  local bronze = Theme.BRONZE
  local top = quad(f, "BORDER", bronze, 0.8)
  hairline(top, "h")
  top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  local bottom = quad(f, "BORDER", bronze, 0.8)
  hairline(bottom, "h")
  bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local function cap(point, x)
    local c = quad(f, "ARTWORK", bronze, 1)
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
  local bg = quad(s, "BACKGROUND", Theme.BLACK, 0.55)
  bg:SetAllPoints(s)
  s.ThemeEdges = edges(s, Theme.BRONZE, 0.8, "BORDER")
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
