#!/usr/bin/env node
// Contract vector generator and round-trip check.
//
// The addon's own encoder can only run inside WoW, so this stands in for the
// half we can verify on a laptop: it builds a wb1! string from a vector JSON the
// same way Export.lua does — canonical JSON, raw deflate, base64url, prefix —
// and then decodes it back through the path the website will use. If this
// disagrees with itself, the format is wrong before anyone logs in.
//
//   node tools/vector.mjs          verify every vector round-trips
//   node tools/vector.mjs --write  also write the .wb1 fixtures next to them
//
// The .wb1 fixtures are what src/lib/warband-import.ts tests against in /app.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'contract', 'vectors');
const PREFIX = 'wb1!';

// Matches Bundle.lua: sorted keys, no whitespace, undefined dropped, empty
// tables emitted as [].
function canonical(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean' || typeof value === 'number') return JSON.stringify(value);
  if (typeof value === 'string') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
  if (keys.length === 0) return '[]';
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
}

const b64url = (buf) => buf.toString('base64url');
const unb64url = (str) => Buffer.from(str, 'base64url');

export function encode(payload) {
  return PREFIX + b64url(deflateRawSync(Buffer.from(canonical(payload), 'utf8'), { level: 9 }));
}

export function decode(str) {
  if (!str.startsWith(PREFIX)) throw new Error(`expected ${PREFIX} prefix`);
  const raw = inflateRawSync(unb64url(str.slice(PREFIX.length)));
  if (raw.length > 25 * 1024) throw new Error('payload over 25KB');
  const payload = JSON.parse(raw.toString('utf8'));
  if (payload.v !== 1) throw new Error(`unsupported wire version ${payload.v}`);
  if (!Array.isArray(payload.characters)) throw new Error('characters is not an array');
  if (payload.characters.length < 1 || payload.characters.length > 20) {
    throw new Error(`characters out of range: ${payload.characters.length}`);
  }
  for (const c of payload.characters) {
    if (!c.guid || !c.name || !c.seenAt?.lastSeen) throw new Error(`character missing required fields: ${c.name ?? '?'}`);
  }
  return payload;
}

const write = process.argv.includes('--write');
let failed = 0;

for (const file of readdirSync(DIR).filter((f) => f.endsWith('.json'))) {
  const source = JSON.parse(readFileSync(join(DIR, file), 'utf8'));
  const wire = encode(source);
  try {
    const back = decode(wire);
    const same = canonical(back) === canonical(source);
    if (!same) throw new Error('round-trip changed the payload');
    const ratio = ((wire.length / canonical(source).length) * 100).toFixed(0);
    console.log(`PASS ${file}  ${canonical(source).length}B json -> ${wire.length}B wire (${ratio}%)  chars=${back.characters.length}`);
    if (write) {
      writeFileSync(join(DIR, file.replace(/\.json$/, '.wb1')), wire + '\n');
      console.log(`     wrote ${file.replace(/\.json$/, '.wb1')}`);
    }
  } catch (e) {
    failed++;
    console.log(`FAIL ${file}  ${e.message}`);
  }
}

// Rejections the website must also make.
const bad = [
  ['no prefix', 'aGVsbG8'],
  ['garbage body', 'wb1!not-a-deflate-stream'],
];
for (const [label, input] of bad) {
  try {
    decode(input);
    failed++;
    console.log(`FAIL rejects ${label}: accepted it`);
  } catch {
    console.log(`PASS rejects ${label}`);
  }
}

process.exit(failed === 0 ? 0 : 1);
