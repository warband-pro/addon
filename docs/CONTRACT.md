# WarbandPro — wire contract wb1!

This file is the law for both addon Lua and web app D1. Any change bumps version and needs web importer update same day.

## Prefix versioning

- `wb0!` — Camp DNA share URLs you already have (existing)
- `wb1!` — Inventory + lockouts bundle (this repo v1)
- `wb2!` — future (talents, hero talents, maybe weekly quests)

Format = `{versionPrefix}{base64url(deflate(jsonPayload))}`

No newlines, no spaces, single line paste. WoW EditBox caps high but we avoid whitespace.

## v1 JSON payload — canonical shape

Top-level:

```json
{
  "v": 1,
  "addon": "1.0.0",
  "exportedAt": 1724001234,
  "gameVersion": "12.1.0",
  "interface": 120001,
  "bundle": {
    "count": 3,
    "freshestSeenAt": 1724001200,
    "oldestSeenAt": 1723980000
  },
  "characters": [ CharacterObject, … ]
}
```

### CharacterObject

```json
{
  "guid": "Player-112-0A1B2C3D",
  "name": "Vocnar",
  "realm": "Wyrmrest Accord",
  "realmSlug": "wyrmrest-accord",
  "faction": "Horde",
  "class": "DRUID",
  "classId": 11,
  "level": 80,
  "xp": 123456,
  "restXP": 234567,
  "guild": {"name":"Moxes","rank":"Initiate","rankIndex":2},
  "lastZone": "Dornogal",
  "hearthZone": "Dornogal",
  "bindZone": "Dornogal",
  "playtimeSec": 1234567,
  "itemLevelAvg": 623,
  "itemLevelEquipped": 621,

  "gold": 8457392,
  "bags": [
    {"bagID":0,"size":30,"free":3,"items":[{"id":211493,"count":20,"link":"|Hitem:211493::::::::80:::::::::|h[Phial]|h","quality":2,"isBound":false,"isCraftingReagent":false}]}
  ],
  "bank": [{"bagID":-1,"size":28,"free":5,"items":[…]}],
  "bankBags": [{"bagID":6,"size":28,"free":28,"items":[]}],
  "reagentBank": {"size":98,"free":12,"items":[…]},
  "warbandBank": {"seenAt":1723999000,"seenByGuid":"...","tabs":[[{id, count}]]},

  "mail": {"countItems":2,"goldPending":120000,"soonestExpiryHours":12,"seenAt":null},
  "auctions": {"countActive":3,"goldHeld":500000,"seenAt":1723998000},

  "currencies": [
    {"id":2815,"name":"Resonance Crystals","quantity":4500,"maxQuantity":20000,"weeklyMax":0,"isAccountWide":false,"discovered":true}
  ],

  "professions": [
    {"id":171,"name":"Alchemy","skill":100,"maxLevel":100,"expansionTier":5,"knownRecipes":89,"totalRecipes":120}
  ],
  "professionCooldowns": [
    {"spellID":12345,"name":"Transmute: Prismatic","readyTime":1724005000,"remainingSec":3600}
  ],

  "instances": [
    {"name":"Nerub-ar Palace","instanceID":1273,"lfgID":0,"difficulty":3,"locked":true,"resetTime":1724200000,"extended":false,
     "bosses":[{"name":"Ulgrax","killed":true},{"name":"Bloodbound Horror","killed":true}]}
  ],
  "worldBosses": [{"name":"Kordac","killed":true,"resetTime":1724200000}],

  "keystone": {"level":12,"dungeonID":503,"dungeonName":"City of Threads","where":"bag","itemID":180653},
  "mythicPlusRuns": [{"mapID":503,"level":12,"timed":true,"chestCount":2,"completedAt":1723989000}],
  "mythicPlusScore": 2345,

  "weeklyVault": {
    "raid": {"progress":1,"threshold":3,"unlocked":false},
    "mplus": {"progress":4,"threshold":8,"unlocked":true},
    "world": {"progress":3,"threshold":3,"unlocked":true}
  },

  "consumables": {"phial":120,"healthPotion":80,"tempPotion":40,"foodFeast":200,"weaponRune":20},

  "seenAt": {
    "lastSeen":1724001000,
    "bag":1724001000,
    "bank":1723999000,
    "warbank":1723999000,
    "currency":1724001000,
    "instance":1723998000,
    "vault":1723997000,
    "mail":null,
    "auctions":null
  }
}
```

### Field rules

- All *_at times = unix seconds UTC from `time()`, not milliseconds. Web converts. Null if never seen.
- `items` limited to inventory — no full equipment (API already). link optional but include for debug quality.
- For bank sections never opened, `free` = null and items = [] so we know "unknown" vs empty.
- Warband bank `seenByGuid` lets web show "Warband Bank updated 1h ago (by Vocnar)" valid across alts.
- `currencies.maxQuantity` 0 = no cap, `weeklyMax` 0 = not weekly-capped.
- `consumables` is derived cache to make Tonight Plan fast: count by regex on known consumable itemIDs, not name match.
- `instances.bosses` bool order matches in-game encounter order, but name included for human search.
- Mail goldPending in copper.
- Any field unknown on old version must be treated as optional by web. New fields additive, bumps minor patch but safe.

## Encoding steps — must be identical both sides

Addon:

```
json    = Bundle.JSON(payload)                         -- no whitespace, keys sorted
deflate = LibDeflate:CompressDeflate(json, {level=9})  -- RAW deflate, no zlib header
b64url  = Export.Base64URL(deflate)                    -- RFC 4648 §5, no = padding
output  = "wb1!" .. b64url
```

