# UI — copy pain and import ease

Copying from WoW chat is notoriously awful. This addon lives or dies by how painless we make copy + paste both sides.

## Game side — export panel

### Problem

ChatFrame EditBox truncates at ~2048 chars, linkifies `-` lines, no scroll, selection dies when you move mouse. Long wb1! 4-7KB for 6 chars dies in default chat. You can't `SetClipboard`. Only manual Ctrl-A Ctrl-C works from a focused EditBox.

### What we build (native Blizzard widgets only, no Ace)

Single panel `WarbandProExportFrame`:

- Trigger: AddonCompartment click (`WarbandPro_OnAddonCompartmentClick`) **and** slash `/warband` **and** keybind optional. No minimap button by default (lightweight). Compartment is Blizzard's stated place now — minimap bloats compat.
- Frame: `CreateFrame("Frame", "WarbandProExportFrame", UIParent, "BackdropTemplate")` 520x460, draggable title "Warband.pro — Export Warband", close X, Esc to close (`tinsert(UISpecialFrames, frame:GetName())`).
- Inside:
  - Header row freshness dots summary: "6 chars · freshest 12m ago · Warbank 1h ago (by Vocnar)" — one line readable so before copy you know it's not stale.
  - Middle: ScrollFrame + EditBox (not single-line Input). Important props:
    - `editBox:SetMultiLine(true)` `SetMaxLetters(0)` (0 = no limit, Blizzard caveat but our 7KB under 20KB okay)
    - `editBox:SetAutoFocus(true)` so on show it focuses immediately
    - `editBox:SetFontObject(GameFontHighlightSmall)` mono for copy reliably
    - `editBox:HighlightText()` on OnShow so Ctrl-C alone works, no drag
    - `editBox:SetScript("OnEscapePressed", function() frame:Hide() end)`
    - no `OnTextChanged` loop — we set once per export, user copy only.
  - Bottom: two buttons:
    - `[ Select All ]` does `editBox:HighlightText()` + `editBox:SetFocus()` — 1 click for users who missed auto-highlight
    - `[ Copy Close ]` note: text still needs Ctrl-C. Button just hides frame after after they copied? Actually keep open until Ctrl-C.
  - 3 small helper text lines:
    - "1. Press Ctrl+A then Ctrl+C (auto-selected)"
    - "2. In warband.pro hit Import (i) or Ctrl+V"
    - "3. Esc closes this"
  - Streamer toggle implicit: gold hidden to `•••` only if settings.StreamSafe true — we default show gold but honor toggle later.

Why not `StaticPopupDialogs`? That template's EditBox capped at ~1024 historically and steals focus harsh. Custom frame less taint.

### Handling long strings > 20KB (future if we add recipes)

If len > 20480 we chunk into `wb1.1/3` etc? But v1 we target 4-7KB so not needed. Guard: if > 20KB we show second page "String too long for copy popup >20KB — use slim mode" and offer ` /warband copy current` fallback single-char.

### Automation safety

- If InCombatLockdown() > opening panel blocks: show red bar "cannot export in combat" (secure rule) then queues reopen after combat via `PLAYER_REGEN_ENABLED` one-shot. Fail closed, not error spam.
- No OnUpdate, no ticker scanning while panel open — only static string.

### Manual test proof it's easy

From `docs/QA.md` checklist expanded:

- /warband opens within 2 clicks: Compartment -> click export or slash "/warband"
- Auto-highlighted on open without mouse drag (human just hits Ctrl-C)
- Ctrl-A + Ctrl-C works, pastes into Notepad startswith wb1! exact len reported at bottom.
- Esc closes, second open same behavior.
- Multi-char bundle 6 still in single EditBox scrollable, scrollbar appears but highlight still all.


## Web side — Import simplicity

Goal you said: "just hit Import and maybe grab from your clipboard if not we just pop a box you throw it in". Yes.

### Where it lives

/app Camp page top bar and Settings > Import. Hotkey `i` to open anywhere (like command palette). Existing `Sync.astro` button-only prefetch surface — we mimic button-only pattern no auto-pull.

