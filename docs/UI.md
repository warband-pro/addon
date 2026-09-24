# UI — copy pain and import ease


## v2 look (1.23.0, finished in 1.24.0) — what changed and what did not

The window wears Plumber's visual language now — near-black warm-brown ground,
thin bronze hairlines, a title band with the tab row under it, text-only tabs
(white active, gold idle, underline bar on the active one), plaque section
headers, gold divider between the header and the content, flat buttons and
checkboxes that light under the mouse — built entirely from Blizzard textures,
Blizzard font objects and this addon's own `Theme.lua` builders. No Plumber
art or code ships; the MIT/GPL boundary is documented in Theme.lua.

**The templates stay for their behavior and lose their paint.** The window is
still a `ButtonFrameTemplate` (title, close button, Esc, the inset every panel
anchors to), the tabs are still `PanelTabButtonTemplate`, the paste field is
still an `InputBoxTemplate`, the scroll frames are still
`UIPanelScrollFrameTemplate`. `Theme.SkinWindow`, `Theme.StyleTab`,
`Theme.SkinInput` and `Theme.SkinScroll` hide the box art by parentKey — every
hide guarded, so a renamed key costs the paint and never the widget — and draw
the flat version over it. Buttons on the panels are `Theme.MakeButton` (a bare
Button with a dark ground, a bronze edge and a HIGHLIGHT-layer sheet); the one
secure button, Disenchant, is born a `SecureActionButtonTemplate` and skinned
with `Theme.SkinButton`, which is textures and font objects and nothing
protected. The vendor window's Sell-list button stays a stock
`UIPanelButtonTemplate`: it lives in Blizzard's frame and should match it.

**Fonts are Font objects, not `SetFont` calls** (1.24.0). A Button re-applies
its state font object to its label on every Enable/Disable, and the client's
own `PanelTemplates_SelectTab` disables the selected tab — so 1.23.0's 16px tab
labels lasted until the first click. `Theme.Font(key)` builds named Font
objects once (`CreateFont`, copied from a game font so the locale face comes
along, then sized and tinted) and hands those to the buttons' normal /
highlight / disabled slots; `Theme.RefreshTabs` re-sets the disabled slot after
every `PanelTemplates_SetTab`, because the client's select overwrites it. The
tab-box list covers the current client's parentKeys (`LeftActive` and friends)
as well as the older ones, so the active tab no longer draws stock art under
its label.

**Hairlines are one physical pixel.** `PixelUtil.SetHeight(tex, 1, 1)` where
the client has it, so a bronze rule at a UI scale below one does not blur or
vanish. Without it the line is one UI unit, which is what 1.23.0 drew.

- **Header**: a 30px title band (icon, "Warband.pro" in gold serif, the close
  X drawn as two hairlines) over the tab row, then the divider at
  `Theme.DIVIDER_Y`; the inset starts at `Theme.INSET_Y`. 1.23.0 hung the tabs
  off the window's bottom edge, where every stock panel keeps its boxed tabs
  and where a text-only tab floats over the world with nothing behind it.
- **"You are here" is selected, not disabled** (1.24.0). The export's slice row
  marks the scope you are on with `Theme.SetSelected` — bronze ground, bright
  edges, white label — where 1.23.0 disabled it, the client's idiom, which on
  this ground reads as broken. The pager arrows still disable at an edge,
  because that one genuinely cannot be pressed.
- **Roster tab**: persistent left sidebar (All plus one row per character with
  class color, class icon, compact vault and keystone status in the model's
  tone, then the account-wide resource rows), parted from the grid by a
  hairline. Rows are `Theme.MakeListRow` — a HIGHLIGHT-layer sheet under the
  mouse, a bronze ground and bar when selected — and a character row's hover
  is the grid column header's `columnTip`, so the two cannot disagree. The
  list is a bare `ScrollFrame` driven by the wheel with a 2px thumb that
  appears only when there is somewhere to scroll to (1.24.0; through 1.23.0 a
  warband taller than the window drew over the footer). Clicking a row narrows
  the grid to that character; the selected character gets Great Vault slot
  buttons (`n/m`, locked dimmed gray, unlocked full white). The grid, its rules
  (absent-is-not-zero, collapsible groups, no live reads), and the warbank
  footer are unchanged. Model: `Roster.Sidebar` (+ tests); seasons:
  `Roster.Seasons` (one entry today, the selector enables when a second lands).
- **Options tab**: three panes under section headings and parted by hairlines
  — Data / Automation / Display nav on the left, **checkbox rows** in the
  middle, the hovered or last-clicked option's name and description on the
  right. A setting is one click: the row and its box are two targets for the
  same toggle, and the mouse arriving is what puts a row's description in the
  pane (1.24.0; 1.23.0 kept the checkbox on the right, which made every
  setting select-then-toggle). Same controls, same saved variables.
- **Export/Import**: plaque headers name the string each tab holds (the export
  plaque follows the slice scope); the paste field takes the caret when the
  tab opens, on the same 0-second timer the export tab uses for its highlight
  (1.24.0). Wire format, slice row, pager, and the paste flow are untouched.

