# Docs — coding reference (trim before ship)

This folder is instruction manual for coder AI that will never see game output. Each file answers one question, no overlap. When you ship light, keep README + CONTRACT excerpt only and delete rest.

**Read order for AI:**

1. **FLOW.md** — Goal + user behavior. Why addon exists (API has 0 paths for gold/bank/bags/curr/vault/mail — vendor search proves), who Voc is (6 Voc- tanks 3H/3A, second-monitor web+game back-and-forth 4-10 exports per night, Saturday push), what success looks like, when data matters for Tonight Plan.
2. **RESEARCH-REFERENCE.md** — Midnight 12.0+ modern best practices. Interface 120001, no Ace3/libstub, load order libs→core→data→ui, account-wide WarbandProDB guid-keyed, event-driven not OnUpdate, throttle BAG_UPDATE .5s, C_Container/C_Bank 5-tab warbank only readable at banker, CLEU dead + Secret Values taint gotcha, LibDeflate wb1! standard.
3. **CONTRACT.md** — wb1! wire law. JSON shape top-level {v,addon,exportedAt,gameVersion,interface,bundle{count,freshest,oldest},characters[CharacterObject]}, CharacterObject fields gold/bags/bank/bankBags/reagentBank/warbandBank{seenAt,seenByGuid,tabs}/mail/auctions/currencies/professions/cooldowns/instances/worldBosses/keystone/runs/score/vault/consumables/seenAt timestamps. Encoding json->deflate lvl9->b64url -_ strip padding -> "wb1!" + payload. Validation: reject >20 chars, >25KB decoded, null tolerant for never-seen banks, gold stream-safe optional, missing chars not deleted.
4. **UI.md** — Copy pain fix + Import ease. Game panel 520x460 frame, ScrollFrame+EditBox Multi MaxLetters(0) AutoFocus HighlightText on Show wrapped Timer.After(0), Select All button, Esc closes, combat queue fail closed, warbank freshness header. Web Import omnipresent top-right sink `[ ↻ sync / ↥ import ▼ ]` next to battletag avatar, tries `navigator.clipboard.readText()` inside click (must be gesture), auto-fill preview if wb1! present else big textarea auto-focus placeholder paste fallback. Preview table 🟢<6h 🟡<3d 🔴>3d ⚪never with hover bag 2m bank 5d warbank 14d open to refresh, warn half stale, Confirm upserts D1 character_addon_cache, Toast imported 6 freshest 2m, Tonight Plan re-eval block vs grey based on freshness.
5. **TESTING.md** — Layers: offline luacheck + busted pure Bundle/Export/freshness dots + contract vector round-trip decode identical addon↔web, then 5-min manual scripted screenshot-parsable for AI (single char fresh, multi-char 6 bundle, warbank shared shared seenAt seenBy, combat disabled, vault matches in-game UI visual, memory <2MB, string 4-7KB).
6. **QA.md** — Copy-paste checklist release. Single char fresh, multi 6, warbank shared, combat lockdown, taintLog 0, BugSack empty, mem, len, dots. Result format `PASS/FAIL` lines human pastes back to AI for iteration.
7. **CI.md** — GitHub Actions ci.yml push luacheck+toc validator+vector, packager.yml on tag v* BigWigsMods -> CF/Wago/WI, .pkgmeta minimal, version via tag @project-version@ replace, changelog conventional commits.
8. **PROMPT.md** — Single copy-paste prompt for coder that has /app and /addon, full file list, locked decisions, impl roadmap pure->impure->UI, acceptance taint 0 mem <2MB bundle <8KB single, string prefix wb1!

**Contract vectors:** `contract/vectors/v1-min.json` minimal golden vector for CI — addon compress -> web decompress must identity. Add `v1-full.json`, `v1-bundle-6.json` via manual `/warband dump` later.

**When shipping light:** Delete docs/ except CONTRACT.md excerpt pasted into README appendix. Keep root flat per your rule (Problem -> How to install one paste/npx -> How to use 2-3 copy-pastes -> What it catches -> Inside 4-6 files). No badges, no extra dotfiles.

**Second-monitor flow doc** lives inside FLOW.md section 2-3 — omnipresent sink reason.

How to edit docs before code: keep CONTRACT shape stable, version bumps minor additive null tolerant major wb2! break. Update FLOW.md if behavior observed in actual Saturday push differs.
