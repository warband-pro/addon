# warband.pro — companion addon

> Problem: Battle.net API can't see what your chars actually hold — bags, bank, warband bank, gold, currencies, lockouts fresh vs stale, vault. Altoholic + SavedInstances have it, but web doesn't.

Warband.pro answers "who should I play tonight" from API — ilvl, spec, vault, lockouts summary. This addon gives it the other 60% — where stuff is, broke or not, 0 phials, spark capped.

Retail Midnight 12.1 only, super lightweight, compatible with whatever UI you run, no auto-upload ever.

## Core — multi-char bundle

Single-char paste gets annoying fast — 6 exports every Saturday? No.

- Addon keeps account-wide `WarbandProDB` guid-keyed. Each login silently updates that char's snapshot in background (throttled .5s on bag/move, on bank open, vault open).
- You play normally Mon-Sat.
- Any char: `/warband` → auto-highlighted box → Ctrl+C copies `wb1!aH...` containing all Voc- tanks you've played since install (4-7KB for 6).
- Web top-right sink `[ ↻ sync / ↥ import ▼ ]` omnipresent → Import → auto-grabs clipboard wb1! if you just copied, else big paste box → preview 🟢🟡🔴 → Confirm.

Default bundle. Still have `/warband copy current` single for streaming.

## How it works (10 sec)

1. Install to `_retail_/Interface/AddOns/WarbandPro`, /reload or full WoW restart if TOC bump.
2. Log any char — snapshot saved silently.
3. Log alt 2..6 through week, 0 extra steps.
4. Saturday push before +12s: `/warband` → Ctrl+C.
5. warband.pro second monitor `[ ↻ sync / ↥ import ]` → Import (i) → preview:
```
Vocnar — 2h ago — 847g — 312 pots — fresh
Voctara — 3d ago (!) — 12g — Warband Bank not seen since Aug 14
Vocgrim — 12m ago — fresh
```
Confirm → D1 upserts per-char. Missing char not deleted, stays ⚪ never.

## What it captures — Altoholic+SavedInstances superset, pruned

Take both lists intersectioned Midnight relevance, prune mounts/pets/recipes full 10k list.

- Identity: guid, name, realmSlug, faction, class, level, xp, restXP, guild+rank, lastZone, hearth, playtime, ilvl avg/equipped (cross-check)
- Money+banks: gold copper, bags[{bagID,size,free,items[{id,count,link,quality,isBound,isCraftingReagent}]}], bank+bankBags, reagentBank, warbandBank{seenAt,seenByGuid,tabs[[{id,count}]]}, mail{countItems,goldPending,soonestExpiry}, auctions{countActive,goldHeld}
- Currencies: [{id,name,quantity,maxQty,weeklyMax,isAccountWide}] — Crests, Flightstones, Tender etc with caps
- Professions: [{id,name,skill,max,expansionTier,knownRecipes,totalRecipes}], cooldowns[{spellID,name,readyTime,remaining}] like Transmute
- Lockouts: instances[{name,instanceID,difficulty 1=LFR/2=N/3=H/4=M,locked,resetTime,extended,bosses[{name,killed}]}], worldBosses[{name,killed,resetTime}]
- Mythic+/Vault: keystone{level,dungeonID,dungeonName,where bag|bank}, mythicPlusRuns[{mapID,level,timed,chestCount}], mythicPlusScore, weeklyVault{raid,mplus,world progress/threshold/unlocked}
- Consumables rollup derived fast for Tonight Plan: {phial,healthPotion,tempPotion,foodFeast,weaponRune}
- SeenAt per-section: lastSeen,bag,bank,warbank,currency,instance,vault,mail,auctions — for staleness dots.

Explicitly skip v1: full equipment (API has), mounts/pets/toys/achieves (account-wide bloat), recipe full list (keep counts), guild bank (only personal warbank), chat log, auction full listings.

### What the scaffold does not capture yet