Everything below still describes the window — read this section first for
where the chrome went. Where a paragraph below says a control is "disabled" for
the scope you are on or names a stock template for the paint, this section is
the current word.


Copying from WoW chat is notoriously awful. This addon lives or dies by how painless we make copy + paste both sides.

## Game side — one native window (1.5.0)

One frame, `WarbandProFrame`, with four tabs under the title band (the v2
section above says where they moved): **Roster · To warband.pro · From
warband.pro · Options** — the prose below still calls the middle two the Export
and Import tabs, which is what they do. `/warband` and the addon compartment
open it on Export, `/warband roster` on Roster, `/warband import` (also `junk`)
on Import, `/warband options` on Options. Esc closes (`UISpecialFrames`), the
whole window drags, and it clamps to the screen.

**A site string pasted into the export box walks to the Import tab (1.25.0).**
The export box reverts whatever is typed into it, which is right for a stray
keystroke and was wrong for the one paste this window exists to receive: the
site says "copy for the addon", the player opens `/warband` — the Export tab —
and pastes, and the string vanished without a word. `pastedInto` recovers what
the paste put in, and a `wbc1!`/`wbg1!` prefix hands it to the Import tab's
own `acceptInbound`, so the receipt and the refusals are the same ones a paste
on the right tab gets.

**The keybind closes the window as well as opening it.** A focused EditBox eats
every key, so the toggle binding could open the window and never close it while
the export string or the paste field had the caret. Both boxes ask
`GetBindingFromClick` whether the key they received is `WARBANDPRO_TOGGLE` and
hide the frame if so.

**Roster is tab 1 and is not what the window opens on**, which is deliberate
and is the one place tab order and default disagree. Reading precedes acting,
so the tab you read sits leftmost; but `/warband` has always landed on a
highlighted export box and FLOW.md counts that path at under two seconds, so
every door that existed before still opens the tab it always opened.

```
+--[crystal]--- Warband.pro -------------------------------[x]-+
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

### Roster tab (1.9.0)

The grid. Every character across the top, everything this addon knows about
them down the side.

```
+--[crystal]--- Warband.pro -------------------------------[x]-+
|  6 characters                                                |
|                *Vocnar *Voctara *Voctesa *Vocgrim  ...       |
|                 80·621  80·618   80·614   77·602             |
|  +--------------------------------------------------------+  |
|  | - this week                                            |  |
|  | vault · raid     1/3     2/3     --      1/3           |  |
|  | vault · mythic+  8/8 (1) 4/8     --      1/8           |  |
|  | keystone         +12     +9      --      --            |  |
|  | - lockouts                                             |  |
|  | Nerub-ar (Heroic) 2/8    8/8     --      --            |  |
|  | - currencies                                           |  |
|  | Valorstones      1,900/2,000  240/2,000  --            |  |
|  +--------------------------------------------------------+  |
|  warband bank 1h ago (by Vocnar) · 5,000g                  // |
+--------------------------------------------------------------+
   [ Roster ] [ Export ] [ Import ] [ Options ]
```

(`//` is the corner grip. `[ < ][ > ]` appear beside it only when the warband
is wider than the window can be dragged.)

**The arrangement is SavedInstances', and that is the whole design decision.**
Characters are COLUMNS and tracked things are ROWS, because the question an alt
player actually asks is *which of them still has this*, and that is a line you
read across rather than six panes you hold in your head. Its class-coloured
name over a level, its two-or-three-character cells (`3/8`), its labelled row
groups with a rule between them, its self-first-then-realm-then-name column
sort (`cpairs_sort`) and its raids-above-dungeons row sort are all ported.

**What could not be ported is how it draws.** SavedInstances builds its grid
with LibQTip on top of Ace3, and this addon ships neither and is not going to —
`RESEARCH-REFERENCE.md` is the standing answer and this was not the change that
reopened it. So the MODEL is ported and the rendering is ours, out of the
client's own FontStrings. That split is also why our grid is *testable* and
SavedInstances' equivalent is not: `Roster.lua` is a DB table in and a display
model out, with no WoW API anywhere in it, and `tools/roster-test.lua` holds
every rule below.

**Three rules, and the first one is the one a grid is most likely to destroy:**

1. **Absent is not zero.** A section a character has never had read draws an
   EMPTY cell, never a `0`. That is the distinction `seenAt` exists to carry;
   a blank column reads as "nothing there" when it means "nobody looked", and
   `0/8` means we looked and nothing had died. The model expresses this in its
   type — an unknown is an absent cell, not a grey one — rather than as a
   convention a renderer has to remember.
2. **A row nobody has a value for is not drawn.** SavedInstances gives every
   instance a per-row `always | saved | never`; the useful half of that with no
   config attached is "show it if somebody is saved to it". An alt player's
   list of *possible* lockouts is far longer than their list of real ones, and
   a grid of mostly-blank rows is a grid nobody reads.
3. **Nothing in it reads the game.** Every number already went through
   `ns.safe` on the way into the DB. Reading it back out is table work, so the
   grid cannot throw in the middle of a raid.

