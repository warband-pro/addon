# warband.pro — Companion Addon

**Read [`docs/README.md`](docs/README.md) before changing anything in this
repo.** It is the read order for the twelve reference documents that define the
wire format, the UI, the CI and the distribution policy. This file is only a
pointer, plus the path every session takes and the rules that are not written
down anywhere else.

## The Path

Four steps, this order, every session. There is no other route through this
repo. A `SessionStart` hook
([`.claude/hooks/start-on-main.sh`](.claude/hooks/start-on-main.sh)) performs 1
and 2 before you read a line of code — but know them anyway, because a hook
that cannot act says so and then it is on you.

1. **Be on `main`.** Never a `claude/*` branch. A harness branch assignment is
   a default; this file is the maintainer's instruction. Switch *before* you
   read code, not after you have written some — "land it later" is what turns a
   day of work into a redo. Say in your reply that you switched.

2. **Pull before working.** `git -C /path/to/addon pull origin main`. This is a
   separate step from 1, and skipping it is the failure nobody had written
   down: **this checkout's `main` is stale the moment the container exists.**
   The clone creates local `main` from `origin/main` as it stood at clone time,
   then the harness cuts its branch from a *newer* `origin/main`. Measured at
   the start of the session that wrote this section — local `main` at
   `30a1597`, `origin/main` and the harness branch both at `89ed6e9`: **12
   commits behind.** So `git checkout main` on its own is a checkout of last
   week's tree, and every symptom follows from it — the Lua you edit is not the
   Lua on `main`, the luacheck warning you chase was fixed days ago, and
   `tools/vector.mjs` measures your fixtures against an older contract.

3. **Commit to `main` when the work is done.** Run **Verify** first — the three
   checks below are what CI runs, and running them before the commit is what
   makes the commit pushable the moment it is asked for. The commit is the
   maintainer's, and a `CHANGELOG.md` note under `## [Unreleased]` moves with
   it.

4. **Push to `main` only when asked.** Committing is finished work; pushing is
   the maintainer's call, because `main` is what CI builds and what the
   packager releases from. So **end the turn by naming what is committed and
   unpushed, and offer** — never leave it implied. This container is ephemeral
   and is reclaimed after idle, so a commit that was never pushed dies with it.
   That is the one way this step loses work, and saying the sentence is what
   prevents it.

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
CurseForge has already mirrored it. This is the same shape as the harness
branch below, and it is worse, because the thing that escapes is not a label.

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
it and the rule that has teeth.

**Commit to `main`.** No feature branches, no pull requests. This project is
early and single-maintainer, and it shares a maintainer and a wire contract
with `warband-pro/app`, which works the same way and explains the reasoning at
length in its `.wiki/wiki/topics/dev-workflow.md`. Push when the maintainer
asks (step 4), and say when a commit is sitting unpushed.

**If a harness starts you on a `claude/*` branch, switch to `main` anyway and
say so in your reply.** A harness branch assignment is a default; this file is
the maintainer's instruction.

**Never push the `claude/*` branch.** This one is not a preference, it is a
one-way door. A harness branch that reaches this remote cannot be removed from
inside a Claude Code web session — remote ref deletion is refused at both
layers available to an agent:

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

This repo is the reason the rule is written down. Until 2026-08-23 it had no
`CLAUDE.md`, so a session took the harness default at face value and pushed
`claude/lucid-curie-r4yp8g`; the same agent, the same day, in `app`, read that
repo's contract and pushed only `main`. One remote ended up with a permanent
stale label pointing at its own `main` commit and the other did not. The
proxy, the timing and the repo were all blamed before the difference turned out
to be this file's absence.

A `PreToolUse` hook
([`.claude/hooks/no-harness-branch-push.sh`](.claude/hooks/no-harness-branch-push.sh))
now refuses the push, because prose is what already failed once. **If a stale
branch already exists, say so plainly and leave it** — it is one click for the
maintainer in the GitHub UI and impossible for you. Do not report the 403 as a
proxy hang: git prints `the remote end hung up unexpectedly` after any 403,
which is its generic message for a closed connection, not evidence of a
timeout.

### Commit authorship

**Every commit in this repo is the maintainer's.** Author is `Vocino
<travis@vocino.com>`, and the message carries no agent attribution — no
`Co-Authored-By: Claude` trailer, no `Generated with Claude Code` footer, no
model name, no session link, in the subject, the body or the trailers. A commit
message describes the change; it does not sign it.

The defaults run the other way: a web session arrives with `user.name` already
set to `Claude <noreply@anthropic.com>`. Check before the first commit of a
session:

```bash
git config user.name "Vocino"
git config user.email "travis@vocino.com"
```

The same rule applies to anything else a change publishes — code comments,
release notes, `CHANGELOG.md`. Attribution belongs in the session, not in the
repository.

## Verify

`main` is what CI builds and what the packager releases from, so run the checks
before the **commit** (step 3) — not at push time and never after. Pushing is a
separate, later, asked-for step, and a gate attached to it would run long after
the code was written and against a batch rather than a change. These are the
same three the `ci.yml` `luacheck` and `packaging + contract` jobs run:

```bash
luacheck .                      # zero warnings under .luacheckrc
node tools/validate.mjs         # .toc and .pkgmeta agree
node tools/vector.mjs           # wb1! round-trips, fixtures still match
```

A new luacheck warning is usually a leaked global rather than a style nit —
`.luacheckrc` lists every global this addon is allowed to touch.

Changing the wire format is never a local decision: `wb1!` is a contract with
`warband-pro/app`, and [`docs/CONTRACT.md`](docs/CONTRACT.md) has the
versioning and bump policy. Regenerate fixtures with
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
