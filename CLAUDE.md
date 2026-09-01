# warband.pro — Companion Addon

**Read [`docs/README.md`](docs/README.md) before changing anything in this
repo.** It is the read order for the twelve reference documents that define the
wire format, the UI, the CI and the distribution policy. This file is only a
pointer, plus the path every session takes and the rules that are not written
down anywhere else.

## The Path

Four steps, this order, every session. **None of them is a branch decision** —
that is the change of 2026-08-26 and the reason for it is under **Git** below.

1. **Work on the branch you are already on.** Whatever the harness assigned is
   fine, and it is very likely the *newest* ref in this checkout. The clone
   creates local `main` from `origin/main` as it stood at clone time, then the
   harness cuts its branch from a *newer* `origin/main`. Measured twice — local
   `main` at `30a1597` while `origin/main` and the harness branch were both at
   `89ed6e9`: **12 commits behind**, and the app repo was 36 behind on the same
   mechanism. So `git checkout main` is a checkout of last week's tree, and
   every symptom follows from it — the Lua you edit is not the Lua that ships,
   the luacheck warning you chase was fixed days ago, and `tools/vector.mjs`
   measures your fixtures against an older contract. **Do not switch to `main`
   to start clean.** If you are already on `main`, pull before working:
   `git -C /path/to/addon pull origin main`.

2. **Run Verify before you commit.** The three checks below are what CI runs,
   and running them first is what makes the branch mergeable the moment it is
   pushed.

3. **Commit.** The commit is the maintainer's, and a `CHANGELOG.md` note under
   `## [Unreleased]` moves with it when the change is one a player would notice.

4. **Push the branch and open a pull request, in the same turn.** Merge it
   yourself. `main` is what CI builds and what the packager releases from, so a
   merge is a real event — but Verify is what makes it safe, and it already ran
   at step 2. This container is ephemeral and is reclaimed after idle, so work
   that is committed and never pushed dies with it.

## Defaults

**Nothing here is a question.** This is the standing answer to what a session
would otherwise stop and ask — the toolchain, the commands, where a file goes,
what a new function should look like. Every line is read off this repo rather
than proposed for it, and the same rule the docs live under applies: **where
this and the code disagree, the code is right and this gets corrected in
place.**

### Toolchain

| | |
|---|---|
| Addon language | **Lua 5.1** — what the WoW client runs. Not 5.4 syntax, ever: no goto, no integer division, no bitwise operators. |
| Client target | Retail **Midnight**, `## Interface: 120100`. Retail only; there is no Classic branch. |
| Lint | **luacheck** against `.luacheckrc`, **0 warnings** |
| Tooling | **Node 22**, plain ESM `.mjs` under `tools/` |
| Dependencies | **none, in either direction.** There is no `package.json` — every tool imports `node:fs`, `node:path`, `node:url`, `node:zlib` and nothing else. LibDeflate is vendored as one file in `Vendor/`, and `.pkgmeta` has no `externals:` block on purpose. |

**Neither Lua nor luacheck is installed in a fresh container.** Measured
2026-09-01: `node` is on the path, `lua5.1` and `luacheck` are not. Install them
before Verify rather than reporting the tests as unrunnable — it is the same two
commands CI uses, takes about 40 seconds, and `.claude/settings.json` allows
both without asking:

```bash
apt-get update && apt-get install -y --no-install-recommends lua5.1 luarocks
luarocks install luacheck
```

### Verify, as one block

The **Verify** section below is the authority; this is the copy-pasteable form,
and it is the whole gate — there is no build step, no formatter and no test
runner beyond `lua5.1` running a file.

```bash
luacheck .
node tools/validate.mjs
node tools/vector.mjs
node tools/slop.mjs --unreleased
for t in import junk gear gearset freshness roster; do lua5.1 tools/$t-test.lua; done
node tools/vector.mjs --write && git diff --exit-code -- docs/contract/vectors
```

The last line is a **separate** check from `node tools/vector.mjs` and fails on
its own; the reason that trips people is under **Verify**. A green run of all
six is a green PR, because `ci.yml` runs exactly these.