**A group shuts, and stays shut.** Click a group's label and its rows fold
away; the header stays, with a `+` in front of it and the number of rows it is
holding — `+ currencies  (11)`. Click it again and they come back. Which groups
are shut lives in `opts.rosterShut`, keyed by the group's label rather than its
position, because which groups a warband has depends on what has been scanned
and an index would move under the player the first time a lockout appeared.
Only the shut ones are stored, so an addon nobody has clicked this on carries
no key at all.

This is the half of SavedInstances' category config that is worth having
without the config: five groups against a window that shows about forty rows
means the grid is a scroll, and a player who is looking at lockouts is not
looking at currencies. Shutting is in-place and reversible in one click, which
a checkbox on another tab is not.

**A shut group is not an empty one, and the count is what says so.** A header
with a rule under it and nothing else is exactly what a group that turned out
to have nothing looks like — and a group with nothing to say is not drawn at
all (rule 2 above), so the two states must not render the same. `Roster.Lines`
owns both, which is why the flattening moved out of `UI.lua` and into the
model: the page slice and the shut set answer the same question about a row and
about the header above it, and two copies of that rule is how a header outlives
its last row.

**The grid fits the warband, and the window resizes (unreleased).** Two fixed
numbers remain, and only because the text decides them: a label column wide
enough for `Nerub-ar Palace (Heroic)` is 152px, and a cell that can still hold
`4,500/20,000` is 56px. Everything else is measured at render time from the
scroll frame the cells live in — `fittingCols()` — so widening the window buys
columns and nothing else has to be told.

The window opens at **680x520, which is eight columns**, derived rather than
chosen: `152 + 8x56 + 6` gutter, plus about 72 for the chrome between the
frame's edge and the scroll frame's. It drags from a corner grip between 560x460
and 1600x1000, and the size and position are remembered in `opts.window` — the
same `opts` idiom, and the same write-on-drag-stop timing, as the minimap
button's angle. A size stored by an older build is clamped to the current bounds
on the way back IN as well as out, so a bound change can never leave a window
that cannot be reached or resized back.

**The minimum height is set by the Options tab, not by the grid** — it was 420
until the currency filter added a fifth checkbox, and the tallest tab is what
decides how short the window may get. Its controls run top-down at a fixed pitch
against a version line pinned to the panel's bottom, so five of them and a
footer need 460. That clamp on the way in is what makes raising it safe: a
player who had left the window at 420 gets it back at 460 rather than losing it.

`[ < ]` and `[ > ]` survive for the case where a warband genuinely will not fit
the widest window, but they are hidden unless that is true.

**This replaced a fixed six columns and a fixed 24 rows, and the second was a
bug rather than a limit.** The model built every row and the scroll child was
sized for all of them, but the widget pool held 24 and only those were ever
painted — so a real warband (a measured 38 lines: 16 currencies, 9 professions,
the vault, pockets) scrolled off the bottom of its own grid into blank space,
with no indication that anything was missing. Both pools now grow on demand to
what the model and the window between them ask for.

Column headers sit OUTSIDE the scroll frame, so scrolling the rows never scrolls
away the names they belong to — and they are offset by the same 8px the scroll
frame is inset into its well, because a header that is a child of the panel and
a cell that is a child of the scroll frame do not otherwise line up.

**A group header carries a rule and a row highlights under the mouse.** Reading
a 14px row across twelve columns is exactly where an eye loses its place, and
these are the two things SavedInstances gets from LibQTip that we owed it.

**Two inks: labels are grey and values are white.** A group's name, a row's
name and the words around a count are chrome and read dim; the number in the
cell is what you came for and is the brightest thing in the frame. Anything
that is neither is a *tone*, and the tones are the whole attention system —
green earned, gold close, red gone, class colour for whose it is.

Through 1.21.0 this was one weight: labels, headings and values all arrived in
`GameFontHighlightSmall`, so the tab opened onto a wall of same-brightness text
and the number you were after had to be found rather than seen. Dimming the
chrome is the whole of the fix; no tone changed and no colour was added.

The header text and its `+`/`-` are grey, and the stripe under them carries the
separation at 10%. **They were gold**, for a reason that the ink ramp retired:
grey read as disabled while the data rows were *white*, which put a heading at
less weight than the rows it named. With the labels grey and only the values
bright, a heading no longer has to out-shout its block — it has to step out of
the way, and the one thing on the line that is not text does the separating.

**Row groups, in order:** `this week` (the three vault buckets, keystone, m+
score), `lockouts` (one row per instance-and-difficulty anybody is saved to,
raids first, plus a world-boss count), `currencies` (one row per currency the
game is still metering for somebody — see below), `cooldowns` (one row per
trade skill cooldown anybody is metering), `from warband.pro` (what a `wbc1!`
paste left for each character). The warband bank is account-wide and so has no
column to live in; it is the footer line, with how many of its tabs were
actually read.

**`professions` and `pockets` were removed in 1.20.1**, and the reason is the
question the grid exists to answer: *what character do I swap to, for what
activity.* A skill number and a bag count do not answer it, and nine profession
rows and eight pocket rows between them pushed the groups that do below the
fold. Both are still captured and both still go out on `wb1!` — the site reads
them; the grid no longer draws them. Gold survives as the column header figure,
where it costs no row.

