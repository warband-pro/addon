# AI Coder Prompt — lightweight initial setup

You have two repos:
- /app = warband.pro web (Astro + Cloudflare Worker + D1) — path ~/workspace/goals/warband-pro-wow-warband-tracker/files/app or /app if flat
- /addon = WoW companion addon — empty except README + docs/

Goal: scaffold super lightweight, compat-first retail Midnight 12.1 addon exporting Altoholic+SavedInstances superset as multi-char bundle wb1! plus web import sink.

Read in order before any code:
1. docs/FLOW.md — user story (second-monitor back-and-forth, frequent sync/export, Saturday push)
2. docs/RESEARCH-REFERENCE.md — Midnight Interface 120001, no Ace3/LibStub, account-wide WarbandProDB, throttle BAG_UPDATE .5s, C_Container/C_Bank 5 tabs, Secret Values/CLEU dodge, LibDeflate -_ base64url
3. docs/CONTRACT.md — wb1! shape, validation, vectors v1-min.json, DoS caps >20 chars / >25KB reject
4. docs/UI.md — game EditBox auto-highlight Ctrl+C pain fix, web Import modal auto-clipboard.readText() inside click + textarea fallback, omnipresent top-right sink `[ ↻ sync / ↥ import ▼ ]`
5. docs/TESTING.md + docs/QA.md

Locked:

- Retail only, Interface: 120001, Lua 5.1, vanilla (no Ace3/LibStub/CallbackHandler), vendor only LibDeflate one file
- ## SavedVariables: WarbandProDB = {v=1, chars={[guid]=…}, warbandBank={seenAt, seenByGuid, tabs}, lastExport}
- Multi-char bundle default, `wb1!` prefix, `wb0!` reserved Camp DNA, single pastes 6 alts, 4-7KB bundle 6
- Staleness dot logic 🟢<6h 🟡<3d 🔴>3d ⚪never, per-section seenAt bag/bank/warbank/currency/instance/vault/mail
- Warbank shared: if Vocnar opened warbank, export from Voctara still includes that snapshot with seenByGuid Vocnar
- Top-right sink in MenuBar.astro [ ↻ sync / ↥ import ▼ ] omnipresent + hotkey `i` opens import, existing `[data-sync-all]` mirrors remain driven by keys.ts
- Trust: no network ever from addon, stream-safe gold toggle, D1 write only user_id own, gold/warbank never in wb0 DNA unless opt-in

File list (flat root, fewest moving parts):
- WarbandPro.toc — IconTexture, AddonCompartmentFunc, SavedVariables, load order Libs/LibDeflate.lua first then Init/Core/Store/Scan/Instances/Bundle/Export/UI
- Init.lua — namespace table WarbandPro = {}, event dispatcher frame, slash SLASH_WARBANDPRO1 = "/warband"
- Core.lua — PLAYER_LOGIN/ENTERING_WORLD handling, combat queue for export
- Store.lua — account-wide orphan handling, guid-keyed update this char only, 90d cleanup optional /warband optimize
- Scan.lua — bags/bank/reagent/warbank/gold/currencies/consumables via C_Container, no scans of other chars
- Instances.lua — GetSavedInstanceInfo/WorldBoss, C_MythicPlus keystone/runs/score, C_WeeklyRewards vault, lockout bosses bool
- Bundle.lua — chars values -> json + meta + seenAt freshest/oldest, consumables rollup by itemID not name
- Export.lua — json->deflate lvl9->EncodeForPrint -_ strip = -> wb1!
- UI.lua — single frame 520x460, ScrollFrame+EditBox multi MaxLetters(0) auto HighlightText on Show wrapped C_Timer.After(0), combat lockdown safe, streamer toggle later
- Vendor/LibDeflate.lua
- .pkgmeta minimal, .luacheckrc, .github/workflows/ci.yml (luacheck+vector) + packager.yml on v*

App side:
- src/lib/warband-import.ts pure: base64url -> inflate via pako/DecompressionStream -> JSON parse -> validate schema -> staleness map, vitest offline + contract vectors
- src/components/ImportModal.astro — Import click tries clipboard, fallback textarea, preview table rows with class color, confirm upserts D1 character_addon_cache(table spec in CONTRACT/RESEARCH: user_id, realm_slug, char_name, data_json, last_seen_ms, bank_seen_ms, warband_seen_ms, imported_at_ms, addon_version), missing chars not deleted
- src/components/MenuBar.astro add combined sink button, drive existing data-sync-all + new import open via keys.ts
- Hotkey `i` via keys.ts mapping import open

Tests before push:

- luacheck . 0 warns
- node contract vector round-trip: addon compress ≡ web decompress identity
- optional busted spec_bundle.lua, freshness dot logic pure
- toc validator folder name==toc base

Manual human 5-min pass pastes back:

```
PASS BugSack empty
PASS taint 0
PASS single count 1
PASS multi count 6
PASS warbank shared valid
PASS combat lockdown safe
PASS copy prefix wb1! len 6420
PASS dots 6 green
PASS web preview 6 green
PASS mem <2MB
```

If any FAIL include screenshot truncated + /dump redacted + taint.log line.

When done, CI build lint only, no game test needed beyond vector. Ship light later: trim docs/ to CONTRACT excerpt only, flat root, no badges.

Do not delete docs/RESEARCH-REFERENCE.md yet — it's reference still.
