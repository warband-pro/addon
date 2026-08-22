# WarbandPro — wire contract wb1!

This file is the law for both addon Lua and web app D1. Any change bumps version and needs web importer update same day.

## Prefix versioning

- `wb0!` — Camp DNA share URLs you already have (existing)
- `wb1!` — Inventory + lockouts bundle (this repo v1). Gear and talents (see
  below) landed here too, additively, rather than waiting on `wb2!` — the
  website's own research found equipped gear needs no addon at all, so what
  was left to add (bag/bank gear, spec loadouts) was small enough to stay on
  the existing prefix.
- `wb2!` — future, still reserved. Nothing in this repo produces it yet.

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
  "race": "Tauren",
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

  "gear": [
    {"slot":1,"where":"equipped","id":212018,"ilvl":639,
     "s":"item:212018::::::::80:250::9:6:12053:10390:1520:10255:1:28:2462:::"}
  ],
  "talents": {
    "activeSpecID": 103,
    "specs": [
      {"specID":103,"name":"Feral","role":"DAMAGER","heroSpecID":31,
       "loadout":"C0PAAA…","seenAt":1723999000}
    ]
  },

  "mail": {"countItems":2,"goldPending":120000,"soonestExpiryHours":12,"seenAt":null},
  "auctions": {"countActive":3,"goldHeld":500000,"seenAt":1723998000},

  "currencies": [
    {"id":2815,"name":"Resonance Crystals","quantity":4500,"maxQuantity":20000,"weeklyMax":0,"earnedThisWeek":320,"isAccountWide":false,"discovered":true}
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
    "auctions":null,
    "profession":1724001000,
    "gear":1724001000,
    "talents":1723999000
  }
}
```

### Field rules

- All *_at times = unix seconds UTC from `time()`, not milliseconds. Web converts. Null if never seen.
- `race` is `UnitRace("player")`'s second return — the race **file token**,
  not the localized display name. The example above (`"Tauren"`) hides this
  because file token and display name happen to coincide for that race:
  `NightElf` carries no space where "Night Elf" does, and `Scourge` is the
  file token behind the localized "Undead". Decode against the token.
- `items` limited to inventory stacks — no bonus IDs, no enchant, no sockets. `gear[]` (below) is where that detail lives, for equipped items and for anything in a bag or bank that could be equipped. link optional but include for debug quality.
- For bank sections never opened, `free` = null and items = [] so we know "unknown" vs empty.
- Warband bank `seenByGuid` lets web show "Warband Bank updated 1h ago (by Vocnar)" valid across alts.
- `currencies.maxQuantity` 0 = no cap, `weeklyMax` 0 = not weekly-capped.
  `earnedThisWeek` is how much of `weeklyMax` this reset period has earned so
  far; web gates it on its own weekly-reset clock (`lastResetMs`) before
  trusting it for a cap warning, the same way it gates the vault.
- `consumables` is derived cache to make Tonight Plan fast: count by regex on known consumable itemIDs, not name match.
- `instances.bosses` bool order matches in-game encounter order, but name included for human search.
- Mail goldPending in copper.
- Any field unknown on old version must be treated as optional by web. New fields additive, bumps minor patch but safe.

**Fields shown above that no code in this repo currently produces —
aspirational, not a current promise:** `bankBags`, `bindZone`, `playtimeSec`,
`professionCooldowns`, `auctions.goldHeld`, `mail.seenAt`,
`professions.expansionTier`/`knownRecipes`/`totalRecipes`,
`instances.lfgID`. The CharacterObject example above is this file's stated
target shape, not a report of what `Scan.lua` actually walks — grep this
repo's Lua before decoding against any field in this section that a website
does not already read successfully from a real paste. `playtimeSec`
specifically needs `RequestTimePlayed()`, which prints to the player's own
chat frame — "silent on load" is the louder promise, so it stays unbuilt on
purpose, not by oversight.

## `gear[]` and `talents` — added in addon 1.1.0

The equipped-gear profile itself needs no addon at all: Blizzard's Profile API
(`/profile/wow/character/{realm}/{name}/equipment`) already returns
`bonus_list`, `sockets`, `enchantments`, `modified_crafting_stat` and real
per-item `level.value`. What the API cannot see is inventory — a bag or bank
holding a better piece than what's equipped — and that gap is what `gear[]`
closes. Equipped items ride along too, so best-in-bags compares gear captured
in the same moment from the same source, rather than a fresh addon snapshot
against an equipment document that only refreshes at the wearer's last logout.

### `gear[]` — one flat array per character

```json
{"slot":1,"where":"equipped","id":212018,"ilvl":639,
 "s":"item:212018::::::::80:250::9:6:12053:10390:1520:10255:1:28:2462:::"}
