# Testing strategy — WoW addon you can't run headless

We can't auto-run WoW Lua outside game. AI will never see /reload output directly. We need layers to catch most before manual pass, and make manual pass so repeatable a sick LLM can read screenshot text back.

## Layering philosophy

Like modern Midnight template docs: debugging first-class, every feature degradable, build on events not polling.

We split code into two halves:

- **Pure / deterministic** — can be unit tested on CLI: Bundle.lua, Export.lua decode flow, consumables rollup, freshness dot logic, CONTRACT validators, gold math, and **Roster.lua's whole grid model** (1.9.0 — a DB table in, a display model out). WoW API = 0 inside these. Injection: caller passes data tables, function returns tables/strings. No globals.
- **Impure / WoW-bound** — Scan.lua, Instances.lua, Cooldowns.lua, Store.lua, UI.lua, Core.lua dispatcher. Require GAME. Test via manual checklist + BugSack + /dump + screenshots.

`Cooldowns.lua` splits the same way the bank scan does, and there is no third
category for it: the *read* needs a profession window open in a real client and
is checked in `QA.md`, while the **bookkeeping either side of it is pure and is
tested here** — the merge-by-skill-line rule lives in `Store.PutProfessionCooldowns`
with `tools/freshness-test.lua` behind it, and the cell rules live in Roster.lua
with `tools/roster-test.lua` behind them. That is the same seam that caught the
warband bank replacing four tabs with one and stamping the loss fresh.

The roster is the clearest case the split has: the grid is a display, and a
display is the thing hand-checking is worst at — six columns of numbers all
look plausible. So every rule about WHAT is in a cell lives in Roster.lua and
is tested here (`tools/roster-test.lua`, 36 assertions), and what is left for
the QA pass is only whether it draws: alignment, paging, the class colours.
**The rule most worth a test rather than an eyeball is that an absent reading
draws an empty cell and never a `0`** — on screen those two differ by one
character and mean opposite things.

That means AI can get high confidence before human opens WoW: if pure tests pass + luacheck clean + .toc list valid, only WoW integration remains risky.

## 1) Offline checks (run every commit, CI)

### Luacheck (lint)

Template comes with `.luacheckrc`. Put at repo root:

```
std = "lua51"
globals = {"SLASH_WARBANDPRO1","SlashCmdList","WarbandProDB","WarbandPro"} // minimal whitelist, prefer addonTable
ignore = {"212/self"} // allow unused self for colon vs dot tolerance
-- WoW globals defined via compat
read_globals = {"time","date","tostring","tonumber","math","string","table","C_Timer","C_Container","C_Bank","C_MythicPlus","C_WeeklyRewards","GetRealmName","UnitGUID","UnitName"}
```

Run: `luacheck .` must be 0 warnings.

### Pure Lua tests on host lua (5.1)

Install busted or plain lua. File `tests/spec_bundle.lua`:

- Takes `v1-min.json` from vectors, encodes via LibDeflate in pure-lua stub (Node test uses pako), decodes round-trip exact equal.
- bundle → wb1! prefix, b64url alphabet `-_` only, strip `=` padding.
- parse rejected if >20 chars, >25KB decoded.
- freshness dot: input seenAt delta → 🟢<6h 🟡<3d 🔴>3d ⚪null correct.
- consumables rollup: 20x phial itemID => phial 20 even if split stacks.

Run in CI via `lua -l tests.vendor.libdeflate tests/spec_bundle.lua` (vendor pure Lua copy if needed) or Node equivalent if we ship Node decoder in /app.

### CONTRACT vector test

CI job `check-contract-vectors`: load each `docs/contract/vectors/*.json`, compress via LibDeflate JS (Node pako_deflate equivalent to LibDeflate) and verify round-trip decodes back exactly with web decoder 1:1. Ensures addon compress ≡ web decompress. If vectors drift we fail PR.

### TOC validator

Script `scripts/validate-toc.ps1` in themizeguy skill — scans .toc file lists exist, Interface matches select(4, GetBuildInfo()) via local install scan, folder name matches .toc base.

### .pkgmeta validity

CI checks `BigWigsMods/packager` prep lints .pkgmeta yaml/required deps.

## 2) In-game manual — scripted to be screenshot-readable

Human (you) logs once per char per test pass. We make game expose text UI so AI can read screenshot if needed.