### Flow

1. User clicks [Import] or hits `i`
2. Modal mounts, tries `navigator.clipboard.readText()` inside click handler (must be user gesture else Permission Denied). If succeeds and text startsWith `wb1!` or `wb0!` length > 10, we auto-fill preview immediately — 0 paste needed!
3. If clipboard empty / permission denied / not wb1! — show big <textarea> auto-focused, placeholder "Paste wb1! string here — press Ctrl+V", paste triggers debounce preview render (~150ms).
4. Preview table live (no confirm yet):
   - header "Warband bundle — 6 chars — exported 12m ago"
   - rows: name · realm · faction dot 🟢<6h 🟡<3d 🔴>3d ⚪never · gold · bag free slots · bank free · warbank age · phials etc derived (same as Tracker Preview in README)
   - warn if bundle older than 3d for > half chars: "half stale — you may want to log alts again later"
5. [Confirm Import] upserts into character_addon_cache D1: per char row keyed by user_id+realm_slug+char_name guid? Use guid if possible for renames. Overwrites last_seen_ms etc but missing chars in bundle NOT deleted (keeps prior).
6. Toast "Imported 6 characters · 2m ago freshened" then Data staleness dots in Camp refresh without reload.
7. Modal closes on Esc, stores imported_at_ms for staleness calculation.

### Clipboard nuance

- Modern Chrome/Edge allow `readText()` only in click context and only over HTTPS — warband.pro is HTTPS so fine. Fallback paste box works on Firefox / Safari where permission more strict.
- Never `readText()` polling, only inside Import click.
- Don't auto-submit — user must still press Confirm after preview so they see staleness before overriding.

### Paste validation UX

On paste, if not starting wb1!:

- If starts wb0! — say "That's Camp DNA share, not inventory — use Share import tab"
- Else "Doesn't look like Warband string — starts with wb1! ? Try /warband copy again"
- Too long >25KB decoded or >20 chars — red "bundle too large, try /warband copy current single"

All client-side before D1 write — no server blast.

### Accessibility

- Text area monospaced JetBrains Mono same as bench aesthetic, neon pink #ff2e88 border muted.
- Data table small but readable, names in class color (read-only).
- Keyboard: Tab from textarea to Confirm, Enter confirms.
- Mobile: if phone clipboard — still works but Warband addon mobile never (WoW PC only) so desktop flow prioritized.

### Tonight Plan integration after import

After Confirm, Tonight Plan re-evaluates using fresh consumables data:
- If 0 phials and data fresh (<6h) block +12 suggestion with red.
- If 0 phials but data 5d old (yellow) grey text "per last import 5d ago — verify?"
This ties multi-char bundle to actual push value you wanted.

## AI coding hints (since AI never sees game)

- Implement UI.lua pure creation, no scraping. Export.lua returns wb1! string, callable standalone `WarbandPro.Export():GetBundleString()` so /warband copy script can unit test string generation without frame.
- UI.lua OnShow hook sets editBox:SetText(bundleString), HighlightText() — must be after frame shown else highlight evap. Wrap in C_Timer.After(0, Highlight).
- For web app, isolate import modal Decode logic into pure file `src/lib/warband-import.ts` which busted/vitest can test offline: base64url → deflate → json → validate schema → freshness map. UI handles clipboard only.
- Screenshot contract: human shows Export panel open with auto-highlighted string + Web modal preview table 6 rows + QA PASS lines.

## Copy-paste difficulty addressed

WoW chat = hard. This panel = 1 shortcut: /warband Enter -> Ctrl-C. Web side = 0 shortcuts if clipboard permission succeeds: Click Import -> Preview appears (auto grabbed) -> Confirm. If permission denied -> Ctrl-V fallback. Either way under 5 sec for 6 alts Saturday before your push.

When we ship light, this UI description remains but docs/UI.md can be trimmed to CONTRACT + QA minus implementation rambling.

