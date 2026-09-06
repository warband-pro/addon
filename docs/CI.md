# CI, packaging, and releases

Two workflows, one packager, no manual zip. Cutting a release is one command or
one button, and everything between that and the download page is automatic.

## What runs, and when

### `.github/workflows/ci.yml` — every push to `main`, every PR

| Job | What it proves |
| --- | --- |
| `luacheck` | Zero warnings under `.luacheckrc`. That file lists every global the addon may touch, so a new warning is usually a leaked global rather than a style nit. |
| `packaging + contract` | `tools/validate.mjs` — the `.toc` and `.pkgmeta` are internally consistent. `tools/vector.mjs` — a `wb1!` payload survives encode → decode unchanged, and the committed `.wb1` fixtures still match. `tools/slop.mjs --unreleased` — the notes accumulating under `## [Unreleased]` read like a person wrote them. `tools/released.mjs` — the newest version in `CHANGELOG.md` has a tag, so it actually reached a download page. |
| `package (dry run)` | The real packager builds the real zip with uploads switched off, and attaches it as a workflow artifact. |

That artifact matters: **every push to `main` produces a downloadable, correctly
structured zip** under the run's Artifacts. Testers install builds without anyone
cutting a version.

### `.github/workflows/release.yml` — on a `v*` tag, or on demand