**Values are right-justified in their cell, labels are not.** A centred value
moves with its own width, so `0/2` and `43,418g` begin in different places and a
column of numbers offers the eye no edge to run down. Flushing them to the right
of the 56px cell gives one, which is what SavedInstances' compact values do. The
row labels stay left-justified and the column headers stay centred — a name is a
label, not a member of a series.

**And the digits are tabular.** An edge is only half the job: the game font this
window is otherwise built from is proportional, so its `1` is narrower than its
`8` and a column of `3/8`, `11/8`, `6/8` wanders either side of its own slashes
even when every value ends flush. Cells are drawn in the client's own number
face (`NumberFontNormalSmall`, Arial Narrow), resized to the window's small
font so a cell does not stand taller than the label beside it. It is taken as a
template NAME rather than as a font object because a non-Latin client swaps the
file behind that name; cells are ASCII by construction, and the names — which
are not — stay in the game font.

**Hover is where the parity actually lands.** A cell is two or three characters
because that is what makes a row readable *across*; everything it summarises
lives in the cell's own tooltip, which is the feature people name when they say
SavedInstances reads well. A lockout cell says `2/8` and its hover names every
boss dead and alive and how long until it resets; a vault bucket's hover lists
each slot's threshold and whether it is earned — detail `Instances.lua` has
stored since 1.2.0 that nothing had ever read. A currency's hover carries the
**weekly** cap, which is the urgent one: a weekly that resets unspent is gone,
where a total cap merely stops accruing. A column header's hover carries realm,
guild, level, item level, gold, last zone and when it was scanned, because none
of that fits in 56px and all of it identifies the character.

Mechanically this is why a cell is a `Frame` wrapping a FontString rather than a
bare FontString: a FontString takes no mouse input. Pooled at build like every
other widget here, and a hit area with no cell under it is hidden and has its
tooltip cleared — a pooled widget that keeps the last render's tooltip is
exactly the bug this arrangement invites.

**An expired lockout is not drawn.** `resetTime` is absolute unix seconds, so a
character last played before the reset carries a saved instance that has
certainly gone. Drawing it would state something known to be false, which is
worse than the blank it becomes — the blank correctly says nobody has looked
since. Whether they re-locked is a different question and an unread one. This is
SavedInstances' `ShowExpired` decided rather than configured, and it is decided
the way this addon decides everything else: a reading it cannot stand behind is
not shown. A lockout with no `resetTime` at all predates the field and stays.

#### The currency rows — which ones, and what a colour means

**A currency earns a row when the game is still metering it for somebody**: it
has a total cap, or a weekly cap, or a character in this warband earned some of
it this week. The test runs across the whole warband rather than per character,
so one alt still earning a currency keeps its row for the nine who are not —
which is the point of a grid.

Everything else is a pile left over from an expansion nobody here is playing —
Timewarped Badges, the marks of three seasons ago, one line each, padding the
sixteen-row currency group measured above, between the two rows you opened the
tab for. **SavedInstances answers this with a checklist of every currency in
the game**, which is the largest thing in its options and is maintenance the
player does on the addon's behalf every time an expansion retires a currency and
mints four more. The signal is already on the wire here, so this is decided
rather than configured — the same move as the expired lockout above.

**And the season's own currencies are pinned past that test.** The live rule has
one hole in it and it is the hole a delve night falls into: a Restored Coffer Key
has no total cap, no weekly cap and — once the player has stopped picking up
shards — nothing earned this week either, so the currency they check *before*
queueing for a delve is the one the heuristic hides. The answer worth having is
the one a row that is not drawn cannot print: **zero coffer keys is itself the
signal**, go earn shards.

So `Roster.lua` holds one table of the season's currency ids at the top of its
currency section — Restored Coffer Key, Coffer Key Shards, Undercoin, Untainted
Mana-Crystals, Tidal Spark Dust and the five Mistcrests for Season 2 of Midnight
— and a pinned currency gets a row whenever *anybody* in the warband has had it
read, metered or not. Pinning does not invent a currency nobody has ever seen.

**A pinned zero is a reading rather than a gap**, and it is the one place rule 1
above is answered by the stamp instead of the value: a character whose currency
list was read and carries no line for Restored Coffer Key holds none of them, so
the cell says `0`, because `seenAt.currency` is what says we looked. A character
whose currencies were never read keeps the empty cell, exactly as everywhere
else. Everything unpinned behaves as described above, hidden count included.

This is developer maintenance once a season and **not player configuration** —
there is no checkbox for it and there is not going to be one, for the same reason
the group has no per-currency checklist. Whoever ships the season rollover edits
those ids and nothing else; a retired currency needs no removal, because it stops
matching anything anybody scanned and the row goes with it.

**Each row draws the currency's own icon before its name.** SavedInstances does
this and it is most of why its currency list reads faster than ours did: the
icon arrives before the word, so you find Valorstones by shape rather than by
reading down a column of names that all begin with a capital letter. The icon
is the row's rather than a cell's — a currency is the same currency across every
character — and it comes off the stored `icon` file id, so an alt offline since
last week still shows one. A row nobody has an icon for keeps the whole label
column and looks exactly as it did. Instance and profession rows stay text.

