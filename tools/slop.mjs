#!/usr/bin/env node
// The slop pass — read the release notes the way a stranger in Discord will.
//
// Every release section in CHANGELOG.md ends up in three places players read:
// the GitHub Release body, the CurseForge/Wago/WoWI description, and now a
// Discord embed. That is the whole audience, reading text nobody proofread
// after it was written. This is the proofreader.
//
//   node tools/slop.mjs 1.0.2          check the section for one version
//   node tools/slop.mjs --unreleased   check ## [Unreleased], fine if empty
//
// It looks for the specific tells of machine-written marketing copy: borrowed
// vocabulary, announcement voice, hedging filler, and adjectives standing in
// for numbers. It does *not* police this repo's actual voice — em dashes, bold
// sentence leads, fragments, and long technical paragraphs are the house style
// and are deliberately not flagged. Add a rule only for something that would
// embarrass the project if a player read it aloud.
//
// Exits non-zero on any finding. SLOP_OK=1 downgrades to a warning, for the
// case where a rule is wrong and the release should not wait on a fix.

import { section, CHANGELOG } from './changelog.mjs';

// Discord truncates an embed description at 4096 characters, mid-word, with no
// indication anything was cut. Leave headroom for what the action adds.
const DISCORD_LIMIT = 4096;
const DISCORD_BUDGET = 3900;

