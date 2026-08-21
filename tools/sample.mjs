#!/usr/bin/env node
// Generate a realistic `wb1!` bundle for testing the website's import UI.
//
// This is NOT a contract vector — `vector.mjs` owns those, and its fixtures are
// frozen so a drift between the two repos fails a test. This one is the
// opposite: every stamp is relative to the moment you run it, so the freshness
// dots land where you want them rather than ageing into red the week after.
//
//   node tools/sample.mjs              6 characters, mixed freshness
//   node tools/sample.mjs --chars 3    fewer
//   node tools/sample.mjs --fresh      every character seen minutes ago
//   node tools/sample.mjs --json       print the payload instead of the string
//
// The character names are the maintainer's real roster on purpose: the site
// keys addon rows on "<realm-slug>:<name>", so a real import later overwrites
// these rather than leaving orphans beside them.

import { deflateRawSync } from 'node:zlib';

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const value = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? Number(args[i + 1]) : fallback;
};

const NOW = Math.floor(Date.now() / 1000);
const MIN = 60;
const HOUR = 3600;
const DAY = 86400;

// A deterministic generator, so two runs a second apart differ only in their
// timestamps. Nothing here needs to be unpredictable, and a stable body makes
// two sample strings diffable.
let seed = 20260818;
const rnd = (n) => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return Math.floor((seed / 2147483648) * n);
};

// Item ids are plausible-looking rather than real. The website resolves names
// and icons from Game Data by id, so a wrong id renders as a missing item, not
// as a broken page — which is itself worth seeing at least once.
const REAGENT = Array.from({ length: 40 }, () => 190000 + rnd(20000));
const pick = () => (rnd(10) < 6 ? REAGENT[rnd(REAGENT.length)] : 210000 + rnd(20000));

// A structurally plausible item string, same liberty the ids above take: not a
// real bonus-ID encoding, just something shaped like one so the import preview
// has something to render for gear[].s.
function itemString(id, spec) {
  return `item:${id}::::::::80:${spec.id}::1:${1000 + rnd(9000)}:::`;
}

// Slots 1-19 minus 4 (shirt) and 19 (tabard) — matches Gear.lua's EQUIPPED_SLOTS.
const EQUIP_SLOTS = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];

function gear(spec, ilvlBase) {
  const equipped = EQUIP_SLOTS.map((slot) => {
    const id = 210000 + rnd(20000);
    return { slot, where: 'equipped', id, ilvl: ilvlBase + rnd(15), s: itemString(id, spec) };
  });
  // A couple of unequipped pieces so a preview of best-in-bags has something to
  // compare against — a spare ring and a spare trinket.
  const spare = [11, 13].map((slot) => {
    const id = 210000 + rnd(20000);
    return { slot, where: 'bag', id, ilvl: ilvlBase - 10 + rnd(20), s: itemString(id, spec) };
  });
  return [...equipped, ...spare];
}

const LOADOUT_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
function loadoutCode() {
  let s = 'C';
  for (let i = 0; i < 40; i++) s += LOADOUT_ALPHABET[rnd(LOADOUT_ALPHABET.length)];
  return s;
}

// One plausible spec per class in the cast. Real spec ids, made-up loadouts.
const SPEC_BY_CLASS = {
  DRUID: { specID: 103, name: 'Feral', role: 'DAMAGER' },
  PALADIN: { specID: 66, name: 'Protection', role: 'TANK' },
  MAGE: { specID: 63, name: 'Fire', role: 'DAMAGER' },
  PRIEST: { specID: 257, name: 'Holy', role: 'HEALER' },
  WARRIOR: { specID: 71, name: 'Arms', role: 'DAMAGER' },
  ROGUE: { specID: 259, name: 'Assassination', role: 'DAMAGER' },
};

function talents(spec, seen) {
  const sp = SPEC_BY_CLASS[spec.cls];
  if (!sp) return undefined;
  return {
    activeSpecID: sp.specID,
    specs: [{ specID: sp.specID, name: sp.name, role: sp.role, heroSpecID: 30 + rnd(10), loadout: loadoutCode(), seenAt: seen }],
  };
}

function bags(count, fill) {
  return Array.from({ length: count }, (_, b) => {
    const size = b === 0 ? 32 : 34;
    const used = Math.round(size * fill);
    return {
      bagID: b,
      size,
      free: size - used,
      items: Array.from({ length: used }, () => ({
        id: pick(),
        count: 1 + rnd(180),
        quality: rnd(5),
      })),
    };
  });
}

/**
 * The cast. `seenAgo` drives the dot: under 6h green, under 3d yellow, beyond
 * red — and `bankAgo` null is the case the preview has to print as "not opened"
 * rather than as an empty bank.
 */
const CAST = [
  { name: 'Vocnar',   realm: 'Wyrmrest Accord', slug: 'wyrmrest-accord', cls: 'DRUID',   id: 11, gold: 8457392000, seenAgo: 12 * MIN,  bankAgo: 2 * HOUR,  phial: 42, fill: 0.9 },
  { name: 'Vocsaris', realm: 'Wyrmrest Accord', slug: 'wyrmrest-accord', cls: 'PALADIN', id: 2,  gold: 1204500,    seenAgo: 3 * HOUR,  bankAgo: null,      phial: 0,  fill: 0.97 },
  { name: 'Voctesa',  realm: 'Moon Guard',      slug: 'moon-guard',      cls: 'MAGE',    id: 8,  gold: 45900000,   seenAgo: 30 * HOUR, bankAgo: 30 * HOUR, phial: 8,  fill: 0.6 },
  { name: 'Vocsylra', realm: 'Moon Guard',      slug: 'moon-guard',      cls: 'PRIEST',  id: 5,  gold: 780000,     seenAgo: 2 * DAY,   bankAgo: 6 * DAY,   phial: 120, fill: 0.4 },
  { name: 'Vocgrim',  realm: 'Wyrmrest Accord', slug: 'wyrmrest-accord', cls: 'WARRIOR', id: 1,  gold: 96000,      seenAgo: 9 * DAY,   bankAgo: 22 * DAY, phial: 0,  fill: 0.75 },
  { name: 'Voctara',  realm: 'Wyrmrest Accord', slug: 'wyrmrest-accord', cls: 'ROGUE',   id: 4,  gold: 33150000,   seenAgo: 41 * MIN,  bankAgo: 5 * DAY,  phial: 15, fill: 0.5 },
];