The list above is the target. Five fields on it are not in the first scaffold,
each for a stated reason — the contract treats every one as optional, so the
website reads a bundle without them today and picks them up the day they appear:

- **`playtime`** — `RequestTimePlayed()` prints "Total time played" to chat, and
  "chat is silent on load" is the louder promise. Needs a chat filter first.
- **`knownRecipes` / `totalRecipes` / `expansionTier`** — need the profession
  window open and a full `C_TradeSkillUI` walk, the most expensive thing this
  addon could do. Skill level and cap are captured.
- **`professionCooldowns`** — same window, same cost.
- **`auctions.goldHeld`** — `GetNumOwnedAuctions()` is free on
  `OWNED_AUCTIONS_UPDATED`; the gold total needs a full owned-auction query.
- **`keystone.where`** — we know you own a key, not which bag it sits in.

Two more moved rather than vanished: `warbandBank` is at the payload root
instead of on every character, and item entries dropped `link` and
`isCraftingReagent`. Both are measured decisions, written up in
[docs/CONTRACT.md](docs/CONTRACT.md) under "v1 as implemented".

## Staleness UX

Dashboard per-char dot 🟢<6h 🟡<3d 🔴>3d ⚪ never. Hover "Bags 2h ago, Bank 5d ago (open bank to refresh), Warbank 14d". Inspector "Addon import" section age+bank status, filter stale>3d.

Tonight Plan: 0 phials + fresh 20m → hard block "hit AH before raid". 0 phials + 5d old yellow → grey "per last import 5d ago — verify?" not block.

Data never deletes, stale just lowers confidence.

## Format wb1!

`wb1!<base64url(deflate(jsonPayload))>`

Single line hash, not human readable on purpose — compact, no chat linkify, harder accidental inject. No whitespace. json canonical unsorted? sorted keys deterministic for vector test. Same envelope bundle 6 and single len1 array — web parser no branch.

- wb0 reserved Camp DNA URLs you already have.
- wb1 inventory bundle.
- wb2 future talents.

Encoding: json -> LibDeflate CompressDeflate level9 (raw deflate) -> base64url, no padding -> prefix. Web decode is the inverse: `DecompressionStream("deflate-raw")` or `pako.inflateRaw`, then validate v==1 and characters len 1..20. Not `EncodeForPrint`, and not `"deflate"` — CONTRACT.md explains both.

Size, measured rather than guessed: **~8.6KB for one character, ~26KB for six**, with full bag/bank/warband contents. The 4-7KB figure above is what you get without per-item lists.

See `docs/CONTRACT.md` + vector `docs/contract/vectors/v1-min.json`.

## Trust

- No network requests ever — verify in .toc, verify code.
- SavedVariables only <200KB for 6 chars (typical bigger addons ~50KB per char due to mounts — we skip).
- No OnUpdate scanner, only BAG_UPDATE throttled, etc.
- Export copy popup user decides paste — you paste to own site only, user_id only. Gold/warbank never in wb0 DNA unless opt-in "include gold".
- Stream-safe toggle collapses gold to ••• (future checkbox).

## Install (pre-CurseForge tester)

```
git clone https://github.com/warband-pro/addon.git WarbandPro
mv WarbandPro _retail_/Interface/AddOns/WarbandPro
# /reload inside game, full restart needed if .toc changed
# /warband
```

CF: Warband.pro Companion (name reserved).

## Use

```
/warband                panel + bundle preview freshness
/warband copy           same panel — the panel is how you copy
/warband copy current   single-char only for test/stream
/warband clear <name>   remove a character from the DB
/warband status         count, bundle size, per-section ages, API failures
/warband optimize       prune chars not seen 90d
```

Web: `/settings/import` textarea auto-clipboard grab if wb1! present, preview table, Confirm → upserts `character_addon_cache`.

## Second-monitor frequent flow (why omnipresent sink)

Game main monitor, web second monitor. Back-and-forth 4-10 times per night:

1. Log out char → eyes slide second monitor → top-right `[ ↻ sync ]` because roster stale after logout.
2. Loot spark, open vault, open warbank — addon already updated that char background no remembering.
3. Copy: `/warband Enter Ctrl+C` 1 sec.
4. Eyes back second monitor → Import click (hotkey `i`) — if clipboard holds wb1! from 10 sec ago preview appears auto zero Ctrl+V. Else textarea auto focus Ctrl+V.
5. Preview confirm → Tonight Plan flips vault 3/8→4/8 etc without extra sync because vault in bundle.
6. Repeat on next alt.

So sync+import must live in Menubar sink visible every route, not in system page only. Block-embedded ghost sync mirrors stay but drive same handler via keys.ts.

See `docs/FLOW.md` full story, `docs/UI.md` copy pain detail.

## Repo shape — tiny, buildable artifact

- flat root: WarbandPro.toc, Init.lua, Store.lua, Scan.lua, Instances.lua, Bundle.lua, Export.lua, UI.lua, Core.lua, Vendor/LibDeflate.lua, .pkgmeta, .luacheckrc
- tools/vector.mjs — contract round-trip, the only test that runs without WoW
- docs/ reference folder (trim before CF ship) — see docs/README.md read order.
- No test harness inside WoW — but pure functions testable offline via luacheck + busted + vector round-trip.
- CI workflows are not written yet. `luacheck .` and `node tools/vector.mjs` are what a ci.yml would run.

Load order in the .toc is vendor → namespace → data → UI → dispatcher; Core.lua is
last because it registers events the moment it loads. The installed folder must be
named `WarbandPro`, matching `WarbandPro.toc`, or the client silently skips it —
and a .toc change needs a full client restart, not `/reload`.

For AI coder: see `docs/PROMPT.md` single prompt copy-paste that has /app + /addon paths, locked decisions list, file list, acceptance checks mem<2MB bundle<8KB single taint 0 dots green, QA PASS/FAIL format.

## Modern stack (Midnight 12.0+)

Template tracked Interface 120001 Lua 5.1, secret values taint apocalypse (CLEU dead), Compartment entry, C_Container new C_Bank 5 tabs, Settings.RegisterCanvasLayoutCategory modern options, BigWigs packager CI. Docs linked in `docs/RESEARCH-REFERENCE.md`.

## Docs index (coding reference)

- docs/FLOW.md — Goal + user behavior (second-monitor back-and-forth, frequent exports, Saturday push)
- docs/RESEARCH-REFERENCE.md — Midnight modern best practices (no Ace3, load order, throttle .5s, Secret/ CLEU avoidance, LibDeflate std)
- docs/CONTRACT.md — wb1! law + schema + versioning + DoS caps + vectors
- docs/UI.md — copy pain game EditBox Multi MaxLetters(0) HighlightText Timer.After(0) + web Import modal clipboard inside click fallback paste + preview dots
- docs/TESTING.md — layering pure vs impure offline luacheck busted vector vs 5-min manual script screenshot-parseable
- docs/QA.md — manual checklist release 5-min copy-paste PASS/FAIL lines
- docs/CI.md — packager, semver, tokens
- docs/PROMPT.md — prompt for AI coder /app+/addon
- docs/APP-IMPORT.md — the /app side proposal: D1 tables, import route, pure decoder

When shipping light: keep this README + CONTRACT excerpt, nuke docs/.

## Decisions locked vs open

Locked: multi-char bundle default ✓, staleness per-section stamps ✓, retail Midnight only ✓, wb1! format ✓, vendor LibDeflate ✓, omnipresent sink top-right ✓, pure/impure split testability ✓
Open: minimap Y/N default off — Compartment enough?, itemName in bundle or id-only + Game Data lookup smaller on web?, warbank stamp shared vs per-char (shared makes sense), recipe total totalRecipes needs static fetch, CF vs Wago first?

---
Next: scaffold toc+init skeleton, then /app import sink patch — AI prompt ready in docs/PROMPT.md.
