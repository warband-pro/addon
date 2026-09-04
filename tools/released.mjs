#!/usr/bin/env node
// Did the version in CHANGELOG.md ever reach a player?
//
//   node tools/released.mjs             report; fails on a broken changelog
//   node tools/released.mjs --shipped   also fails when the newest version
//                                       has no tag. This is the one CI runs
//                                       on main.
//
// The addon has no version number in it. `## Version: @project-version@` in the
// .toc is a placeholder the packager fills in from the tag it is building, so
// **the tag is the version** — there is no file to bump and nothing in the tree
// says which release it is. A version therefore exists in two places that can
// disagree: a `## [x.y.z]` heading here, and a `vx.y.z` tag on the remote. The
// heading is what a person writes; the tag is what ships. Nothing connected
// them, and writing the heading feels like cutting the release.
//
// It is not, and this repo has the record to prove it. 1.3.0 and 1.4.0 were
// written up, dated, merged — and never tagged, so CurseForge went 1.2.0 →
// 1.5.0 and two versions of work sat in main where no player could reach it.
// 1.9.0 did it again three months later: the whole Roster grid, written up on
// 2026-09-02, still not on CurseForge or Wago two days later. Three of the
// thirteen versions this changelog describes were never released at all.
//
// Nothing caught it because every check in CI reads the tree, and the tree is
// identical either way — the tag is on the remote, which is exactly the thing
// none of them look at. So this one does.
//
// It shells out to git for the tag list, which makes it the only tool here
// that imports node:child_process. The zero-dependency rule is about packages,
// not the standard library, and the alternative — parsing .git/refs and
// packed-refs by hand — would be a second implementation of `git tag`.

import { execFileSync } from 'node:child_process';
import { section, versions, CHANGELOG, ROOT } from './changelog.mjs';

const shipped = process.argv.includes('--shipped');
const problems = [];
const notes = [];
const fail = (msg) => problems.push(msg);
const note = (msg) => notes.push(msg);

// --- what has shipped ----------------------------------------------------
// A shallow checkout has no tags, and neither does a repo before its first
// release. Both look the same from here, so say so out loud rather than
// passing quietly — a silent skip is how this check would come to mean
// nothing.
function gitTags() {
  try {
    return execFileSync('git', ['tag', '--list', 'v*'], { cwd: ROOT, encoding: 'utf8' })
      .split('\n')
      .map((t) => t.trim().replace(/^v/, ''))
      .filter((t) => /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/.test(t));
  } catch {
    return null;
  }
}

const tags = gitTags();
if (tags === null) {
  console.log('NOTE not a git checkout — nothing to compare the changelog against');
  process.exit(0);
}
if (tags.length === 0) {
  console.log('NOTE no v* tags here. Either nothing has been released yet, or');
  console.log('     this checkout never fetched them — `git fetch --tags` and try again.');
  process.exit(0);
}

const tagged = new Set(tags);
const written = versions();
if (written.length === 0) {
  console.log(`FAIL ${CHANGELOG} has no '## [x.y.z]' section at all`);
  process.exit(1);
}

// --- semver, enough of it ------------------------------------------------
// Prerelease suffixes sort before the release they lead to, which is the only
// part of the spec that matters here.
const parts = (v) => {
  const [core, pre] = v.split('-');
  return { nums: core.split('.').map(Number), pre };
};
function compare(a, b) {
  const A = parts(a);
  const B = parts(b);
  for (let i = 0; i < 3; i++) {
    if (A.nums[i] !== B.nums[i]) return A.nums[i] - B.nums[i];
  }
  if (A.pre === B.pre) return 0;
  if (!A.pre) return 1;
  if (!B.pre) return -1;
  return A.pre < B.pre ? -1 : 1;
}
const highest = (list) => [...list].sort(compare).at(-1);

const newest = written[0];
const highestWritten = highest(written);
const highestTag = highest(tags);

