# WarbandPro — wire contract wb1!

This file is the law for both addon Lua and web app D1. Any change bumps version and needs web importer update same day.

## Prefix versioning

- `wb0!` — Camp DNA share URLs you already have (existing)
- `wb1!` — Inventory + lockouts bundle (this repo v1). Gear and talents (see
  below) landed here too, additively, rather than waiting on `wb2!` — the
  website's own research found equipped gear needs no addon at all, so what
  was left to add (bag/bank gear, spec loadouts) was small enough to stay on
  the existing prefix.
- `wb2!` — future, still reserved. Nothing in this repo produces it yet, and
  `wbc1!` deliberately did not spend it.
- `wbc1!` — the **return** direction, added in 1.4.0: the cleanup list
  warband.pro produces and the player pastes into `/warband junk`. A separate
  channel rather than a version of the one above, so it can version on its own
  schedule — see the `wbc1!` section for the payload and the matching rules.

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
  "interface": 120100,
  "bundle": {
    "count": 3,
    "freshestSeenAt": 1724001200,
    "oldestSeenAt": 1723980000,
    "droppedOverCap": 21,
    "page": 1,
    "pages": 3
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
     "s":"item:212018::::::::80:250::9:6:12053:10390:1520:10255:1:28:2462:::"},
    {"slot":11,"where":"bag","id":215135,"ilvl":626,"n":"Seal of the Poisoned Pact","q":3,"cls":4,"sub":0,
     "s":"item:215135::::::::80:250::4:6:12053:1:28:::"}
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
    "reagentBank":1723999000,
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
- **A stamp moves only if that section was actually read this pass.** The bank
  and the reagent bank are two containers that can come back independently, so
  they are two stamps — `seenAt.reagentBank` was added in 1.8.0, and before it
  a reagent-bank-only read moved the shared `bank` stamp and drew a fresh dot
  on bank contents from the previous banker visit. A section absent from
  `seenAt` has never been read; a section whose stamp did not move was looked
  for and not found, and its stored value is exactly as old as the stamp says.
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
{"slot":1,"where":"equipped","id":212018,"ilvl":639,"n":"Aureate Sentry's Greathelm",
 "cls":4,"sub":4,
 "s":"item:212018::::::::80:250::9:6:12053:10390:1520:10255:1:28:2462:::"}
