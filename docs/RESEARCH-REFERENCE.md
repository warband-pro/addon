# warband.pro addon — research reference for coding (Midnight 12.0+ / 12.1)

You wanted super lightweight + compatible with whatever else user runs. This is cheat sheet we pull from when we code later. Trim before ship, keep in repo now.

Source research: frikkern midnight template, themizeguy wow-addon-dev skill, warband-nexus patterns, LibDeflate/WeakAuras export, Blizzard addon compartment changes.

## Target

- Retail only, Midnight 12.1
- Interface: `120100` for Midnight 12.1 (verified). Single comma-delimited Interface line if we support Classic later, but v1 retail only.
- Lua 5.1 (WoW retail)
- Zero deps except vendored LibDeflate (MIT, one file) for wb1! strings. No Ace3, no LibStub.

## Why no Ace3

Midnight template is explicit: complete addon template with modern Blizzard API patterns (no Ace3 dependency) — stable, minimal surface area = fewer breakage points. Ace3 pulls AceAddon, AceDB, AceConfig, CallbackHandler, LibStub. Each is break point on patch + taint risk. For exporter that just scans bags/bank and copies string, vanilla Lua is highest confidence for lightweight + compat.

## TOC — minimal that works now

```
## Interface: 120100
## Title: Warband.pro
## Notes: Lightweight warband bundle — bags, bank, currencies, lockouts from all alts
## Author: warband.pro
## Version: @project-version@ (replaced by BigWigs packager)
## SavedVariables: WarbandProDB
## IconTexture: Interface\Icons\inv_enchant_voidcrystal
## AddonCompartmentFunc: WarbandPro_OnAddonCompartmentClick
## Category: warband.pro companion
## X-Curse-Project-ID: xxx (once registered)

Init.lua
Libs\LibDeflate\LibDeflate.lua
Core.lua
Store.lua
Scan.lua
Instances.lua
Bundle.lua
Export.lua
UI.lua
```

Load order matters: Libs → Compat (none needed) → Core → Data → UI → Config. WoW loads file order listed.

`IconTexture` + `AddonCompartmentFunc` = Blizzard's new addon compartment. Sits in minimap-adjacent Blizzard addon list. User clicks, we open panel. Still no LibDBIcon — 1.5.0 added a minimap button, but hand-built from CreateFrame and the client's own ring texture, so no LibStub and nothing registered. See docs/UI.md "Minimap button".

## SavedVariables — warband bundle accumulation

Pattern from modern skill docs: ADDON_LOADED vs PLAYER_LOGIN lifecycle, single top-level table with `or {}` init, deep-merge defaults additive.

We want account-wide, not per-char. So `## SavedVariables: WarbandProDB` not PerCharacter.

Shape:

```lua
WarbandProDB = WarbandProDB or {}
WarbandProDB.v = 1
WarbandProDB.chars = WarbandProDB.chars or {}
WarbandProDB.warbandBank = WarbandProDB.warbandBank or { seenAt = nil, items = {} }
WarbandProDB.lastExport = WarbandProDB.lastExport or 0
```

On PLAYER_LOGIN or PLAYER_ENTERING_WORLD, update this char's entry:

```lua
local guid = UnitGUID("player")  -- stable across renames, better than name+realm
WarbandProDB.chars[guid] = {
  name = UnitName("player"),
  realmSlug = GetRealmName() -> slug,
  faction = UnitFactionGroup("player"),
  class = classFile,
  level = UnitLevel("player"),
  -- ... scanned fields
  lastSeen = time(),
  bagSeenAt, bankSeenAt, warbankSeenAt, currencySeenAt, instanceSeenAt
}
```

Why GUID keyed: your Voc- names are locked but renames still GUID-stable. Store name also for display.

On export we bundle values of chars table into array len 1..6 similar to Altoholic but smaller. Don't scan other chars — we only update current char, bundle is last-known snapshots of all chars user already logged since install.

TTL cleanup: optional `/warband optimize` removes chars not seen 90d like Warband Nexus does, average ~50KB per char normal but we will be ~8KB per due to no recipes.

## Event-driven, not polling — performance pattern

Modern best practice: build on events, not polling, treat combat constrained. Make features degradable (fail closed not spam errors). Exact quote from foundations doc.

For us — register only what we need, throttle BAG_UPDATE 0.5s (Warband Nexus pattern), debounce search if we add search .5s.

Events we listen:

- PLAYER_LOGIN / PLAYER_ENTERING_WORLD — first snapshot
- BAG_UPDATE + BAG_UPDATE_DELAYED — bags (throttled)
- PLAYER_MONEY — gold
- CURRENCY_DISPLAY_UPDATE / CURRENCY_TRANSFER_LOG_UPDATE — currencies
- BANKFRAME_OPENED / ACCOUNT_BANK_OPENED / REAGENTBANK_OPENED — Bank + warband bank contents (only readable when open)
- ACCOUNT_BANK_TAB_DATA_CHANGED — Warband Bank (5 tabs) new API C_Bank
- BOSS_KILL / ENCOUNTER_END / UPDATE_INSTANCE_INFO / LOCKOUT — lockouts
- WEEKLY_REWARDS_UPDATE — vault
- TRADE_SKILL_CLOSE / SKILL_LINES_CHANGED — professions CD placeholder

Never use OnUpdate loop. Use C_Timer.After with generation counter pattern to cancel old callbacks if user spam logs.

## C_Container modern API

Old GetContainerItemInfo deprecated. Now `C_Container.GetContainerNumSlots(bagID)`, `C_Container.GetContainerItemInfo`, `C_Container.GetBagName`. Same for banks.

Reagent bank: `C_Container.IsBagSlot` stuff, but `GetReagentBank` etc.

## Warband Bank — Midnight new

`C_Bank.FetchBankTabData`, 5 tabs account-wide, only live when you talk to banker. Pattern from Warband Nexus:

- Auto-sync when you open bank
- UI opens (optionally) at bank
- Warband gold tracked separately
- WarbankSeenAt shared across chars? If Vocnar opens warbank, it is valid for Voctara bundle — stamp "Warband Bank updated 1h ago (by Vocnar)"

## Mythic+, Vault, Lockouts — SavedInstances parity superset

SavedInstances tracks per instance per difficulty per boss bool, reset times, extended. We copy that shape but web-readable.

Implement Instances.lua responsibilities:

- Get saved instances via `GetSavedInstanceInfo` / `RequestRaidInfo`
- Boss kills: boolean array
- World bosses: `GetSavedWorldBossInfo`
- Keystone: `C_MythicPlus.GetOwnedKeystoneLevel`, `C_MythicPlus.GetOwnedKeystoneChallengeMapID` — in bag check via item scanning
- Runs: `C_MythicPlus.GetRunHistory`
- Score: `C_ChallengeMode.GetOverallDungeonScore`
- Vault: `C_WeeklyRewards.CanClaimRewards`, `C_WeeklyRewards.GetActivities`

All pure query, no secret value taint? Careful: vault aura presence check uses C_UnitAuras.GetPlayerAuraBySpellID safe truthy only, don't read fields off result.

## Vault, CLEU, Secret Values — Midnight break

Patch 12.0 introduced Secret Values. Reading aura.spellId on private aura throws secret tainted error permanently attributes taint to addon for session. Workaround: truthy check only, tonumber(UnitLevel(unit)) scrub.

CLEU no longer fires for addon code. For damage meters dead, but instance mods need per-use-case replacements with ENCOUNTER_* events. We don't meter, so minor.

Bottom line: for inventory exporter, Midnight changes barely affect us unless we read combat fields. Avoid combat log reading entirely.

## Export — wb1! deflate pattern

Standard in WeakAuras, Today-in-WoW goals: `AceSerializer → LibDeflate → print-safe, prefix !TIWG:1!` but AceSerializer heavy. We can do JSON → LibDeflate → base64url.

WeakAuras import is copy import string Copy WeakAura Import String → paste into /wa import → ready.

We copy: `/warband` panel big EditBox unfocused, user Ctrl-A Ctrl-C. Prefix wb1! reserves wb0 for Camp DNA you already have. wb2 future talents.

Be careful EditBox SetMaxLetters(0) for >2048 length — Blizzard default caps low. Set to 0 = no limit but must handle scrolling.

Sizing: 1 char 2-4KB raw ≈ 1KB deflated, 6 chars 12-18KB raw → 4-7KB deflated+b64url. WoW EditBox handles ~20KB fine with scroll.

## UI decisions for lightweight + compatible

Compat rules from modern docs: never read fields off potentially-secret without check, use tonumber scrub, avoid global hooks.

UI:

- One Frame, semi Blizzard-ish but minimal. Single 400x500 panel with list + Copy button.
- No XML templating (optional but adds one file). Use CreateFrame Lua entirely — modern Blizzard still mixes XML+Lua but CreateFrame is fine.
- Addon Compartment func opens panel. Escape closes.
- EditBox pure Blizzard Widget: label, ScrollFrame, EditBox, Button Copy. Copy selects HighlightText.
- Minimap icon on by default since 1.5.0, toggleable on the Options tab and with `/warband minimap on|off`. Not LibDBIcon: a Button parented to `Minimap`, positioned by angle, dragged on an OnUpdate that exists only between OnDragStart and OnDragStop. Compat cost is zero because nothing is registered with anything.
- No keybind globals.
- No tooltip injection by default (like Warband Nexus has enhanced tooltips showing locations). Cool but taint risk if we hook GameTooltip. Save for v2 optional.
- Slash: /warband panel, /warband copy, /warband copy current, /warband status (debug), /warband dump raw json to chat truncated.
- Settings: modern API Settings.RegisterAddOnSetting() / Settings.RegisterCanvasLayoutCategory (from midnight template features). Single checkbox 'enable compartment' etc.