The group header **says how many it left out** — `currencies · 4 hidden` — for
the reason the minimap glance prints `+2` rather than simply stopping at three: a
header that silently drops rows is a bug report waiting to be filed, and one
that counts them sends the player to the switch that shows them. That switch is
**Show every currency in the Roster grid** on the Options tab, one checkbox
rather than one per currency. A warband holding nothing but legacy currencies
gets no group at all, by the same rule that drops every other empty group.

**Urgency leads, then the alphabet.** Name order is the right tiebreak and the
wrong headline: a currency at its cap is being thrown away while the player
reads, and in a group docs measured at sixteen rows the red cell only warns the
player who reads all sixteen looking for one. So the rows rank by the worst
thing any character's cell says — at the cap first, then the warnings (90% of a
cap, or this week's allowance already earned), then everything else in the name
order it had. The rank is read back off the cells rather than recomputed, which
is what stops a row leading the group while its own colour says nothing is
wrong.

And the header counts them — `currencies · 2 at cap`, `currencies · 2 at cap ·
4 hidden` when both are true. It is the same honesty device as `N hidden`
pointed the other way: not what the header is leaving out, but what the warband
is losing right now, so one look at the label answers *do I need to go spend
something* without reading a row. With nothing at a cap the header is exactly
what it was. **The count is deliberately not crest-scoped** — the season table above is a
list of ids and nothing more, and the season-scoped *judgements* stay on the
website, so any capped currency leads.

**Colour is the two things you can act on.** SavedInstances paints green under
the cap, red at it and yellow at a weekly cap; the green half is decoration
here, because this grid's rule is that colour is state and sixteen green rows
state nothing. So `plain` is what fine looks like, and the tones left are:

- **red — at the cap.** Everything earned towards it from here is thrown away.
  The hover says so.
- **orange — nine tenths of the way there, or this week's allowance already
  earned.** The first is the warning that arrives while it is still worth
  something; the second answers "should I run more of this", and the hover's
  weekly fraction says which of the two you are looking at.

Being at the cap **used to be orange as well**, which made "go spend this" and
"too late" the same colour — and the minimap glance has called the second one
red since 1.9.0, so the grid and the hover disagreed about the same currency.

#### The cooldown rows — the group whose useful state is the expired one

Trade skill cooldowns sit under the currencies, one row per recipe: the alchemy
transmutes, the daily forges, anything the client meters. It is SavedInstances'
trade skill row, and it is the one place in this grid where **a timestamp in the
past is the answer rather than something to refuse.**

Everything else here counts towards something being taken away, and the rule for
those is the expired lockout above — past its reset it is *known* to be gone, so
drawing it would state something false. A cooldown inverts that exactly: past
its ready time it is *known* to be ready, and an alt with a transmute waiting is
the whole reason to look. Same absolute stamp, same arithmetic, opposite
conclusion, which is why the rule is stated per group rather than applied to
every timestamp on sight.

| cell | means |
|---|---|
| `ready` (green) | the cooldown has run out. Log in and use it. |
| `2/3` (green) | a charge-based cooldown with charges in hand. |
| `18h` | still counting down, with nothing spendable. |
| *empty* | this character has never had a profession window open, so we have nothing to say. Not "ready" — that would be inventing a fact about an alt. |

**Charges beat the timer where they disagree**, and they disagree often: a
charge-based cooldown can be counting down and usable at the same time, so a
cell that only read the timer would send a player away from something they could
do immediately. The hover carries the profession, the charge count, whether it
is a daily, and how long it has been waiting.

**Which recipes get a row is decided the way the currencies are.**
SavedInstances carries a per-expansion table of trade skill cooldown spell ids
and grows it every patch; we walk what the open profession window actually
lists, and a recipe earns a row the first time the client reports a cooldown on
it. From then on it is remembered — including after the cooldown runs out, which
is the state worth knowing.

**They are read only while a profession window is open**, the same as the bank
and the mailbox, and `C_TradeSkillUI` answers for that one profession and
nothing else. So the stored list is merged per skill line rather than replaced —
opening Alchemy must not forget Tuesday's Blacksmithing cooldown — and it
carries its own `professionCooldown` freshness stamp instead of sharing
`profession`, which `SKILL_LINES_CHANGED` moves at every login. Sharing it would
put a fresh dot on a transmute timer nobody has looked at since Tuesday, which
is the reagent bank's bug with a different window in front of it.

### `from warband.pro` — the group SavedInstances cannot have

SavedInstances has no other side. This addon does, and the last row group is
what the website last sent back, per character: whether a gear set is stored and
how much of it is wearable, how many items are on the clear-out list, how many
specs have a build assigned, and **how old the whole answer is**.

It reads `db.junk[guid]` and `db.gearset[guid]` — written by a `wbc1!` paste,
keyed by the same guid the columns already sort on.

