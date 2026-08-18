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
json = JSON encode (no whitespace or pretty, sort keys deterministic for test vectors)
deflate = LibDeflate:CompressDeflate(json, {level=9})
b64url = LibDeflate:EncodeForPrint(deflate) -> replace +/ with -_, strip = padding
output = "wb1!" .. b64url
```

Web:

```
assert string startsWith "wb1!"
b64 = strip prefix
inflate via pako or LibDeflate JS counterpart (we use DecompressionStream)
parse JSON, validate v==1, characters array len 1..20, each object validates minimal fields (guid, name, seenAt.lastSeen)
reject if >25KB after decode (DoS) or >20 chars
```

Test vectors in `docs/contract/vectors/v1.json` and `v1-bundle-6.json` must be kept.

## Version bump policy

- Patch (v1.0.0 -> v1.0.1) addon only, shape same, consumer unchanged.
- Minor v1 -> web adds optional fields but still accepts old. Old addon still valid.
- Major v1 -> v2 (wb2!) shape breaking, old string rejected with helpful "update addon" message in web UI.

## Security / DoS

- Never allow >20 characters in bundle, reject.
- Never stuff borrower data cross-user_id: web writes D1 only under authed user_id.
- Gold/warbank never in wb0 DNA shares unless user toggles "include gold" — web option, not addon feature.

## Sample vectors

See `vectors/v1-min.json` (1 char minimal) and `vectors/v1-full.json` (1 char full with all banks). Generated via `tools/generate-vector.lua` if you make one later.