### Layout

```
*.lua           the addon, flat at the root, loaded in .toc order
Vendor/         upstream LibDeflate, verbatim and unlinted — never reformat it
tools/          Node and Lua checks. Never ships (.pkgmeta strips it).
docs/           the twelve reference documents. Never ships.
docs/contract/  the golden wb1!/wbc1! vectors, regenerated not hand-edited
.github/        ci.yml and release.yml
```

**Flat root, and flat means flat.** A new Lua file goes at the root and gets a
line in `WarbandPro.toc` in load order — libs → namespace → data → UI →
`Core.lua` last, because Core registers events at load. `tools/validate.mjs`
fails the build if a listed file is missing or an unlisted one exists, and the
`.claude` commit hook treats a `.lua` file with a slash in its path as a file
that does not belong to this repo. Do not create a source directory.

Where a change goes, by default: **an existing file.** There are fourteen at the
root and each owns one subject — reading a WoW API is `Scan.lua`, item classification is
`Gear.lua`, anything that parses a string somebody else produced is
`Import.lua`, anything that turns the stored DB into something to look at is
`Roster.lua`, anything with a frame is `UI.lua`. A new file is a decision worth
a sentence in the commit; adding to the right existing one is not.

### Conventions

- **One global, deliberately.** `_G.WarbandPro = ns` in `Init.lua`, and
  everything else hangs off the private addon table: `local _, ns = ...` at the
  top of every file, then `ns.Gear = Gear`. `.luacheckrc`'s `globals` list is
  therefore also the leak audit — **a new luacheck warning is usually a leaked
  global, not a style nit.** Do not add a name to that list to silence one
  without knowing why it is there.
- **Every WoW API call goes through `ns.safe`.** 75 call sites across ten
  files. Midnight renamed and moved enough of the container and bank surface
  that a nil field must cost one section of one snapshot, never a Lua error in
  the middle of the user's raid. A section that cannot be read **goes missing
  rather than throwing**, and the wire format is null-tolerant so the website
  can tell "not read" from "read, empty" — `docs/CONTRACT.md` is the law on
  which is which.
- **Naming.** `PascalCase.lua` files, one module table per file named after it;
  `local function camelCase` for file-local helpers; `ns.camelCase` for shared
  ones; `SCREAMING_SNAKE` for constant tables (`EQUIPPED_SLOTS`,
  `EQUIPLOC_SLOT`). Constants that cross the wire live in `Init.lua`.
- **Formatting** is `.editorconfig` and it is not negotiable by feel: two
  spaces, LF, final newline, no trailing whitespace, 100 columns for Lua.
  luacheck allows 120 bytes and comments are exempt, because the box-drawing
  section rules measure long in bytes and short on screen.
- **Comments carry the reasoning.** The house style is a prose header saying
  what a file is for and what was tried and rejected — `Init.lua` on why
  `ns.LibDeflate` has a fallback, `Gear.lua` on why gear rides the item string
  instead of a decomposed model. A comment restating the line under it is
  noise.

### Testing

- **Pure code is tested off-client; impure code is a manual checklist.** That
  split is `docs/TESTING.md` and it is the whole strategy. `Bundle.lua`,
  `Export.lua`, `Import.lua`, `Gear.lua`, `GearSet.lua`, `Junk.lua` and
  `Roster.lua` are pure and have `tools/<subject>-test.lua`; `Scan.lua`,
  `Store.lua`, `UI.lua` and `Core.lua` are WoW-bound and are verified by
  `docs/QA.md` in game.
- **Tests are hand-rolled `lua5.1` scripts, not busted.** Each one stands a fake
  client API in front of the module, counts `pass`/`fail` and exits non-zero —
  copy the shape of `tools/import-test.lua`, which loads the *shipped*
  `Init.lua` rather than restating the namespace, because a fixture that
  restates the contract cannot catch the shipped file failing to meet it.
- **No coverage number, and the bar is a rule instead:** a change to a pure
  module arrives with its case in that module's test file, and a wire-format
  change arrives with regenerated fixtures. 295 assertions across the five
  files today.
