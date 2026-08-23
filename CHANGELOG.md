# Changelog

Release notes for Warband.pro Companion. The packager sends the section matching the tag to CurseForge, Wago, and WoWInterface verbatim, so this is what players read — not the commit log.

**The release workflow looks for `## [1.0.1]` exactly.** A tag without a matching heading here fails the release before anything is published. Write the section first, then tag.

It also reads the section for machine-written marketing voice and fails on that — same check, so run it yourself before you tag:

```
node tools/slop.mjs 1.0.2
```

CI runs it against `## [Unreleased]` on every push, so notes written as you go are already clean at tag time. The rules are in [tools/slop.mjs](tools/slop.mjs) and they only flag borrowed phrasing, keynote voice, and adjectives standing in for numbers — the terse fragments and em dashes here are the house style and stay.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [semver](https://semver.org/), with the wire format as the thing being versioned:

- **MAJOR** — `wb1!` → `wb2!`. The website rejects old strings with "update your addon".
- **MINOR** — a new optional field or capture. The website still reads older bundles.
- **PATCH** — a fix. Payload shape unchanged.

The wire contract itself is specified in [docs/CONTRACT.md](docs/CONTRACT.md).

## [Unreleased]

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

[Unreleased]: https://github.com/warband-pro/addon/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/warband-pro/addon/releases/tag/v1.3.0
[1.2.0]: https://github.com/warband-pro/addon/releases/tag/v1.2.0
[1.1.0]: https://github.com/warband-pro/addon/releases/tag/v1.1.0
[1.0.2]: https://github.com/warband-pro/addon/releases/tag/v1.0.2
[1.0.1]: https://github.com/warband-pro/addon/releases/tag/v1.0.1
[1.0.0]: https://github.com/warband-pro/addon/releases/tag/v1.0.0