function character(spec, index) {
  const seen = NOW - (flag('fresh') ? 6 * MIN + index * 60 : spec.seenAgo);
  const bank = spec.bankAgo === null ? null : NOW - (flag('fresh') ? 20 * MIN : spec.bankAgo);

  const c = {
    guid: `Player-112-0A1B2C${String(index).padStart(2, '0')}`,
    name: spec.name,
    realm: spec.realm,
    realmSlug: spec.slug,
    faction: spec.slug === 'moon-guard' ? 'Alliance' : 'Horde',
    class: spec.cls,
    classId: spec.id,
    race: spec.slug === 'moon-guard' ? 'NightElf' : 'Tauren',
    level: 80,
    itemLevelAvg: 610 + rnd(30),
    itemLevelEquipped: 608 + rnd(28),
    guild: { name: 'Moxes', rank: 'Initiate', rankIndex: 2 },
    lastZone: 'Dornogal',
    hearthZone: 'Dornogal',
    gold: spec.gold,
    bags: bags(6, spec.fill),
    gear: gear(spec, 608 + rnd(28)),
    talents: talents(spec, seen),
    currencies: Array.from({ length: 12 }, (_, k) => ({
      id: 2800 + k,
      name: `Currency ${k + 1}`,
      quantity: rnd(20000),
      maxQuantity: k % 3 === 0 ? 20000 : 0,
      weeklyMax: 0,
      isAccountWide: k % 4 === 0,
      discovered: true,
    })),
    professions: [
      { id: 171, name: 'Alchemy', skill: 60 + rnd(40), maxLevel: 100 },
      { id: 197, name: 'Tailoring', skill: 60 + rnd(40), maxLevel: 100 },
    ],
    instances: index % 2 === 0
      ? [{
          name: 'Nerub-ar Palace',
          instanceID: 1273,
          difficulty: 3,
          difficultyName: 'Heroic',
          isRaid: true,
          locked: true,
          extended: false,
          resetTime: NOW + 3 * DAY,
          bosses: ['Ulgrax', 'Bloodbound Horror', 'Sikran', 'Rasha’nan'].map((name, i) => ({
            name,
            killed: i < 2,
          })),
        }]
      : [],
    worldBosses: [],
    mythicPlusScore: 1200 + rnd(1400),
    weeklyVault: {
      mplus: { progress: rnd(9), threshold: 8, unlocked: rnd(3), slots: 3 },
      raid: { progress: rnd(7), threshold: 6, unlocked: rnd(2), slots: 3 },
    },
    // The one field the Tonight Plan will block a raid night on, which is why
    // one character in this cast has zero and one has never been looked at.
    consumables: { phial: spec.phial, potion: rnd(60), foodFeast: rnd(200), weaponRune: rnd(20) },
    seenAt: {
      lastSeen: seen,
      bag: seen,
      currency: seen,
      instance: seen - 20 * MIN,
      vault: seen - 40 * MIN,
      gear: seen,
      talents: seen,
    },
  };

  if (bank !== null) {
    c.bank = bags(4, 0.5).map((b, i) => ({ ...b, bagID: i === 0 ? -1 : 5 + i }));
    c.seenAt.bank = bank;
  }
  return c;
}

const count = Math.max(1, Math.min(value('chars', 6), CAST.length));
const characters = CAST.slice(0, count).map(character);
const seenAll = characters.map((c) => c.seenAt.lastSeen);

const payload = {
  v: 1,
  addon: '0.1.0-sample',
  exportedAt: NOW,
  gameVersion: '12.1.0',
  interface: 120001,
  bundle: {
    count: characters.length,
    freshestSeenAt: Math.max(...seenAll),
    oldestSeenAt: Math.min(...seenAll),
  },
  // Account-wide, at the root — one vault, credited to whoever last opened it.
  warbandBank: {
    seenAt: NOW - (flag('fresh') ? 15 * MIN : 2 * HOUR),
    seenByGuid: 'Player-112-0A1B2C00',
    seenByName: 'Vocnar',
    gold: 512000000,
    tabs: Array.from({ length: 5 }, (_, t) => ({
      bagID: 13 + t,
      size: 98,
      free: 98 - 60,
      items: Array.from({ length: 60 }, () => ({ id: pick(), count: 1 + rnd(200), quality: rnd(5) })),
    })),
  },
  characters,
};

// Canonical JSON, same rule as Bundle.lua: sorted keys, no whitespace.
function canonical(v) {
  if (v === null || v === undefined) return 'null';
  if (typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  const keys = Object.keys(v).filter((k) => v[k] !== undefined).sort();
  if (keys.length === 0) return '[]';
  return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
}

const json = canonical(payload);
if (flag('json')) {
  console.log(JSON.stringify(payload, null, 2));
} else {
  const wire = 'wb1!' + deflateRawSync(Buffer.from(json, 'utf8'), { level: 9 }).toString('base64url');
  console.error(
    `${characters.length} characters · ${(json.length / 1024).toFixed(1)}KB json -> ${(wire.length / 1024).toFixed(1)}KB wire`,
  );
  console.log(wire);
}