**It draws the plan's existence and age, never its reasoning.** Not which item
is better, not how far behind a slot is, not who to play tonight: those need the
season loot table, per-item stats and weights, none of which are in this client,
and a second surface guessing at them would be a second surface being wrong. The
website decides; this says whether its answer arrived and how stale it has gone.
The clear-out hover breaks down by verdict and reason (`3 to sell`, `1 to
disenchant`, `gap`, `dupe`) rather than by item name, because the wire carries
no display name — `Junk.lua` resolves those live against the bags as they are
now, and a name stored an hour ago is a name for an item that may have moved.

The plan-age row uses `ns.dot`'s own thresholds rather than new ones: a plan and
a scan go stale at the same rate, because they describe the same bags.

Why it belongs in the grid rather than on the Import tab: **the Import tab is
the character at the keyboard, and this is a warband question.** Before it,
finding out which of nine alts had an unapplied plan meant logging into nine
alts.

**It reads the same DB the export encodes**, so it is not a second source of
truth and cannot drift from the bundle: what the grid shows is what the paste
will carry. That is the reason it belongs in this window rather than in one of
its own.

### Export tab

- Header line of freshness: "6 characters · freshest 12m ago · warband bank 1h
  ago (by Vocnar)" — readable before you copy, so you know it's not stale. In the
  smaller scope it opens with the scope in words: "this character only · 1
  character · freshest 2m ago", because "1 character" alone reads the same
  whether the panel sliced the warband or the warband is that small.
- **The slice row** (1.19.0): `[ Whole warband ] [ This character ]`, and on the
  right the pager. The scope was always a wire switch and never a control — the
  tab opened on the whole warband and the smaller slice lived behind `/warband
  copy current`, a command a player mid-dungeon does not type. Both mid-session
  gear flows want this character and the camp flow wants the warband, so it is
  one click either way. The button for the scope you are already on is
  **disabled**, which is the same "you are here" `SetEnabled` the roster's pager
  uses. Both slash commands still work and are unchanged.
- **The choice does not survive a close.** `UI.Open` sets the scope to the whole
  warband unless the caller names one, so a best-in-bags export cannot silently
  hand the camp flow a one-character bundle the next time the window opens. It
  used to keep the last scope, which mattered little when only a slash command
  could set it and matters a lot now that a click can.
- **The pager, when the warband is larger than one bundle holds** (1.8.0, the
  arrows 1.19.0): `page 1 of 3  [ < ] [ > ]`, and the header says "20 of 41 —
  the rest go out a page at a time". One bundle carries at most `ns.MAX_CHARS`,
  so a 41-character warband is three copies. The header said "page 1 of 3 —
  /warband copy 2 for the next 20" until the arrows replaced it: it was the last
  instruction on the tab that was a command rather than a control. The arrows
  belong to the warband scope only — one character never pages — and
  `refreshScope` adopts the page `Bundle.Build` actually clamped to, so a
  `/warband copy 99` cannot leave an arrow looking dead. The line before all of
  this reported the count left out and offered `/warband clear <name>` — deleting
  an alt to make room, which is the wrong answer for the player who has the
  problem. See [`CONTRACT.md`](CONTRACT.md) § paging for why the pages accumulate
  on the far side rather than overwriting each other.
- Character rows with the traffic-light dots, then the string in a
  ScrollFrame + multiline EditBox inside an inset well:
  - `SetMaxLetters(0)` — the default cap would truncate the wire
  - `HighlightText()` + focus on a 0-second timer after show, so Ctrl+C alone
    works with no drag; `[ Select all ]` is the one-click recovery for anyone
    who clicked elsewhere first
  - `OnTextChanged` reverts user typing — this box is copied *from*, and a
    broken paste must never reach the website
- Footer: wire name, bytes on the wire from bytes of JSON, and past
  `ns.SOFT_BYTES` the word "large" plus a `[ Just this character ]` button beside
  `[ Select all ]` (1.19.0). The note read "(large — try /warband copy current)":
  a warning whose remedy was a command, printed at the one moment the player is
  least likely to go and learn one. It is the same offer as the slice row's
  second button and deliberately a second door onto it — the row is where the
  choice lives, the footer is where the warning is, and a warning you can act on
  without moving your eyes is worth the widget. It is hidden in the smaller scope,
  where the cap is not in play.

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

  **The set is called what the spec is called, with the spec's icon — since
  1.11.0.** `Protection`, not `warband.pro Protection`: the header line, the
  button's save and the receipt all use the client's own name for the spec at
  the keyboard, and a set an older build saved under the branded name is
  renamed to it rather than left beside a new one. A set the player already
  has under that name is updated in place with its icon untouched. The wire's
  proposed name is only used when the client cannot read a spec.

  **Since 1.10.0 the set is drawn under the counts, slot by slot.** One row
  per item on the wire, in slot order: the item's icon, the slot (`ring 2`,
  `main hand`), the item's name in its quality colour with its item level,
  and where it is right now — `worn` (muted; AMR's `E`), `in bags` (green;
  the button will equip it), `in your bank` or `not in your bags` (yellow;
  an errand first). Hovering a row opens the client's own item tooltip off
  the wire's item string, so the stats of what the site picked are readable
  without leaving the tab. The model is `GearSet.Rows`/`GearSet.StateText`,
  pure and tested; `UI.lua` only lays it out. An item the client has never
  seen this session has no name yet and is drawn as `item 221151` until
  `GET_ITEM_INFO_RECEIVED` redraws the rows. The junk well anchors under the
  list, so a set of three costs three lines and no set costs none. This is
  the delta the maintainer's own AskMrRobot comparison named (app#71): their
  import screen shows the set and marks what is already on; ours showed a
  count.

  **Since 1.8.0 the row is about the setup for the spec you are in.** A paste
  stores one setup per spec the website solved, so switching spec switches
  which set this row offers — no dropdown, because there is exactly one setup
  per spec and the game already knows which spec you are. When you have setups
  but none for the spec you are standing in, the row says that rather than
  going blank: "none for this spec — 2 stored for others". Blank would send a
  player back to the website for a string they have already pasted.

  **`/warband equip` (1.8.0) is the same button without the window.** It calls
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