Runs `ci.yml` in full first, then runs the slop pass on the section being
released (see below), then hands the repo to
[BigWigsMods/packager](https://github.com/BigWigsMods/packager), which:

1. substitutes `@project-version@` in the `.toc` and `LibDeflate.lua` from the tag,
2. builds `WarbandPro-v1.0.0.zip` with `docs/`, `tools/`, and the dotfiles stripped per `.pkgmeta`,
3. copies `LICENSE` into the zip as `LICENSE.txt`,
4. creates a GitHub Release with the zip attached,
5. uploads to CurseForge, Wago, and WoWInterface, using the matching `## [x.y.z]` section of `CHANGELOG.md` as the release notes.

A site is uploaded to only when **both** its token secret and its `.toc` id are
present. Missing either one logs a warning and skips that site — which is how
this pipeline is useful before the CurseForge project exists.

Then it reads the release back with `gh release view` and posts it into Discord
with [SethCohen/github-releases-to-discord](https://github.com/SethCohen/github-releases-to-discord).
No `DISCORD_WEBHOOK` secret means that step is skipped, same as any other site.

## Why the Discord post is a step and not its own workflow

The action's README shows a standalone workflow on `release: published`. That
does not work here, and it fails *silently*, so it is worth knowing why.

The packager creates the GitHub Release using `GITHUB_TOKEN`. GitHub will not
start a workflow run from an event that token caused — a deliberate guard
against a workflow triggering itself in a loop, and one no permission setting
waives. A `release: published` workflow would sit there and never fire, which
looks exactly like a misconfigured webhook.

So the announcement runs inside the release job, right after packaging, and
passes `release_name` / `release_body` / `release_html_url` explicitly instead
of reading `github.event.release` — that context is empty on a tag push. It also
means Discord shows the release body verbatim rather than a second, separately
rendered copy of the changelog.

Which is why the release body has to be right at the source. `.pkgmeta` names
CHANGELOG.md as the `manual-changelog` and the packager ships that file
**whole**; it has no notion of a tag's section. Every release through v1.5.0
therefore published the entire changelog to all four audiences, and Discord
truncated it at 4096 characters somewhere inside notes nobody had reached. The
"Release notes for this tag only" step now runs `tools/notes.mjs` and writes
the one section over CHANGELOG.md in the checkout, before the packager sees it.
Nothing is committed, and the zip's own changelog becomes what is new in that
version.

The parser is shared: `tools/changelog.mjs` finds a section and both
`tools/slop.mjs` and `tools/notes.mjs` use it, so what the slop pass proofreads
is what the release publishes. Splitting those was how the budget below came to
be guarding a number that did not apply.

## The slop pass

`tools/slop.mjs` reads a changelog section the way a stranger scrolling Discord
will. That section is the release in four places at once — the GitHub Release
body, three distribution sites, and now a Discord embed — so it gets proofread
before any of them see it.

```bash
node tools/slop.mjs 1.0.2      # the section for one version
node tools/slop.mjs --unreleased
```

It fails on borrowed marketing vocabulary, keynote voice, essay filler,
adjectives standing in for numbers, the constructions that only ever come out of
a language model, emoji leading a bullet or heading, and a section long enough
that Discord will cut it off mid-sentence at 4096 characters. It deliberately
does **not** flag this project's own voice: em dashes, bold sentence leads,
fragments, and dense technical paragraphs all pass.

The release workflow runs it before tagging, so a finding stops the release. CI
runs it on `## [Unreleased]` every push, so the notes are clean well before tag
day. If a rule is wrong and the release should not wait on a fix, `SLOP_OK=1`
downgrades findings to warnings — but the better move is usually to delete the
rule, because a rule that fires on good writing will keep doing it.

## Cutting a release

Write the changelog section first, and run the slop pass on it. Both paths
refuse to release without a section, because a version with empty release notes
is what players actually see.

```bash
git tag -a v1.0.0 -m v1.0.0 && git push origin v1.0.0
```

Or, from the browser: **Actions → Release → Run workflow → `1.0.0`**. That path
validates the version string, the changelog section, and tag uniqueness *before*
writing the tag, then tags and pushes it for you.

**An agent has to use the second path.** Pushing a tag from a Claude Code web
session is refused, the same way deleting a remote branch is:

```
git push origin v1.9.0
  POST /warband-pro/addon/git-receive-pack   HTTP/1.1 403 Forbidden
  send-pack: unexpected disconnect while reading sideband packet
  fatal: the remote end hung up unexpectedly
```

Branch pushes go through; a tag ref does not, and `POST /repos/.../git/refs` is
refused through the same proxy — so there is nothing to retry and nothing to
wait out. Note the `hung up unexpectedly` line: git prints it after any 403 and
it is not evidence of a timeout.

The workflow dispatch has no such hole, because the tag is created by the runner
rather than pushed from here — `Actions → Release → Run workflow`, or the API
call behind that button. v1.9.0 went out that way, and so did v1.8.0.

### Writing the section is not cutting the release

**The tag is the version.** There is no version number anywhere in the addon —
`## Version: @project-version@` is a placeholder the packager fills in from the
tag it is building — so a release exists as two separate things: a `## [x.y.z]`
heading in `CHANGELOG.md`, which a person writes, and a `vx.y.z` tag on the
remote, which is what ships. Writing the heading is the part that feels like
cutting the release. It is not the part that publishes anything.

Three versions have been lost in that gap. **1.3.0 and 1.4.0** were written up,
dated and merged and never tagged, so CurseForge went 1.2.0 → 1.5.0 and two
versions of work sat in `main` where no player could reach it. **1.9.0** did the
same thing on 2026-09-02: the entire Roster grid, described in the changelog and
absent from every download page.

Nothing caught any of them, because every other check in CI reads the tree and
the tree is identical either way. The tag is on the remote — the one place none
of them look.

```bash
node tools/released.mjs            # report, locally, any time
node tools/released.mjs --shipped  # what main runs; fails on an untagged version
```

It fails a push to `main` when the newest section has no tag, so an unshipped
version turns the branch red and the failure prints the two commands that fix
it. On a pull request and on a release run it reports without failing — the
section is written before the tag by design on the first, and the release
workflow calls CI *before* it creates the tag on the second.

It also answers the question the nudge exists for: what is queued under
`## [Unreleased]`, and what number that would go out under.

```
NOTE ## [Unreleased] holds 1 note under fixed — a patch on top of 1.9.0, so v1.9.1.
```

Notes accumulating there is normal and never a failure. A version described in
the changelog and missing from CurseForge is neither.

## What to configure, once

### Repository secrets

Settings → Secrets and variables → Actions:

| Secret | Where it comes from |
| --- | --- |
| `CF_API_KEY` | CurseForge → account settings → API Tokens |
| `WAGO_API_TOKEN` | Wago → account → API keys |
| `WOWI_API_TOKEN` | WoWInterface → settings → API token |
| `DISCORD_WEBHOOK` | Discord → channel → Edit Channel → Integrations → Webhooks → Copy Webhook URL |

`GITHUB_TOKEN` is issued by Actions itself — nothing to add. No token belongs in
a file in this repo, ever; `tools/validate.mjs` and `.gitignore` assume that.

### Project ids in the `.toc`

The packager reads them from `WarbandPro.toc`, not from `.pkgmeta`. Placeholders
are commented out at the top of that file — uncomment and fill each one as the
project is created:

```
## X-Curse-Project-ID: 000000
## X-Wago-ID: RNLkzbGo  (warband-pro)
## X-WoWI-ID: 00000
```

`tools/validate.mjs` prints a `NOTE` for each id still missing, so the state is
visible in every CI run rather than discovered on release day.

## Versioning

Semver, anchored to **what the player has to do about it** — not to the shape of
the payload:

- **MAJOR** — they have to update or it stops working. `wb1!` → `wb2!`: old strings rejected with "update your addon".
- **MINOR** — something new. A new capture, a new field on the wire, or a new thing the in-game UI does.
- **PATCH** — a fix. No new capture, no new field, no new control.

**This section used to say the wire format was the thing being versioned**, and
that was already wrong when it was written: 1.5.0 added a minimap button, a
keybinding and an options tab and moved no wire field at all — a MINOR by every
instinct and not by a rule that only knew about payload shape. The wire is still
the hard edge of MAJOR, because it is the only change a player cannot absorb by
ignoring it. **A wire break is at least a MAJOR; not every MAJOR is a wire
break.** `CHANGELOG.md` carries the long version of this rule and
`docs/CONTRACT.md` is the law for the wire half.

The addon version and the wire version move independently: many addon minors can
ship against `wb1!`.

## Branching

`main` only, direct push, tag to release. No PR ceremony for a one-maintainer
repo — CI still runs on every push, so the safety net is the same.

## Running the checks locally — and the half you cannot

CI installs `lua5.1` and `luarocks` on an Ubuntu runner. **A Windows
workstation has neither, and deliberately does not** — see below. So the
offline checks split cleanly by runtime, and it is worth knowing which half you
are actually running before you push. The count is left out on purpose: this
line said "seven" while the table under it listed eight, because a number in
prose does not move when a row is added and the row is what CI reads.

| Check | Needs | On a Node-only machine |
|-------|-------|------------------------|
| `node tools/validate.mjs` | Node | ✅ runs |
| `node tools/vector.mjs` | Node | ✅ runs |
| `node tools/slop.mjs --unreleased` | Node | ✅ runs |
| `node tools/vector.mjs --write` + `git diff --exit-code -- docs/contract/vectors` | Node | ✅ runs |
| `luacheck .` | lua5.1 + luarocks | ❌ CI only |
| `lua5.1 tools/gear-test.lua` | lua5.1 | ❌ CI only |
| `lua5.1 tools/import-test.lua` | lua5.1 | ❌ CI only |
| `lua5.1 tools/junk-test.lua` | lua5.1 | ❌ CI only |
| `lua5.1 tools/gearset-test.lua` | lua5.1 | ❌ CI only |
| `lua5.1 tools/freshness-test.lua` | lua5.1 | ❌ CI only |
| `lua5.1 tools/roster-test.lua` | lua5.1 | ❌ CI only |

```bash
node tools/validate.mjs && node tools/vector.mjs && node tools/slop.mjs --unreleased
```

That is the whole local gate on a Node-only box, and it proves packaging, the
`.toc`, the wire format and the release notes. It proves **nothing about the
Lua** — not the lint, not the gear classifier, not the import decoder.

**This is a deliberate trade, not an oversight.** Installing lua5.1 + luarocks
to mirror a 17-second CI job means carrying a second language toolchain on a
machine whose whole operating principle is one good tool per job. The Lua half
runs on every push and on every PR, and `main` is push-only for one maintainer,
so the feedback gap is a single push rather than a review cycle. **Push and read
the CI result** — do not assume a green local run means a green build. A leaked
global or an off-by-one in the gear classifier will be caught by the runner and
nowhere else.

If that gap ever stops being acceptable — a Lua change big enough that a
push-and-wait loop is too slow — the fix is `lua5.1` plus
`luarocks install luacheck`, and the four `lua5.1` lines above become runnable
verbatim. Nothing in the repo needs to change for that.

## What CI cannot catch

Everything that needs a live client. These stay manual, in `docs/QA.md`:

- Game APIs returning nil out of party, or an instance lock reading empty.
- Taint from reading a secret value mid-session.
- `EditBox` copy limits on the real client.
- `C_Bank` returning nil when you are not at a banker, versus a genuine transient failure.