```

| Field | Meaning |
| --- | --- |
| `slot` | Canonical inventory slot number (1-19, see below). For a bag or bank item this is the slot it *would* occupy if equipped, not a container slot. |
| `where` | `"equipped"` \| `"bag"` \| `"bank"` \| `"warbank"`. Never `"reagent"` — the reagent bank cannot hold gear. |
| `id` | The item's numeric id. Redundant with the id embedded in `s`; kept so the website can resolve name/icon/filter without parsing the string. Deflate folds the duplication. |
| `ilvl` | `C_Item.GetCurrentItemLevel` at capture time — upgrade track, crest investment and all, which a bare item id cannot tell you. Optional; omitted if the client could not answer. |
| `s` | The item string, **verbatim**: everything between `\|H` and `\|h` in the hyperlink. Not decomposed — see below. |
| `n` | Display name, out of the same hyperlink's brackets. Added in 1.3.0; bag/bank/warbank entries only. The website has no item-id-to-name lookup at all, so without this a cleanup row renders as a bare id. |
| `q` | Numeric quality, 0 Poor … 5 Legendary, from the container item info. Added in 1.3.0; bag/bank/warbank entries only. |
| `b` | Soulbound. **Emitted only when true** — absence means NOT bound, never "unknown", matching `items[].isBound`. The website's BoE guard depends on that reading. Added in 1.3.0; bag/bank/warbank entries only. |
| `cls` | Item class id (2 Weapon, 4 Armor), `GetItemInfoInstant` position 6. Added in 1.3.0; bag/bank/warbank entries only. |
| `sub` | Item subclass id, `GetItemInfoInstant` position 7, **verbatim and uninterpreted**. For armor it is 1 Cloth … 4 Plate *on the eight slots that have an armor weight* — and **a cloak reports 1 as well**, which is not a weight and not a claim that only cloth wearers may equip it. Necks, rings and trinkets report 0. With `cls` this is what lets the website call an item unwearable by this class, and the slot is what says whether the question is answerable at all — see the note below. Added in 1.3.0; bag/bank/warbank entries only. |
| `th` | **Two-handed.** Weapon-slot entries only (`slot` 16 or 17), and a real boolean on every one of them — never omitted-when-false, so its absence dates the bundle rather than needing a second field the way `b` does. `slot` collapses `INVTYPE_2HWEAPON` and `INVTYPE_WEAPON` to the same 16, so without this a consumer cannot tell a two-hander from a one-hander and will call a 2H an upgrade over a main hand while the off-hand beside it is silently unequipped. Only `INVTYPE_2HWEAPON` is claimed: `INVTYPE_RANGED`/`INVTYPE_RANGEDRIGHT` cover bows and guns (two-handed) but also wands (not), and no spec equipping any of the three carries an off-hand, so the distinction is unreachable and not worth a wrong claim. Added in 1.7.0; bag/bank/warbank entries only. |
| `st` | The item's stat values: `C_Item.GetItemStats` tokens **verbatim**, a map of `ITEM_MOD_*` string → number (e.g. `{"ITEM_MOD_CRIT_RATING_SHORT":581,"ITEM_MOD_INTELLECT_SHORT":1204}`). Never compacted, never interpreted — a token this addon has not heard of still reaches the wire, and a consumer ignores what it does not know. Omitted when the client could not answer (an uncached item on a cold login); absence means "not read", never "no stats". Added in 1.6.0; bag/bank/warbank entries only. |

**`sub` is a subclass, not an armor weight, and `slot` is what tells them
apart.** Subclass 1 means Cloth on head, shoulders, chest, waist, legs, feet,
wrists and hands. On `slot` 15 it means *cloak*, an item every class wears.
The addon sends what `GetItemInfoInstant` returned and interprets neither; a
consumer that tests the subclass against a class's armor proficiency must
first check that the slot is one of the eight, or it will call every cloak in
a plate wearer's bags unwearable. warband.pro did exactly that until
2026-08-23, and the verdict rides `wbc1!` back here as a disenchant, so the
cost of the misreading is a destroyed item rather than a wrong row.

**The 1.3.0 fields never appear on `where:"equipped"` entries.** The website
resolves an equipped item through the Profile API, which already carries name,
quality and class, so repeating them here would be dead weight on every
character. All five are optional and additive on `wb1!`: a bundle from an
older addon carries none of them, and the website reads absence as "this addon
did not send it", never as a value.

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

**`n`, `q`, `b`, `cls` and `sub` were added in 1.3.0 for the cleanup feature**
(`wbc1!`, below). All five are additive on `wb1!` and optional: an older
website reading a newer bundle simply does not see them, and a newer website
reading an older bundle must treat their absence as "not looked at" rather
than as a value — the same rule every other optional field carries.

**`st` was added in 1.6.0 for best-in-bags.** Ordering two owned items needs
their stat values, and the Profile API only has stats for *equipped* items —
the same asymmetry that made `gear[]` exist at all. The alternative was a Game
Data call per owned item id on the website, and that trade has now been
declined three times for the same reason (`ilvl` in 1.1.0, `n` in 1.3.0): a
per-item resolution cost grows with the warband, a per-question one does not.
The tokens repeat across every entry of every character, which is exactly what
deflate folds — measured with `tools/sample.mjs`, the field costs roughly
half a kilobyte of wire per character against a 150KB paste guard.

One tradeoff is priced in rather than solved: a best-in-bags comparison reads
the *owned* side's stats from this field, captured moments ago, and the
*equipped* side's from a Profile API document that refreshes at last logout.
The two can be one logout apart. That is the same staleness `ilvl` has carried
since 1.1.0, and the remedy when it matters is a fresh logout, not a wire
change — equipped entries do not carry `st` for the same reason they carry
none of the 1.3.0 fields.

The name is the load-bearing one. The website has no item-id-to-name lookup at
all: resolving one means a Game Data call per item id, which is exactly the
cost item search avoids by resolving the *query* instead. A cleanup list is the
opposite shape — it starts from inventory — so a name already sitting in the
hyperlink here saves a call per row there. It is read with a second `match` on
the link the item string already came from, not from `GetItemInfo`, which is
async and may not have loaded when the scan runs.

`cls`/`sub` come from `ns.itemInfo`, which memoizes `GetItemInfoInstant` per
item id for the session and was already being called to classify the slot — so
both fields cost nothing beyond the bytes. They exist so the website can judge
whether *this* character can wear an item without shipping an armor-class table
or an equippable-items dump: **the addon does not filter gear by what the
character can use**, it never has, and `EQUIPLOC_SLOT` gates on equip location
only. A plate chest in a druid’s bag belongs on the wire; until 1.3.0 the
website had no way to know it was plate.

> **Correction, 2026-08-23.** This paragraph read "has always been on the
> wire". True of the intent, false of the fact: **no bag, bank or
> warband-bank gear reached the wire at all between 1.1.0 and 1.3.0.**
> `ns.itemInfo` read `GetItemInfoInstant`’s icon (position 5) where it meant
> to read `itemEquipLoc` (position 4), so `EQUIPLOC_SLOT` missed on every
> item and `Gear.Visit` returned early every time. Equipped gear was
> unaffected — `Gear.Equipped` walks fixed slot numbers and never consults
> equipLoc — which is exactly why nobody noticed: the wire looked populated.
> Fixed in 1.3.0 and pinned by `tools/gear-test.lua`, whose fixture puts a
> valid `INVTYPE_*` string in the icon position so a repeat reads as a wrong
> slot rather than as an empty bag.
>
> Two consequences when reading older data: a bundle from 1.1.0-1.2.x carries
> `gear[]` entries that are **100% `where:"equipped"`**, and the website’s
> best-in-bags had no input for its entire existence.

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
     "loadout":"C0PAAA…","seenAt":1723999000,
     "loadouts":[
       {"id":31,"name":"Raid","s":"C0PAAA…","seenAt":1723999000},
       {"id":42,"name":"M+","s":"C0PBBB…","seenAt":1723998000}
     ]}
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

#### `loadouts[]` — added in 1.8.0, additive

`loadout` is the string for whichever build was active at the last scan.
`loadouts` is the player's **named** saved builds for that spec, which is what
lets warband.pro say "this is your raid build" rather than "this is the build
you happened to be on".

| field | | |
|---|---|---|
| `id` | number | the client's config id, and the identity a merge is keyed on |
| `name` | string | the name the player gave it in the talent UI — `Raid`, `M+`, `Delve`, or anything else |
| `s` | string | the import string, same format as `loadout` |
| `seenAt` | number | when this entry was last read |

**`name` and `s` are each individually optional.** A read that fails leaves
whatever was stored alone rather than clearing it, so an entry can carry a name
with no string, or a string with no name, until a later pass fills the other
in. A consumer must treat a missing `s` as "not readable yet", never as empty.

The list is built by two mechanisms and **only the second is guaranteed**:

1. *Enumeration* — `C_ClassTalents.GetConfigIDsBySpecID` lists the saved
   loadouts and `C_Traits.GenerateImportString` is asked for each. When this
   works, every build arrives in one pass.
2. *Accumulation* — the build the player is actually on is recorded every scan,
   name included, using only the call this addon has always made successfully.

Whether the client will serialize a config that is not active is **unmeasured**
— nothing in CI runs the game — so the format does not depend on the answer.
If (1) returns nothing, `loadouts` still fills in as the player switches
between their builds, the same way `specs` fills in across a spec switch. The
website must therefore be correct with a partial list, and must not assume
three entries because it names three content types.

At most `ns.MAX_LOADOUTS` (8) entries are kept per spec, oldest-capped rather
than evicted: past the cap a new config id is dropped and existing entries keep
updating. The cap is a byte ceiling, not a guess at how many builds anyone has.

**Additive, so `wb1!` does not move.** An older website ignores the field and
reads `loadout` exactly as before. The consequence of a client that drops it is
that named builds are unavailable — never that a wrong one is applied.

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
every `.json` there and writes the matching fixture with `--write`; the web
decoder tests read those fixtures. A vector named `wbc1-*` is the return
direction and gets a `.wbc1` fixture through the same encoder — see the
`wbc1!` section below.

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

## `wbc1!` — the return direction, added in addon 1.4.0

Everything above describes the addon talking to the website. This is the one
string that goes the other way: the cleanup list warband.pro's `/gear` view
produces, which the player pastes into `/warband junk`.

### Why not `wb2!`

`wb2!` is reserved above for a **breaking bump of the outbound wire** and stays
reserved. This is not a new version of that wire — it is a different channel,
carrying a different payload, in the other direction, and it will want to
version on its own schedule. Giving it `wbc1!` also means each decoder can
recognise the other's prefix and say *where the string belongs* rather than
that it is broken: the two paste boxes sit in two different applications, and
a string in the wrong one is misfiled, not malformed. Both sides implement
that refusal, and `tools/vector.mjs` tests it in both directions.

### Envelope — identical to `wb1!`, reversed

```
json    = canonical JSON            -- no whitespace, keys sorted, same rules as Bundle.JSON
deflate = raw deflate               -- no zlib header
b64url  = RFC 4648 §5, no = padding
output  = "wbc1!" .. b64url
```

The website encodes with `CompressionStream("deflate-raw")` and its own
canonical stringifier; the addon decodes with `LibDeflate:DecompressDeflate`
and `Import.JSONDecode`. **No checksum**, matching `wb1!` — deflate fails
loudly on a corrupt stream and both decoders fail closed after it.

The website emits canonical JSON rather than whatever its `JSON.stringify`
produces for one reason: it makes `vectors/wbc1-min.wbc1` a **golden** vector
instead of an example. The committed fixture is byte-identical to what
`src/lib/cleanup.ts` emits, so a test on either side catches the other drifting.
A payload that merely decodes the same would only prove the decoder works.

### Payload

```json
{
  "v": 1,
  "generatedAt": 1724000000,
  "chars": [{
    "guid": "Player-1-TEST",
    "name": "Vocnar",
    "items": [
      {"k":"de","id":221151,"s":"item:221151::...","r":"unusable","ilvl":610},
      {"k":"de","id":215135,"s":"item:215135::...","r":"gap","g":56,"ilvl":570}
    ]
  }]
}
```

| Field | Meaning |
| --- | --- |
| `v` | Format version, `1`. A different value is a hard reject. |
| `generatedAt` | Unix **seconds**, same unit as `seenAt` everywhere else here. The junk panel prints its age; there is no expiry. |
| `chars[].guid` | `UnitGUID("player")`, exactly as this addon stored and sent it. The match key — see below. |
| `chars[].name` | Display only, for the panel header. Never matched on. |
| `items[].k` | The verdict: `sell`, `de` (disenchant), or `del`. |
| `items[].id` | Item id, for display and for a sanity check against the resolved item. |
| `items[].s` | **The identity key.** The verbatim item string, as this addon sent it. |
| `items[].r` | Why: `gap` (far below the equipped piece), `unusable` (wrong armor class), `dupe` (a copy of an item already worn — see below), or `dominated` (another item in the same bags beats it on item level and on every stat at once). **An unknown value is displayed as no reason at all, never rejected**, so the website may add one without an addon release — `dominated` shipped through exactly that door. |
| `items[].g` | Item levels below the equipped item it would replace. Present only when `r` is `gap`. |
| `items[].ilvl` | The item's own level, for the row. Optional. |

### `sets[]` — a setup per spec, added in 1.10.0

`wbg1!` carried one set per character until 1.10.0, because the website could
only solve the spec you were logged out in. It can solve any of them now, and
one set per character became actively wrong: a stored Feral set is not an
answer to a Restoration paperdoll, and pasting an off-spec solve silently
overwrote the set you sent an hour ago, under a name that gave you no way to
notice.

So a character entry may carry `sets`, one entry per spec the website solved:

```json
{"guid":"Player-1-TEST","name":"Vocnar",
 "spec":103,"set":"warband.pro Feral","items":[ ...the Feral set... ],
 "sets":[
   {"spec":103,"set":"warband.pro Feral","items":[ ... ]},
   {"spec":105,"set":"warband.pro Rest","items":[ ... ]}
 ]}
