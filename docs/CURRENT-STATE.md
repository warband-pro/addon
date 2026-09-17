# Current State — the companion addon

What this addon actually does today, read off the tree at `41bfbbc`
(`release: 1.15.0`) rather than off the intent.

**Intent lives in the app repo.** The product's vision — the four pillars, the
product principles and the Opportunity Test every proposal answers — is one
document, `warband-pro/app` at **`.wiki/wiki/topics/vision.md`**, with the app's
own delivery against it at `.wiki/wiki/topics/current-state.md`. That repo is
private; this one is public and MIT, so the vision is referenced here and never
copied. The four pillars, one line each:

- **Camp** — the small subset of the warband the player actually plays. Camp is
  the default scope for everything on the site.
- **Tonight** — one ranked list of next-best activities across the camp. Every
  other pillar pays off here.
- **Gear** — replaces AskMrRobot: Best in Bags, upgrade planning, the Great
  Vault choice, gems and enchants, the clear-out list, and the round trip back
  into the game.
- **Progress** — replaces completionism.com: collections, trading post,
  achievements, reputations, events, decor.

**This addon's job in that.** The Battle.net API covers who a character is and
what they wear. **This addon covers everything the API cannot see**, and it does
it under one hard promise: *no network calls, ever.* The player copies a string
by hand; nothing leaves the client on its own.

The boundary that falls out of it, and the one to carry: **the addon renders
facts and the app renders judgements.** The grid states the vault, the lockouts,
the currencies and the gold; it never ranks a character or prices an item.
`wbc1!` is the deliberate exception and proves the rule — it carries a decision
the addon *acts on* under a click and never draws as a readout.

> **When you ship a change that alters a captured field, the wire, or what a
> paste does, update this file in the same PR.** It is the one document nothing
> forces you to touch.

---

## 1. Architecture at a glance

**Toolchain.** Lua 5.1 (what the client runs), Retail Midnight
`## Interface: 120100`, luacheck at zero warnings, Node 22 for `tools/`. No
`package.json`, no dependencies in either direction. LibDeflate is the one
vendored file.

**Layout.** Flat root, loaded in `WarbandPro.toc` order — vendor → namespace →
data → UI → `Core.lua` last, because Core registers the events.

| File | What it owns |
|------|--------------|
| `Init.lua` | Namespace, the wire prefixes and caps, `ns.safe`, the throttle and dirty-set schedulers |
| `Store.lua` | The only writer of `WarbandProDB`; the 14 stamped sections |
| `Scan.lua` | Every read of the WoW API for the current character |
| `Instances.lua` | Lockouts, world bosses, keystone, M+ history, the Great Vault |
| `Cooldowns.lua` | Trade-skill cooldowns (readable only with the profession window open) |
| `Gear.lua` | Item classification, the equipped/owned scopes, talent capture |
| `Bundle.lua` | Canonical JSON and the payload shape |
| `Export.lua` | JSON → raw deflate → base64url → `wb1!` |
| `Import.lua` | The inverse, plus the `wbc1!`/`wbg1!` readers |
| `Junk.lua` | The stored clear-out list resolved against live bags |
| `GearSet.lua` | The stored equip string: resolve, apply, verify, save |
| `Roster.lua` | The pure display model for the grid |
| `UI.lua` | Every frame — one window, four tabs |
| `Core.lua` | The event table, the dispatcher, `/warband` |
| `Perf.lua` | `/warband perf`, purely additive |

**The two directions.**

- **Out — `wb1!`** — `Bundle.Build` → `Bundle.JSON` (canonical: sorted keys, no
  whitespace, empty table → `[]`) → `LibDeflate:CompressDeflate(level 9)`, raw
  deflate with no zlib header → hand-rolled base64url with no padding → the
  `wb1!` prefix. Capped at 20 characters a page; an oversize warband is **paged
  by character**, never truncated silently, and the site merges pages rather
  than replacing its roster.
- **In — `wbc1!`** (and the pre-1.8.0 equip-only `wbg1!`) — length cap 40 KB,
  base64url decode, inflate, 512 KB decoded cap, then a hand-written recursive
  descent JSON reader with a depth cap of 16. **Nothing is executed** — there is
  no `loadstring`, and `tools/validate.mjs` fails the build on any runtime
  code-building call.

`docs/CONTRACT.md` is the law for both directions.

---

## 2. What this addon captures, by pillar

### Serves Tonight (the app ranks these)

