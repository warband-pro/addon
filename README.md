# warband.pro — companion addon

> Problem: the Battle.net Profile API cannot see what your characters are actually holding.

Warband.pro already answers "who should I play tonight" from the API — ilvl, spec, lockouts, vault, professions. But the other half of Altoholic — *where did I put that* — is a wall. No endpoint returns:

- bags / bank / Warband bank contents
- gold per character
- mail counts
- currencies (crests, flightstones, valorstones, coalescence, etc)
- reagents, consumables, how many health pots you actually have
- which alt has the Spark, which has the Enchanted Crest

Those are impossible from the web. An in-client addon is the only way.

This repo is that addon: a tiny retail-only exporter that quietly remembers every character you log, and when you remember, one paste updates warband.pro with the whole warband.

No auto-sync, no background uploading, no CurseForge account needed. Play normally, hit export when you remember, paste in web. That's it.

## Core decision — multi-character from start

Single-char paste gets old fast. You'd have to remember to export on every alt every night, or your warband screen is always half stale.

So v1 is **warband bundle**: the addon keeps a small account-wide SavedVariables table (`WarbandProDB`). Each time you log a character, it passively updates that character's snapshot (bags, bank, gold, currencies, when). When you type `/warband` on any char, it exports the last-known state of *all* your Voc- tanks you've played since installing — one `wb1!...` string that warband.pro splits into 6 rows.

- Play normally Mon–Sat
- Saturday before your push you hit `/warband` → Copy → Paste once
- warband.pro ingests 6 characters at once

You still can toggle "current only" if you're streaming or just testing. Default is bundle.

## How it works (the 10-second flow)

1. Install addon, log any character — it saves a snapshot silently in background
2. Log alts through the week as you normally would (0 extra steps)
3. Whenever you want: `/warband` → Copy button → copies `wb1!aH...`
4. In warband.pro → Import (hotkey `i` soon) → Paste → preview

Preview shows:

```
Vocnar (Wyrmrest) — 2h ago — 847g — 312 pots
Voctara (Wyrmrest) — 3d ago (!) stale — 12g — Warband Bank not seen since Aug 14
Vocgrim — 12m ago — fresh
```

You confirm, D1 upserts each character with its `exportedAt` / `importedAt`.

If a character isn't in the bundle (never logged since install), we don't delete it — we show it as "never seen via addon" and keep API-only data.

## What it captures (v1 bundle)

Per character, read-only, at last login of that character:

```
meta:
  v: 1
  addon: "1.0.0"
  exportedAt: 1724000000
  bundle: 6 entries
  gameVersion: "12.1.0"
  
characters[]:
  - name: "Vocnar"
    realm: "Wyrmrest Accord"
    realmSlug: "wyrmrest-accord"
    faction: "Horde"
    guid: optional (for dedupe)
    lastSeen: timestamp (when snapshot taken)
    bagVersion: increment on BAG_UPDATE
    bankSeenAt: null | timestamp (null until you open bank)
    warbandBankSeenAt: null | timestamp
    gold: copper int
    bags: [{bagId, slots, items: [{id, count, quality, isBound, isCraftingReagent}]}]
    bank: [{...}] (empty if never opened)
    reagentBank: [...]
    warbandBank: [{...}] (only if opened since install)
    currencies: [{id, name, count, max, weeklyMax, isAccountWide, discoveredAt}]
    consumablesDerived: { pot, phial, rune, food, augment } counts across bags+bank
    professionsSnapshot: optional stub (API already has better, but useful for freshness)
```

Explicitly not in v1:

- Equipped gear (API has it)
- Mounts / pets / toys (account-wide bloat)
- Mail body text / chat
- Scanning guild bank (restricted)
- Real-time sync — still user-initiated export, no auto-upload

## Size target

One char with full bags+bank ~2-4KB string. Six chars ~12-18KB uncompressed JSON, ~4-7KB after deflate+b64url. WoW StaticPopup EditBox handles ~20KB fine if we use `SetMaxLetters(0)` and scroll frame. If it tips over, we slice into `wb1.1/3` chunks (not v1) or ship slim mode that drops item names (we only need IDs — web looks up Game Data for names later).

## Staleness UX on warband.pro (you asked)

App side needs two tables/views:

1. New `character_addon_cache` D1: `user_id, realm_slug, char_name, data_json, last_seen_ms, bank_seen_ms, warband_bank_seen_ms, imported_at_ms, addon_version`
2. Dashboard vitals already has API freshness (30m TTL). Addon freshness is orthogonal and user-driven, so show it separately:

