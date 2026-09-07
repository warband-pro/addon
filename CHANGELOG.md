# Changelog

Release notes for Warband.pro. This is what players read, not the commit log.

**One section goes out, not this file.** `tools/notes.mjs` cuts the section matching the tag out of here, and the release workflow hands the packager that and nothing else — so the GitHub release body, the CurseForge and Wago description and the Discord embed all carry one version's notes. See exactly what will publish:

```
node tools/notes.mjs 1.5.0
```

Until 1.5.0 the packager was given this whole file and shipped it whole, header and all history included, and Discord cut it off mid-sentence at 4096 characters. The paragraph you are reading now used to be the first thing every release said.

**The release workflow looks for `## [1.5.0]` exactly.** A tag without a matching heading here fails the release before anything is published. Write the section first, then tag.

**Cutting a release adds a heading, it does not rename `## [Unreleased]`.** Leave that heading in place, empty, above the new one. CI runs `slop.mjs --unreleased` on every push and errors when the section is missing — so renaming it turns `main` red and, on a release run, fails `verify` before the tag is ever created. That is exactly what happened on the first attempt at 1.8.0: the run died in 24 seconds, at the one step that gates everything downstream. `slop.mjs` passes an empty section (`nothing to check`); it is the absent heading it refuses.

It also reads the section for machine-written marketing voice and fails on that — same check, so run it yourself before you tag:

```
node tools/slop.mjs 1.0.2
```

