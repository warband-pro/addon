# UI — copy pain and import ease

Copying from WoW chat is notoriously awful. This addon lives or dies by how painless we make copy + paste both sides.

## Game side — one native window (1.5.0)

One frame, `WarbandProFrame`, with the tabs every stock panel wears along the
bottom: **Export · Import · Options**. `/warband` and the addon compartment
open it on Export, `/warband junk` on Import, `/warband options` on Options.
Esc closes (`UISpecialFrames`), the whole window drags, and it clamps to the
screen.

```
+--[bag icon]-- Warband.pro Companion ---------------------[x]-+
|  6 characters · freshest 12m ago · warband bank 1h (Vocnar)  |
|  * Vocnar-Wyrmrest Accord  12m ago  bank 1h ago              |
|  * Voctara-Wyrmrest Accord  3d ago                           |
|  +--------------------------------------------------------+  |
|  | wb1!aH4sIAAAAAAAA...                        (selected) |  |
|  +--------------------------------------------------------+  |
|  1. Ctrl+C copies  2. warband.pro > Import  3. Esc closes    |
|  wb1! · 6420 bytes from 39104 of JSON        [ Select all ]  |
+--------------------------------------------------------------+
   [ Export ] [ Import ] [ Options ]
```

**Built from Blizzard's own templates, on purpose.** `ButtonFrameTemplate`
for the chrome (portrait, title, close button, inset), `PanelTabButtonTemplate`
plus the `PanelTemplates_*` helpers for the tabs, `InputBoxTemplate` for the
paste field, `InsetFrameTemplate` for the text wells, `UIPanelButtonTemplate`
and `UICheckButtonTemplate` for controls. This replaced 1.0-1.4's hand-rolled
flat backdrop for one reason: a window assembled from the client's parts looks
like the client and *inherits the player's interface settings* — UI scale,
font scale, colorblind text — with zero code of ours. Ask Mr. Robot's addon is
the shape reference (export string out, website verdicts in, options beside
them); the skin is deliberately not ours but Blizzard's. Text colors inside
the window use the client's palette (gray for muted, gold for warnings, the
standard quality colors) rather than the website's.

Still no Ace, no LibStub registration, no minimap button — the compartment is
Blizzard's stated place now. Mixin calls that could plausibly move
(`SetTitle`, `SetPortraitToAsset`) are guarded so a rename costs the title or
the icon, never the window.

### Export tab

- Header line of freshness: "6 characters · freshest 12m ago · warband bank 1h
  ago (by Vocnar)" — readable before you copy, so you know it's not stale.
- Character rows with the traffic-light dots, then the string in a
  ScrollFrame + multiline EditBox inside an inset well:
  - `SetMaxLetters(0)` — the default cap would truncate the wire
  - `HighlightText()` + focus on a 0-second timer after show, so Ctrl+C alone
    works with no drag; `[ Select all ]` is the one-click recovery for anyone
    who clicked elsewhere first
  - `OnTextChanged` reverts user typing — this box is copied *from*, and a
    broken paste must never reach the website
- Footer: wire name, bytes on the wire from bytes of JSON, and a warning past
  `ns.SOFT_BYTES` pointing at `/warband copy current`.

### Import tab

The clear-out list — the string warband.pro sends back (`wbc1!`), decoded by
Import.lua, resolved against the live bags by Junk.lua:

- A native `InputBoxTemplate` paste field at the top. It decodes on paste and
  clears itself; rejections print the decoder's sentence for that failure.
  No revert rule here — this box is pasted *into*, its text is the player's.
- One row per resolved item: quality-colored name, item level, the reason
  (`cannot wear` / `N behind` / `grey`), then `[Sell]` and, for enchanters,
  a secure `[Disenchant]`.

**One window did not merge the two paste rules.** 1.4.0 ran two frames
specifically so "revert what the user types" could never apply to the box the
user pastes into. The rules turned out to belong to the *widgets*, not the
frames: each EditBox carries its own unconditionally, and the tab split keeps
the two boxes from ever being the same widget. What the merge actually bought
is one muscle-memory location for everything warband.pro, which is the AMR
lesson.

**The rows are real Buttons, and the disenchant one is secure.** Disenchanting
is a spell cast at an item — protected, so an addon may not do it, and may only
place a `SecureActionButtonTemplate` under the player's own click. The pool of
rows is built once at first open and its attributes are re-baked out of combat
on every redraw; nothing is created, reparented or rewritten during a fight.

**Combat closes this tab only.** `PLAYER_REGEN_DISABLED` hides the window when
the Import tab is up (a row holds a bag position, and a position that moved is
the wrong item), and `PLAYER_REGEN_ENABLED` brings it back; switching *to* the
tab mid-fight is refused with the same sentence. The Export tab holds no
secure state, so a string left open through a ready-check stays put.

**Sell is dark away from a merchant** rather than hidden. A row that changes
shape when you walk up to a vendor is harder to read than one that lights up,
and `Junk.Sell` checks the merchant flag again on click — the window can close
between a draw and a press, and `UseContainerItem` outside a merchant *uses*
the item instead of selling it.

**Greys are found here, not sent.** The website's copy of your bags is as old
as your last paste; vendor trash is only worth listing if it is what you are
carrying now.

### Options tab

Native checkboxes over the same `WarbandProDB.opts` the slash commands write —
the tab and `/warband gear on|off` are two doors to one switch:

- **Capture gear** (`includeGear`) — turning it on rescans immediately, same
  as the slash command.
- **Include item links** (`includeLinks`) — the debug toggle that was
  previously reachable only by editing SavedVariables.
- **Open the clear-out list at merchants** (`autoJunk`, off by default) — at
  `MERCHANT_SHOW`, if the resolved list has rows, the Import tab opens by
  itself and closes again at `MERCHANT_CLOSED` — unless the player switched
  tabs meanwhile, which makes the window theirs. It never auto-opens in
  combat, and never over a window already open. This is the one AMR
  convenience worth porting whole ("automatically show junk list at
  vendors"); their auto-equip and gear-set halves depend on a gear-set import
  that does not exist on this wire yet.

No UI-scale option, deliberately: AMR needs one because its window is skinned
from scratch; this window inherits the player's scale by being made of the
client's own parts.

### Automation safety

- Opening the window in combat queues it (`UI.pendingOpen`) and
  `PLAYER_REGEN_ENABLED` honors the request exactly once. Fail closed, not
  error spam.
- No OnUpdate, no ticker while the window is open — the export string is
  static, and the junk list redraws only on the events Core.lua already
  watches.

### Manual test proof it's easy

From `docs/QA.md` checklist expanded:

- /warband opens within 2 clicks: Compartment -> click or slash "/warband"
- Auto-highlighted on open without mouse drag (human just hits Ctrl-C)
- Ctrl-A + Ctrl-C works, pastes into Notepad startswith wb1! exact len reported at bottom.
- Esc closes, second open same behavior.
- Multi-char bundle 6 still in single EditBox scrollable, scrollbar appears but highlight still all.
- Tabs: Export ↔ Import ↔ Options round trip keeps each tab's state; the
  selected tab survives a combat hide/reopen.
- Window matches the client's UI scale — change scale in Settings, /reload,
  the window tracks it with no option of its own.

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

