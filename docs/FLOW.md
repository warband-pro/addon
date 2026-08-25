# Goal + User Behavior — what we're actually building for

## Goal (one sentence)

Make warband.pro answer "who do I play tonight" with truth, not API guesses: where stuff is, who has gold/phials, whose lockout is usable, what's about to cap.

The Blizzard API can't do this. Ever. 14 fields only (name, realm, guid, class, level, ilvl, spec, role, 2 profs, guild, faction). Zero paths for gold, bank, bags, mail, auction, currencies playtime. Warbandeer vendor OpenAPI search confirms 0 paths for vault/curr/gold/lockout/mail/bank/bag. Addon is only source.

So this addon is the bridge — lightweight bundle that makes Altoholic + SavedInstances web-readable, once.

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

5. **Repeat 4-10 times per play night** — You will log alts to check the vault, to transfer gold, to grab mats. Each time you export again. So export must be <2 sec: `/warband` Enter Ctrl+C, or one key — the binding lives under Key Bindings > WarbandPro and ships unbound, because a key this addon assigned itself would take one the player has already spent. Auto-highlight, Esc closes.

6. **Saturday push** — Play normally Mon-Sat, Saturday before +12 you paste once and get all 6 current. You never remembered per-char export.

### What does NOT happen

- Not thinking about addon install after first 5 min (CurseForge or `_retail_/Interface/AddOns/` drag).
- Not reading tooltips scanning (we don't do tooltip injection).
- Not auto-uploading in background (trust/privacy — user-initiated only, we never network).
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

## What we document elsewhere

- `RESEARCH-REFERENCE.md` → Midnight 12.0+ rules, why no Ace3, Interface 120001, Compartment, C_Container/C_Bank, Secret Values/CLEU avoidance, LibDeflate wb1! standard.
- `CONTRACT.md` → wire shape, versioning, validation, DoS caps.
- `UI.md` → the game panel's exact EditBox props and auto-highlight. The website is the app repo's to specify; UI.md carries a pointer, not a design.
- `TESTING.md` → offline luacheck + pure tests + vector round-trip + 5-min manual pass scripted for AI screenshot parse.
- `QA.md` → copy-paste result format `PASS/FAIL`.
- `CI.md` → packager, semver, tokens.

This FLOW.md is the story — why we need every piece above.