### First-run checklist (~5 min per char)

- Fully quit WoW (TOC change not /reload enough)
- Enable only WarbandPro + BugSack/BugGrabber
- Log one char: chat should be silent (no print on load). Only /warband status shows panel.
- /warband status → dumps `WarbandProDB.chars count = 0 -> 1` after login snapshot. Screenshot its lines.
- Open bags, move item, wait 1s (BAG_UPDATE debounce) — DB bagSeenAt timestamp increments /dump WarbandProDB.chars[guid].seenAt.bag.
- Open bank — until opened bank field `free` = nil. After open, numbers show, snapshot includes bank items.
- Open Warband Bank — unless opened, warbandBank.seenAt = nil. After open, Warband Bank shared seenAt stamps.
- Check currencies tab — gold decimal shows. /dump WarbandProDB.chars[guid].currencies count >= expected.
- /warband copy — big EditBox appears, string starts `wb1!`. Ctrl-A Ctrl-C copies. Paste into web /import → preview table shows 1 char 🟢.
- Try multi: log alt 2, /warband copy → bundle len 2. Web ingests 2 but leaves old char untouched (does not delete missing).
- In combat -> /warband button disabled or "can't export in combat" red text (combat lockdown fail-closed).

### BugSack must stay empty entire pass

If Luacheck clean, usually empty, but verify.

### Taint check

`/console taintLog 1` before pass, `/reload` after full sweep, check `Logs/taint.log` for line with WarbandPro. Must be empty. Secret Values mistake triggers taint permanently for session — we mostly safe but stay cautious.

### Warband Bank isolation test

- Log Vocnar, open Warband Bank containing 100 Crest. Log Voctara (did NOT open bank). Export from Voctara — bundle must still contain Warband Bank from Vocnar's last snapshot with seenByGuid Vocnar + seenAt original. This proves shared account-wide bank modeling.

### Performance

- /script with batch measurement: `collectgarbage`, measure addon memory after load vs after full scan — delta <2MB. No OnUpdate.

## 3) App side import tests (pure)

Vitest in /app: decoder for wb1! using pako, validate schema, rejectoversized, upsert D1 with staleness calculation, never includes gold in DNA unless includeGold opt-in toggle.

Include contract vectors from addon repo as git submodule or copy (your vet).

## 4) Screenshot contract so AI can parse manual results

Manual tester pastes output as text lines not vague "it broke":

```
PASS/FAIL WarbandPro taint 0
PASS/FAIL BugSack empty
PASS/FAIL status count 6
PASS/FAIL copy prefix wb1!
PASS/FAIL bundle count 6
PASS/FAIL warbank shared seenAt valid
PASS/FAIL vault progress matches in-game UI (visually check 4/8)
PASS/FAIL web preview dots correct 6x green
Memory: 1.2 MB
String bytes: 6420
```

That format can be fed back to AI for next fix loop.

## 5) Automation for non-WoW parts

Packager CI fails if token leakage, .toc name mismatch, luacheck warn, contract vectors fail.

## Edge cases we document before code so AI anticipates outcome

- Bank never opened -> bank field = {free=null,items=[]}. We show "open bank to refresh" in UI, not 0.
- Mailbox never opened -> mail.seenAt null, we show ⚪ never not zero pending.
- Warband Bank Never opened -> same null state.
- Currency not discovered — item id not in game client yet after new patch, discovery flag false — web lookup fallback to id display.
- Currency weekly cap exceeding: quantity may exceed weeklyMax after character transfer? Show clamp warning not crash.
- Reset time past -> locked false fallback? Our Instance parser treats resetTime < now as unlocked next cycle.
- Key not found -> keystone field null, not {} to avoid falsy shmup.
- Recipe total not yet fetch able on first login after expansion — knownRecipes only, total null.

Each baked into CONTRACT.md validator: web tolerates null, addon never crash on null api.

## Tooling for AI to verify before it sees game

- Generate vectors in game manually once via `/warband dump` redacted. Paste into repo vectors/ as golden. CI enforces new code still matches vector decompress identical.

- Provide `docs/QA.md` checklist with copy-paste /dump macros so human can run in 2 minutes without remembering.

That way AI never blocked: it writes pure logic, triggers offline tests (luacheck + busted + vector), human runs 5-min checklist pass pasted back text-formatted as above, AI's next iteration deterministic.

