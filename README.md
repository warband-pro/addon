# warband.pro — companion addon

> Problem: the Battle.net Profile API cannot see what your characters are actually holding.

Warband.pro already answers "who should I play tonight" from the API — ilvl, spec, lockouts, vault, professions. But the other half of Altoholic — *where did I put that* — is a wall. No endpoint returns:

- bags / bank / Warband bank contents
- gold per character
- mail
- currencies (including volatile ones like crests, flightstones, coalescing?)
- reagents, consumables, how many health pots you actually have
- which alt has the Spark, which has the Enchanted Crest

Those are impossible from the web. An in-client addon is the only way.

This repo is that addon: a tiny, retail-only, single-purpose exporter that turns your current character into a copyable hash string you paste into warband.pro.

No auto-sync, no background uploading, no CurseForge account needed. You press a button in game, you paste in web. That's it.

## How it works (the 10-second flow)

1. In WoW, type `/warband` or click the minimap button — opens the exporter
2. Hit Copy — copies something like `wb1!aH...long base64...` to clipboard
3. In warband.pro, open Import (soon: `i` key, or `/settings/import`)
4. Paste — warband.pro ingests, validates version prefix, decompresses, shows you "what's inside" before it saves

The string is opaque and versioned. `wb1!` is v1. Future versions add fields without breaking old pastes. If you paste into Discord by accident, it's just compressed JSON — no tokens, no auth, no location.

## Why hash-string, not direct upload?

- Trust: you see exactly when data leaves the game. Nothing phones home.
- Simplicity: no OAuth dance in-game, no server for the addon to talk to
- Works offline on the LUA side — you can copy in a raid and paste later when you get back to browser
- Same pattern as WeakAuras / Plater import strings — players already know it

The web app never has to guess: if you pasted it, you meant to share it.

## What it captures (v1 sketch)

From your current character, read-only, at export time:

```
meta:
  v: 1
  addonVersion: "1.0.0"
  exportedAt: 172321...
  character: "Vocnar"
  realm: "Wyrmrest Accord"
  guid: optional, for dedupe, never sent elsewhere
  retail: true (no Classic)

bags:
  - bagId, slots, items: [id, count, quality, bound?]
bank + reagent bank + warband bank (if open)

gold: copper int

currencies:
  - id, name, count, max, weeklyMax, isAccountWide

consumables summary (derived):
  pots, phials, runes, food, augments — counts across bags+bank so Tonight Plan can say "you're out of flask charges"

reagents: optional roll-up for crafting cover

location: zone? optional, for "last seen" freshness
```

Explicitly not in v1:

- Equipped gear (API already has it and better)
- Achievement / illusion / mount lists (account-wide, heavy, not needed for this job)
- Chat, guild chat, mail contents beyond counts
- Anything that requires scanning other characters — v1 is "this character only." Warband view is built by pasting 6 times, one per alt, not by the addon peeking.

v2 ideas: scan all warband alts from the Warband bank window if you open it, auto-roll all 6 characters from one export if they're cached locally.

## Format

```
wb1!<base64url(deflate(JSON))>
```

- JSON first so it's debuggable
- deflate for size (bags are repetitive)
- base64url so it survives Discord/WhatsApp but still paste-safe
- `wb1!` prefix so warband.pro can route: `wb0` would be DNA camp strings, `wb1` is inventory, future `wb2` could be talents or something else
- No encryption — you already have the data in your paste buffer if you want to base64-decode it locally. If you want proof it hasn't been tampered with between client and site, we add a CRC32 suffix later — but paste is user-to-own-site, so it's overkill for v1.

Size target: one maxed character with full bags+bank+Warband bank tab ~ 2-4KB string. Big but still selectable in the Blizzard copy box. If it gets bigger we chunk with `wb1.1/3` etc, or we ship a "slim mode" that skips item names and only sends IDs.

## Privacy / trust model

