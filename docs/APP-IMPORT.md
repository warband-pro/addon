# App side — proposal for `/app`

Nothing in `/app` has been changed. This is the proposal, written after reading
the cache pattern that repo already uses, so the import lands as one more
instance of an existing shape rather than a new one.

## What `/app` already does

Per-character Blizzard documents live in three tables that share one schema —
`lockout_cache`, `character_detail_cache`, `character_profile_cache`:

```sql
(user_id TEXT, char_key TEXT, payload_json TEXT, fetched_at_ms INTEGER,
 PRIMARY KEY (user_id, char_key), FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)
```

`char_key` is `campKey()` — `"<realm-slug>:<character-name>"`, both lowercased —
and `src/lib/bnet-client.ts` reads and writes all three through two generic
helpers (`readDocCache` / `writeDocCache`) whose table name is a closed union of
literals. Adding a fourth member to that union is the whole integration.

## Recommended table

```sql
-- migrations/0012_character_addon_cache.sql
-- What the addon knows and the Battle.net API cannot: bag and bank contents,
-- gold, currencies with caps, lockout boss detail, the vault, consumables.
--
-- Same shape as the three document caches next door, deliberately: the payload
-- is one wire CharacterObject, and every staleness stamp the UI needs is already
-- inside it as seenAt.{lastSeen,bag,bank,warbank,currency,instance,vault}. This
-- plugs straight into readDocCache/writeDocCache by adding one literal to the
-- DocCacheTable union.
--
-- fetched_at_ms is the *import* time, not a Blizzard fetch time. The addon's own
-- stamps are what decide the freshness dot; this column only answers "when did
-- this user last paste".
CREATE TABLE IF NOT EXISTS character_addon_cache (
  user_id TEXT NOT NULL,
  char_key TEXT NOT NULL,          -- campKey(): "<realm-slug>:<name>", lowercased
  payload_json TEXT NOT NULL,      -- one CharacterObject, wb1! v1
  fetched_at_ms INTEGER NOT NULL,
  PRIMARY KEY (user_id, char_key),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_addon_cache_user ON character_addon_cache(user_id);
CREATE INDEX IF NOT EXISTS idx_character_addon_cache_fetched_at_ms ON character_addon_cache(fetched_at_ms);

-- The warband bank is one vault per account, not per character, so it gets one
-- row per user rather than being repeated on every character. Same reason the
-- addon moved it to the payload root — see CONTRACT.md "v1 as implemented".
CREATE TABLE IF NOT EXISTS warband_bank_cache (
  user_id TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,      -- { seenAt, seenByGuid, seenByName, gold, tabs[] }
  fetched_at_ms INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### Why not the column list from the brief

`(user_id, realm_slug, char_name, data_json, last_seen_ms, bank_seen_ms,
warband_seen_ms, imported_at_ms, addon_version)` works, and if you want to filter
staleness in SQL — `WHERE last_seen_ms < ?` to drive a "stale alts" query without
reading every payload — it is the better table. Two costs, both small, both worth
naming before you pick:

- It no longer matches `DocCacheTable`, so it needs its own read/write pair
  instead of the two that already exist.
- `realm_slug` + `char_name` as separate columns means every join back to camp
  and roster re-derives `campKey()` at the call site, where the rest of the app
  passes one key.

If you take that route, keep `char_key` **as well as** the split columns, and put
`guid` on the row too — the addon is GUID-keyed, so a renamed character keeps its
history there and only `char_key` moves.

## Import route

`POST /api/addon/import`, mirroring `src/pages/api/bnet/roster.ts`: pull `DB` off
`locals.runtime.env`, `getValidSessionFromRequest`, 401 on no session, write only
under `sessionInfo.sess.user_id`. Body is `{ bundle: "wb1!..." }`.

The decode is pure and belongs in `src/lib/warband-import.ts` so vitest can run it
with no Worker:

```ts
export function decodeBundle(input: string): Bundle   // throws on anything below
```

1. `input.startsWith('wb1!')` — `wb0!` gets "that is a Camp DNA share, not an
   inventory bundle"; anything else gets "run /warband copy again".
2. base64url → bytes → `DecompressionStream('deflate-raw')` (**not** `'deflate'`;
   the addon emits a raw stream).
3. Cap the *decoded* bytes at **1MB**, not 25KB — a single character with full
   bags is ~39KB of JSON and six are ~154KB. Measured table in CONTRACT.md.
4. `payload.v === 1`, `characters` an array of 1..20, each with `guid`, `name`,
   and `seenAt.lastSeen`.
5. Return the payload plus a derived freshness row per character.

`tools/vector.mjs` in this repo is that algorithm in ~40 lines, and
`docs/contract/vectors/v1-min.wb1` is a ready fixture to test against.

Upsert per character with `ON CONFLICT(user_id, char_key) DO UPDATE`, in one
`db.batch()`. **Characters absent from the bundle are never deleted** — an alt you
did not log this week stays at its old snapshot and goes red, which is the entire
staleness model.

## Freshness, one source

The addon draws its dots from `ns.dot()` in `Init.lua`: green under 6h, yellow
under 3d, red beyond, grey for never. The importer preview must use the same
three numbers, per section, off `seenAt` — bag, bank, warbank, currency,
instance, vault — with the warband bank read from the account-wide row and
labelled with `seenByName`: "Warband Bank 1h ago (by Vocnar)".

Staleness lowers confidence, it never deletes. The Tonight Plan reads the same
stamps: zero phials on a fresh snapshot is a hard block, zero phials on a
five-day-old snapshot is grey text asking you to verify.
