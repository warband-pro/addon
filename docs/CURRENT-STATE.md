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
| Great Vault — `raid`/`mplus`/`world`/`pvp` buckets, with per-slot `rows[]`, the example `r`, and the generated `vaultChoices` | `Instances.Vault`, `Instances.lua` | **not yet** — captured for `app#313`; `pvp` ranks nowhere (A5) |
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

`/warband gear off` withholds `gear[]` from the export without losing the
capture — and the omission is now a documented signal rather than a bare
absence: the strip keeps `seenAt.gear`, so the site reads the stamp without
the data as "withheld" and keeps what it holds, and the export tab header
says so while the toggle is off (`CONTRACT.md` § Withheld gear).

### Serves Progress

**Two captures, and both exist because Blizzard publishes nothing.** That is
what they have in common and it is the whole shape of this pillar's half of the
addon: everything else here supplements an API, and these two replace one.

`tradingPost` at the payload root, added in 1.15.0 — `tender`, `month`,
`items[]` (this month's shelf with `purchased`), `activities[]` (the traveler's
log). Blizzard publishes *nothing* about the trading post — seven paths, all
404. The app reads it, joins the shelf to what the account already owns, and
ranks what is leaving this month as a deadline.

`decor` at the payload root, added in 1.16.0 — `owned[]` (item ids, ascending
and deduped) and `unmatched` (owned entries the client would not name). Read
from `C_HousingCatalog`'s searcher when the housing catalogue is opened, and
**not** from `Scan.All`: it is the whole catalogue plus an info read per entry,
which is the bank's weight rather than the shelf's. Blizzard publishes the decor
*catalogue* and no ownership for it — `/profile/user/wow/collections/decor` is
the one collection path that 404s rather than refusing a wrong credential — so
this is the only section on the wire with no Battle.net fallback at all.

### Captured, and the app reads it but never ranks it

`gold`, bag and bank free space, `mail` (`countMails`, `countItems`,
`goldPending`, `soonestExpiryHours`), `currencies[]`, `auctions.countActive`,
`professions`, `mythicPlusScore`, `instances` detail.

`currencies[].icon` (1.17.0) is the one field here the app does not read at all
and is not meant to: it is the client's `iconFileID`, captured so the in-game
grid can draw a currency's icon beside its name for an alt whose currency list
logged out with them. A file id resolves on the WoW client and nowhere else, so
this is a stored-for-the-addon field rather than an unfinished crossing.

### Not captured at all — deliberately

- **Reputations.** No `C_Reputation` call anywhere.
- **Collections** — mounts, pets, toys, transmog, achievements. All five come
  from Battle.net directly, so capturing them here would be a second answer to a
  question that already has one. Housing decor moved off this list in 1.16.0 and
  is under *Serves Progress* above, because it is the one the API cannot
  answer.
- **Playtime.** `RequestTimePlayed()` prints into the player's chat frame, so it
  stays unbuilt on purpose (`docs/CONTRACT.md`).
- No combat log parsing, no aura reads, no other characters' data.

### Named in the contract, produced by no code today