## Compatibility checklist

- Load order: Libraries first, then Compat, Core, Data, UI, Config
- SavedVariables unique name
- Top-level folder name matches .toc base name — WoW hard rule else won't load.
- Use unique global only WarbandPro or addonTable namespace, no other globals.
- No frame scanning glob search, no GetGlobal dummy loops.
- Check version on load `/dump select(4, GetBuildInfo())` to verify Interface 120001 matches client.
- Fail closed: if in combat, export button disabled or queued until out-of-combat (SECURE rules)
- No OnUpdate heavy, no heavy loops in events. BAG_UPDATE throttle prevents UI spam when looting.
- Taint quarantine: don't call protected APIs from OnShow. Keep pre-logic pure.

## Performance budget target

- Memory <5MB idle (vs ElvUI 30MB). Our 6-char DB <200KB — warband-nexus average 50KB per char bigger because recipes over 3800 items cached plus mounts etc. We skip those.
- CPU — throttle prevents lag when looting all bags.
- No LibStub versioning bloat, no Ace3 overhead.

## Distribution

- BigWigsMods/packager via .pkgmeta standard to produce CurseForge/Wago/WoWInterface zips. CI/CD via GitHub Actions workflow in template (release.yml).
- .luacheckrc linting
- Folder naming hard: folder name WarbandPro must match WarbandPro.toc name
- Manual development during coding: copy template/ directory to WoW Interface/AddOns folder, rename, edit .toc, /reload. Note TOC change needs full WoW restart not just /reload.

## Data scope — what we actually capture (Altoholic+SavedInstances superset)

Warbandeer tracking issue says app vendor OpenAPI schema has zero paths for vault, currency, gold, lockout, mail, bank, bag, playtime, housing — addon only source.

Warbandeer roster.rs extracts 14 fields (name, realm, guid, class, level, ilevel, spec, role, two professions, guild, faction). Warbandeer_Characters stores per char: gold + weekly wealth history, warband bank gold, currencies/crests, Great Vault progress, Mythic+ keystones, raid/delve lockouts, mail with expiry, auctions with expiry+gold, playtime lifetime+per-day, bags+bank contents, quests, titles + account-wide title catalog, reputations, profession knowledge, houses — README states title catalog exists so tools reading your saved data can name a title without game running.

That is our ideal source-of-truth list for bundle:

- gold, warbank gold
- currencies/crests weekly/max
- Great Vault
- M+ keystones, run history, score
- lockouts (raid+delve+world boss), bosses bool, reset
- mail count+expiry, auctions
- playtime
- bags/bank/warbank breakdown items id/count/link/quality/where
- quests (weekly)
- titles/rep (light — skipped for v1 weight)
- profession knowledge/talents current tier
- consumables rollup for Tonight Plan

Explicitly not v1: equipment full (API already), recipe full list 10k rows per char (keep counts), mounts/pets/toys (account-wide), guild bank (only warband personal), chat log.

## Implementation roadmap

1. Scaffold Init.lua namespace, Core.lua event dispatcher, .toc
2. Store.lua account-wide DB with v/migration
3. Scan.lua bags/bank/reagent/warbank/gold/currencies/consumables derived for Tonight Plan
4. Instances.lua lockouts/bosses/worldboss/keystone/vault/score — SavedInstances parity
5. Bundle.lua chars[] → json + meta + seenAt
6. Export.lua deflate + b64url + wb1! + copy popup
7. UI.lua single panel + freshness dots + compartment func
8. Verify: /reload, BugSack clear, SavedVariables file <200KB, export string <7KB for 6 chars

## Decisions log

Locked: multi-char bundle default ✓, staleness per-section stamps ✓, retail Midnight only ✓, wb1! format ✓, vendor only LibDeflate ✓
Open: minimap Y/N default off, itemName in bundle or id-only + Game Data lookup (size tradeoff), warband bank stamp shared vs per-char (shared makes sense), recipe count total need static data, CF vs wago first

## Future cleanup before ship

Repo flat root per your rule (README → Problem → How to install one npx/paste → How to use 2-3 copy-pastes → What it catches → What's inside 4-6 files). No badges clutter. Keep README lean after this reference moves to wiki or deleted.

---
All from frikkern midnight template docs, themizeguy wow-addon-dev references, warband-nexus Scanner/DB patterns, WeakAuras export lessons.