// [pattern, why it is a problem]. Grouped by the kind of tell, not by severity
// — everything here fails.
const RULES = [
  // Vocabulary that arrives with the machine and never with a person.
  [/\bdelv(e|es|ed|ing)\b/i, 'nobody has ever said "delve" out loud'],
  [/\bseamless(ly)?\b/i, 'say what actually happens instead'],
  [/\brobust\b/i, 'means nothing — name the failure it survives'],
  [/\bleverag(e|es|ed|ing)\b/i, 'it is "use"'],
  [/\belevat(e|es|ed|ing)\b/i, 'marketing verb'],
  [/\bunleash(es|ed|ing)?\b/i, 'marketing verb'],
  [/\bempower(s|ed|ing)?\b/i, 'marketing verb'],
  [/\bstreamlin(e|es|ed|ing)\b/i, 'marketing verb'],
  [/\bsupercharg|turbocharg/i, 'marketing verb'],
  [/\bcutting[- ]edge\b/i, 'dead phrase'],
  [/\bgame[- ]chang(er|ing)\b/i, 'dead phrase'],
  [/\brevolutionis|revolutioniz/i, 'it is an addon changelog'],
  [/\btransformative\b/i, 'dead phrase'],
  [/\bholistic\b/i, 'dead phrase'],
  [/\bsynerg(y|ies|istic)\b/i, 'dead phrase'],
  [/\bbest[- ]in[- ]class\b|\bworld[- ]class\b/i, 'dead phrase'],
  [/\b(plethora|myriad)\b/i, 'say the number'],
  [/\btapestry\b/i, 'the tell of tells'],
  [/\ba testament to\b/i, 'dead phrase'],
  [/\b(harness|unlock) the (power|potential)\b/i, 'dead phrase'],
  [/\bnavigat(e|es|ing) the complexit/i, 'dead phrase'],

  // Announcement voice. Release notes are notes, not a keynote.
  [/\bwe(?:'re| are) (excited|thrilled|pleased|happy|proud)\b/i, 'skip the feelings, lead with the change'],
  [/\b(excited|thrilled|happy|pleased|proud) to announce\b/i, 'skip the feelings, lead with the change'],
  [/\bwithout further ado\b/i, 'then do not have an ado'],
  [/\b(let'?s )?div(e|es|ing) (in|into)\b/i, 'keynote voice'],
  [/\bstay tuned\b/i, 'keynote voice'],
  [/^as always[,!]/im, 'keynote voice'],
  [/\bhappy (gaming|raiding|hunting|coding|adventuring)\b/i, 'sign-off nobody asked for'],
  [/\bin today'?s\b/i, 'essay opener'],
  [/\bfast[- ]paced\b/i, 'essay opener'],
  [/\blook no further\b/i, 'ad copy'],
  [/\bto the next level\b/i, 'ad copy'],
  [/\brest assured\b/i, 'ad copy'],

  // Filler that survives because it sounds like writing.
  [/\bit(?:'s| is) (important|worth) (to note|noting)\b/i, 'then just note it'],
  [/\bplease note that\b/i, 'drop the preamble'],
  [/^(moreover|furthermore|additionally|overall|in conclusion|to summari[sz]e|in summary)\b/im, 'essay connective — start the sentence'],
  [/\bat the end of the day\b/i, 'filler'],

  // Adjectives doing a number's job. This project measures things, so say the
  // measurement — "4-7KB for 6 chars" is the standard 1.0.0 set.
  [/\b(significantly|dramatically|drastically|vastly|massively|greatly|substantially)\b/i, 'quantify it or cut it'],
  [/\bblazing(ly)? fast\b/i, 'quantify it or cut it'],
  [/\bunder the hood\b/i, 'say which part'],

  // Constructions that only ever come out of a model.
  [/\b(isn'?t|is not|not) just\b[^.\n]{1,60}\bit(?:'s| is)\b/i, 'the "not just X, it\'s Y" construction'],
  [/\bwhether you(?:'re| are)\b/i, 'the "whether you\'re X or Y" construction'],
  [/\b(more \w+|\w{3,}er|\w{4,}ly), (more \w+|\w{3,}er|\w{4,}ly),? and (more \w+|\w{3,}er|\w{4,}ly)\b/i, 'rule-of-three adjective list'],

  // Emoji as decoration. Inline status glyphs are fine — 1.0.0 uses the
  // website's own preview dots to explain what the import screen shows — but an
  // emoji leading a bullet or a heading reads as a product launch post.
  [/^\s*[-*]\s+[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]/u, 'emoji-led bullet reads as a launch post'],
  [/^#{1,6}\s.*[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]/u, 'emoji in a heading reads as a launch post'],
];

const arg = process.argv[2];
if (!arg) {
  console.error('usage: node tools/slop.mjs <version> | --unreleased');
  process.exit(2);
}
// Located by the one parser both this and tools/notes.mjs use, so what gets
// proofread here is exactly what the release publishes.
const found = section(arg);
const { wanted } = found;
if (!found.found) {
  console.error(`::error::${CHANGELOG} has no '## [${wanted}]' section — write the release notes first`);
  process.exit(1);
}
const { start, body, prose } = found;

if (arg === '--unreleased' && prose === '') {
  console.log('slop: ## [Unreleased] is empty, nothing to check');
  process.exit(0);
}
if (prose === '') {
  console.error(`::error::${CHANGELOG} section '## [${wanted}]' is empty — that is what players would read`);
  process.exit(1);
}

const findings = [];
body.forEach((line, i) => {
  const lineNo = start + 2 + i; // 1-based, offset past the heading
  for (const [re, why] of RULES) {
    const m = line.match(re);
    if (m) findings.push({ lineNo, hit: m[0].trim(), why });
  }
});

// Length is a slop problem too: a section Discord cuts off mid-sentence reads
// worse than one that was written short in the first place.
if (prose.length > DISCORD_BUDGET) {
  findings.push({
    lineNo: start + 1,
    hit: `${prose.length} characters`,
    why: `Discord cuts an embed at ${DISCORD_LIMIT} with no ellipsis — keep this under ${DISCORD_BUDGET}`,
  });
}

if (findings.length === 0) {
  console.log(`slop: ## [${wanted}] reads clean (${prose.length} chars, budget ${DISCORD_BUDGET})`);
  process.exit(0);
}

const soft = process.env.SLOP_OK === '1';
const level = soft ? 'warning' : 'error';
for (const f of findings) {
  console.error(`::${level} file=${CHANGELOG},line=${f.lineNo}::slop: "${f.hit}" — ${f.why}`);
  console.error(`${CHANGELOG}:${f.lineNo}  "${f.hit}"  ${f.why}`);
}
console.error(`\n${findings.length} finding(s) in ## [${wanted}]. Rewrite them, or set SLOP_OK=1 if a rule is wrong.`);
process.exit(soft ? 0 : 1);