Web:

```
assert string startsWith "wb1!"
body = strip prefix
inflate: DecompressionStream("deflate-raw"), or pako.inflateRaw
parse JSON, validate v==1, characters array len 1..20, each object validates minimal fields (guid, name, seenAt.lastSeen)
reject if over the decoded size cap (see below) or >20 chars
```

Test vectors live in `docs/contract/vectors/`. `node tools/vector.mjs` round-trips
every `.json` there and writes the matching `.wb1` fixture with `--write`; the
web decoder tests read those fixtures.

### Two corrections the code made to this section

Both were found while writing Export.lua, and the code is right.

1. **It is not `EncodeForPrint`.** LibDeflate's print codec uses its own
   printable 6-bit alphabet — not base64, not base64url — so no amount of
   swapping `+/` for `-_` turns its output into something `atob` can read.
   `Export.Base64URL` is a real RFC 4648 §5 encoder, verified byte-for-byte
   against Node's `Buffer.toString("base64url")`.
2. **It is `deflate-raw`, not `deflate`.** `CompressDeflate` emits a bare
   deflate stream with no zlib header, so `DecompressionStream("deflate")`
   rejects it. Use `"deflate-raw"` / `pako.inflateRaw`. `CompressZlib` would be
   the other way to settle this, at the cost of six bytes; raw stays.

## Version bump policy

- Patch (v1.0.0 -> v1.0.1) addon only, shape same, consumer unchanged.
- Minor v1 -> web adds optional fields but still accepts old. Old addon still valid.
- Major v1 -> v2 (wb2!) shape breaking, old string rejected with helpful "update addon" message in web UI.

## v1 as implemented — four shape changes

The CharacterObject above is the target. Four things moved when it met the game
and a byte count. Each is additive or narrowing, so a website written to the
shape above still reads these bundles; a website written to *these* notes reads
them better.

### 1. `warbandBank` sits at the payload root, not on each character

```json
{ "v":1, "bundle":{…}, "warbandBank":{ "seenAt":…, "seenByGuid":…, "seenByName":"Vocnar", "gold":…, "tabs":[…] }, "characters":[…] }
```

It is one account-wide vault. Repeating five tabs of items on every character
cost **22KB of wire on a six-character bundle** for data every character shares,
because deflate's 32KB window cannot reach back far enough to fold the copies
into each other. Each character still carries `seenAt.warbank`, so the dots can
still say which character last stood at the banker, and `seenByName` is the
credit line for "Warband Bank 1h ago (by Vocnar)".

When that character is forgotten (`/warband clear`) or pruned (`/warband optimize`), the account-wide vault remains — the tabs and gold do not belong to the character — but `seenByGuid`/`seenByName` are cleared so the UI never names a GUID that no longer has a snapshot. Web Import keeps the vault row under `warband_bank_cache`, attribution moves to next seer.

### 2. Items carry `{id, count, quality?, isBound?}` — no `link`, no `isCraftingReagent`

Name, icon, quality colour and item class are all derivable from the id through
Game Data, which the website already calls. `link` is available behind
`WarbandProDB.opts.includeLinks = true` for debugging a specific item and costs
about 30% more wire when on.

### 3. `consumables` is `{phial, potion, foodFeast, weaponRune}`

Bucketed by item subclass (flask / potion / food-drink / item-enhancement), not
by a table of item ids that goes stale every patch. `healthPotion` and
`tempPotion` cannot be told apart from each other by class, so they are **absent
rather than zero** until `POTION_IDS` in Scan.lua is filled with Midnight ids —
absent means "unknown", zero would mean "you have none", and the Tonight Plan
blocks a raid on that difference.

### 4. `weeklyVault` buckets carry counts, not a single boolean

```json
"weeklyVault": { "raid": {"progress":4,"threshold":6,"unlocked":1,"slots":3,"level":626} }
```

`unlocked` is how many of that row's three slots are earned, `threshold` is the
next one still reachable and is **absent once all three are earned**. Bucket keys
come from `Enum.WeeklyRewardChestThresholdType` as the client shipped it, so a
type the addon does not recognise is dropped rather than guessed at.

## Security / DoS

- Never allow >20 characters in bundle, reject.
- Never stuff borrower data cross-user_id: web writes D1 only under authed user_id.
- Gold/warbank never in wb0 DNA shares unless user toggles "include gold" — web option, not addon feature.

### The size caps, measured

The "4-7KB for six characters" estimate elsewhere in these docs holds only for a
bundle with **no per-item lists**. With bags, bank and warband bank contents —
which is the entire "where is my stuff" feature — the real numbers, from
`tools/vector.mjs` against a synthetic full-inventory warband:

| characters | JSON | wire (`wb1!…`) |
|---|---|---|
| 1 | ~39KB | ~8.6KB |
| 6 | ~154KB | ~26KB |
| 20 (the cap) | ~474KB | ~73KB |

So the "reject >25KB after decode" rule would reject a single character. The
importer's real caps must be **1MB decoded and 20 characters**, with the
paste-box guard at ~150KB of wire. A 26KB paste is unremarkable — WeakAuras
strings routinely run larger — and `SetMaxLetters(0)` on the export EditBox is
what makes it copyable.

## Sample vectors

`vectors/v1-min.json` is one minimal character, and `v1-min.wb1` beside it is
that vector encoded — the fixture the web decoder tests against. Regenerate both
with `node tools/vector.mjs --write`.
