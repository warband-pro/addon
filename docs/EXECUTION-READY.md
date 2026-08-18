# Execution Ready — final check

We did final doc pass on Tue 2026-08-18 15:01 PT. This repo is ready to hand to coder.

## What you have

- Total doc lines: ~1122 (README 150 + docs 950 + vector 20) — no code yet.
- No TODO/FIXME/TBD — clean.
- 11 commits on main, latest 440925a `docs: final push — FLOW + PROMPT + simplified README + optimized docs index`.

## Reading order (AI must follow)

1. README.md (5 min) — problem, multi-char bundle, 10-sec flow, what it captures, staleness, format, trust, install/use, second-monitor flow, repo shape, modern stack, docs index, decisions locked/open.
2. docs/FLOW.md (6 min) — user Voc 6 Voc- tanks 3H/3A, games Sat push + weekday 2h, second monitor 4-10 exports/night, back-and-forth detailed steps 1-6, what does NOT happen, omnipresent sink top-right reason, when data matters, success looks like.
3. docs/RESEARCH-REFERENCE.md (8 min) — Interface 120001 Midnight, no Ace3/LibStub, load order libs→core→data→ui, account-wide WarbandProDB guid-keyed, event-driven throttle .5s, C_Container new, C_Bank 5 tabs only at banker, vault/currency, CLEU dead/Secret Values taint, LibDeflate -_ base64url std, Compat Func, Settings modern, BigWigs packager.
4. docs/CONTRACT.md + vectors/v1-min.json (7 min) — wb1! law, versioning wb0/wb1/wb2, JSON top-level + CharacterObject full, field rules seenAt unix sec, banks null vs empty, warbank seenByGuid, currencies caps, consumables derived, encoding steps deflate lvl9 + b64url strip = prefix, web decode validate + DoS caps >20 chars >25KB decoded reject, bump policy patch/minor/major.
5. docs/UI.md (5 min) — game panel 520x460 BackdropTemplate draggable, header freshness, ScrollFrame+EditBox Multi MaxLetters(0) AutoFocus HighlightText on Show C_Timer.After(0), Select All + Copy Close buttons, helper lines 1-3, streamer gold ••• toggle later, >20KB guard slim mode, combat queue fail closed via PLAYER_REGEN_ENABLED one-shot, manual proof easy checklist.
   Web sink `[ ↻ sync / ↥ import ▼ ]` omnipresent in Menubar next to avatar, tries navigator.clipboard.readText() inside click else textarea auto-focus, preview 🟢🟡🔴 hover bag 2m bank 5d warbank 14d, warn half stale, Confirm upserts D1 character_addon_cache, toast, Tonight Plan re-eval block vs grey.
6. docs/TESTING.md (4 min) — pure vs impure split, offline luacheck + busted pure + contract vector round-trip identity addon↔web, 5-min manual screenshot-parsable single char fresh multi 6 warbank shared combat safe vault matches memory <2MB string 4-7KB, edge list banks never opened = null not 0 etc.
7. docs/QA.md (2 min) — preflight fully quit WoW not /reload, only WarbandPro+BugSack, taintLog 1, fresh install wipe optional, pass1 single char fresh list 9 items, pass2 multi 5 items warbank shared, pass3 edge combat/memory/size, result format PASS/FAIL lines machine-parseable.
8. docs/CI.md (2 min) — ci.yml luacheck+toc validator+vector, packager.yml on v* BigWigsMods CF/Wago/WI, .pkgmeta externals vendored one-file LibDeflate preferred, release flow semver MAJOR break wb2! MINOR additive null safe PATCH fix, changelog conventional commits flat lowercased no em dash, tokens secrets.
9. docs/PROMPT.md (2 min) — single copy-paste prompt /app+/addon paths, read order, locked list 8 items, file list flat root fewest moving parts toc load order + 10 lua + vendor + pkgmeta + luacheckrc + workflows, app side warband-import.ts pure vitest + ImportModal.astro clipboard auto + Menubar sink + hotkey i via keys.ts, tests luacheck+vector+busted+toc validator, manual PASS lines list 10.
10. docs/README.md (1 min) index repeat.

## Why this is optimized simple flow

- Flat root rule you set kept even in docs/ — each doc answers one Q, no duplicate area.
- No bloat mount/pet/toy/recipes full — counts only, pruned per your hate-bloat.
- Multi-char bundle decided, no longer debating per-char vs bundle.
- Staleness per-section not just per-char — addresses Vault after open edge you flagged.
- Game copy pain explicitly solved — EditBox Multi MaxLetters(0) HighlightText After(0) is known painkiller from WeakAuras pattern, not guessed.
- Web import auto-grab trick legal only inside click gesture — documented why polling won't work.
- Frequent second-monitor 4-10x/night flow documented as number one use, not Saturday-only assumption.
- Contract null-tolerant vs unknown — so addon can evolve minor additive without web breaking that Saturday push.

## Decisions locked vs open — clear

Locked: multi-char default, staleness per-section stamps, retail Midnight only, wb1! format, vendor LibDeflate only, omnipresent top-right sink, pure/impure test split, flow second monitor.

Open last 5 before code but not blocking start:
- minimap Y/N (default off)
- itemName in bundle or id-only + Game Data lookup (size vs debugging tradeoff)
- warbank shared stamp wording "by Vocnar" vs per-char stamp same time (shared makes sense)
- recipe totalRecipes needs static data fetch (maybe borrow from Warbandeer static-data.json idea)
- CF vs Wago first (CF larger but review slower, Wago instant)

## What coder does next (when you unleash)

Pure files first day: Bundle.lua, Export.lua, warband-import.ts + vitest, freshness dot logic → luacheck clean, vector round-trip green → high confidence before human opens WoW.

Impure day 2: Store.lua account-wide orphan handling guid-keyed only current char, Scan.lua C_Container + C_Bank + currencies, Instances.lua GetSavedInstanceInfo / WorldBoss / MyPlus / WeeklyRewards, Core init event dispatcher combat queue.

UI day 3 last: UI.lua single frame + ImportModal.astro + Menubar sink edit + keys.ts `i` binding.

Acceptance described in PROMPT.md: no taint, BugSack empty, bundle prefix wb1! len 6420ish 6 bundle, mem <2MB, dots 6 green, web preview same, warbank shared valid, combat safe.

## Ships light guarantee

When ready to ship, we delete docs/ except contracted excerpt into README appendix, keep root flat Problem → Install one paste → Use 2-3 copy-pastes → What it catches → Inside 4-6 files, no badges clutter, per your minimalism rule.

CI won't exist yet but .pkgmeta minimal will be added by coder per template.

Ready.