- **A display gets a model, and the model gets the tests.** `Roster.lua` is
  the pattern: everything deciding what a cell says is pure and tested, and
  `UI.lua` is left with layout only. Six columns of plausible-looking numbers
  is exactly what a hand check cannot audit.
- **Never hand-edit `docs/contract/vectors`.** `node tools/vector.mjs --write`
  is deterministic; regenerate and commit.

### Commits, changelog, releases

**Conventional Commits with a scope, in the maintainer's voice** —
`type(scope): what is now true`, lowercase, no trailing period, the outcome
rather than the mechanics. Types in use: `feat`, `fix`, `docs`, `ci`, `chore`,
and `release: N.N.N — summary` for a cut. `fix(bindings): Bindings.xml is
loaded by name, so listing it in the .toc loads it twice` is the register.

**A `CHANGELOG.md` note under `## [Unreleased]` moves with the commit** when a
player would notice the change — and only then. It is written for players, not
for the commit log, and `tools/slop.mjs` fails CI on notes that read like
marketing. Leave the `## [Unreleased]` heading in place when cutting a release;
removing it turns `main` red.

**Cutting a release is not a routine decision and is not yours to make
unasked.** A tag ships to CurseForge and Wago and cannot be recalled;
`.claude/settings.json` asks before `git tag` and before pushing one. What
number a release gets is `CHANGELOG.md`'s semver rule — anchored to what the
player has to do about it, not to payload shape.

### The rest, stated once

- **No network calls, ever.** The central promise of this addon and of
  `docs/POLICY.md`. Nothing leaves the client on its own; the player copies a
  string by hand. This is not a performance trade-off to revisit.
- **No Ace3, no LibStub, no new library.** `docs/RESEARCH-REFERENCE.md` says
  why. LibDeflate is the one vendored dependency and it stays one file.
- **A wire-format change is never a local decision.** `wb1!` is a contract with
  `warband-pro/app`; `docs/CONTRACT.md` says when the prefix moves — additive
  and narrowing changes do not spend one, only a break does.
- **`.claude/settings.json` is a convenience, not a boundary.** The allow list
  covers the six Verify commands, the toolchain install, git and the PR tools so
  a session does not stop mid-path; the deny list restates rules already in
  prose — no force-push, no discarding uncommitted work, and no retrying the
  remote-ref delete that is 403 every time. The commit hook is the boundary, and
  it is in `.claude/hooks/`.

## Start Here

| Question | Document |
|----------|----------|
| What is this and who is it for? | [`docs/FLOW.md`](docs/FLOW.md) |
| What may I call in Midnight 12.1? | [`docs/RESEARCH-REFERENCE.md`](docs/RESEARCH-REFERENCE.md) |
| The `wb1!` wire format | [`docs/CONTRACT.md`](docs/CONTRACT.md) |
| The in-game window | [`docs/UI.md`](docs/UI.md) |
| What must pass before a push | [`docs/TESTING.md`](docs/TESTING.md), [`docs/CI.md`](docs/CI.md) |
| Release checklist | [`docs/QA.md`](docs/QA.md) |
| What the app side expects | [`docs/APP-IMPORT.md`](docs/APP-IMPORT.md) |
| Distribution rules | [`docs/POLICY.md`](docs/POLICY.md) |

## Never Mix the Two Repositories

**This repo is public and `warband-pro/app` is not.** This one is MIT on
GitHub and the packager ships it to CurseForge and Wago on every tag. That one
holds Battle.net and Discord client secrets, a session signing key, Cloudflare
account and D1 database ids, and a wiki whose own contract says credentials and
unpublished ids never enter it.

**A file that crosses from there to here is published, and publishing is a
one-way door.** A later commit does not un-ship a release: the tag is out and
CurseForge has already mirrored it. It is the same shape as the undeletable
remote ref under **Git** below, and it is worse by a wide margin, because what
escapes is content rather than a label. **This is why the branch rules could be
relaxed on 2026-08-26 and these could not** — the cost of the branch mistake was
a stale name in a list, and the cost of this one is a secret on CurseForge.