### Sell list — the button on the vendor window (1.20.0)

**The panel is for picking; the vendor window is for selling.** A `Sell list
(N)` button is parented to Blizzard's own `MerchantFrame`, below it on the
right — the one edge with nothing on it, since the Merchant and Buyback tabs
hang off the bottom-left and the money frame sits inside the bottom-right. It
exists only while a merchant is open and this character has at least one live
sell row, and it hides again at zero rather than sitting there disabled: a dark
row explains itself inside this addon's own panel, and a dark button in
Blizzard's window is furniture left in someone else's house.

**It sells exactly what the panel offers, because it asks the same function.**
`Junk.SellPlan` takes the rows where `Junk.Sellable` is true *and* the verdict
reads `sell` — the site said sell, or it is a grey. A `de` row on an enchanter
keeps its own `[Sell]` in the panel and is not in the plan: overruling the
advice one item at a time is a different act from overruling twelve under one
confirm. `del` rows and unsellable ones are never in it at all.

**The confirm is required, and it is not the grays-button precedent.** Zygor's
button sells vendor trash; this sells gear a website judged, and the only way
back is the vendor's twelve-slot buyback tab. The `StaticPopup` states the
count and the take — "at least" when the client has not cached every price,
since an uncached item still sells but cannot be totalled — and names buyback.
There is no timer and no auto-sell on merchant open: the confirm click is the
one hardware event that drives the loop.

**The plan is rebuilt at the confirm, not read off the label.** The count on
the button comes from the walk made at `MERCHANT_SHOW`; bags move between
opening a vendor and pressing a button, and a bag position from that walk is
exactly the stale coordinate `Junk.lua`'s header forbids. Rows that left the
bags are simply absent from the second walk, which is the same thing the
panel's missing count already reports. A chat line says what sold and for how
much when it is done.

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
- **Show every currency in the Roster grid** (`allCurrencies`, off by default) —
  the escape hatch for the filter described under the Roster tab. Off, the grid
  lists what the game is still metering and its header counts what it left out;
  on, every currency any character is carrying gets a row. One checkbox, not
  SavedInstances' one per currency.

No UI-scale option, deliberately: AMR needs one because its window is skinned
from scratch; this window inherits the player's scale by being made of the
client's own parts.

### Minimap button

`WarbandProMinimapButton`, parented to `Minimap`, added in 1.5.0. Click for the
export string, right-click for the Options tab, drag to move it round the ring.

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

#### The hover — SavedInstances' primary tooltip

```
Warband.pro
* 6 characters  ·  freshest 12m ago

vault ready       Vocnar 3 slots  Voctara 1 slot
keystone          Vocnar +12  Voctara +9  Voctesa +7  +2
saved             Vocnar 2  Voctesa 1
at cap            Vocnar Weathered Crest  Voctesa 2 currencies

                  *Vocnar  *Voctara  *Voctesa  *Vocmar
this week
vault · raid         2/4 (1)     4/4 (2)       1/4        —
keystone                 +12          +9         +7        —
lockouts
Liberation (H)           6/8         8/8          —      saved
world bosses               2           1          —        —
currencies
[] Valorstones         1,240       2,000        320        —
[] Weathered Crest        90          45         90        —

+2 characters  ·  +7 rows did not fit
Click  ·  the export string      Right-click  ·  options
Drag  ·  move it round the ring      /warband roster  ·  the same grid, scrollable
```

**The hover is the grid** (1.18.0). Through 1.17.1 it was the four summary
lines above and nothing else, which is a summary where a decade of
SavedInstances muscle memory expects the whole picture — that addon's hover is
not the route to the answer, it *is* the answer, and the window is the
follow-up question. So the grid moved into the hover and the Roster tab stayed
as the surface you *act* on: it scrolls, it shuts a group, it pages, and it
sits beside the export and import boxes the window exists for. **The hover
reads; the tab acts.**

`Roster.Hover` is the model and it is `Roster.Build` plus `Roster.Lines` — the
same two calls `UI.RenderRoster` makes — so the hover cannot disagree with the
tab, and neither can disagree with the bundle the export encodes. Nothing on
this path builds a bundle: a hover is not worth an encode and a deflate.

