# Warband.pro Companion

[![CI](https://github.com/warband-pro/addon/actions/workflows/ci.yml/badge.svg)](https://github.com/warband-pro/addon/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Companion addon for [warband.pro](https://warband.pro)** — the site that answers "who should I play tonight."

**What it is:** warband.pro reads your Battle.net roster — ilvl, spec, vault progress, lockout summary. The Blizzard API can't see where your stuff actually lives. This companion fills that gap: bags, bank, warband bank, gold, currencies, professions, mail, auctions, instance lockouts, keystone, weekly vault — from every alt you log.

**What it's not:** Not a data broker, not an auto-uploader, not a UI overhaul. No network calls. Ever. You play normally, hit `/warband`, paste once into warband.pro.

Retail Midnight 12.1 only, super lightweight, works with whatever UI you run.

## Why you need a companion

The Battle.net Profile API exposes 14 fields per character (name, realm, guid, class, level, ilvl, spec, role, 2 profs, guild, faction). Zero paths for gold, bank, bags, currencies, vault capping, mail. The Warbandeer OpenAPI confirms 0 paths for those.

If you want warband.pro to know "Vocnar has 120 phials in Warband Bank" or "Voctara's warbank hasn't been seen in 5 days, open it to refresh," you need this addon.

It's the same problem Altoholic + SavedInstances solve locally — we make it web-readable in one `wb1!` string so warband.pro's Tonight Plan isn't guessing.

## How it works (10 seconds)

1. Install this addon (CurseForge / Wago / WoWI — or Actions → CI → Artifact zip while pre-release).
2. Log any character — snapshot saved silently in account-wide `WarbandProDB`.
3. Log alts 2..6 through the week — 0 extra steps, bag updates throttled .5s.
4. Any character: `/warband` → auto-highlighted box → `Ctrl+C` copies `wb1!aH...` (4-7KB for 6 chars, ~26KB with full bag contents).
5. Second monitor, [warband.pro](https://warband.pro) open — top-right `[ ↻ sync / ↥ import ]` → Import (`i` hotkey) → auto-grabs clipboard if you just copied, else paste → preview:

```
Vocnar — 2h ago — 847g — 312 pots — fresh
Voctara — 3d ago (!) — 12g — Warbank not seen since Aug 14
Vocgrim — 12m ago — fresh
```

Confirm → warband.pro upserts each char. Missing chars stay, just stale.

Default is multi-char bundle so you don't remember per-char exports. Single-char `/warband copy current` exists for streaming / testing.

## What it captures — Altoholic + SavedInstances superset, pruned

Midnight-relevant only, mounts/pets/toys/recipes full 10k list skipped (counts only):

- Identity: guid, name, realmSlug, faction, class, level, xp, restXP, guild+rank, lastZone, hearth, playtime, ilvl avg/equipped
- Money+banks: gold, bags[{bagID,size,free,items[{id,count,quality}]} implicitly via Scan.lua], bank+bankBags, reagentBank, warbandBank{seenAt,seenByGuid,tabs}, mail{countItems,goldPending,soonestExpiry}, auctions{countActive,goldHeld}
- Currencies: [{id,name,quantity,maxQty,weeklyMax,isAccountWide}] — Crests, Flightstones, Tender etc
- Professions: [{id,name,skill,max}], cooldowns ready-time later
- Lockouts: instances[{name,instanceID,difficulty LFR/N/H/M,locked,resetTime,extended,bosses[{name,killed}]}], worldBosses[{name,killed,resetTime}]
- Mythic+/Vault: keystone{level,dungeonID}, runs[{mapID,level,timed}], score, weeklyVault{raid,mplus,world progress/threshold/unlocked}
- Consumables rollup for Tonight Plan: {phial,healthPotion,tempPotion,foodFeast,weaponRune}
- Per-section seenAt: lastSeen,bag,bank,warbank,currency,instance,vault — for 🟢<6h 🟡<3d 🔴>3d ⚪never dots.

Skipped v1: full equipment (API has it), mounts/pets/toys/achieves, recipe full list, guild bank (only personal warbank), chat, auction listings.

## Staleness — trust but verify

Site shows per-char dot, hover "Bags 2h ago, Bank 5d ago (open bank to refresh), Warbank 14d". Inspector "Addon import" section. Tonight Plan: 0 phials + fresh 20m → hard block "hit AH before raid", 0 phials + 5d old → grey "per last import 5d ago — verify?" not block. Data never deletes, stale just lowers confidence.

## Format — `wb1!`

Single-line hash, not human-readable on purpose: `wb1!<base64url(deflate(json))>` — compact (~8.6KB 1 char, ~26KB 6 chars full), no chat linkify, harder accidental inject. `wb0!` reserved for Camp DNA. `wb2!` future talents. Site decodes with `pako.inflateRaw` / `DecompressionStream('deflate-raw')` inverse of LibDeflate raw deflate lvl9. Validated v==1, len 1..20 chars, size <25KB decoded. See [CONTRACT.md](docs/CONTRACT.md) + vector `docs/contract/vectors/v1-min.json`.

## Companion trust

- No network requests — check .toc, check code.
- SavedVariables <200KB for 6 chars.
- No OnUpdate scanner, only BAG_UPDATE throttled .5s, BANKFRAME_OPENED etc.
- Export is copy-only, you decide to paste to your own account on warband.pro.
- Stream-safe toggle planned collapses gold to •••.

## Install

**Release (once live):** CurseForge, Wago, WoWI — search "Warband.pro Companion" in your manager (CurseForge app, WowUp, etc).

**Pre-release test:** Actions → CI → latest main run → Artifacts → `WarbandPro-<sha>.zip` — unzip into `_retail_/Interface/AddOns/`.

**From source:**

```bash
git clone https://github.com/warband-pro/addon.git WarbandPro
mv WarbandPro _retail_/Interface/AddOns/
```

In-game `/reload` (full restart needed if .toc changed), then `/warband`.

## Use

```
/warband                panel + bundle freshness
/warband copy           bundle wb1! to clipboard
/warband copy current   single-char only
/warband dump           raw json (debug, /console)
/warband clear <name>   prune from DB
/warband status         debug counts/len/lastSeen
/warband optimize       prune chars not seen 90d
```

On [warband.pro](https://warband.pro): `/settings/import` or top-right Import (`i`) → auto-clipboard grab if `wb1!` present → preview → Confirm → Tonight Plan re-evaluates.

## Sites — this repo deploys everywhere

This repo is the single source that ships to all three addon sites via BigWigs packager on `v*` tags:

- **CurseForge:** `X-Curse-Project-ID` in `WarbandPro.toc` → set once project exists
- **Wago:** `X-Wago-ID` in toc → set once project exists
- **WoWInterface:** `X-WoWI-ID` in toc → set once project exists

GitHub Release flow: `git tag -a v1.0.0 -m v1.0.0 && git push origin v1.0.0` — or Actions → Release → Run workflow. CI must be green, `CHANGELOG.md` must have `## [1.0.0]` heading, packager substitutes `@project-version@` from tag.

Until IDs are set, release warns "site skipped — no token" rather than failing — so you can ship to GitHub Releases before CurseForge exists.

## Second-monitor flow — why omnipresent import matters

Game on main monitor, warband.pro on second interior monitoring. Back-and-forth 4-10 times per night: log out → glance sync, loot spark / open vault / open warbank → addon already snapped it, `/warband Enter Ctrl+C` 1 sec, second monitor Import click (`i`) — if clipboard holds `wb1!` from 10 sec ago preview appears zero paste, else auto-focus Ctrl+V, Confirm → Tonight Plan flips.

Top-right sink `[ ↻ sync / ↥ import ▼ ]` lives every route, mirrors ghost sync buttons in blocks.

## Repo shape

- `WarbandPro.toc`, `Init.lua`, `Core.lua`, `Store.lua`, `Scan.lua`, `Instances.lua`, `Bundle.lua`, `Export.lua`, `UI.lua`, `Vendor/LibDeflate.lua`
- `tools/validate.mjs`, `tools/vector.mjs`, `tools/sample.mjs`, `CHANGELOG.md`, `.pkgmeta`, `.github/workflows/ci.yml` + `release.yml`
- `docs/` — coding reference, trimmed before CurseForge zip via `.pkgmeta` ignore. See `docs/README.md` read order: FLOW → RESEARCH-REFERENCE → CONTRACT → UI → TESTING → QA → CI → PROMPT → EXECUTION-READY.

When shipping light, flat root, no badges clutter, per your rule Problem→Install→Use→What it catches→Inside 4-6 files (this README already does it).

## Decisions

Locked: multi-char default ✓, staleness per-section stamps ✓, retail Midnight only ✓, wb1! format ✓, vendor LibDeflate only ✓, omnipresent sink top-right ✓, companion framing ✓, vanilla no Ace3/LibStub ✓

Open 5 before 1.0: minimap N default off — Compartment enough?, itemName in bundle or id-only + Game Data lookup?, warbank stamp shared vs per-char?, recipe totalRecipes static fetch?, CF vs Wago first?

---
Next: scaffold toc+init skeleton done, addon+import sink patch live — prompt ready in docs/PROMPT.md. All deploys target "Warband.pro Companion" pointing to [warband.pro](https://warband.pro).