```

| Field | Meaning |
| --- | --- |
| `sets[].spec` | **Required.** The specialization id this setup was solved for, and the key it is stored under. An entry without one is dropped — it has nothing to be filed as. |
| `sets[].set` | The Equipment Manager set name for this setup. Proposed, not final — see below. |
| `sets[].items` | Exactly the same shape as `items` above, validated by the same code. |

**`sets` is additive, and safely so.** `spec`, `set` and `items` at the
character level still describe the **first** setup — the spec being played — so
an addon older than 1.10.0 reads those, behaves exactly as it always did, and
simply never learns the off-spec setups exist. That is the opposite of the
`keep` field the cleanup wire deliberately does not have: dropping `sets` costs
a stale client setups it never had, where dropping `keep` would have had it
sell a ring it should not. Neither prefix nor `v` moves.

**A record that names specs answers only for the spec being played.** With
`sets` present, `GearSet.Stored()` returns the setup matching the active spec
or nothing at all — never another spec's gear. A record with no spec anywhere
(an older website, or a character whose spec could not be resolved) makes no
claim and still applies to whoever is standing there.

### The set name is proposed here and settled by the client

`set` is what the website would like the Equipment Manager set called. It is
not authoritative, because **`C_EquipmentSet` enforces a name length this addon
has no API to read**, and a constant in the website would be a guess about a
client it never runs in. Guessing high fails in the worst direction:
`CreateEquipmentSet` does nothing and the player gets equipped gear, no saved
set, and no explanation.

So `saveSet` tries the proposed name, then progressively shorter ones, and uses
whichever the client actually accepts — the receipt names that one. Truncation
drops the spec before the brand: two specs colliding on one truncated name is a
player watching one set update twice, where losing `warband.pro` leaves a set
they cannot pick out from their own.

### Matching is by item string, and nothing else

**The wire carries no bag coordinates, deliberately.** A bag position captured
at export time is stale by the time the string comes back — the player looted,
sold, sorted, ran a dungeon — and `C_Container.UseContainerItem` on a slot that
moved sells *whatever is there now*. That is the one failure this feature must
never have, and the only way to be sure of it is to never carry a coordinate
that could be believed.

So `Junk.Resolve()` walks the live bags at display time and matches on `s`. A
verdict finds the item it was written about, or it finds nothing and the panel
says how many are no longer in the bags. Coordinates come from the walk that
just happened, never from storage.

**A verdict applies to every live match of its `s`.** The website sends one
entry per distinct string — duplicates are collapsed before encoding — because
two items with the same item string are the same item in every respect the
game exposes, including the `uniqueID` field the string itself carries. Sending
the verdict twice would ask the addon which copy each one meant, and there is
no answer.

### `r: "dupe"` — and why it needed no new field — added 1.9.0

A `dupe` verdict says the player is **already wearing this exact item**, in as
many copies as they could ever wear at once: two for a ring or a trinket, one
everywhere else. Every copy still in a bag is therefore surplus, and "apply to
every live match" — the rule directly above — is already the correct handling.
That is not a happy accident; it is what the verdict was shaped around.

The design that did not survive was the obvious one: let the website flag
surplus copies wherever they sit and add a `keep` count saying how many live
matches to leave alone. **An addon predating that field drops it** — the
decoder whitelists what it reads, deliberately — **and `Junk.Resolve` then
offers every match for sale.** An old client would have sold both copies of a
perfectly good ring, which is the same class of failure the no-coordinates rule
exists to prevent, arriving through a different door. Bumping payload `v` was
the only other way to make it safe, and that hard-rejects the whole string on
every un-updated client, taking the two working verdicts down with it.

So the website only ever emits `dupe` for a copy whose twin is **on the
player's body**, never one merely sitting beside it in the same bag. That case
— two copies in a bag, none worn — stays unflagged, which is the quiet
direction: the surplus copy stays where it already was.

Exactness is the item string, never the item id. Two items sharing an id can
differ in bonus ids, in a crafted stat, in the difficulty they dropped at, and
an id-level test would call a Heroic piece a copy of the Mythic one being worn.
The website reads the equipped side out of this addon's own `gear[]` entries
(`where: "equipped"`) rather than Blizzard's equipment document, because the
document has no item string to compare and this addon captures both sides in
one walk.

**A string from another account matches nothing** and the panel says so. The
guid simply does not appear in `WarbandProDB.chars`, which is the whole check —
no identity is asserted, and nothing about it needs to be private, since the
string carries only what that account's own export already carried.

### Reader caps

| Cap | Value | Why |
| --- | --- | --- |
| input wire length | 40KB | The real bomb guard. `LibDeflate:DecompressDeflate` has no streaming cap, so bounding the *input* is what bounds the work; a legitimate cleanup list for 20 characters is well under a kilobyte. |
| decoded payload | 512KB | Second line, checked after inflate. |
| JSON nesting depth | 16 | `Import.JSONDecode` is recursive-descent and this payload is four levels deep. |

`Import.JSONDecode` is hand-rolled and strict: it accepts exactly the grammar
`Bundle.JSON` emits and rejects trailing garbage. It does **not** use
`loadstring` — `tools/validate.mjs` fails the build on that, and executing a
pasted string would be the single worst thing this addon could do.

## `wbg1!` — the equip direction, added in addon 1.6.0

The second inbound wire: the gear set warband.pro's best-in-bags picked for a
character. The addon decodes it, equips the named items under the player's
click, and saves the result as an Equipment Manager set. Same envelope as
everything else, its own prefix, versioning independently — `wbc1!`'s
precedent exactly, and for the same reason it did not spend `wb2!`: a break in
one direction is not a break in the others.

### Payload

```json
{
  "v": 1,
  "generatedAt": 1724001000,
  "chars": [{
    "guid": "Player-1-TEST",
    "name": "Vocnar",
    "spec": 103,
    "set": "warband.pro",
    "items": [
      {"slot": 1,  "id": 221151, "s": "item:221151:...", "w": "bag"},
      {"slot": 12, "id": 215135, "s": "item:215135:..."}
    ]
  }]
}
```

| Field | Meaning |
| --- | --- |
| `generatedAt` | Unix seconds, when the site built the string. |
| `chars[].guid` | **The match key**, exactly as `wb1!` sent it. Only guids in `WarbandProDB.chars` are kept, same as `wbc1!`. |
| `chars[].name` | Display only. |
| `chars[].spec` | The specialization id the solve ran for. Display and sanity only, never matched. Optional. |
| `chars[].set` | The Equipment Manager set name to create or update. Defaults to `warband.pro` when absent — one set per character, updated in place. |
| `items[].slot` | **The REAL inventory slot, 1-17 minus 4, uncollapsed.** `12` means finger 2. This is the one deliberate asymmetry with `gear[]`: outbound, the addon collapses paired slots because it cannot know which twin a bagged ring would fill; inbound, the website's solve knows exactly which twin it replaces, and this field is how it says so. `EquipCursorItem(slot)` is what honors it — `EquipItemByName` guarantees nothing about twins. |
| `items[].id` | Item id, display and sanity. Optional. |
| `items[].s` | **The identity key.** The verbatim item string, as `gear[]` sent it. An entry without one is dropped at decode. |
| `items[].w` | Where the site last saw the item (`bag`/`bank`/`warbank`). Optional — it powers the "in your bank — retrieve it first" line when the item is not in the carried bags. |

**Only the slots that change ride the wire.** Slots the solve left alone are
omitted: `C_EquipmentSet.SaveEquipmentSet` snapshots the live paperdoll, so
everything already worn joins the set for free — and the website has no
verbatim item string for an API-sourced equipped item anyway, so a keeper
entry would be an identity key the addon might mis-resolve. Locked slots on
the site simply never appear. An empty `items` list is a rejection
(`no_items`): a set that changes nothing has nothing to say.

### Matching, applying, and when the set is saved

Matching is by item string against a live walk of the **carried bags**, the
`wbc1!` doctrine unchanged — no coordinates on the wire, ever. Each stored
item resolves to one of three buckets: **already** (the target slot's
`GetInventoryItemLink` string equals `s`), **ready** (matched in a carried
bag, with coordinates from the walk that just happened), or **missing** (with
`w` naming where to fetch it from).

The apply order matters and is pinned by `tools/gearset-test.lua`: every ready
item is equipped first (`PickupContainerItem` at the walked coordinates, then
`EquipCursorItem` at the wire's slot), and the set is saved only after
`PLAYER_EQUIPMENT_CHANGED` confirms the equips landed — `SaveEquipmentSet`
snapshots whatever is worn *at that moment*, so saving in the equip's frame
would save the old kit. A three-second deadline saves what actually verified
and the receipt says which equips never landed. Combat fails closed at every
step: no equip starts in combat, and combat mid-apply drops the pending save
with a line saying to press the button again — never a deferred queue.

Partial application is the normal case and is honest: the set saved is the
paperdoll as it actually stands, and a missing item costs a receipt line,
never a wrong equip.

### Reader caps

Identical to `wbc1!`'s: 40KB input wire, 512KB decoded, JSON depth 16, same
hand-rolled strict decoder, no `loadstring`. Every decoder refuses the other
two prefixes **by name** — a misfiled paste is valid somewhere else, and the
refusal says where it belongs.

## When the prefix moves

This section is about **the wire**, and only the wire. The addon's own release
number is a different question with a different answer, and it lives in
[../CHANGELOG.md](../CHANGELOG.md) — keeping both here is what let the two drift
apart once already, when this file's rules were written in addon-version terms
(`v1.0.0 -> v1.0.1`) that had nothing to do with the prefix they were describing.

Three ways a payload can change, and only one of them spends a prefix:

- **Additive** — a new optional field. The prefix does not move. A website
  written against the older shape still reads the bundle and ignores what it
  does not know; a website written against the newer one reads a missing field
  as absent rather than as an error. Everything in `v1` after 1.0.0 arrived this
  way, including gear and talents, which is why they are on `wb1!` and not
  `wb2!`.
- **Narrowing** — a cap tightens or a field stops being emitted. Also no prefix
  move, provided the consumer already tolerates absence, which the field rules
  above require of it.
- **Breaking** — an existing field changes meaning, type, or position. This is
  the only one that costs a prefix: `wb1!` → `wb2!`, and the website rejects the
  old string with "update your addon" rather than misreading it.

A prefix move is a MAJOR release of the addon, because the player has to act.
The reverse does not follow — a MAJOR can happen for a reason that never touches
the wire.

**All directions version independently.** `wbc1!` (1.4.0) and `wbg1!` (1.6.0)
are separate channels, and neither spent `wb2!`. A break in one is not a break
in the others.

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

**Each tab carries its own `seenAt`, and the vault carries `tabsOwned` and
`partial` — added in 1.8.0, additive.** The root `seenAt` is when somebody last
stood at the banker. It is not how fresh the contents are, and treating it as
such was wrong in a way nothing could see: `ACCOUNT_BANK_TAB_DATA_CHANGED`
fires once per tab as the client streams the data in, so the first walk after a
banker opens routinely sees one tab of five — and the addon replaced the stored
vault with that one tab and stamped it fresh. Tabs now merge by `bagID` and a
tab that did not load keeps its own older stamp.

```json
"warbandBank": {
  "seenAt": 1724000000, "seenByName": "Vocnar", "gold": 4500000,
  "tabsOwned": 5, "partial": true,
  "tabs": [ {"bagID":13,"size":98,"free":12,"seenAt":1724000000,"items":[…]},
            {"bagID":14,"size":98,"free":40,"seenAt":1723800000,"items":[…]} ]
}
```

- `tabs[].seenAt` — when *that tab* was last read. Absent on a vault stored
  before 1.8.0; fall back to the root `seenAt`. The oldest of these is the age
  to draw the vault's dot from.
- `tabsOwned` — how many tabs the account has purchased, from
  `C_Bank.FetchPurchasedBankTabData`. **Absent when the client would not say**,
  and then no completeness claim is made at all. It is the only honest
  denominator: an unread tab and an unbought tab both report zero slots, so
  counting what came back can never tell them apart.
- `partial` — `true` when fewer tabs are stored than the account owns, i.e.
  some tab has never been read. Absent, never `false`, in keeping with the
  absent-means-unknown rule everywhere else here. A web client should say "4 of
  5 tabs" rather than presenting the vault as complete.

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
"weeklyVault": { "raid": {"progress":2,"threshold":4,"unlocked":1,"slots":3,
                          "rows":[{"t":2,"p":2,"l":14,"d":"Normal"},{"t":4,"p":2,"l":0},{"t":6,"p":2,"l":0}]} }
```

