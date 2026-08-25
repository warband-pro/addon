#!/usr/bin/env node
// Packaging pre-flight — the checks that would otherwise be found by a player.
//
// Every failure here is something the WoW client fails at *silently*: a folder
// whose name does not match the .toc, a file listed in the .toc that was
// renamed, a Lua file nobody loads. None of it throws an error in game; the
// addon simply does not appear, or a chunk of it quietly never runs.
//
//   node tools/validate.mjs
//
// Exits non-zero if anything is wrong, and prints every problem it found rather
// than stopping at the first one.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const problems = [];
const notes = [];
const fail = (msg) => problems.push(msg);
const note = (msg) => notes.push(msg);

const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const here = (p) => existsSync(join(ROOT, p));

// --- .pkgmeta ------------------------------------------------------------
// A deliberately dumb reader. .pkgmeta is YAML, but we need three facts out of
// it and a YAML parser is a dependency this repo does not have.
const pkgmeta = here('.pkgmeta') ? read('.pkgmeta') : null;
if (!pkgmeta) fail('.pkgmeta is missing — the packager needs it to name the folder');

const packageAs = pkgmeta?.match(/^package-as:\s*(\S+)/m)?.[1];
if (pkgmeta && !packageAs) {
  fail('.pkgmeta has no `package-as:` — the zip would be named after the repo, not the addon');
}

// The zero-dependency rule, enforced rather than trusted. LibDeflate is
// vendored so a release never depends on fetching a repo at package time.
if (pkgmeta && /^externals:/m.test(pkgmeta)) {
  fail('.pkgmeta declares `externals:` — the zero-dependency rule has slipped (see Vendor/)');
}
if (pkgmeta && !/^license-output:/m.test(pkgmeta)) {
  fail('.pkgmeta has no `license-output:` — the zip would ship without a license file');
}

// --- .toc ----------------------------------------------------------------
const tocName = `${packageAs ?? 'WarbandPro'}.toc`;
if (!here(tocName)) {
  fail(`${tocName} is missing — the client skips a folder whose .toc does not match its name`);
  report();
}

const toc = read(tocName);
const directive = (key) =>
  toc.match(new RegExp(String.raw`^##\s*${key}\s*:\s*(.+?)\s*$`, 'm'))?.[1];

for (const key of ['Interface', 'Title', 'Notes', 'Author', 'Version', 'SavedVariables']) {
  if (!directive(key)) fail(`${tocName} is missing "## ${key}:"`);
}

const iface = directive('Interface');
if (iface && !/^\d{5,6}(\s*,\s*\d{5,6})*$/.test(iface)) {
  fail(`${tocName} "## Interface: ${iface}" is not a valid interface number`);
}

// The packager substitutes this at build time from the tag. A literal version
// here means someone hand-edited it, and every future release ships that string.
const version = directive('Version');
if (version && version !== '@project-version@') {
  fail(`${tocName} "## Version: ${version}" should be "@project-version@" — the packager fills it from the tag`);
}

// --- files listed in the .toc actually exist, with matching case ---------
// Case matters. Most players are on Windows, where it does not, but the
// packager runs on Linux — where a path with the wrong case is simply absent.
const BACKSLASH = String.fromCharCode(92);
const listed = toc
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => line.split(BACKSLASH).join('/'));

const existsExactly = (relative) => {
  let dir = ROOT;
  for (const part of relative.split('/')) {
    let entries;
    try {
      entries = readdirSync(dir);
    } catch {
      return false;
    }
    if (!entries.includes(part)) return false;
    dir = join(dir, part);
  }
  return true;
};

for (const entry of listed) {
  if (!existsExactly(entry)) {
    fail(`${tocName} lists "${entry}" but no such file exists (check spelling and case)`);
  }
}

// --- Bindings.xml must not be in the .toc --------------------------------
// The client finds Bindings.xml by name and parses it as bindings. Listing it
// here parses it a second time as general UI XML, which rejects the Binding
// element and every attribute on it — three LUA_WARNINGs per login, and the
// warnings name real attributes, so the obvious reading is that the schema
// changed. Two correct attributes were deleted chasing that before the element
// line was read. Cheaper to make the mistake unrepeatable than to write it down.
if (listed.some((entry) => entry.toLowerCase() === 'bindings.xml')) {
  fail(`${tocName} lists Bindings.xml — the client already loads it by name, and listing it parses it again as UI XML (see the comment in Bindings.xml)`);
}

// --- every shipped Lua file is loaded by something -----------------------
const luaFiles = [];
const SKIP = new Set(['.git', '.github', '.release', 'docs', 'tools', 'node_modules']);
const walk = (relative) => {
  for (const name of readdirSync(join(ROOT, relative || '.'))) {
    if (SKIP.has(name)) continue;
    const rel = relative ? `${relative}/${name}` : name;
    if (statSync(join(ROOT, rel)).isDirectory()) walk(rel);
    else if (name.endsWith('.lua')) luaFiles.push(rel);
  }
};
walk('');