`bankBags`, `bindZone`, `playtimeSec`, `auctions.goldHeld`, `mail.seenAt`,
`professions.expansionTier` / `knownRecipes` / `totalRecipes`, `instances.lfgID`.

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
auctions, profession, professionCooldown, gear, talents, tradingPost, decor` — plus
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

A paste **decodes and stores, and does nothing else.** It reads on the Import
tab (`/warband import`, also `junk`), and since 1.25.0 a site string pasted
into the export box is handed to that same reader rather than reverted; a
refused paste stays selected so the next one replaces it. `wbc1!` carries up to
four sections per character: `items` (clear-out verdicts), `gear` (a solved set
per spec), `builds` (which saved talent build is the raid one) and `shop` (gems
and enchants to buy). Only guids already in `db.chars` are kept, and an absent
section is skipped rather than cleared.

Every game-state action is behind a click or a typed command:

| Action | What triggers it |
|--------|------------------|
| Sell one bag slot | the row's `[Sell]` button, which re-checks the merchant is still open. Drawn only for rows `Junk.Sellable` accepts — never a `del` row, and never an item the client gives a sell price of 0, which the vendor would refuse |
| Sell the whole list | the `Sell list (N)` button on Blizzard's `MerchantFrame`, then a `StaticPopup` confirm stating the count, the take and that buyback is available. The plan is `Junk.SellPlan` — `Junk.Sellable` **and** a verdict of `sell`, so never a `de` row on an enchanter, never a `del` row, never an unsellable one — and it is rebuilt at the confirm, not read off the button's label |
| Disenchant | a **secure** `SecureActionButtonTemplate` the player clicks; the addon only bakes the macro text out of combat |
| Delete | **never.** No button is drawn for a `del` verdict — nor for an unsellable item, whose verdict falls back to `disenchant` or `delete by hand` — and nothing in the addon deletes an item |
| Equip the set, load the build, save the Equipment Manager set | the `Equip N & save set` button, or `/warband equip [raid\|mplus\|delve]`. The receipt ends by asking for a fresh export, because the site cannot see the equip until one lands |
| Auction-house search | a left click on a shopping row, and only while the AH is open |

Three things happen without a second click, stated plainly because the promise
deserves the audit:

1. **`GearSet.Verify`** writes an Equipment Manager set off
   `PLAYER_EQUIPMENT_CHANGED` — but only ever as the tail of an `Apply` the
   player started, and it aborts if combat begins.
2. **Auto-opening the Import tab at a merchant**, behind `opts.autoJunk`,
   **default off**. It opens a window; it sells nothing. The `Sell list (N)`
   button appears on the same event and is the same shape of promise: it draws
   itself, and nothing is sold until the player clicks it and confirms.
3. **Combat logging** — `LoggingCombat(true/false)` on zoning, behind
   `opts.autoLog`, **default off**, raids only.

No equip starts in combat, the Import tab cannot be entered in combat, and
dirty scopes are held back until combat ends.

---

## 5. Gaps and drift

Each of these is a GitHub issue labelled `agent` in the repo it belongs to.

| # | Finding | Evidence | Proposed resolution |
|---|---------|----------|---------------------|
| ~~A1~~ | ~~The trading post's five event handlers are defined and never registered.~~ **Closed 2026-09-17.** All five `PERKS_*` names are in `EVENTS`, so opening the shelf refreshes it and buying something marks it purchased without waiting for the next login. | [`#46`](https://github.com/warband-pro/addon/issues/46) | Done, plus the check this row asked for: `tools/validate.mjs` now fails the build when any `handlers.X` names an event `EVENTS` does not register. It was put in `validate.mjs` rather than `freshness-test.lua` because it is a static property of `Core.lua` — no fake client needed, and it runs in the packaging job every push. |
| ~~A2~~ | ~~Nothing on the app side reads `tradingPost`.~~ **Closed 2026-09-17**, hours after it was written down: the app decodes the section, stores it, joins this month's shelf to what the account already owns and ranks what is leaving as a deadline. | [`app#130`](https://github.com/warband-pro/app/issues/130) | Nothing to do here — but it makes **A1 sharper, not moot**: the app now renders a shelf that this addon only reads at `PLAYER_LOGIN`. |
| ~~A3~~ | ~~`consumables.healthPotion` and `tempPotion` are specified and never emitted.~~ **Closed 2026-09-21.** Deleted the branches, the `POTION_IDS` table and the contract lines — health and temporary potions ride inside `potion`, which is what `Scan.Consumables` has always emitted. | [`app#267`](https://github.com/warband-pro/app/issues/267) | Done, plus the check this row asked for in spirit: `tools/validate.mjs` now fails the build when the `consumables` example in `CONTRACT.md` names a bucket `Scan.lua` does not emit, or misses one it does. |
| ~~A4~~ | ~~Housing decor ownership has no capture.~~ **Closed 2026-09-17.** `Scan.Decor` reads `C_HousingCatalog`'s searcher and `decor` rides at the payload root. Issue #48's first question — *is there an API to call* — resolved yes, which is what unblocked it. | [`#48`](https://github.com/warband-pro/addon/issues/48) | Done. The remaining risk is not the design but the names: `C_HousingCatalog` is as unexercised here as `C_PerksProgram` was, so `docs/QA.md`'s new section is what settles it in game. |
| [A5](https://github.com/warband-pro/app/issues/137) | **The Great Vault `pvp` bucket is captured and ranks nowhere.** | `Instances.lua` sends it; the app has no `pvp` activity kind | App-side decision: rank it, or state that PvP is out of scope. |

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

**Amended the same day** for the housing decor capture and the event-registration
fix that came out of building it: §2 gained `decor` and lost it from the
deliberately-uncaptured list, §3's section list gained it, and §5's A1 and A4
both closed. A1 closed by accident — the merge that brought this article onto the
decor branch is what surfaced the missing registrations, before the issue filing
it had been read.

## See also

- [`README.md`](README.md) — the read order for the twelve reference documents.
- [`CONTRACT.md`](CONTRACT.md) — the law for `wb1!`, `wbc1!` and `wbg1!`.
- [`FLOW.md`](FLOW.md) — who the player is and what the loop is.
- [`TESTING.md`](TESTING.md) — the pure/impure split.
- `warband-pro/app` `.wiki/wiki/topics/vision.md` — the product vision (private repo).