`unlocked` is how many of that row's three slots are earned, `threshold` is the
next one still reachable and is **absent once all three are earned**. Bucket keys
come from `Enum.WeeklyRewardChestThresholdType` as the client shipped it, so a
type the addon does not recognise is dropped rather than guessed at.

#### `rows[]` — per slot, since 1.2.0

Additive on `wb1!`: absent from every bundle exported before 1.2.0, and a
consumer that ignores it behaves exactly as it did. `{t}`hreshold, `{p}`rogress,
`{l}`evel raw, `{d}`ifficulty resolved — three per bucket, ~90 bytes before
deflate folds the repeated keys.

The summary fields are a summary **of** these rows, and the collapse was lossy in
a way that cost the website a sentence. A bucket carries only the *next*
threshold, so the thresholds of slots already earned were gone, and "one more
heroic boss raises the slot you already have" could not be said from it at all —
the site had to reason from a hardcoded `[2,4,6]` that goes stale at an
expansion.

Two rules a consumer must not soften:

- **`l` means something different on every row** — a keystone level on `mplus`, a
  difficulty id on `raid`. Do not compare it across buckets, and do not resolve
  it yourself.
- **`d` is sent for `raid` only, and only when `GetDifficultyInfo` answered.** A
  missing `d` is the client declining, never "unknown, assume LFR". It is not
  sent on `mplus` on purpose: `GetDifficultyInfo(14)` returns "Normal" whether
  that 14 arrived as a raid difficulty or as a +14 key, and a plausible wrong
  answer is worse than none.