// --- the checks ----------------------------------------------------------

// The file is newest-first, and notes.mjs, slop.mjs and the release workflow
// all take the top heading as "the version this is". A heading out of order
// makes that read the wrong section.
if (newest !== highestWritten) {
  fail(
    `${CHANGELOG} is out of order — the top section is [${newest}] but [${highestWritten}] is higher up the number line. Newest first.`,
  );
}

// A tag ahead of the changelog is a release that went out with somebody else's
// notes: notes.mjs cuts by exact heading, so the release would have failed —
// unless the tag was pushed without one at all.
if (compare(highestTag, highestWritten) > 0) {
  fail(
    `v${highestTag} is tagged but ${CHANGELOG}'s newest section is [${highestWritten}] — a release shipped with no notes of its own`,
  );
}

for (const tag of tags) {
  if (!written.includes(tag)) {
    fail(`v${tag} is tagged with no '## [${tag}]' section — players downloaded it with nothing to read`);
  }
}

// The drift this whole file exists for.
const stranded = written.filter((v) => !tagged.has(v) && compare(v, highestTag) < 0);
if (stranded.length > 0) {
  note(
    `never released: ${[...stranded].sort(compare).join(', ')} — written up, skipped, and now behind v${highestTag}. History; nothing to do.`,
  );
}

if (!tagged.has(newest)) {
  const message =
    `${CHANGELOG}'s newest section is [${newest}] and there is no v${newest} tag. ` +
    `That version is not on CurseForge or Wago — the newest thing a player can download is v${highestTag}. ` +
    `Ship it:\n       git tag -a v${newest} -m v${newest} && git push origin v${newest}`;
  if (shipped) fail(message);
  else note(message);
}

// --- what is waiting for a number ----------------------------------------
// Notes accumulate under ## [Unreleased] on purpose, so this is never a
// failure. It is the nudge: here is what is queued, and here is the number it
// would go out under.
const bump = (v, kind) => {
  const [major, minor, patch] = v.split('-')[0].split('.').map(Number);
  if (kind === 'minor') return `${major}.${minor + 1}.0`;
  return `${major}.${minor}.${patch + 1}`;
};

const pending = section('--unreleased');
if (!pending.found) {
  fail(`${CHANGELOG} has no '## [Unreleased]' heading — cutting a release adds a section, it does not rename that one`);
} else if (pending.prose !== '') {
  const kinds = pending.body
    .map((l) => l.match(/^###\s+(\w+)/)?.[1])
    .filter(Boolean)
    .map((k) => k.toLowerCase());
  const kind = kinds.includes('added') ? 'minor' : 'patch';
  // On top of the newest *written* version, not the newest tag. If [1.9.0] is
  // sitting untagged the next number is 1.9.1, not 1.8.1 — 1.9.0 is spent the
  // moment its heading exists, whether or not anyone has shipped it yet.
  const next = bump(newest, kind);
  const lines = pending.body.filter((l) => l.trim().startsWith('-')).length;
  note(
    `## [Unreleased] holds ${lines} note${lines === 1 ? '' : 's'} under ${kinds.join(', ') || 'no heading'} — a ${kind} on top of ${newest}, so v${next}. ` +
      `A wire break is a MAJOR instead; docs/CONTRACT.md decides that, not this.`,
  );
}

// --- report --------------------------------------------------------------
for (const n of notes) console.log(`NOTE ${n}`);
if (problems.length === 0) {
  console.log(`PASS newest section [${newest}]${tagged.has(newest) ? ` is tagged and released` : ` is not tagged yet`} — ${tags.length} releases behind it`);
  process.exit(0);
}
for (const p of problems) {
  if (process.env.GITHUB_ACTIONS) console.log(`::error::${p.replace(/\n\s+/g, ' ')}`);
  console.log(`FAIL ${p}`);
}
console.log(`\n${problems.length} problem${problems.length === 1 ? '' : 's'}`);
process.exit(1);
