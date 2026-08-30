# UI — copy pain and import ease

Copying from WoW chat is notoriously awful. This addon lives or dies by how painless we make copy + paste both sides.

## Game side — one native window (1.5.0)

One frame, `WarbandProFrame`, with the tabs every stock panel wears along the
bottom: **Export · Import · Options**. `/warband` and the addon compartment
open it on Export, `/warband junk` on Import, `/warband options` on Options.
Esc closes (`UISpecialFrames`), the whole window drags, and it clamps to the
screen.

```
+--[crystal]--- Warband.pro Companion ---------------------[x]-+
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

Still no Ace and no LibStub registration. There is a minimap button as of
1.5.0 (below) and it changes nothing about that: it is CreateFrame and one
cosine, not LibDBIcon, so the addon still registers with nothing. Mixin calls
that could plausibly move (`SetTitle`, `SetPortraitToAsset`) are guarded so a
rename costs the title or the icon, never the window.

### Export tab

- Header line of freshness: "6 characters · freshest 12m ago · warband bank 1h
  ago (by Vocnar)" — readable before you copy, so you know it's not stale.
- **The page line, when the warband is larger than one bundle holds** (1.8.0):
  "page 1 of 3 — /warband copy 2 for the next 20". One bundle carries at most
  `ns.MAX_CHARS`, so a 41-character warband is three copies, and the header is
  where the player learns there are two more to make. It replaced a line that
  reported the count left out and offered `/warband clear <name>` — deleting an
  alt to make room, which is the wrong answer for the player who has the
  problem. See [`CONTRACT.md`](CONTRACT.md) § paging for why the pages
  accumulate on the far side rather than overwriting each other.
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

Everything warband.pro sends back, in one box — the clear-out list (`wbc1!`)
and, since 1.6.0, the equip string (`wbg1!`). The paste field dispatches on
the prefix; each decoder still refuses the other's string *by name*, so a
misrouted call fails toward a sentence rather than "invalid":

- A native `InputBoxTemplate` paste field at the top. It decodes on paste and
  clears itself; rejections print the decoder's sentence for that failure.
  No revert rule here — this box is pasted *into*, its text is the player's.
- **The gear-set row**, between the paste field and the junk list: one status
  line (`gear set:  3 to equip · 1 already worn · 1 missing (1 in your bank)
  · set from 2h ago`) and one `[Equip N & save set]` button. The counts come
  from a resolve made at render time — the same freshness rule as the junk
  rows — so the button never promises an equip it cannot find. When
  everything wearable is worn the button reads `[Save set]`; when nothing is
  actionable it hides. The equip itself is GearSet.lua's job: equip every
  ready item under this click, verify off `PLAYER_EQUIPMENT_CHANGED`, save
  the Equipment Manager set only after the server confirms, and print one
  receipt. An ordinary button, not a secure one — equipping out of combat is
  not protected, and the tab is gone before combat can make it so.

  **Since 1.10.0 the row is about the setup for the spec you are in.** A paste
  stores one setup per spec the website solved, so switching spec switches
  which set this row offers — no dropdown, because there is exactly one setup
  per spec and the game already knows which spec you are. When you have setups
  but none for the spec you are standing in, the row says that rather than
  going blank: "none for this spec — 2 stored for others". Blank would send a
  player back to the website for a string they have already pasted.

  **`/warband equip` (1.9.0) is the same button without the window.** It calls
  the same `GearSet.Apply`, so the receipt, the verify and the Equipment
  Manager save are identical — what it removes is having to open a frame
  first, which is what makes it bindable to an action bar. It tells the two
  refusals apart rather than sharing one line: in combat is temporary and
  worth retrying, no stored set means go and paste one, and a single "nothing
  happened" would send the second player to wait out a fight that was never
  the problem. (`Apply` returns nil for both, which is why the slash handler
  checks rather than reporting whatever it gets back.)
- One row per resolved junk item: quality-colored name, item level, the
  reason (`cannot wear` / `N behind` / `grey`), then `[Sell]` and, for
  enchanters, a secure `[Disenchant]`.

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
- **Show the minimap button** (`minimap`, on by default) — the same switch as
  `/warband minimap on|off`. It is on this tab and the button's right click
  opens this tab, so the control that removes the icon is one click from the
  icon itself.
- **Open the clear-out list at merchants** (`autoJunk`, off by default) — at
  `MERCHANT_SHOW`, if the resolved list has rows, the Import tab opens by
  itself and closes again at `MERCHANT_CLOSED` — unless the player switched
  tabs meanwhile, which makes the window theirs. It never auto-opens in
  combat, and never over a window already open. This is the one AMR
  convenience worth porting whole ("automatically show junk list at
  vendors"); their auto-equip and gear-set halves arrived in 1.6.0 as the
  `wbg1!` equip string and the gear-set row above.

No UI-scale option, deliberately: AMR needs one because its window is skinned
from scratch; this window inherits the player's scale by being made of the
client's own parts.

### Minimap button

`WarbandProMinimapButton`, parented to `Minimap`, added in 1.5.0. Click for the
export string, right-click for the Options tab, drag to move it round the ring;
the hover tooltip says how many characters are stored and how fresh the
freshest is, so a glance answers "do I need to export" without opening
anything.

**Why it exists now and not before.** `docs/FLOW.md` ruled it out on
compatibility grounds, and the argument was really about the library: a minimap
button meant LibDBIcon, LibDBIcon meant LibStub, and this addon ships neither.
Hand-built, there is no dependency to weigh — the ring is Blizzard's
`MiniMap-TrackingBorder` and the face is `ns.ICON`, the same texture the window
wears as its portrait and the .toc names for the compartment; both are already
in the player's client. What decided it is the loop in
`docs/FLOW.md`: four to ten exports a play night, each an alt-tab out of a
fight. The compartment is a list of every addon installed, so each of those was
a click, a read and a second click.

The compartment entry stays. It costs one `.toc` line, and it is where a player
who turned this button off goes looking.

**Position is an angle, not a point.** `opts.minimapAngle` is degrees round the
ring and `UI.lua` owns the default (216°, the emptiest arc of the stock ring),
which is why `Store.lua` does not write one — a DB from before the button
gains one by not having it.

**The drag handler is the addon's only OnUpdate.** `OnDragStart` installs it and
`OnDragStop` removes it, so it runs while the mouse button is down and never
otherwise; what it reads is the cursor, not the game. Everything watching the
client still hangs off an event and a throttle (`Init.lua`).

### Automation safety

- Opening the window in combat queues it (`UI.pendingOpen`) and
  `PLAYER_REGEN_ENABLED` honors the request exactly once. Fail closed, not
  error spam.
- No OnUpdate, no ticker while the window is open — the export string is
  static, and the junk list redraws only on the events Core.lua already
  watches.

### Manual test proof it's easy

From `docs/QA.md` checklist expanded:

- /warband opens in one click on the minimap button — or the Compartment,
  or the slash command, or the keybinding (Key Bindings > Warband.pro
  Companion), all landing on the Export tab
- Auto-highlighted on open without mouse drag (human just hits Ctrl-C)
- Ctrl-A + Ctrl-C works, pastes into Notepad startswith wb1! exact len reported at bottom.
- Esc closes, second open same behavior.
- Multi-char bundle 6 still in single EditBox scrollable, scrollbar appears but highlight still all.
- Tabs: Export ↔ Import ↔ Options round trip keeps each tab's state; the
  selected tab survives a combat hide/reopen.
- Window matches the client's UI scale — change scale in Settings, /reload,
  the window tracks it with no option of its own.

## Web side — what actually shipped

**This section described a modal that was never built — corrected 2026-08-24.**

It specified a web import *modal* with `navigator.clipboard.readText()`, a
preview table, a `[Confirm Import]` button, a toast, and a 25 KB size cap. None
of that is what `warband-pro/app` does, and some of it was actively dangerous to
build from: the cap is wrong by a factor of forty, so a perfectly ordinary
six-character bundle would have been rejected as "too large" with advice
(`/warband copy current`) that then sends a single alt.

What the site actually does, and the only description of it this repo should
carry:

| | |
|---|---|
| Where | a one-line field in the rail's `$ import` block, on **every** route |
| Reached by | pressing `i` anywhere, or the rail's own field directly |
| Submit | paste, then Enter. No preview step, no confirm button |
| Feedback | a receipt listing what arrived, which decays after six seconds; the block's `never`/`38m ago` stamp is the part that persists |
| Size cap | 1 MB decoded, 1..20 characters — see [CONTRACT.md](CONTRACT.md) and [APP-IMPORT.md](APP-IMPORT.md) |

The import surface went route → overlay → rail field, and the reasoning for
each move is recorded in the app repo's own wiki
(`.wiki/wiki/concepts/shell-model.md` §10), which is where the web UI is
specified. **This repo owns the wire, not the website.** A second description of
one surface, maintained in a repo that cannot see it, is the drift both projects
already know about — it is why the app derives its landing page from an
inventory instead of writing it, and it is why the four stale names for this one
field ("warband.pro > Import", `/settings/import`, "Camp page top bar", "the
top-right sink") all survived for months.

**The rule this leaves behind:** anything in this repo describing the website is
either the wire contract, or a pointer. It is never a design.

## AI coding hints (since AI never sees game)

- Implement UI.lua pure creation, no scraping. Export.lua returns wb1! string, callable standalone `WarbandPro.Export():GetBundleString()` so /warband copy script can unit test string generation without frame.
- UI.lua OnShow hook sets editBox:SetText(bundleString), HighlightText() — must be after frame shown else highlight evap. Wrap in C_Timer.After(0, Highlight).
- For web app, isolate import modal Decode logic into pure file `src/lib/warband-import.ts` which busted/vitest can test offline: base64url → deflate → json → validate schema → freshness map. UI handles clipboard only.
- Screenshot contract: human shows Export panel open with auto-highlighted string + Web modal preview table 6 rows + QA PASS lines.

## Copy-paste difficulty addressed

WoW chat = hard. This panel is two keystrokes: `/warband` Enter, then Ctrl+C on
a string that is already selected — or one keybind, since 2026-08-24, which is
what docs/FLOW.md had been promising all along. The web side is three: `i`,
Ctrl+V, Enter. Six alts in well under five seconds, and the panel says `copied`
when the first half is done.