`level` on the **bucket** is a max across rows whose ordering it does not own.
That is fine where the field is a keystone level and wrong where it is a
difficulty id — raid ids sort LFR (17) above Mythic (16), so the "best" slot it
named could be the worst one — so **`level` is no longer sent on the `raid`
bucket**. It was never read. `rows[].d` is what anyone reaching for it wanted.

### A warband larger than the cap is paged, not truncated — added in 1.8.0

The cap is **per bundle**, not per warband. A player with 41 characters sends
three bundles: `/warband copy` is page 1, `/warband copy 2` is the next twenty,
and so on. Characters are ordered newest-seen first and that order is stable
between calls, so the pages partition the warband with no gap and no repeat.

```json
"bundle": { "count": 20, "droppedOverCap": 21, "page": 1, "pages": 3 }
```

- `droppedOverCap` — how many characters are **not in this bundle**. Absent, not
  zero, when the bundle holds the whole warband.
- `page` / `pages` — which twenty this is, and how many there are. **Both absent
  when the warband fits in one bundle**, in keeping with absent-means-unknown
  everywhere else here: a bundle with no `pages` is the whole warband.

**This works only because the importer merges rather than replaces.** The web
side upserts by character key and never deletes a row the bundle omits, so
pages accumulate into one roster on the far side. A consumer that treated a
bundle as the complete roster — deleting what it does not carry — would make
page 2 erase page 1, and must not.