The risk is not carelessness with secrets. It is that **both repos are checked
out side by side, at sibling paths, and take near identical git commands.** On
2026-08-24 a session working across both ran two commands meant for this repo
while the shell was still in the app's directory — a `git pull` and a
`git branch -d`. Neither did harm; one was redundant and the other errored. The
same slip one line later, between a `git add -A` and a `git commit`, commits the
app's working tree here.

So:

- **One change, one repo.** A single commit never spans both. Cross-repo work —
  a `wb1!` change, a label both sides print — is two commits in two repos, and
  [`docs/CONTRACT.md`](docs/CONTRACT.md) is the seam they meet at.
- **Name the repo in the command** when both are open: `git -C /path/to/addon`,
  not `cd` and hope. `pwd` before any `git add`.
- **Nothing from the app is ever copied here** — not a config value, not a
  secret, not a snippet of its wiki. What this repo needs to know about the app
  is the wire format, and that lives in `docs/CONTRACT.md` and
  [`docs/APP-IMPORT.md`](docs/APP-IMPORT.md).

A `PreToolUse` hook
([`.claude/hooks/one-repo-per-commit.sh`](.claude/hooks/one-repo-per-commit.sh))
refuses a commit whose staged files are not this addon's, and refuses one
carrying a line that looks like a real credential. **It is an allowlist, not a
denylist** — it describes what this repo *is*, so it catches `src/`, `.wiki/`,
`wrangler.jsonc` and everything else over there without naming any of them. It
reads this repo's index whatever directory the command ran in, because a check
that trusted the command's own cwd would be blind exactly when it matters.

Prose is the other half and not a substitute: this file records, immediately
below, what happened the last time this repo relied on prose alone.

## Git

**The Path** at the top is the workflow. This section is the reasoning behind
it and the one constraint that still has teeth.

**Branch, push, PR, merge — take whatever the harness set up.** There is no
branch policy here to reconcile against, deliberately. This repo shares a
maintainer and a wire contract with `warband-pro/app`, which works the same way
and keeps the long version in its `.wiki/wiki/topics/dev-workflow.md`.

**This changed on 2026-08-26, and it is the reverse of what this file said
before.** The old rule was `main` only, never a `claude/*` branch, never a PR,
with two hooks enforcing it. The problem was not that the rule was wrong in
principle — it was that **the harness assigns a branch every session and a
repository cannot opt out**, so the contract and the platform disagreed at the
top of every session and reconciling them became the work. The maintainer's
report: *Claude keeps going back and forth, creating a branch anyway and then
working in `main` regardless.* Agreeing with the default costs a pull request.
Disagreeing with it cost the start of every session.

**Branch cleanup is a repository setting, not your job.** Settings → General →
*Automatically delete head branches* must stay on, because **an agent cannot
delete a remote ref from inside a Claude Code web session** — it is refused at
both layers available to one:

```
git push origin --delete <branch>
  POST /warband-pro/addon/git-receive-pack   HTTP/1.1 403 Forbidden

DELETE /repos/warband-pro/addon/git/refs/heads/<branch>
  403 {"message":"Write access to this GitHub API path is not permitted
       through this proxy."}
```

and the GitHub MCP server offers `create_branch` with no delete counterpart.
Creating, updating and force-updating refs all succeed; only deletion is
refused, on every branch, every time. It is a platform guardrail, so there is
nothing to retry and nothing to wait out.

**If merged branches pile up on the remote, say so plainly and leave them** —
one click for the maintainer in the GitHub UI, impossible for you. Do not
report the 403 as a proxy hang: git prints `the remote end hung up
unexpectedly` after any 403, which is its generic message for a closed
connection, not evidence of a timeout. And do not answer it by reintroducing a
branch policy; the checkbox is the answer.

This repo is where that constraint was learned the expensive way. Until
2026-08-23 it had no `CLAUDE.md`, so a session took the harness default at face
value and pushed `claude/lucid-curie-r4yp8g`, leaving a permanent stale label;
the same agent, the same day, in `app`, read that repo's contract and pushed
only `main`. It never recurred — checked 2026-08-26, `git ls-remote --heads` on
both remotes shows `main` and one long-lived `gear-tracker` and no `claude/*`
ref at all. One incident, ten days of policy. That arithmetic is why the policy
went and the checkbox stayed.

