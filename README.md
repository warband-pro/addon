# warband.pro — companion addon

> Problem: the Battle.net Profile API cannot see what your characters are actually holding.

Warband.pro answers "who should I play tonight" from the API — ilvl, spec, lockouts, vault, professions. The other half is the wall: where did I put that, how broke am I, which alt has the spark. No endpoint returns:

- bags / bank / Warband bank contents
- gold per character
- mail pending
- currencies with caps (crests, flightstones, trader's tender, etc)
- reagents, consumables counts
- lockouts per boss per difficulty fresh enough to trust

This addon is that bridge: tiny, retail-only, no auto-sync. Play normally, paste once, web gets the rest.

## Core decision — multi-character bundle

Single-char paste is annoying. You'd have to remember 6 exports every Saturday.

v1 is warband bundle: addon keeps account-wide `WarbandProDB`. Each login silently updates that char's snapshot. `/warband` → Copy exports all 6 Voc- tanks you've played since installing in one `wb1!...` string. One paste.

You can still do `/warband copy current` for streaming / testing. Default is bundle.

## How it works

1. Install, log any char — snapshot saved
2. Log alts through week (0 extra steps)
3. `/warband` → Copy
4. warband.pro Import (i) → Paste → preview:

```
Vocnar — 2h ago — 847g — 312 pots — fresh
Voctara — 3d ago (!) — 12g — Warband Bank not seen since Aug 14
Vocgrim — 12m ago — fresh
```

Confirm → D1 upserts each char with `imported_at`.

If char never seen, we keep API-only and show "never via addon."

## Staleness UX (you asked)

Dashboard shows per-char:

- dot 🟢 <6h / 🟡 <3d / 🔴 >3d / ⚪ never
- hover: "Bags 2h ago, Bank 5d ago (open bank to refresh), Warbank 14d"
- inspector: "Addon import" section with age + bank status, filter "stale >3d"
- Tonight Plan: if 0 phials and data 5d old → grey "per last import (5d ago) verify?", if 20m old → hard block "hit AH before raid"

Data never deletes — stale just lowers confidence.

## Altoholic + SavedInstances — what we match

You said pull anything those two do. They are gold standard. If we miss a field, users notice.

### Altoholic tracks

- Summary: level, xp, rest xp, money, playtime, ilevel, bind loc, hearth, guild+rank, spec, last zone
- Inventory: bags size/free, bank slots/free, reagent bank, equipped (light), bag contents exhaustive id/count/link/quality/bound
- Professions: primary/secondary level, current tier, recipes known/total per expansion, cooldown timers ready-at (Transmute etc)
- Currencies: gold + every token (Flightstones, Crests, Tender, etc) with total/weekly/max, account-wide flag
- Quests/Resets: dailies/weeklies completed, LFR cooldowns
- Mail & Auctions: count, gold pending, expiry — needs mailbox open
- Talents, guild?

### SavedInstances tracks

- Raid lockouts per instance per difficulty (LFR/N/H/M), reset time, bosses killed bool array, extended flag
- World Bosses killed bool + reset
- Mythic+: runs this week, best per map, score, keystone in bags/bank (level+dungeon)
- Vault: raid/M+/world progress thresholds
- Emissaries/Callings/Paragon: callings completed, paragon caches, weekly Sparks/Catalyst charges, profession weekly knowledge
- Weekly currency caps/warnings, trade skill daily CDs ready
- Warband vault flow

### Our v1 bundle — unified superset we actually need

Take both, cut to Midnight 12.1 relevance, prune bloat:

```
meta { v, addonVersion, exportedAt, gameVersion, bundleCount }

characters[]:
  identity:
    guid, name, realmSlug, faction, class, level, xp, restXP
    guild{name, rank}, lastZone, hearthZone, bindZone
    playtimeSec, itemLevelAvg/Equipped (cross-check)

  money + banks:
    gold copper
    bags [{bagID, size, free, items[{id, count, link, quality, isBound, isCraftingReagent}]}]
    bank + bankBags [{...}] + free
    reagentBank [{...}]
    warbandBank [{...}] + seenAt (null if never opened)
    mail {countItems, goldPending, soonestExpiryDays} — only if mailbox opened
    auctions {countActive, goldHeld} — light

  currencies:
    [{id, name, quantity, maxQty, weeklyMax, isAccountWide}]

  professions + CDs:
    professions [{id, name, skill, maxLevel, expansionTier, knownRecipes, totalRecipes}]
    professionCooldowns [{spellID, name, readyTime, remainingSec}]

  lockouts (SavedInstances core):
    instances [{name, instanceID, difficulty (1=LFR/2=N/3=H/4=M), locked, resetTime, bosses[{name,killed}], extended}]
    worldBosses [{name, killed, resetTime}]
  
  mythic+ / vault:
    keystone {level, dungeonID, dungeonName, where (bag|bank)}
    mythicPlusRuns [{mapID, level, timed, chestCount}]
    mythicPlusScore
    weeklyVault {raid tiers, mPlus tiers, world tiers, unlocked? thresholds}

  consumable rollup (derived fast for Tonight Plan):
    {phial, healthPotion, tempPotion, foodFeast, weaponRune, augment, bandage}

  meta per char:
    lastSeen, bagSeenAt, bankSeenAt, warbankSeenAt, currencySeenAt, instanceSeenAt, vaultSeenAt
```

### What we skip even though they do it

- Full equipment (API already good)
- Full recipe list 10k rows — keep counts only for v1 (60% size saved)
- Mounts/pets/toys/achievements — account-wide bloat, API-available
- Full guild bank (only warband bank, personal)
- Auction full listings, chat logs
- No OnUpdate scanner — events only: BAG_UPDATE, PLAYER_MONEY, CURRENCY_DISPLAY_UPDATE, BANKFRAME_OPENED, ACCOUNT_BANK_OPENED, BOSS_KILL

### Why this wins

API gave 40% — ilvl, spec, guild, prof name, lockout summary. This gives other 60% — where stuff is, broke or not, lockout fresh enough for reset math, craft CD ready, tender about to cap, 0 phials.

Enables Tonight Plan:

- "Don't +12 Vocgrim — 0 phials, AH closed, but Vocnar has 120 in WBank"
- "Voctara 8/9 Normal Amirdrassil — 1 left vs fresh alt"
- "WBank 47 Spark fragments scattered across 3 chars — consolidate"
- "Herbalism transmute ready on 4 chars — log them first ~12k"

One paste, no per-char remembering.

## Format

`wb1!<base64url(deflate(JSON))>`

Same envelope for single-char (len 1 array) and bundle (len 6) so web parser doesn't branch.

- wb0 reserved Camp DNA you have
- wb1 inventory+lockouts bundle
- wb2 future talents

No encryption, paste user→own site. Add CRC suffix later if needed.

Size: 1 char 2-4KB raw ~1KB deflated, 6 chars ~12-18KB raw → 4-7KB b64. WoW EditBox with SetMaxLetters(0) + scroll handles ~20KB fine. If overflow we add slim mode (id+count only) or chunk wb1.1/3.

## Trust

- No network requests, ever — verify in .toc
- SavedVariables only, <200KB for 6 chars
- No OnUpdate — update current char only on events
- Export via Blizzard copy popup — user decides paste
- Web writes D1 user_id only, gold/warbank never in camp DNA unless opt-in "include gold"
- Stream-safe toggle hides gold to "•••"

## How to install (pre-CF)

```
git clone https://github.com/warband-pro/addon.git WarbandPro
# move to _retail_/Interface/AddOns/
# /reload /warband
```

CF: Warband.pro Companion (reserved name)

## How to use

```
/warband                panel + bundle preview
/warband copy           bundle
/warband copy current   single
/warband dump           raw json to console
/warband clear <name>   remove guid from DB
```

Web: /import textarea preview → upsert character_addon_cache D1 (user_id, realm_slug, char_name, data_json, last_seen_ms, bank_seen_ms, warband_seen_ms, imported_at_ms)

## Repo shape

- flat root, fewest moving parts
- WarbandPro.toc
- core.lua (slash, lifecycle)
- store.lua (account-wide accumulation)
- scan.lua (bags/bank/currency/gold read-only current)
- instances.lua (lockouts, bosses, keys, vault) — SavedInstances parity
- bundle.lua (chars array → json)
- export.lua (deflate → b64u + wb1! + copy box)
- ui.lua (single panel, freshness dots)
- Vendor/LibDeflate (MIT, one file)

No test harness — WoW loader is test + scripts/verify.lua lint.

## Non-goals

- Not full Altoholic rewrite — no tooltip injection, item search UI in-game
- Not sync engine
- Not Classic — Midnight 12.1 only retail

## Decisions locked

- Multi-char bundle default ✓ you chose this today
- Staleness UX per-char + per-section (bank/warbank separate stamps) ✓

## Open

- Bundle includes itemName or id only? id-only smaller, needs Game Data lookup on web. Currencies include names.
- Warbank account-wide stamp shared across chars? Yes freshness "WBank 1h ago (by Vocnar)" makes sense.
- Freshness thresholds: 6h/3d worked for push groups? Saturday push = Monday data 3d old = yellow, maybe fine.
- Guid keying vs realm+name (Voc- locked so stable, guid safer)
- CF packaging chapter

---
Next: scaff WarbandPro.toc + store.lua + single panel, then web import route that accepts wb1! and writes character_addon_cache. No balance until round-trip works.

---

## For coding later — modern stack reference (Midnight 12.0+, condensed)

> Full 241-line checklist is in `docs/RESEARCH-REFERENCE.md` in this repo. That doc is the code bible — this is tl;dr for quick recall.

**Target:** Retail Midnight/12.1, Interface 120001, Lua 5.1, vanilla (no Ace3/LibStub), LibDeflate only vendor.

**TOC:**
```
## Interface: 120001
## Title: Warband.pro
## SavedVariables: WarbandProDB
## IconTexture: Interface\Icons\INV_Misc_Bag_10
## AddonCompartmentFunc: WarbandPro_OnAddonCompartmentClick
Init.lua | Libs/LibDeflate.lua | Core.lua | Store.lua | Scan.lua | Instances.lua | Bundle.lua | Export.lua | UI.lua
```

**Why no Ace3:** minimal surface = fewer breakage points on patches — Midnight template explicitly says modern pattern is no Ace3 dep. Our exporter doesn't need AceDB.

**SavedVariables:** one account-wide `WarbandProDB = { v=1, chars={[guid]=…}, warbandBank, lastExport }`. GUID-keyed stable across renames. Update current char only on events, bundle values of whole table. ~8KB per char vs typical 50KB per char for bigger addons because we skip recipes/mounts.

**Events + perf:** PLAYER_LOGIN, BAG_UPDATE throttled .5s, PLAYER_MONEY, CURRENCY_DISPLAY_UPDATE, BANKFRAME_OPENED/ACCOUNT_BANK_OPENED/REAGENTBANK, BOSS_KILL/ENCOUNTER_END/UPDATE_INSTANCE_INFO, WEEKLY_REWARDS_UPDATE. No OnUpdate, use C_Timer generation counter to cancel stale callbacks. Fail closed if called in combat.

**C_Container new:** `C_Container.GetContainerNumSlots`, `GetContainerItemInfo` — old GetBag API dead. Warband Bank = `C_Bank` 5 tabs, only live when banker open — stamp seenAt shared: "WBank 1h ago (by Vocnar)" valid all alts.

**Midnight breaks:** Secret Values — reading aura.spellId on private aura throws taint forever. Don't touch combat auras. CLEU doesn't fire for addons anymore, use per-event replacements (we don't meter anyway). So inventory+lockout exporter unaffected if we avoid combat log.

**Export:** WeakAuras pattern `Copy Import String` → Ctrl-A Ctrl-C. Same UX. JSON → deflate → base64url `wb1!`. 6 chars => 4-7KB fits EditBox SetMaxLetters(0) + scroll. wb0 reserved Camp DNA.

**UI:** One panel, Blizzard native widgets, Compartment entry point (no minimap lib default), slash /warband /warband copy /warband status. Debug first-class /addon status + /addon debug. No tooltip hooks (overlap fix to avoid taint with ElvUI). No global leakage besides `WarbandPro`.

**Compat:** Folder name == .toc base name (WoW hard rule). Load order libs → core → data → ui → config. Unique SavedVariables name. No frame scanning, no GetGlobal loops. TOC bump needs full WoW restart, not just /reload.

**Data scope = Altoholic + SavedInstances ideal vendor:** Warbandeer issue says REST API has zero paths for vault/curr/gold/lockout/mail/bank/bag/playtime/housing — addon only source. Warbandeer_Characters stores per char gold + warbank gold, currencies/crests, Great Vault, M+ keystones + history + score, raid/delve lockouts + bosses + reset, world bosses, mail+expiry, auctions+gold, playtime, bags+bank+wbank items, quests, titles catalog for external naming, rep, prof knowledge. That's exact superset we bundle (skip mounts/equipment full for weight/size).

**Size/perf goal:** <5MB mem idle, <200KB SavedVars for 6 chars, no polling, throttle BAG_UPDATE to not spam on loot.

**Packaging:** BigWigs packager .pkgmeta → CF/Wago zip via GitHub Action. .luacheckrc + scripts/get-interface-version.ps1 validation.

For full thing with sources, see `docs/RESEARCH-REFERENCE.md`. That file will be deleted before ship to keep repo light — it's coding reference now.
