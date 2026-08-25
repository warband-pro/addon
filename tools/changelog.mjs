// The changelog's one parser.
//
// No shebang, unlike everything else in tools/: this one is imported, never
// run. Every other .mjs here is a command.
//
// Two things read a release section out of CHANGELOG.md and they must agree:
// tools/slop.mjs proofreads it before a tag, and tools/notes.mjs is what the
// release actually publishes. A second copy of "find the heading, stop at the
// next one" is a copy that drifts, and the drift would be silent in the
// direction that matters — slop passing a section the release never sends.
//
// Not a command. `node tools/notes.mjs <version>` is the one you run.

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CHANGELOG = 'CHANGELOG.md';

/**
 * One release section, located by version or by `--unreleased`.
 *
 * `start` is the 0-based index of the heading line, which slop.mjs needs to
 * report findings at a real file:line. `heading` is that line; `body` is
 * everything under it; `prose` is the body trimmed, which is what a player
 * ends up reading and therefore what gets measured and proofread.
 */
export function section(arg) {
  const wanted = arg === '--unreleased' ? 'Unreleased' : String(arg).replace(/^v/, '');
  const lines = readFileSync(join(ROOT, CHANGELOG), 'utf8').split('\n');

  const start = lines.findIndex((l) => l.startsWith(`## [${wanted}]`));
  if (start === -1) return { wanted, found: false };

  // Everything up to the next `## `. Link reference definitions at the bottom
  // of the file start with `[`, not `#`, so the last section would otherwise
  // swallow them — cut on those too.
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## ') || /^\[[^\]]+\]:\s/.test(lines[i])) {
      end = i;
      break;
    }
  }

  const body = lines.slice(start + 1, end);
  return { wanted, found: true, start, heading: lines[start], body, prose: body.join('\n').trim() };
}