| Captured | Where | Reaches the app's ranking? |
|----------|-------|:--:|
| Great Vault — `raid`/`mplus`/`world`/`pvp` buckets, with per-slot `rows[]` | `Instances.Vault`, `Instances.lua` | **yes**, except `pvp` |
| Keystone in the bag — level, dungeon | `Instances.Keystone`, `Instances.lua` | **yes** |
| Owned gear — `gear[]` with `where`, `ilvl`, `st` stat map, `set` tier id | `Gear.Visit`, `Gear.lua` | **yes** (Best in Bags, the `equip` line) |
| Level, XP, `restXP`, `xpMax` | `Scan.Identity`, `Scan.lua` | **yes** for level; rested is display-only |
| Consumables — `phial` | `Scan.Consumables`, `Scan.lua` | **note only**, never scored |
| Lockouts, world bosses | `Instances.Lockouts`, `Instances.lua` | the app prefers the API's own lockout read |

### Serves Gear

`gear[]` in four scopes (`equipped`, `bag`, `bank`, `warbank`), with the
verbatim item string `s` rather than a decomposed model; `talents` with every
saved loadout per spec; `professionCooldowns`; the warband bank at the payload
root (five tabs repeated across six characters costs ~22 KB for one shared
vault).

### Serves Progress

`tradingPost` at the payload root, added in 1.15.0 — `tender`, `month`,
`items[]` (this month's shelf with `purchased`), `activities[]` (the traveler's
log). **This is the only Progress capture that exists.** See §5.

### Captured, and the app reads it but never ranks it

`gold`, bag and bank free space, `mail` (`countMails`, `countItems`,
`goldPending`, `soonestExpiryHours`), `currencies[]`, `auctions.countActive`,
`professions`, `mythicPlusScore`, `instances` detail.

### Not captured at all — deliberately

- **Reputations.** No `C_Reputation` call anywhere.
- **Collections** — mounts, pets, toys, transmog, achievements, housing decor.
  The app gets the first four from Battle.net; **decor ownership has no API at
  all** (`/profile/user/wow/collections/decor` 404s), so the app's milestone
  names an addon capture as its only fallback and it does not exist yet.
- **Playtime.** `RequestTimePlayed()` prints into the player's chat frame, so it
  stays unbuilt on purpose (`docs/CONTRACT.md`).
- No combat log parsing, no aura reads, no other characters' data.

### Named in the contract, produced by no code today

`bankBags`, `bindZone`, `playtimeSec`, `auctions.goldHeld`, `mail.seenAt`,
`professions.expansionTier` / `knownRecipes` / `totalRecipes`, `instances.lfgID`.
Also `consumables.healthPotion` and `consumables.tempPotion` — both are gated on
`POTION_IDS` in `Scan.lua`, **which is an empty table**, so neither field is
ever emitted.

---

## 3. Events and freshness

40 event names are registered in one table in `Core.lua`, each inside its own
`pcall` so an unknown name on a given client is skipped rather than fatal.
Nothing polls: the only `OnUpdate` in the addon is installed by the minimap
button while it is being dragged.

Two clocks decide everything, and which one a feature is on is the design
question:

- **The addon's clock** is automatic and event-driven over about forty events,
  so the bundle is already fresh and the player never decides to scan.
- **The player's clock** is manual and deliberate, and fires when something
  changed enough to be worth a paste.

**Freshness is per section, and absent is never zero.** Fourteen stamps live in
`seenAt` — `bag, bank, reagentBank, warbank, currency, instance, vault, mail,
auctions, profession, professionCooldown, gear, talents, tradingPost` — plus
`lastSeen`. A stamp moves only if that section was actually read this pass, and
a section that could not be read goes **missing rather than throwing**. Every
WoW API call goes through `ns.safe`, 75 call sites across ten files, because
Midnight renamed enough of the container and bank surface that a nil field must
cost one section of one snapshot and never a Lua error mid-raid.

`free: null` with `items: []` means "never opened". `maxQuantity: 0` means
uncapped. The single documented exception to absent-≠-empty is `restXP` when
`xpMax` is present, where an absent `restXP` is a real zero.

---

## 4. The return leg — and what acts without a click

A paste **decodes and stores, and does nothing else.** `wbc1!` carries up to
four sections per character: `items` (clear-out verdicts), `gear` (a solved set
per spec), `builds` (which saved talent build is the raid one) and `shop` (gems
and enchants to buy). Only guids already in `db.chars` are kept, and an absent
section is skipped rather than cleared.