Before 1.8.0 the addon truncated instead: the oldest characters were cut from
the wire, `droppedOverCap` said how many, **and nothing on either side read it**,
so a player's 21st alt did not exist on the website with no line anywhere saying
why. The in-game remedy offered was `/warband clear <name>` — delete an alt to
make room — which is the wrong answer for the player who has twenty-one of them.

## Security / DoS

- Never allow >20 characters in **one bundle**, reject. A larger warband arrives
  as several bundles; see the paging section above.
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
to gear. 1.8.0's `loadouts[]` multiplies that by however many named builds the
player has saved, which is why it is capped at eight rather than left open —
the realistic case is two or three.

### What 1.3.0's five fields add, measured

Same six-character roster again, `tools/sample.mjs` before and after. The
sample also grew two deliberately-junk bag entries per character in 1.3.0 — a
list of nothing tests nothing — so the two effects are separated here rather
than reported as one number:

| | JSON | wire |
|---|---|---|
| 1.2.0 | 82.3KB | 16.4KB |
| + `n`/`q`/`b`/`cls`/`sub` on the same entries | 87.4KB | 17.3KB |
| + two junk bag entries per character | 89.2KB | 17.7KB |
| **field delta for 6 characters** | **+5.1KB** | **+0.9KB** |
| **field delta per character** | **~+0.85KB** | **~+0.15KB** |

The name is nearly all of it, and it still deflates well — names repeat their
vocabulary across a warband, which is exactly what a 32KB window is good at.
Carried to the 20-character cap the five fields cost roughly **+3KB wire**,
landing near ~87KB against the same 1MB decoded ceiling. Nothing here moves a
cap.

## Sample vectors

`vectors/v1-min.json` is one minimal character, and `v1-min.wb1` beside it is
that vector encoded — the fixture the web decoder tests against.
`vectors/v1-gear.json`/`v1-gear.wb1` add `gear[]` and `talents`. Regenerate
all four with `node tools/vector.mjs --write`. All four are hand-written, not
captured from the game — see the item-string correction above for what that
means for `v1-gear`'s `s` values specifically.
