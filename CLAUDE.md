# warband.pro — Companion Addon

**Read [`docs/README.md`](docs/README.md) before changing anything in this
repo.** It is the read order for the twelve reference documents that define the
wire format, the UI, the CI and the distribution policy. This file is only a
pointer, plus the two rules that are not written down anywhere else.

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

## Git

**Commit and push straight to `main`.** No feature branches, no pull requests.
This project is early and single-maintainer, and it shares a maintainer and a
wire contract with `warband-pro/app`, which works the same way and explains the
reasoning at length in its `.wiki/wiki/topics/dev-workflow.md`.

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
before pushing, not after. These are the same three the `ci.yml` `luacheck` and
`packaging + contract` jobs run:

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