```

| Field | Meaning |
| --- | --- |
| `slot` | Canonical inventory slot number (1-19, see below). For a bag or bank item this is the slot it *would* occupy if equipped, not a container slot. |
| `where` | `"equipped"` \| `"bag"` \| `"bank"` \| `"warbank"`. Never `"reagent"` — the reagent bank cannot hold gear. |
| `id` | The item's numeric id. Redundant with the id embedded in `s`; kept so the website can resolve name/icon/filter without parsing the string. Deflate folds the duplication. |
| `ilvl` | `C_Item.GetCurrentItemLevel` at capture time — upgrade track, crest investment and all, which a bare item id cannot tell you. Optional; omitted if the client could not answer. |
| `s` | The item string, **verbatim**: everything between `\|H` and `\|h` in the hyperlink. Not decomposed — see below. |

**Cosmetic slots are excluded everywhere**: shirt (4) and tabard (19) never
appear, matching the website's `SLOTS` table in `gear.ts`.

**Slot numbers, standard WoW inventory IDs:**

| # | Slot | # | Slot | # | Slot |
| --- | --- | --- | --- | --- | --- |
| 1 | Head | 8 | Feet | 15 | Back |
| 2 | Neck | 9 | Wrist | 16 | Main hand |
| 3 | Shoulder | 10 | Hands | 17 | Off hand / shield / held |
| 5 | Chest | 11 | Finger 1 | | |
| 6 | Waist | 12 | Finger 2 | | |
| 7 | Legs | 13 | Trinket 1 | | |
| | | 14 | Trinket 2 | | |

For an equipped item this is the real slot Blizzard reports. For a bag or bank
item, the addon derives it from the item's equip location and **collapses
paired slots to one representative**: any ring lands on 11, any trinket on 13,
any off-hand-family item (shield, held item, off-hand weapon) on 17 — the
addon cannot know which of the two ring slots a bagged ring would go in, so it
does not guess. A character can therefore have more than one `gear[]` entry at
`slot: 11`, one `where: "equipped"` and others `where: "bag"` or `"bank"`.

**Duplication with `bags[].items[]` is deliberate.** A gear piece sitting in a
bag appears twice in the payload: once as a plain `{id, count}` stack in the
existing `bags[]`/`bank[]` arrays (which back item search), and once here with
full detail. This keeps both consumers simple rather than teaching the search
feature to read `gear[]` or vice versa; deflate absorbs the cost.

### Parsing `s` — the item string

`s` is not addon-specific. It is the same substring SimulationCraft's own
in-game addon exports, and the same thing an `/itemname` chat link carries
between the `\|H` and `\|h` markers. Colon-separated position, left to right:

```
item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel:specializationID:modifiersMask:itemContext:numBonusIDs:bonusID1:bonusID2:...:numModifiers:modType1:modValue1:modType2:modValue2:...:upgradeValue
```

**Correction:** this table named the field at position 11 `reforgeID` through
1.0.x. Reforging left the game in Warlords of Draenor; the modern layout
carries `modifiersMask` there and `itemContext` at 12, pushing `numBonusIDs`
to position 13. The wire itself never carried a `reforgeID` value — only this
document's description of it was wrong, and only for a field nothing in this
repo or the website ever read positionally before now.

The fields that matter for a SimC render or a gear audit:

- **`enchantID`** (position 2) — the permanent enchant on the item, 0 or empty
  if none.
- **`gem1..gem4`** (positions 3-6) — socketed gem item ids, 0 or empty for an
  empty socket. Socket *count* is implied by which positions are present, not
  stated separately.
- **`numBonusIDs` + the bonus ID list right after it** (position 13+) — this
  is what tells apart a Normal, Heroic and Mythic copy of the same base item
  id, and what encodes tier-set pieces, Warbound trackers, and crafted-item
  quality tiers. Read the count first, then take exactly that many following
  colon-separated fields as the bonus IDs.
- **The modifier list, immediately after the bonus IDs** — pairs of
  `(modifierType, modifierValue)`. Crafted items' chosen stat allocation
  (`modified_crafting_stat` on the Profile API) lives here as one or more
  modifier pairs; a plain drop has an empty list.
- **`upgradeValue`** (final field) — the item's position within its current
  upgrade track, where present.

**None of the above has been checked against a real captured string.** Every
item string in this repo — both sample vectors and `tools/sample.mjs`'s
generated ones — is synthetic. `sample.mjs` says so outright ("not a real
bonus-ID encoding, just something shaped like one"), and the two strings in
`vectors/v1-gear.json` disagree with each other on field count. The website's
`parseItemString()` (`gear.ts`) is written defensively as a result: it trusts
only the first ten fields (id through specialization, stable across every
modern expansion by community consensus) and treats the bonus-ID list as a
validated guess — a count, then that many positive integers, accepted only
when the shape holds all the way through. A wrong guess here costs
enrichment on an *owned* item (sockets, enchant, bonus IDs), never a
best-in-bags call, which reads only `slot` and `ilvl`. **Confirm this table
against a real `/warband copy` capture before trusting it anywhere the
defensive parser does not already guard against being wrong**, and
regenerate the vectors from that capture rather than continuing to hand-write
them.

An empty position between colons means "not set", not zero — `item:212018::::::::80:250::9:...`
has no enchant and no gems. Treat a missing trailing section as absent rather
than defaulting it to a number.

The addon does not decompose this string into named fields before sending it.
Doing so would couple this repo to whatever item model the website settles on
and to SimC's own positional format changing out from under a hand-rolled
parser here; the raw string is both lossless and exactly what the existing
SimC exporter (`simc.ts`) already knows how to consume for equipped gear.

### `talents`

```json
{
  "activeSpecID": 103,
  "specs": [
    {"specID":103,"name":"Feral","role":"DAMAGER","heroSpecID":31,
     "loadout":"C0PAAA…","seenAt":1723999000}
  ]
}
```

`specs` is an **array, not a map keyed by spec id** — `Bundle.JSON` only
encodes string keys, so a numeric key would silently vanish. `loadout` is the
same string `C_Traits.GenerateImportString` produces and the in-game talent
UI's own Copy button exports; it is what the website's `talent_loadout_code`
field already reads from the Blizzard Profile API, so this is a freshness and
independence improvement, not new information the site lacked.

Only the **active** spec's loadout is readable at any moment, so a character's
`specs` list **accumulates** across visits rather than being replaced each
scan: switch to a second spec and back, and both entries persist, each
carrying its own `seenAt`. A spec entry the addon has never seen active simply
never appears — absence means "not yet observed on this spec", not "empty".

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

**The vectors verify the envelope, not the item-string contents.** They round-trip
correctly — deflate, base64url, the `wb1!` prefix — and are real proof that
encode/decode agree on the outer format. But every `gear[].s` value inside
them is hand-written, not captured from the game, and the two vectors
disagree with each other on field count (see the item-string correction
above). The web decoder's own tests pin these vectors for structure and
counts only, deliberately not for what `s` decodes to.

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

### What `gear[]` and `talents` add, measured

`tools/sample.mjs` before and after 1.1.0, same six-character roster, same bag
fill:

| | JSON | wire |
|---|---|---|
| before (bags/bank/currencies only) | 70.9KB | 13.1KB |
| after (+ `gear[]`, `talents`) | 82.3KB | 16.4KB |
| delta for 6 characters | +11.4KB | +3.3KB |
| delta per character | ~+1.9KB | ~+0.55KB |

`gear[]` costs roughly a fixed amount per character — about 18 entries (16-17
equipped slots plus whatever unequipped pieces are worth sending), regardless
of how full the character's bags are — so the per-character delta above should
carry over to the heavier synthetic warband the 1/6/20 table used: **~512KB
JSON / ~84KB wire at the 20-character cap**, still well inside the 1MB decoded
limit. `talents` costs one loadout string per known spec and is small relative
to gear.

## Sample vectors

`vectors/v1-min.json` is one minimal character, and `v1-min.wb1` beside it is
that vector encoded — the fixture the web decoder tests against.
`vectors/v1-gear.json`/`v1-gear.wb1` add `gear[]` and `talents`. Regenerate
all four with `node tools/vector.mjs --write`. All four are hand-written, not
captured from the game — see the item-string correction above for what that
means for `v1-gear`'s `s` values specifically.