CI runs it against `## [Unreleased]` on every push, so notes written as you go are already clean at tag time. The rules are in [tools/slop.mjs](tools/slop.mjs) and they only flag borrowed phrasing, keynote voice, and adjectives standing in for numbers — the terse fragments and em dashes here are the house style and stay.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [semver](https://semver.org/), anchored to **what the player has to do about it**:

- **MAJOR** — they have to update, or it stops working. `wb1!` → `wb2!`: the website rejects strings from an older addon with "update your addon".
- **MINOR** — something new. A new capture, a new field on the wire, or a new thing the in-game UI does. Nothing they already do breaks, and the website still reads older bundles.
- **PATCH** — a fix. No new capture, no new field, no new control.

**This used to say the wire format was the thing being versioned**, and it stopped
being true one release before it was corrected. 1.5.0 added a minimap button, a
keybinding and an options tab and changed **no wire field at all** — a MINOR by
the rule above and by every instinct, but not by a rule that only knew about
payload shape. 1.1.0 through 1.4.0 all happened to move the wire, so the narrow
rule described four releases in a row and looked settled.

The wire is still the hard edge of MAJOR, because it is the only change a player
cannot absorb by ignoring it — the string in their clipboard stops being
accepted by a website they do not control. That prefix has its own rules, and
they are in [docs/CONTRACT.md](docs/CONTRACT.md), which is law for this repo and
`warband-pro/app` at once. **A wire break is at least a MAJOR here; not every
MAJOR has to be a wire break.**

## [Unreleased]

### Changed

**The addon is now called Warband.pro, not Warband.pro Companion.** There is
already an unrelated addon named Warband Companion, so the two sat next to each
other in every addon manager's search results reading as the same thing. The
name in your addon list, the window title, the minimap tooltip and the Key
Bindings section all say `Warband.pro` now — so if you had the export bound to a
key, that section moved and the binding itself did not. Nothing else changed:
same folder, same `WarbandProDB`, same `/warband`, same saved data, and the
update installs over what you have. It is still the companion to warband.pro;
that is what it does rather than what it is called.

### Fixed

**A build named after your spec stops showing up on warband.pro.** If you play
Protection, the site listed a fourth build called `Protection` beside the ones
you saved, and there was nothing in the talent UI to delete because you never
made it — it was the config you are currently playing, which the game names
after your spec, and the addon was exporting it as though you had saved it.
Only the builds the talent UI lists go out now, so the starter build stays out
too. One export after updating clears the extra one off your character page.

## [1.13.0] — 2026-09-06 — fold away the part of the grid you are not reading

### Added

**Click a group in the Roster grid to fold it away.** Seven groups of rows
against a window that shows about forty of them means you scroll past
professions and pockets every time you want to check a lockout. Click a group's
label — `currencies`, `lockouts`, any of them — and its rows fold up behind the
header, which keeps a `+` and the number of rows it is holding so you can tell
a group you shut from one that had nothing in it. Click it again and they come
back. Which groups are folded is remembered between sessions.

## [1.12.1] — 2026-09-06 — a build you delete stops being exported

### Fixed

**A talent build you delete stops being exported.** The addon added every saved
build it saw and never took one away, so a loadout you deleted in the talent UI
kept going out and warband.pro kept listing it beside the ones you still have.
It now drops a build the client no longer lists for that spec. A scan that
cannot read your saved builds at all still changes nothing, so a bad read on
login does not cost you the ones it captured earlier.

## [1.12.0] — 2026-09-05 — the export says how much rested you have banked

### Added

**The export carries how much rested experience each character has.** It always
sent the rested amount and never the size of the level it belongs to, which
made the number impossible to compare between two characters — 400,000 rested
is over a level at 81 and a fraction of one at 89. Both go out now, so
warband.pro can tell you which of your levelling alts an evening pays double
on.

## [1.11.0] — 2026-09-05 — the set is called what the spec is called

### Changed

**The saved set is named after the spec and wears its icon.** `Protection`,
with the Protection icon — not `warband.pro Protection` with a void crystal.
If you already have a set called `Protection`, that is the one that gets
updated. A set this addon saved under the old name is renamed to the new one
the first time you press equip, so you do not end up with two sets holding the
same gear.

## [1.10.0] — 2026-09-05 — the set you pasted, slot by slot

### Added

**The From warband.pro tab shows the gear set itself.** Under the line that
counts what the button will do, one row per piece: its icon, the slot it goes
in, its name and item level, and where it is right now — `worn`, `in bags`, or
`in your bank` when it needs fetching first. Hover a row for the item's own
tooltip. Before this the tab said `3 to equip · 1 already worn` and left you
to trust it; now you can see which three.

**Trade skill cooldowns, in the Roster grid.** A `cooldowns` group under the
professions, one row per recipe, so the alt whose transmute came off cooldown
yesterday says `ready` instead of you logging into six characters to find out.
A cooldown still running shows the time left; one with charges in hand shows
`2/3`, because a charge you can spend beats a timer still counting. Hover a cell
for the profession, the charges and how long it has been waiting.

They are read while your profession window is open, the same as bags at a
banker — open Alchemy once and the addon knows about it from then on, including
after the cooldown runs out. Opening one profession does not forget the others.

**A switch for the currency rows** — Options → *Show every currency in the
Roster grid*. On, the grid lists every currency any character is carrying, the
way it used to.

### Fixed

**The Roster grid stopped drawing after 24 rows.** If you had a full spread of
currencies and a few professions, everything past about the middle of the
currency list was built and never painted — the scrollbar let you scroll down
into empty space where the rest of your grid should have been. Every row the
grid has is now drawn.

### Changed

**The currency rows are this season's, not every currency you have ever held.**
The grid keeps a currency with a cap, a weekly cap, or something earned towards
it this week by anybody in the warband — and the group header counts what it
left out, so `currencies · 4 hidden` tells you the Timewarped Badges are still
there rather than gone.

**A currency at its cap is red now, not orange.** Orange is nine tenths of the
way there, which is while it is still worth going to spend, or a weekly
allowance you have already earned this week. Red is the one that costs you
something, and it is the colour the minimap hover has used for it since 1.9.0 —
the grid was disagreeing with the hover about the same currency.

**The window resizes, and it opens wide enough for eight characters.** Drag the
corner. It remembers the size and where you put it, so a warband of twelve is a
window you set up once. `<` and `>` are still there for a warband wider than
your screen, but most people will not see them again.

**Row groups have a rule above them and a row lights up under the mouse.**
Reading `1,900/2,000` across twelve columns and landing on the right character
was harder than it needed to be.

**Column names line up with the columns.** They were sitting eight pixels to the
left of the cells they name.

**The export string uses the whole width of the window.** It was wrapping at a
fixed width no matter how wide the window got.

## [1.9.0] — 2026-09-04 — see every alt at once

Everything this addon has been collecting since 1.0 went into a compressed
string and nowhere else. This release gives it a screen.

### Added

**A Roster tab, so you can see what this addon has been collecting.** Until now
it gathered everything and showed you a compressed string. `/warband roster`, or
the new first tab, lays your characters out across the top and everything
tracked about them down the side — vault progress, keystones, raid lockouts as
`killed/total`, currencies against their caps, professions, gold, bag space,
phials and food. It is one screen and you read it across: which of them still
owes a vault slot, which one is holding the crests.

Blank is not zero here, and the difference matters. A cell is empty when that
character has never had that thing read — a bank you have not opened, an alt
you have not played since the patch — and shows a number only when it was
actually looked at. Six characters fit at a time; past that the `<` and `>`
buttons page through the rest.

Nothing about exporting changed. `/warband` still opens straight onto the
string with it already selected.

**Hover any cell for the detail behind it.** The grid stays readable by keeping
cells to two or three characters, so everything they summarise is on the mouse.
A raid lockout says `2/8` and its tooltip names every boss you have killed and
every one still alive, plus how long until it resets. A vault cell lists each
slot, what it needs and whether you have earned it. A currency shows what you
have banked and, underneath, what you have earned against this week's cap —
the one that disappears if you do not spend it. A column header carries realm,
guild, level, item level, gold and where that character logged out.

**A `from warband.pro` section shows what the site last sent you.** Paste a
string from warband.pro and the bottom of the grid fills in, per character: how
many pieces of the gear set you can still put on, how many items are on the
clear-out list and why, how many specs have a build assigned, and how old that
answer is. Finding out which of nine alts had an unapplied plan used to mean
logging into nine alts.

**The minimap tooltip answers the question now, instead of telling you where to
go and ask it.** Hover the icon and you get four lines across the whole warband:
who has a Great Vault slot already earned, who is carrying a keystone and what
level, who is saved to something, and who has a currency sitting at its cap and
throwing away everything they earn towards it. Vault is first because it is the
only one on that list you can lose by not logging in before Tuesday.

Three names to a line, then `+2` for the rest, so the tooltip does not grow past
the minimap it hangs off. A line with nobody on it is not drawn at all, and a
character you have not logged into since the reset does not get counted as saved
to a lockout that has since expired — blank still means nobody looked, the same
as it does in the Roster tab.

### Fixed

**Lockouts that already reset are no longer listed.** If you had not logged a
character in since the weekly reset, the addon was still showing you last
week's raid as though you were saved to it. That cell is now blank, which is
the honest answer: the old lockout is gone, and whether you have picked up a
new one is something nobody has checked yet.

- clear orphaned junk lists when warbank attribution is cleared without removing a character — matches optimize path

## [1.8.0] — 2026-08-31 — one string back, and your builds by name

### Added

**One string comes back from warband.pro now, not two.** The site handed you a
clear-out list on one page and an equip string on another, and you pasted each
separately — so doing half the trip left you with gear and no clear-out list,
and nothing said so. Copy once, paste once, and the panel says what arrived:
"read a clear-out list for 3 characters, gear for 2, talent builds for 2".
Equip strings you already have still read exactly as they did.

**If you have more than 20 characters, the rest of them can finally reach the
site.** One copied string holds 20, and past that the addon cut the oldest ones
off the end — a 41-character warband arrived as your most recent 20, and the
other 21 did not exist there. It goes out a page at a time now: `/warband copy`
is the first 20, and the header says "page 1 of 3 — /warband copy 2 for the
next 20". The site merges the pages, so they add up to your whole warband
rather than replacing each other.

**Your gear sets are per spec now, and switching spec switches the set.** A
paste carries a set for every spec warband.pro solved, not just the one you
were last logged out in — so your tank set and your healing set can both live
in the Equipment Manager instead of one quietly writing over the other. Each is
named for its spec, and the panel says plainly when you have sets but none for
the spec you are in.

**`/warband equip` puts your gear set on without opening the window.** It does
what the button in the Import tab does — equips what it can find, saves the
Equipment Manager set, prints the same receipt — so you can drag it onto an
action bar and swap sets between pulls. In combat it says so and waits; with
nothing pasted yet it says that instead of doing nothing quietly.

**Your named talent loadouts go out with the rest of it.** Keep a "Raid", an
"M+" and a "Delve" build in the talent UI and the export carries all three under
the names you gave them, not just the one you were standing in. If the game will
only hand over the build you are on, the list fills in as you switch.

**The junk panel reads two new verdicts from warband.pro.** It can now tell
you when something in your bags is a copy of what you already have on ("already
wearing one"), and when another item in the same bags beats a piece on item
level and on every stat at once ("you own a better one"). Nothing to set up —
paste your cleanup string as usual. Older versions of the addon show the same
rows with no reason text beside them, so this is worth updating for rather than
something you have to update for.

### Fixed

**Your warband bank stopped losing four tabs out of five.** The game hands the
addon each tab's contents separately, a moment apart, so the first look after
you open the bank often finds one tab loaded and the rest still arriving — and
the addon stored that one tab, threw away the four it already had, and marked
the result as just-checked. If you copied your bundle in that moment, warband.pro
showed a one-tab vault and no sign anything was missing. Tabs now update one at
a time, each carrying its own timestamp, so a tab that did not load keeps what it
had. `/warband status` prints how many tabs you own against how many have ever
been read, and the copy panel says "3 of 5 tabs" instead of letting the
timestamp speak for the whole vault.

**The bank and the reagent bank kept one timestamp between them.** Either one
loading marked both as fresh, so bank contents from your last visit to a banker
could show a green dot on the site. They are two timestamps now, and each moves
only when that container was actually read.

**A bank scan could go missing from the copied string.** The export is rebuilt
only when something has changed, and a bank walk was not registering as a
change — so the contents landed in storage and not in the string you pasted.
Anything that scans now registers.

## [1.7.0] — 2026-08-27 — the shield stays on

**Weapons in your bags now say whether they are two-handed.** The export gave a
two-hander and a one-hander the same slot number, so warband.pro could offer you
a 2H as a main-hand upgrade without noticing the shield beside it — and
equipping that puts the shield in your bags. Tanks, and anyone who holds an
off-hand, were the ones paying for it.

### Added

- Two-handed weapons are marked as such on the export, for bags, bank and
  warband bank. warband.pro reads it already: a suggested two-hander now names
  the off-hand it would unequip, on the slot itself rather than after the fact.
  Fury warriors are left alone, since they wield two. Costs a few bytes, and
  only on weapons.

## [1.6.0] — 2026-08-26 — best in bags, and the set comes back

**warband.pro can now tell you what to equip, and hand you a string that
equips it.** Two halves of the same loop: your bags start reporting what each
item's stats actually are, which is what lets the site rank two pieces against
each other rather than trusting item level; and the answer comes back as one
string you paste into the same box the clear-out list uses.

### Added

- Gear in your bags, bank and warband bank now carries its stat values on the
  export — crit, haste, mastery and the rest, read straight off the item. This
  is what lets warband.pro rank two owned pieces against each other instead of
  trusting item level alone. Equipped gear is unchanged; the website already
  reads its stats from Blizzard. Costs about half a kilobyte per character on
  the wire.
- The equip string. warband.pro's best-in-bags now hands back a `wbg1!` string
  naming the set it picked; paste it into the same box the clear-out list
  uses, and a new row on that tab says what would change — `3 to equip · 1
  already worn · 1 missing (1 in your bank)` — with one button that equips
  the lot and saves it as an Equipment Manager set called "warband.pro".
  Items are found in your bags by identity at the moment you click, never by
  a remembered position, and the set is saved only after the server confirms
  what you are actually wearing. Nothing happens in combat, ever; if a fight
  starts mid-swap the addon says to press the button again after.

### Fixed

- Release descriptions on CurseForge and Wago carry one version's notes now.
  Every release up to and including 1.5.0 published this entire file — the
  instructions at the top, then every version back to 1.0.0 — and Discord cut
  that off partway through.

## [1.5.0] — 2026-08-25 — one window, and three ways into it

**Everything this addon does now lives behind one panel, and there is finally
an icon to open it with.** 1.4.0 added the clear-out list as a second frame, so
there were two windows and no way from one to the other. This is one window
with tabs along the bottom the way the game's own panels do it, built from
Blizzard's frame templates so it follows your UI scale and fonts with no
setting of its own. Open it from the minimap, a key, the addon compartment or
`/warband`.

### Added

- A minimap button. Click it for the export string, right-click it for the
  options, drag it anywhere round the ring. Hovering says how many characters
  are stored and how fresh the freshest one is, which is usually the whole
  question. `/warband minimap off` takes it away and the addon compartment
  still opens the window.
- A keybinding. Key Bindings > Warband.pro Companion > Open the export window,
  so the four to ten exports a play night cost one key instead of typing into
  chat. It ships unbound — picking a key for you would take one you had
  already spent.
- An Options tab. Gear capture and item links were slash-and-SavedVariables
  toggles before; they are checkboxes now, and `/warband gear on|off` still
  works.
- Open the clear-out list at merchants — off by default. When a merchant
  window opens and the list has something in your bags, the Import tab opens
  by itself and closes when you leave the merchant.
- `/warband options` opens the window on that tab.
- The panel says `copied` when you press Ctrl+C, and `/warband status` reports
  when you actually copied rather than when you last opened the window.
- One line on your first login after installing, naming the command. Nothing
  else this addon does prints anything, which is right every night except the
  first.
- The clear-out list says what to do with each item, not only why it is on the
  list. An item warband.pro says to delete by hand no longer shows a Sell
  button — the game would not let that button work anyway.
- A paste into the clear-out box now says what it read, and says so when it
  replaced a list you already had.

### Changed

- One window instead of two. `/warband junk` goes to the Import tab; the
  clear-out list, its paste box, Sell and Disenchant all live there and work
  as before. Esc still closes, the export string still selects itself.
- One icon everywhere. The addon compartment, the window's portrait and the
  minimap button are the same purple crystal. It used to be a bag, which is
  hard to pick out of a ring of other brown icons.
- The tabs are named by direction: `To warband.pro` and `From warband.pro`.
  They read Export and Import, which is backwards from the site's own words:
  the site calls receiving this string an import, so a player who had just
  clicked import in the browser opened the tab called Import and was on the
  wrong one.
- Step 2 of the copy instructions says what the site actually does: press `i`,
  paste, Enter. It said "warband.pro > Import", a destination that never
  existed.
- Combat now closes only the Import tab (its buttons cannot be rewritten
  mid-fight). An export string left open through a ready-check stays open.

### Fixed

- Three warnings on every login, from `Bindings.xml` being listed in the
  `.toc` as well as loaded by the client. The keybinding also sat under a
  heading called WARBANDPRO as a row called WARBANDPRO_TOGGLE; it reads as
  words now.
- Pasting a cleanup string into the clear-out panel errored before the
  decoder ever ran: the `wbc1!` prefix was defined in the test fixture but
  not in the addon.
- Junk lists now clear when their character is gone — even from a manual
  SavedVariables edit. Matches the warbank orphan guard that already ran on
  every optimize.

## [1.4.0] — 2026-08-23 — the clear-out panel

**The first thing warband.pro has ever sent back.** Until now this addon only
talked outward: you pasted a string into the site and that was the end of the
conversation. `/warband junk` is the other half. Copy the cleanup list off
warband.pro's gear page, paste it here, and you get a list of what to get rid
of — with a Sell button that works at any merchant and, if you are an
enchanter, a Disenchant button beside it.

### Added

- `/warband junk` — the clear-out panel. Paste box at the top, one row per
  item, an age line so you can see how old the list is.
- Sell at a merchant. The button is dark until a merchant window is open, and
  the item it sells is the one on that row.
- Disenchant, for enchanters. This is your click, not the addon's — the game
  does not allow an addon to cast for you, and this addon does not try. Your
  profession is checked when the panel draws, not when the list was made, so
  dropping enchanting does not leave a button that casts nothing.
- Grey vendor trash is listed too, and it never came from the website. Your
  bags right now are the only honest source for that, and the site's copy is
  as old as your last paste.
- `wbc1!`, the return format. Its own prefix rather than the reserved `wb2!`,
  which is still for a breaking change to the export string.

### How it finds your items

**Not by bag position.** The list is made from an export you took earlier, and
by the time it comes back you have looted, sold, sorted and run a dungeon —
bag slot 14 is not what it was. Selling by remembered position would eventually
sell the wrong thing, so the panel matches items by their full item string and
takes the position from the bags as they are at that moment.

A consequence worth knowing: items you have already got rid of, or moved to the
bank, simply drop off the list, and the header counts them as no longer in your
bags. Two copies of the same item both get listed from one entry.

### Safety

- The panel closes when you enter combat and comes back when you leave. Nothing
  is rewritten mid-fight, which is also why nothing goes stale behind you.
- Pasting your export string into the paste box says so, rather than calling it
  invalid — it is a perfectly good string, just the wrong direction.
- The decoder is hand-written and reads exactly one shape. It does not run
  anything it reads, and 49 tests run against it on every push, including the
  real string the website produces.
- Nothing is ever deleted. The panel can say an item is worth deleting; the
  keystrokes are yours.

## [1.3.0] — 2026-08-23 — bag gear actually reaches the wire, and it has a name

**Every bag, bank and warband-tab gear entry was being dropped before it
reached the wire — since 1.1.0.** The classifier read `GetItemInfoInstant`'s
icon (return 5) where it meant the equip location (return 4). The lookup that
sorts an item into its slot is keyed by `INVTYPE_*` strings, an icon file id
matches none of them, and every owned item fell through. Equipped gear walks
fixed slot numbers and never consults the equip location, so the export looked
populated the whole time — warband.pro's best-in-bags, upgrade column and
cleanup list have been reading an empty array for two minor versions. Found
from a user's real export: 16 `gear[]` entries, all `where:"equipped"`, beside
a bag holding seven items another tool could see.

### Fixed

- Bag, bank and warband-bank gear entries are captured again. One destructuring
  read `equipLoc` at the wrong position; `tools/gear-test.lua` now stands a
  fake client in front of the classifier — with a valid `INVTYPE_*` string
  planted in the icon position — so this exact drift sorts items into the
  wrong slot and fails CI loudly instead of dropping them and passing as an
  empty bag.
- A ding is noticed when it happens. `Scan.Identity` — the pass that reads your
  level, XP, rested XP, zone and item level — only ran at login and on a loading
  screen. Level in the open world, type `/warband copy`, and the string carried
  the level you were an hour ago; it corrected itself the next time you zoned or
  logged out. `PLAYER_LEVEL_UP` and `PLAYER_LEVEL_CHANGED` now run the same pass,
  one second later so `UnitLevel` has caught up.

### Added

- Owned gear entries carry five new optional fields, so warband.pro's cleanup
  view can name what it judges: `n` (display name, from the item's own
  hyperlink — the website has no item-id-to-name lookup), `q` (numeric
  quality), `b` (soulbound, sent only when true — absence means not bound),
  `cls` and `sub` (item class and subclass ids, which is what lets the website
  call plate on a mage unwearable). Equipped entries never carry them: the
  Profile API already answers all five for what is worn. All additive on
  `wb1!`; older bundles keep decoding.

- Measured on the six-character sample: **+0.85KB of JSON and +0.15KB of wire
  per character**, or about +3KB of wire at the 20-character cap. Names repeat
  their words across a warband and deflate folds the repeats. Update and paste
  again; nothing about your stored data needs clearing.

## [1.2.0] — 2026-08-21 — every vault slot, not only the summary

**The Great Vault has two axes and this addon was sending one.** A raid slot
has a threshold *and* a difficulty it will pay at, and the difficulty is not
chosen — the game pays each slot at the difficulty of the kill sitting at that
slot's threshold, so slot 1 pays your second best kill and slot 2 your fourth.
What went on the wire was one collapsed summary per row: the furthest any slot
had got, and the *next* threshold still reachable. The thresholds of slots
already earned were gone with it, so warband.pro could not say the most useful
sentence there is about a raid night — that the slot you already own goes up a
difficulty if you kill one more boss — and told a live camp `2 more for vault
slot 2` when slot 1 was already theirs at normal, one heroic kill from paying
heroic.

- **`weeklyVault.rows[]`, per bucket.** One entry per slot: its own threshold,
  its own progress, the client's raw `level`, and — on the raid row — the
  difficulty that level resolves to. About 90 bytes per bucket before deflate
  folds the repeated keys; the new `v1-vault` contract vector round-trips 705
  bytes of JSON to 476 on the wire.
- **The difficulty is resolved here rather than guessed at by the website.**
  `level` means a different thing on every row — a keystone level on mythic+, a
  difficulty id on raid — so it is looked up against the client's own
  difficulty table, on the raid row only, and left out entirely when that
  lookup declines to answer. `GetDifficultyInfo(14)` returns "Normal" whether
  the 14 arrived as a raid difficulty or as a +14 key, and a plausible wrong
  answer is worse than none at all.
- **`level` is no longer sent on the raid bucket.** It was a max across slots,
  which is fine for a keystone level and wrong for a difficulty id: raid ids
  sort LFR (17) above Mythic (16), so the "best" slot it named could be the
  worst one. Nothing ever read it, and `rows[].d` is what it was reaching for.
- **Wire stays `wb1!`.** `rows` is additive and optional. A site that ignores
  it reads this bundle exactly as it read the last one, and warband.pro still
  reads bundles from every earlier version.

- **Fixed** — a bag move rebuilt `gear[]` from a fresh walk of every container,
  closed bank and warband tabs included. A closed bank reports no slots, so
  bank and warband-tab gear could vanish from the next bundle until you stood
  at a banker again. Bag, bank, and warband-tab gear are now tracked
  separately and only replaced when that scope is actually rescanned.
- **Added** `/warband perf` — scan timing per section, container and slot
  counts, item-info cache hit rate, and addon memory.
- Moving one item no longer walks the bank and every warband tab checking for
  gear and consumables — each scope now walks only its own containers.
- Container, gear, and talent scans hold off during combat and run the moment
  it ends, the same way the export panel already does.
- `/warband status` and a repeat `/warband copy` no longer rebuild and
  recompress the whole bundle when nothing has changed since the last call.

## [1.1.0] — 2026-08-20 — gear and talents on the wire

**warband.pro's gear profile and SimC exporter shipped reading only the
Blizzard API, which already covers everything equipped.** What it cannot see
is inventory — a bag or bank holding a better piece than what you're
wearing — and that is what this release sends.

- **`gear[]`, per character.** Every equipped item, plus anything in a bag,
  personal bank, or warband bank that could be equipped. Each entry carries
  the item string verbatim — the same substring SimulationCraft's own addon
  exports, and the same one the in-game item link uses between `|H` and
  `|h` — so bonus IDs, enchant, gems, and crafted-stat choices all make the
  trip losslessly, along with the item level Blizzard's API cannot see for
  anything you are not wearing. Shirt and tabard are skipped everywhere, same
  as the website's own gear model.
- **`talents`, per character.** The active spec's talent loadout string, plus
  every other spec you have played on that character — only the spec you are
  standing in is readable at any moment, so the list fills in over time rather
  than replacing itself.
- **`race`, per character.** The last field the SimC exporter needed that
  this addon was not already sending.
- **`/warband gear on` / `off`.** Gear capture is on by default. Turning it
  off leaves what was already captured in place and just leaves it out of the
  next copied string — turn it back on and it is there again, no rescan
  required. `/warband status` now reports gear piece count and known specs.
- **Wire stays `wb1!`.** Both fields are additive and optional; warband.pro
  reads bundles from every earlier version exactly as before, and a bundle
  from this version still imports on a site that has not added support for
  the new fields yet.

No breaking change, no migration. `docs/CONTRACT.md` documents the item-string
parse rules for anyone building against this.

## [1.0.2] — 2026-08-20 — fix the empty export box

**If `/warband` gave you an empty box on 1.0.0 or 1.0.1, this is the fix.** Update and it works.

- **Empty export box fixed.** The panel would say "Could not build the bundle" and hand you nothing, no matter how many characters were stored. The addon vendors LibDeflate to compress your bundle, and on any client where another addon had already registered LibDeflate first, ours never reached the addon and compression could not run. That is the common case, not the rare one — LibDeflate ships inside a lot of addons. We now fall back to the copy already loaded.
- **`/warband status` says why a build failed.** The panel points at `status` for the detail, and `status` was not showing it. A failed bundle now prints its reason on its own line.
- **WoWInterface placeholder removed from the `.toc`.** It was set to `00000`. Harmless while no WoWInterface token exists, but the moment one was added the packager would have attempted an upload to a project that does not exist and failed the release instead of skipping the site.
- **Docs.** `/warband dump` was documented in the README and wiki but has never existed. Removed. Wiki troubleshooting also gave the wrong cause for an empty string and now leads with `/warband status`.

No wire format change. Still `wb1!`, still `v: 1`, and warband.pro reads 1.0.0 and 1.0.1 bundles exactly as before.

One correction to the 1.0.0 notes: this addon still ships no LibStub and registers nothing with it, but it will now *read* one that another addon provides, which is what the fix above does.

## [1.0.1] — 2026-08-19 — wire CurseForge auto packaging

- Set `## X-Curse-Project-ID: 1660174` so BigWigs packager targets the real CurseForge project instead of placeholder 000000. Enables CurseForge automatic packaging via org secret `CF_API_KEY`.
- No code changes, no wire format change, still `wb1!`.

## [1.0.0] — 2026-08-19 — Warband.pro Companion launch

First CurseForge release.

**Warband.pro Companion** — companion addon for warband.pro (https://warband.pro). You play normally, log alts 2..6 through the week with zero extra steps — account-wide `WarbandProDB` GUID-keyed updates silently on login, bag move (.5s throttle), bank open, vault open, mail.

Any char: `/warband` → auto-highlighted box → Ctrl+C copies `wb1!aH...` (multi-char bundle default, 4-7KB for 6 chars, ~26KB with full bag contents). Paste on warband.pro Import (hotkey `i`) → preview 🟢🟡🔴 → Confirm. Missing chars stay ⚪ never, stale just lowers confidence.

What it captures — Altoholic + SavedInstances superset, pruned Midnight 12.1:
- Bags, bank+bags, reagentBank, warbandBank with seenByGuid/tabs
- Gold, currencies with weeklyMax/isAccountWide — Crests, Flightstones, Tender
- Professions skill/max, mail count+goldPending, auctions count+goldHeld
- Lockouts LFR/N/H/M with bosses killed + resetTime, worldBosses
- Keystone level/dungeonID, M+ runs timed/chest, score, weeklyVault raid/mplus/world thresholds
- Consumables rollup for Tonight Plan, per-section seenAt for staleness dots

Trust: no network ever, <200KB for 6 chars, no OnUpdate scanner, copy-only, vanilla Lua no Ace3/LibStub, zero deps except vendored LibDeflate MIT zlib (license in Vendor/LibDeflate.lua header).

Retail Midnight 12.1 only. Works with whatever UI you run.

Then future tags auto-upload via BigWigs packager once Project IDs are set.

[Unreleased]: https://github.com/warband-pro/addon/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/warband-pro/addon/releases/tag/v1.5.0
[1.4.0]: https://github.com/warband-pro/addon/releases/tag/v1.4.0
[1.3.0]: https://github.com/warband-pro/addon/releases/tag/v1.3.0
[1.2.0]: https://github.com/warband-pro/addon/releases/tag/v1.2.0
[1.1.0]: https://github.com/warband-pro/addon/releases/tag/v1.1.0
[1.0.2]: https://github.com/warband-pro/addon/releases/tag/v1.0.2
[1.0.1]: https://github.com/warband-pro/addon/releases/tag/v1.0.1
[1.0.0]: https://github.com/warband-pro/addon/releases/tag/v1.0.0