- No network requests from the addon, ever — verify in .toc: no OptionalDeps on anything that talks to web
- No SavedVariables bloat — one string, generated on demand, not kept on disk
- User-initiated only — no `OnUpdate` scanning in background; we listen to `BAG_UPDATE` only to show freshness dot, not to export
- String is local. If you stream, hide the window — same as showing your bags on stream. It's not secret like an API key, but it's yours.
- Warband.pro side: pasted string goes `D1 -> your user only`, never shared to camp unless you say "include in camp cover" — gold and Warband bank are account-wide sensitive, must be opt-in to share

## How to install (for testers — until we ship CurseForge)

```
# one paste:
git clone https://github.com/warband-pro/addon.git WarbandPro

# then move into Interface/AddOns:
# Windows: %WOW%\Interface\AddOns\WarbandPro
# Mac: /Applications/World of Warcraft/_retail_/Interface/AddOns/WarbandPro

# Reload:
# /reload
# /warband
```

Or via CurseForge app later: search `Warband.pro Companion` (reserved).

## How to use (developer flow — pre-UI)

```
/warband
/copy   -> copies string
/warband dump -> prints raw JSON to SavedVariables debug
```

In warband.pro (coming):

- `/import` route or `i` hotkey
- Textarea + paste → preview table:
  - "Vocnar — 847g — 312 pots, 47 flightstones — 2 vault keys?"
- Confirm → writes to `character_addon_cache` D1 table (new), TTL 6h like roster but user-controlled

Tonight Plan will use it if present: if you have 0 phials in bags+bank, don't recommend +12 key at 10pm when the AH is closed. That sort of thing.

## What this repo is

- Flat root (fewest files)
- One .toc, one core.lua, one ui.xml, one exporter, one vendor LibDeflate if needed
- No external libs except maybe `LibDeflate` (MIT) — deflate locally, not a web dep
- No test framework — WoW addon loader is the test, plus a tiny `scripts/verify.lua` that lints build

```
WarbandPro/
  WarbandPro.toc
  core.lua         <- slash command, lifecycle
  scan.lua         <- bags, bank, currencies, gold read-only
  export.lua       <- json -> deflate -> b64u + wb1! prefix + copy box
  ui.xml + ui.lua  <- single panel, copy button, freshness
  Vendor/
    LibDeflate/
```

## What it is not

- Not an Altoholic replacement — no search UI, no tooltip injection, no database of 200 alts. It answers one question for the web: "what is this character holding right now."
- Not a sync engine — we will never auto-upload on login
- Not Classic / SoD / Hardcore — retail Midnight (12.1) only for v1

## Decisions to lock early

1. v1 prefix is `wb1!` — do we reserve `wb0` for DNA strings already?
2. Chunking at 4096 chars? WoW EditBox has limit but copy-friendly static popup bypasses it.
3. Warband Bank: Blizzard restricts API for Warband bank outside the bank window — addon can only read it when you actually open the bank. So first paste without opening bank = incomplete — do we mark freshness as `bankClosed` and grey it out?
4. D1 schema: new `character_addon_cache` vs. extend `character_detail_cache` with nullable addon column? Separate is cleaner for TTL, but join burden for Tonight Plan.
5. CurseForge vs. wago.io vs. GitHub-only for install? CurseForge gives updates but requires packaging chapter.

## Prior art

- Altoholic (inventory — what we are a slice of)
- Bagnon / BagSync / Alto (local DB approach, heavy)
- WarcraftPets & SimC export strings (the copy/paste UX we steal)

## Open questions you're brainstorming now

- Do you want the string to be per-account in one go (all 6 Voc- tanks in one paste) or per-character and you paste 6 times? Single-char is simpler, multi-char is fewer clicks Saturday night.
- Gold + Warband bank are account-wide — if someone shares a camp DNA with gold info inside, are we comfortable? Might need to strip on share.
- Currencies: Game Data changes every patch, ids drift. Store both id+name or id only? Name is safe for web to show, but id is canonical for counting.

---

Write ideas directly in GitHub Issues tagged `[idea]` before code — or drop a line in the warband-pro workspace wiki `.wiki/wiki/topics/camp-vitals.md` under "Companion Addon" section so the next polish run picks it up.

No code in this README — just concepts, until you say build v1.
