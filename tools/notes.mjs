#!/usr/bin/env node
// The release notes for one version — that section, and nothing else.
//
//   node tools/notes.mjs 1.5.0     print the section for that version
//
// Why this exists. `.pkgmeta` names CHANGELOG.md as the `manual-changelog`, and
// the BigWigs packager ships that file **whole**: it does not split it by tag.
// So every release before 1.5.0 published the entire changelog — the
// maintainer-facing header explaining how to cut a release, `## [Unreleased]`,
// and every version back to 1.0.0 — as the GitHub release body, as the
// CurseForge and Wago upload description, and into the Discord embed, which cut
// it off mid-sentence at 4096 characters somewhere inside the notes nobody had
// reached yet.
//
// CHANGELOG.md said the opposite in its own first paragraph ("the packager
// sends the section matching the tag ... verbatim") and had said it since
// 1.0.0. Nothing checked, because the thing to check was in a release log and
// the claim was in a header, and no one reads a release body of their own
// project.
//
// It also meant the slop pass was guarding a budget that never applied: about
// 1200 characters of boilerplate landed ahead of the notes, so a section could
// pass at 3900 and still be truncated. The budget is real now.
//
// release.yml runs this and writes the result over the checkout's CHANGELOG.md
// before the packager sees it. The committed file is untouched.

import { section, CHANGELOG } from './changelog.mjs';

const arg = process.argv[2];
if (!arg) {
  console.error('usage: node tools/notes.mjs <version>');
  process.exit(2);
}

const found = section(arg);
if (!found.found) {
  console.error(`::error::${CHANGELOG} has no '## [${found.wanted}]' section — write the release notes first`);
  process.exit(1);
}
if (found.prose === '') {
  console.error(`::error::${CHANGELOG} section '## [${found.wanted}]' is empty — that is what players would read`);
  process.exit(1);
}

// The heading carries the version and the release's title phrase, which is the
// one line worth having at the top of a release body. Everything above it in
// the file is instructions to whoever cuts the release, and no player has ever
// needed them.
process.stdout.write(`${found.heading}\n\n${found.prose}\n`);
