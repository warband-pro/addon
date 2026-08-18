# Docs — coding reference (trim before ship)

Instruction manual for coder AI that never sees game output. Each file answers one question, no overlap.

**Read this order:**

1. FLOW.md — Goal + user behavior. Why API has 0 paths for gold/bank/bags/curr/vault/mail, who Voc (6 Voc- tanks 3H/3A second-monitor back-and-forth 4-10 exports/night Sat push), success, when data matters for Tonight Plan, omnipresent sink why.
2. RESEARCH-REFERENCE.md — Midnight 12.0+ best practices, Interface 120001, no Ace3/libstub, load order libs→core→data→ui, account-wide WarbandProDB guid-keyed, event-driven throttle .5s, C_Container new, C_Bank 5 tabs only at banker, CLEU dead + Secret Values taint, LibDeflate wb1! -_ std, Compartment Func, Settings modern, packager.
3. CONTRACT.md — wb1! law, versioning wb0/wb1/wb2, JSON top-level+CharacterObject shape, field rules seenAt unix sec null tolerant, banks null vs empty warbank seenByGuid, encoding json->deflate lvl9->b64url strip= -> wb1!+payload, validation DoS caps >20 chars >25KB reject, bump policy.
4. UI.md — Game panel 520x460 BackdropTemplate draggable header freshness dots ScrollFrame+EditBox Multi MaxLetters(0) AutoFocus HighlightText After(0), Select All Copy Close Esc closes combat queue fail closed, Web sink `[ ↻ sync / ↥ import ▼ ]` tries clipboard.readText() inside click auto-fill else textarea fallback preview 🟢🟡🔴 hover bag 2m bank 5d etc warn half stale Confirm upserts D1 toast.
5. TESTING.md — Pure vs impure split offline luacheck+busted+vector round-trip identical addon↔web then 5-min manual screenshot-parsable single char fresh multi 6 warbank shared combat safe vault match mem<2MB string 4-7KB edge list null guards.
6. QA.md — Checklist release 5-min BugSack empty taint 0 single count1 multi count6 warbank shared combat safe wb1! len 6420ish dots 6 green web preview same mem <2MB vault matches, result PASS/FAIL lines parseable.
7. CI.md — GitHub Actions ci.yml push luacheck+toc validator+vector + packager.yml on tag v* BigWigsMods CF/Wago/WI .pkgmeta minimal vendored LibDeflate one-file, version tag @project-version@, changelog conventional commits no em dash.
8. PROMPT.md — One copy-paste prompt /app+/addon paths read order locked 8 file list flat root fewest moving parts 10 Lua + vendor + pkgmeta + luacheckrc + workflows app side pure warband-import.ts + ImportModal.astro + Menubar sink + hotkey i keys.ts tests checklist manual PASS lines.
9. EXECUTION-READY.md — Final check this file summary, why optimized simple flow, locked vs open 5 before code not blocking, next 3 days pure->impure->UI acceptance.

Vectors: contract/vectors/v1-min.json minimal golden for CI identity. Add v1-full.json + v1-bundle-6.json via /warband dump manual later.

When shipping light, delete docs/ except CONTRACT.md excerpt into README appendix. Root flat per your rule Problem→Install one paste→Use 2-3→What it catches→Inside 4-6 files. No badges.

EXECUTION-READY says ready.
