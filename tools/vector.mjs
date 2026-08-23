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
//
// Two wires live here. A vector named wbc1-* is the RETURN direction — what
// warband.pro hands back for the addon's junk list — and rides the identical
// envelope with a different prefix and a different payload shape. Same
// generator on purpose: the two directions cannot be allowed to drift into two
// encoders, because the addon has exactly one base64url table and one deflate
// call to spend on both.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'contract', 'vectors');
const PREFIX = 'wb1!';
const CLEANUP_PREFIX = 'wbc1!';

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

export function encode(payload, prefix = PREFIX) {
  return prefix + b64url(deflateRawSync(Buffer.from(canonical(payload), 'utf8'), { level: 9 }));
}

export function decode(str) {
  if (!str.startsWith(PREFIX)) throw new Error(`expected ${PREFIX} prefix`);
  const raw = inflateRawSync(unb64url(str.slice(PREFIX.length)));
  // CONTRACT.md: the real cap is 1MB decoded, not 25KB — a single character
  // with full bags and bank is already ~39KB of JSON. Matches the web
  // decoder's MAX_DECODED_BYTES in src/lib/warband-import.ts.
  if (raw.length > 1024 * 1024) throw new Error('payload over 1MB');
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

/**
 * The return wire. Caps are the addon's, not the website's: Import.lua reads
 * this on a machine also running a raid, and LibDeflate's DecompressDeflate
 * has no streaming cap, so the INPUT length is the real bomb guard and the
 * output check is a second line rather than the first.
 */
const CLEANUP_MAX_WIRE = 40 * 1024;
const CLEANUP_MAX_DECODED = 512 * 1024;
const CLEANUP_VERDICTS = new Set(['sell', 'de', 'del']);

export function decodeCleanup(str) {
  if (!str.startsWith(CLEANUP_PREFIX)) throw new Error(`expected ${CLEANUP_PREFIX} prefix`);
  if (str.length > CLEANUP_MAX_WIRE) throw new Error('cleanup string over 40KB');
  const raw = inflateRawSync(unb64url(str.slice(CLEANUP_PREFIX.length)));
  if (raw.length > CLEANUP_MAX_DECODED) throw new Error('cleanup payload over 512KB');
  const payload = JSON.parse(raw.toString('utf8'));
  if (payload.v !== 1) throw new Error(`unsupported cleanup version ${payload.v}`);
  if (typeof payload.generatedAt !== 'number') throw new Error('generatedAt missing');
  if (!Array.isArray(payload.chars)) throw new Error('chars is not an array');
  for (const c of payload.chars) {
    if (!c.guid) throw new Error('cleanup character has no guid to match on');
    if (!Array.isArray(c.items)) throw new Error(`items is not an array for ${c.guid}`);
    for (const i of c.items) {
      if (!CLEANUP_VERDICTS.has(i.k)) throw new Error(`unknown verdict ${i.k}`);
      // `s` is the whole identity mechanism — an entry without one names no
      // item the addon can find, so it is a malformed entry rather than a
      // lenient one.
      if (typeof i.s !== 'string' || !i.s) throw new Error('cleanup item has no item string');
    }
  }
  return payload;
}

const isCleanup = (file) => file.startsWith('wbc1-');

const write = process.argv.includes('--write');
let failed = 0;

for (const file of readdirSync(DIR).filter((f) => f.endsWith('.json'))) {
  const cleanup = isCleanup(file);
  const source = JSON.parse(readFileSync(join(DIR, file), 'utf8'));
  const wire = encode(source, cleanup ? CLEANUP_PREFIX : PREFIX);
  try {
    const back = cleanup ? decodeCleanup(wire) : decode(wire);
    const same = canonical(back) === canonical(source);
    if (!same) throw new Error('round-trip changed the payload');
    const ratio = ((wire.length / canonical(source).length) * 100).toFixed(0);
    const count = cleanup ? `chars=${back.chars.length}` : `chars=${back.characters.length}`;
    console.log(`PASS ${file}  ${canonical(source).length}B json -> ${wire.length}B wire (${ratio}%)  ${count}`);
    if (write) {
      const ext = cleanup ? '.wbc1' : '.wb1';
      writeFileSync(join(DIR, file.replace(/\.json$/, ext)), wire + '\n');
      console.log(`     wrote ${file.replace(/\.json$/, ext)}`);
    }
  } catch (e) {
    failed++;
    console.log(`FAIL ${file}  ${e.message}`);
  }
}

// Rejections the website must also make.
const bad = [
  ['no prefix', 'aGVsbG8', decode],
  ['garbage body', 'wb1!not-a-deflate-stream', decode],
  // Each decoder must refuse the other's string. The two are a few centimetres
  // apart in two different applications and a misfiled paste is valid rather
  // than malformed, so the refusal is what lets each side say where it belongs.
  ['a cleanup string in the bundle decoder', 'wbc1!AAAA', decode],
  ['a bundle in the cleanup decoder', 'wb1!AAAA', decodeCleanup],
  ['garbage cleanup body', 'wbc1!not-a-deflate-stream', decodeCleanup],
];
for (const [label, input, fn] of bad) {
  try {
    fn(input);
    failed++;
    console.log(`FAIL rejects ${label}: accepted it`);
  } catch {
    console.log(`PASS rejects ${label}`);
  }
}

process.exit(failed === 0 ? 0 : 1);