Every game-state action is behind a click or a typed command:

| Action | What triggers it |
|--------|------------------|
| Sell one bag slot | the row's `[Sell]` button, which re-checks the merchant is still open |
| Disenchant | a **secure** `SecureActionButtonTemplate` the player clicks; the addon only bakes the macro text out of combat |
| Delete | **never.** No button is drawn for a `del` verdict and nothing in the addon deletes an item |
| Equip the set, load the build, save the Equipment Manager set | the `Equip N & save set` button, or `/warband equip [raid\|mplus\|delve]` |
| Auction-house search | a left click on a shopping row, and only while the AH is open |

Three things happen without a second click, stated plainly because the promise
deserves the audit:

1. **`GearSet.Verify`** writes an Equipment Manager set off
   `PLAYER_EQUIPMENT_CHANGED` — but only ever as the tail of an `Apply` the
   player started, and it aborts if combat begins.
2. **Auto-opening the Import tab at a merchant**, behind `opts.autoJunk`,
   **default off**. It opens a window; it sells nothing.
3. **Combat logging** — `LoggingCombat(true/false)` on zoning, behind
   `opts.autoLog`, **default off**, raids only.

No equip starts in combat, the Import tab cannot be entered in combat, and
dirty scopes are held back until combat ends.

---

## 5. Gaps and drift

Each of these is a GitHub issue labelled `agent` in the repo it belongs to.

| # | Finding | Evidence | Proposed resolution |
|---|---------|----------|---------------------|
| A1 | **The trading post's five event handlers are defined and never registered.** `handlers.PERKS_PROGRAM_OPEN`, `PERKS_PROGRAM_DATA_REFRESH`, `PERKS_PROGRAM_CURRENCY_REFRESH`, `PERKS_ACTIVITIES_UPDATED` and `PERKS_ACTIVITY_COMPLETED` exist in `Core.lua`; none of those names is in the `EVENTS` table. So `Scan.TradingPost` runs **only** from `Scan.All()` at `PLAYER_LOGIN` — opening the trading post never refreshes the shelf, and buying something never marks it purchased until the next login. | grep: `PERKS` occurs nowhere else in the addon | Add the five names to `EVENTS`. `/warband status`'s "N of M events registered" counts only the registered list, so it could not surface this — a `freshness-test.lua` case that asserts every defined handler is registered would. |
| A2 | **Nothing on the app side reads `tradingPost`.** The addon has shipped it since 1.15.0; the app's parser does not declare the field. | app repo: zero references | App-side work. Filed there. |
| A3 | **`consumables.healthPotion` and `tempPotion` are specified and never emitted** — `POTION_IDS` is empty. | `Scan.lua` | Either fill the table or delete the two branches and the contract lines, so the wire stops describing a field it never sends. |
| A4 | **Housing decor ownership has no capture**, and the app's milestone names this addon as the only possible source. | app milestone Phase 4 | A decor scan is a new subject; decide whether it belongs here before the app's Phase 4 starts. |
| A5 | **The Great Vault `pvp` bucket is captured and ranks nowhere.** | `Instances.lua` sends it; the app has no `pvp` activity kind | App-side decision: rank it, or state that PvP is out of scope. |

**Principle check.** No network calls — grepped every `.lua`, `.toc` and `.xml`
outside `Vendor/` for `SendAddonMessage`, `C_ChatInfo`,
`RegisterAddonMessagePrefix`, `SendChatMessage`, `BNSendGameData`, `C_Club`,
`socket`, `http` and any URL. Three hits, all inert: two `## X-Website:`
metadata lines in the `.toc`, and the word "trip" inside a prose comment. The
only outbound-shaped call is `C_AuctionHouse.SendBrowseQuery`, which is a local
search inside the game client, behind a click. No telemetry, no auto-upload, no
payment path. **Clean.**

---

## Last verified

**2026-09-17**, at `41bfbbc` (`release: 1.15.0`). Every file named here exists
at that commit.

## See also

- [`README.md`](README.md) — the read order for the twelve reference documents.
- [`CONTRACT.md`](CONTRACT.md) — the law for `wb1!`, `wbc1!` and `wbg1!`.
- [`FLOW.md`](FLOW.md) — who the player is and what the loop is.
- [`TESTING.md`](TESTING.md) — the pure/impure split.
- `warband-pro/app` `.wiki/wiki/topics/vision.md` — the product vision (private repo).
