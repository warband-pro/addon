# Goal + User Behavior — what we're actually building for

## Goal (one sentence)

Make warband.pro answer "who do I play tonight" with truth, not API guesses: where stuff is, who has gold/phials, whose lockout is usable, what's about to cap.

The Blizzard API can't do this. Ever. 14 fields only (name, realm, guid, class, level, ilvl, spec, role, 2 profs, guild, faction). Zero paths for gold, bank, bags, mail, auction, currencies playtime. Warbandeer vendor OpenAPI search confirms 0 paths for vault/curr/gold/lockout/mail/bank/bag. Addon is only source.

So this addon is the bridge — lightweight bundle that makes Altoholic + SavedInstances web-readable, once.

**The bridge carries traffic both ways, and has since 1.4.0.** This file described an export-only product until 2026-09-02, which was true when it was written and had been wrong for three releases: `wbc1!` (1.4.0), `wbg1!` (1.6.0), and `wbc1!` carrying all three sections (1.8.0). The site answers a question and hands the answer back as a string you paste in here — what to clear out, what to put on, which saved build is the raid build — and the Import tab acts on it in the game. See **The loop is a round trip** below; the wire is CONTRACT.md's and the panel is UI.md's.

## User — Voc, but also every alt-aholic

- 6 tanks, 3H/3A, "Voc-" prefix locked, Horde Wyrmrest Accord / Alliance Moon Guard
- Plays retail Midnight 12.1, default Blizzard UI, only light addons (instawow, etc). Hate bloat.
- Games mostly Saturday night push, some weekday evenings 2h windows. Wants to optimize that window — not waste 20 min hunting mats.
- Second monitor with warband.pro open while playing on primary. Back-and-forth constantly.
- Catches up after long break, needs ilvl-first decisions only. Vault, crests, phials, Sparks matter. Mounts/transmog don't.

## Behavior we WILL see (design for this)

This is not "install once, export once a month". It's frequent, low-friction, ambient:

1. **Log out of char, hit sync** — character logged out after LFR. You glance at the second monitor and press `[sync with battle.net]` in the rail, beside the freshness rows it moves. You just want to know the roster is fresh.

2. **Loot something meaningful, open vault, open warbank** — you just looted Spark fragment, opened Great Vault (3/8 → 4/8), opened Warband Bank with 200 Crests inside, got 20 phials from AH mail. You know that matters for Tonight Plan. You already have WarbandPro snapping it silently in background (bag update throttled .5s, bank opened, vault update). So bundle is already fresh without you remembering.

3. **Second monitor tap to import** — game on the main screen, eyes slide right, you press `i`. The cursor lands in the rail's `$ import` field on whatever route you were reading; Ctrl+V, Enter. A receipt names the characters that arrived and decays after six seconds, and the `$ import` stamp above it moves to `just now`.

4. **Preview → Confirm → Tonight Plan flips** — Web shows 6 rows with staleness dots 🟢 <6h / 🟡 <3d / 🔴 >3d / ⚪ never. Hover says "Bags 2h ago, Bank 5d ago (open bank to refresh)". You confirm, D1 upserts each char individually, missing chars not deleted — just stale. Tonight Plan re-reads consumables rollup: "Vocgrim 0 phials → but Vocnar has 120 in Warbank → don't block +12, just consolidate first".

5. **Repeat 4-10 times per play night** — You will log alts to check the vault, to transfer gold, to grab mats. Each time you export again. So export must be <2 sec: `/warband` Enter Ctrl+C, or one key — the binding lives under Key Bindings > Warband.pro and ships unbound, because a key this addon assigned itself would take one the player has already spent. Auto-highlight, Esc closes.

6. **Saturday push** — Play normally Mon-Sat, Saturday before +12 you paste once and get all 6 current. You never remembered per-char export.

7. **The answer comes back** — site says "worst slot: neck, and you are carrying 3 things worth clearing out". You press `copy for the addon`, alt-tab, `/warband`, Import tab, Ctrl+V. The box clears itself. Gear-set row: `3 to equip · 1 already worn · 1 missing (1 in your bank) · set from 2h ago`, plus junk rows with a reason each. One `[Equip N & save set]` and you are wearing it, with an Equipment Manager set saved once the server confirms — not before, because SaveEquipmentSet snapshots what is worn AT THAT MOMENT.

8. **Sell on the way past a vendor** — `autoJunk` opens the Import tab at `MERCHANT_SHOW` if the resolved list has rows, closes at `MERCHANT_CLOSED`, never in combat and never over a window you already opened. `[Sell]` is dark away from a merchant rather than hidden. `[Disenchant]` is a secure button because it is a spell cast at an item, so it only ever fires under the player's own click.

### The loop is a round trip

Eight steps, two crossings, and **both crossings are a person pressing Ctrl+C and Ctrl+V.** That is the whole shape, and it falls out of the no-network promise rather than being a design choice on top of it:

```
  game  ──[ /warband, minimap, or Export tab ]──  wb1!  ──▶  warband.pro
                                                                  │
                                                            it decides
                                                                  │
  game  ◀──  wbc1!  ──[ Import tab, or /warband equip ]──────────  ┘
     │
   you act on it, and the next wb1! is what says you did
```

Two clocks, and hearing them as one is the mistake this file made:

- **The addon's clock is automatic.** ~30 events — `BAG_UPDATE`, the bank and bank-tab ones, `WEEKLY_REWARDS_UPDATE`, `BOSS_KILL`/`ENCOUNTER_END`, `CHALLENGE_MODE_COMPLETED`, `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_AVG_ITEM_LEVEL_UPDATE`, `TRAIT_CONFIG_UPDATED`, the currency and mail ones. **The player never decides to scan.** Step 2 above is this clock, and it is why the bundle is fresh before anyone thinks about it.
- **The player's clock is deliberate**, and fires at a milestone — the vault ticked, the key went up, the drop landed. 4-10 times a night. Steps 3 and 7 are this clock.

**Neither side may assume the other happened.** A string copied and never pasted looks exactly like one that was, on both sides of the gap. So nothing here applies on paste, and nothing on the site is marked done because a button was pressed. The only evidence a crossing landed is the next crossing back.

**What the return direction refuses, and why each refusal is load-bearing:**

- **Nothing pasted is ever executed.** Hand-rolled JSON decoder for exactly the grammar we emit; `tools/validate.mjs` fails the build on any runtime code-building call anywhere in the zip.
- **No coordinate crosses the wire.** An item is its verbatim item string, resolved against the bags that exist at the moment you press the button. A list an hour old cannot sell the wrong stack.
- **Guid is the only match key**, and only characters already in `WarbandProDB.chars` are kept. A string from someone else's account resolves to nothing and says so.
- **Fail closed in combat, and name which refusal it was.** "You are in combat" is worth retrying in ten seconds; "you have not pasted a set" means go back to the site. One "nothing happened" would send the second player to wait out a fight that was never the problem.
- **Greys are found here, not sent.** The site's copy of your bags is as old as your last paste; vendor trash is only worth listing if it is what you are carrying now.

### What does NOT happen

- Not thinking about addon install after first 5 min (CurseForge or `_retail_/Interface/AddOns/` drag).
- Not reading tooltips scanning (we don't do tooltip injection).
- Not auto-uploading in background (trust/privacy — user-initiated only, we never network).
- Not auto-applying what comes back either — same rule, other direction. A paste stores; a click acts.
- Not opening settings to tweak (default correct: account-wide `WarbandProDB`, minimap button already on the ring, addon compartment as well).
- Not managing recipe full list (too large) — we keep counts.

## App side omnipresent access (sink)

Top-right Menubar `[ ↻ sync / ↥ import ▼ ]` is single place refresh lives regardless of route:

- `↻ Sync API now` — same `data-sync-all` handler, refreshes roster/vitals/lockouts, reloads (purposeful — server-rendered rail would otherwise lie). Shows "API 12m ago".
- **Import** — a one-line field in the rail's `$ import` block, on every route. Paste, Enter. The receipt lists each character with its freshness dot and gold; the block's own stamp is the part that persists.
- bottom small line combining: `API 12m · Addon freshest 2h · Warbank 1d (by Vocnar)` — immediate trust signal second-monitor glance.

Existing block-embedded ghost sync buttons stay as mirrors, driven by same handler via `keys.ts` finding every `[data-sync-all]`. So you still see sync where motivation is (beside stale readout) and in sink where action is.

Hotkeys: `1-4` route, `?` help already. `i` opens import from anywhere.

## When data matters

- Consumables 0 and fresh → block recommendation "hit AH before raid".
- Consumables 0 but 5d old (yellow) → greyed "per last import 5d ago — verify?" not block.
- Vault progress addon-provided vs API — addon often fresher if you just opened vault on alt that API hasn't roster-fetched yet.
- Crests/tender near cap → warning "about to cap" if we show currencies later.
- Warbank scattered — 47 Spark fragments across 3 chars suggests consolidate.

## Success looks like

- Human never says "do I need to re-export?". The copy panel names the freshest stamp and warns before the copy when every character is stale; it says `copied` when Ctrl+C lands, so "did that work" is answered where it is asked.
- No data loss on export: Warband Bank seen 1h ago by Vocnar still present even if you exported from Voctara who didn't open bank. Shared account-wide.
- No combat taint: export in combat safely disabled, queue reopen after `PLAYER_REGEN_ENABLED`.
- Memory <2MB for 6 chars, SavedVariables <200KB.
- String 4-7KB bundle 6, fits EditBox, copy-paste <5 sec for whole Saturday push.
- **One paste back, not two.** A player who does half the return trip must not end up with a gear set and no clear-out list, with nothing saying so. That was true until 1.8.0 and is what `wbc1!` growing three sections fixed.
- **The gear-set row never promises an equip it cannot find.** Counts come from a resolve at render time, so `1 missing (1 in your bank)` is a fact about your bags now rather than about the string.

## What we document elsewhere

- `RESEARCH-REFERENCE.md` → Midnight 12.0+ rules, why no Ace3, Interface 120001, Compartment, C_Container/C_Bank, Secret Values/CLEU avoidance, LibDeflate wb1! standard.
- `CONTRACT.md` → wire shape, versioning, validation, DoS caps — **all three directions**: `wb1!` out, `wbc1!` back, `wbg1!` still read and no longer written.
- `UI.md` → the game panel's exact EditBox props and auto-highlight, and the Import tab that acts on what comes back — the gear-set row, the junk rows, why Disenchant is a secure button. The website is the app repo's to specify; UI.md carries a pointer, not a design.
- `TESTING.md` → offline luacheck + pure tests + vector round-trip + 5-min manual pass scripted for AI screenshot parse.
- `QA.md` → copy-paste result format `PASS/FAIL`.
- `CI.md` → packager, semver, tokens.

This FLOW.md is the story — why we need every piece above.