In Camp table row:

- dot: 🟢 fresh `<6h`, 🟡 `<3d`, 🔴 `>3d`, ⚪ `never`
- on hover: "Bags 2h ago, Bank 5d ago (open bank to refresh), Warband Bank 14d ago"
- compact: "2h / bank 5d" second line under item level

In Inspector pane:

- section "Addon import" listing each char in bundle with age + Bank/Warbank status
- filter: "show only stale >3d"
- call to action if no import yet: "Install addon → Paste once → see reagents here"

In Tonight Plan:

- If you have 0 phials across all characters *known to addon* but data is stale >7d, don't block the +12 recommendation — grey it: "out of phials per last import (5d ago) — verify?"
- If fresh and 0 phials, do block: "You're out, hit AH before raid"

Data never auto-deletes: stale just means lower confidence, not missing. User can clear a character from bundle via addon panel: `/warband clear Vocgrim` or via web settings.

## Format

```
wb1!<base64url(deflate(JSON))>
```

Bundle JSON example shape unsaid above, includes `characters: []`. Same envelope for single-char (array len 1) so web parser doesn't branch.

- `wb0` reserved for Camp DNA URLs you already have
- `wb1` inventory bundle
- `wb2` future (talents / hero talents?)

No encryption. Paste is user → own site. If we want tamper-evidence later, add CRC32 `!` suffix, but not v1.

## Trust model

- No network requests from addon, ever
- SavedVariables only: `WarbandProDB` account-wide, <200KB for 6 chars
- No `OnUpdate` scanning — we listen to `BAG_UPDATE`, `PLAYER_MONEY`, `CURRENCY_DISPLAY_UPDATE`, `BANKFRAME_OPENED`, `ACCOUNT_BANK_OPENED` just to update that char's snapshot. No scan of other characters.
- Export copies string to clipboard via Blizzard copy popup — you then decide to paste to warband.pro
- Web: pasted string writes D1 under your user_id only. Gold/Warband Bank never shared in camp DNA unless you opt-in "include gold in share"
- Stream-safe: addon window shows counts, not gold by default — streamer toggle collapses gold to "•••"

## How to install (tester flow pre-CurseForge)

```
git clone https://github.com/warband-pro/addon.git WarbandPro
# Move to _retail_/Interface/AddOns/WarbandPro
# /reload
# /warband
```

Future: CurseForge "Warband.pro Companion" (name reserved).

## How to use (dev)

```
/warband             -> panel, bundle preview (6 chars, freshness dots)
/warband copy        -> copy bundle
/warband copy current-> single-char only
/warband dump        -> print raw JSON to /console for debug
/warband clear       -> wipe that guid from local DB
```

Web:

- `/import` textarea + preview table
- Confirm → upserts `character_addon_cache`

## What this repo is

- Flat root, fewest files
- `WarbandPro.toc`
- `core.lua` (lifecycle, slash)
- `store.lua` (SavedVariables accumulation across characters)
- `scan.lua` (bags/bank/currencies/gold read-only, current char)
- `bundle.lua` (assemble characters[] -> json)
- `export.lua` (json -> deflate -> b64u + wb1! prefix + copy popup)
- `ui.lua` + optionally `ui.xml` single panel
- Vendor: LibDeflate (MIT) one file

No test harness — WoW loader is the test + `scripts/verify.lua` lint.

## Non-goals

- Not Altoholic / Bagnon rewrite — no tooltip injection, no item search UI in-game, no 200-alt database viewer. One panel.
- Not a sync engine — never auto-uploads
- Not Classic — retail Midnight 12.1 only

## Open questions

- Bundle size: do we include itemName or only id+count? id-only smaller, but needs Game Data lookup on web side. Simpler v1 maybe include name for currencies only.
- Warband Bank is account-wide but Blizzard only lets you read it when you open it on *any* char — do we stamp it as shared? If you open Warband Bank on Vocnar, is that valid for Voctara bundle? Yes, but freshness should be "Warband Bank updated 1h ago (by Vocnar)"
- Freshness thresholds: 6h/3d? Does Saturday push mean most data is week-old Monday? Maybe Tonight Plan should down-weight addon data that age more gently.
- Reset before implementing: do we need a guid to key characters across renames? realm+name is stable for Voc- prefix you locked, but guid is safer — store both.
- CurseForge packaging chapter

---

V1 next: implement store.lua + bundle JSON + panel with freshness, then web import route that accepts wb1! and writes `character_addon_cache`. No balance changes until bundle round-trips once.