### Commit authorship is not a rule — removed 2026-08-26

**Whatever identity the session arrives with is fine.** Nothing to check, pin or
amend, and no reason to stop and ask about the author or an "Unverified" badge.

This said the reverse from 2026-08-23 until 2026-08-26: every commit had to be
`Vocino <travis@vocino.com>`, with no agent attribution in the message. **It
worked** — 49 commits here and 111 in the app, not one authored by an agent.

It was removed because it bought little against what it cost to carry, and
because the record it protected is muddied in the one place a stranger looks
anyway. **This repo is the example**: GitHub's contributors panel lists `claude`
beside `vocino`, and nothing here supports it — `git log` across every ref and
all seven tags returns 57 commits by `Vocino` and `vocino` only, and GitHub's
own commit search returns zero for `author:claude`. It is a cache of history
that no longer exists, plausibly the pre-`CLAUDE.md` `claude/lucid-curie-r4yp8g`
merge. **No repo-side rule reaches it**; only GitHub Support can force a
recompute.

`CHANGELOG.md` is a separate question and unchanged — it is what players read,
so it stays written for them, and `tools/slop.mjs` still fails CI on notes that
do not read like a person wrote them.

## Verify

`main` is what CI builds and what the packager releases from, so run the checks
before the **commit** (step 2) — not at merge time and never after. A gate
attached to the merge would run long after the code was written and against a
batch rather than a change. These are what the `ci.yml` `luacheck` and
`packaging + contract` jobs run, so a green run here is a green PR:

```bash
luacheck .                      # zero warnings under .luacheckrc
node tools/validate.mjs         # .toc and .pkgmeta agree
node tools/vector.mjs           # wb1! round-trips
node tools/slop.mjs --unreleased   # the notes read like a person wrote them

for t in import junk gear gearset freshness roster; do lua5.1 tools/$t-test.lua; done

# The fixture check, which is NOT the line above and fails separately:
node tools/vector.mjs --write && git diff --exit-code -- docs/contract/vectors
```

**`node tools/vector.mjs` does not check that the committed fixtures match** —
it round-trips the vectors in memory and passes on a tree whose `.wb1` files
are stale. Matching is the separate `--write` and `git diff` above, and it is
the one that fails alone. **This block said "the same three" and named the
round-trip as the fixture check until 2026-08-30**, and a session that ran all
three green pushed a PR that CI failed on stale fixtures within a minute.
`--write` is deterministic, so regenerating and committing is the whole fix.

A new luacheck warning is usually a leaked global rather than a style nit —
`.luacheckrc` lists every global this addon is allowed to touch.

Changing the wire format is never a local decision: `wb1!` is a contract with
`warband-pro/app`, and [`docs/CONTRACT.md`](docs/CONTRACT.md) says when the
prefix moves — additive and narrowing changes do not spend one, and only a
break does. **What number the next release gets is a different question**, and
[`CHANGELOG.md`](CHANGELOG.md) answers it: semver anchored to what the player
has to do about it, not to payload shape. A wire break is at least a MAJOR; not
every MAJOR is a wire break. Regenerate fixtures with
`node tools/vector.mjs --write`.

## Working Conventions

- **No network calls. Ever.** This is the addon's central promise to its users
  and to [`docs/POLICY.md`](docs/POLICY.md). The player copies a string out by
  hand; nothing leaves the client on its own.
- **Flat root, fewest moving parts.** Lua files live at the repository root and
  load in the order the `.toc` lists — libs, core, data, ui.
- **No Ace3, no LibStub.** See
  [`docs/RESEARCH-REFERENCE.md`](docs/RESEARCH-REFERENCE.md).
- **Notes accumulate under `## [Unreleased]` in `CHANGELOG.md`,** and
  `tools/slop.mjs --unreleased` fails CI if they do not read like a person
  wrote them.