**The summary band stays above it.** A grid answers per character; those four
lines answer *across* the warband, which is the only shape in which four lines
cover twenty alts, and the grid under them cannot say what they say.

**Three things the panel is not.**

1. **Not a skin.** `TooltipBackdropTemplate` is the client's own tooltip
   chrome — the nine-slice `GameTooltip` itself wears — so the panel inherits
   the player's tooltip settings and UI scale rather than imitating them. This
   is the same rule the window follows and for the same reason. GameTooltip
   could not *be* the panel: it is two columns (`AddDoubleLine`) and a warband
   is twenty. If the template is not there to build on, `makeHoverGrid` returns
   nil and the button falls back to the four-line glance — a missing frame
   costs the grid, never the session.
2. **Not a window.** No scrollbar and no click. What does not fit is trimmed by
   the model and **counted out loud** in the footer, which also names the tab
   that has the rest: a hover that quietly showed nine of twenty alts would be
   worse than the summary it replaced. `Roster.Hover` takes the column and line
   budgets as arguments because the model has no idea how wide `UIParent` is —
   `hoverFit` measures the screen and passes them in. Columns come off the end
   of the sorted list, so the character at the keyboard survives every trim, and
   a group header left standing over nothing goes with its rows.
3. **Not a second tooltip surface.** The per-cell detail — which bosses are
   dead, when the lockout resets, how much of a weekly cap is spent — is the
   real `GameTooltip`, hung off the panel's left edge, titled with the
   character's name in their class colour over the row's label in orange. That
   is the half of SavedInstances people actually name, and it is the same
   `cell.tip` the tab already draws.

**Colour is the same grammar the tab uses**, and so is the ink ramp: grey for
labels and group headings, white for values, green / gold / red for the cell
tones, gold for the title, and class colour for a character's name and nothing
else. A colour is a status or an identity, never both.

A group heading here is a grey label over its own rule, at the tab's 10% —
**it was an orange word and no rule at all**, which is a colour standing in for
a line on the one surface that most needs to stay quiet behind its values.
Orange survives where it has no alternative: inside the per-cell `GameTooltip`,
which has no texture to rule a section off with.

**Leaving is a question, not an instruction.** The button and the panel are two
frames sharing a border, so an `OnLeave` on either means nothing on its own —
one `C_Timer.After(0.1)` then asks where the cursor actually ended up, and the
panel closes only if it is on neither. That is what lets the rows be hovered at
all. It is not an `OnUpdate`: the addon's only one is still the drag handler.

##### The summary band

**In SavedInstances, hovering the icon is not the route to the answer — it is
the answer**, and opening a window is the follow-up question. Through 1.9.0
this hover said how many characters were stored and then listed slash commands:
enough to tell you the addon was installed, and nothing about the warband it
had been watching.

A hover carries about four lines before it stops being a glance, so it carries
the four that decide a night — **a vault slot already earned, the keystone in
the bag, what is locked, and what has stopped accruing.** The grid answers each
of those *per character*; the glance answers them *across the warband*, which
is the only shape in which four lines can cover twenty alts. Vault leads
because it is the only one you can lose by not logging in before Tuesday.

`Roster.Glance` is the model and `UI.lua` paints it — the same split the grid
has, so the file with the rules is the file with tests, and both surfaces read
one DB and cannot disagree about it.

**The grid's three rules survive the compression**, and the first is again the
one the format is most likely to destroy:

1. **Absent is not zero.** A character whose vault has never been read is not
   counted as having no slots — it is not counted at all. Every test is "did
   this character have an answer", never "was the answer zero", so an unscanned
   alt is silent rather than reassuring.
2. **A line nobody has a value for is not drawn.** An account with no keystone
   anywhere gets no keystone line, not an empty one.
3. **Names, where a name is what you act on.** "2 characters have a keystone"
   sends you to the grid to find out which; `Vocnar +12` does not. The column
   sort already puts the character at the keyboard first, so the name you check
   the others against leads the line for free.

**Colour is state, never decoration.** The label carries the tone — `vault
ready` green, `saved` gold, `at cap` red — and the names carry their class
colour, which is identity. That is SavedInstances' rule and the reason its
tooltip stays readable at twenty characters.

A label with no tone reads grey, which is the `keystone` line: it used to
arrive in the same white as the `+12` beside it and so said *look here* about
nothing at all.

**Shrink-to-fit is decided, not configured.** A line names at most three
characters and appends `+2` for the rest. This is SavedInstances' fit-to-screen
answered the way this addon answers everything: a tooltip that grows with the
warband ends up covering the minimap it is anchored to, which is the one thing
a minimap tooltip must not do — and `+2` is honest about the omission where
simply stopping at three would not be.

An expired lockout is not counted, by the same absolute-`resetTime` rule the
grid's rows use. The glance refuses harder than the grid does: there is no cell
to hover for the detail that would correct it.

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
  or the slash command, or the keybinding (Key Bindings > Warband.pro),
  all landing on the Export tab
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