for (const file of luaFiles) {
  if (!listed.includes(file)) {
    fail(`${file} is not listed in ${tocName} — it would ship in the zip and never load`);
  }
}

// --- the trust promise, enforced -----------------------------------------
// The README promises "no network requests ever, no auto-upload". WoW gives an
// addon a small number of ways to push data off the client, and none of them
// belong here. This check is what makes that promise reviewable by a machine.
const FORBIDDEN = [
  [/\bSendAddonMessage\b/, 'SendAddonMessage'],
  [/\bSendChatMessage\b/, 'SendChatMessage'],
  [/\bBNSendGameData\b/, 'BNSendGameData'],
  [/\bSendServerMessage\b/, 'SendServerMessage'],
];
for (const file of luaFiles) {
  if (file.startsWith('Vendor/')) continue;
  const source = read(file);
  for (const [pattern, name] of FORBIDDEN) {
    if (pattern.test(source)) {
      fail(`${file} calls ${name} — this addon promises it never transmits (README "Trust")`);
    }
  }
}

// --- distribution policy, the machine-checkable parts --------------------
// CurseForge defers to the game developer's terms, so the binding rules for a
// WoW addon are Blizzard's: free, no advertising, no donation solicitation, and
// code that is "completely visible" — no obfuscation, no minification, nothing
// assembled from a string at runtime. docs/POLICY.md maps each rule to how this
// repo satisfies it; the ones a script can hold are held here.

const TITLE = directive('Title');
if (TITLE && /\d+\.\d+/.test(TITLE)) {
  fail(`"## Title: ${TITLE}" contains a version number — CurseForge requires versions live in the description, not the name`);
}

for (const file of luaFiles) {
  const source = read(file);

  // Obfuscation and minification. A shipped Lua file is meant to be read; a
  // 2000-byte line is either generated or hiding something. Vendor/ is checked
  // too — "completely visible" covers everything inside the zip.
  const longest = source.split(/\r?\n/).reduce((n, l) => Math.max(n, l.length), 0);
  if (longest > 2000) {
    fail(`${file} has a ${longest}-byte line — reads as minified, and addon code must stay visible`);
  }

  // Code assembled at runtime cannot be reviewed by a moderator reading the
  // file, which is the whole point of the visibility rule.
  for (const [pattern, name] of [
    [/\bloadstring\s*\(/, 'loadstring'],
    [/\bRunScript\s*\(/, 'RunScript'],
    [/(?<![\w.])load\s*\(/, 'load'],
  ]) {
    if (pattern.test(source)) {
      fail(`${file} builds code at runtime via ${name}() — addon code must be readable as shipped`);
    }
  }

  if (file.startsWith('Vendor/')) continue;

  // Advertising and donation solicitation are both out, and both are things a
  // well-meaning "support me" string walks straight into.
  for (const [pattern, what] of [
    [/\bdonat(e|ion)/i, 'a donation request'],
    [/\b(patreon|ko-?fi|paypal|buymeacoffee|boosty)\b/i, 'a funding link'],
    [/\bsubscrib/i, 'a subscription pitch'],
  ]) {
    if (pattern.test(source)) {
      fail(`${file} contains ${what} — addons may not solicit donations or advertise in game`);
    }
  }
}

// --- packaging hygiene ---------------------------------------------------
for (const required of ['LICENSE', 'README.md', 'CHANGELOG.md', 'Vendor/LibDeflate.lua']) {
  if (!here(required)) fail(`${required} is missing`);
}

// Distribution ids live in the .toc, which is where the packager reads them.
// Their absence is not a failure — it is the state before the projects exist.
for (const [key, site] of [
  ['X-Curse-Project-ID', 'CurseForge'],
  ['X-Wago-ID', 'Wago'],
  ['X-WoWI-ID', 'WoWInterface'],
]) {
  const id = directive(key);
  if (!id) {
    note(`no "## ${key}:" in ${tocName} — releases skip ${site} until it is added`);
  } else if (/^0+$/.test(id)) {
    // A placeholder is worse than an absent id. With no id the packager skips
    // the site; with 00000 and a token it attempts a real upload to a project
    // that does not exist, and takes the whole release down with it.
    fail(`${tocName} has "## ${key}: ${id}" — a placeholder id fails the ${site} upload instead of skipping it. Comment it out until the project exists.`);
  }
}

report();

function report() {
  for (const n of notes) console.log(`NOTE ${n}`);
  if (problems.length === 0) {
    console.log(
      `PASS ${tocName} — ${listed.length} files listed, ${luaFiles.length} Lua files, all accounted for`,
    );
    process.exit(0);
  }
  for (const p of problems) console.log(`FAIL ${p}`);
  console.log(`\n${problems.length} problem${problems.length === 1 ? '' : 's'}`);
  process.exit(1);
}
