# CI, packaging, and releases

Two workflows, one packager, no manual zip. Cutting a release is one command or
one button, and everything between that and the download page is automatic.

## What runs, and when

### `.github/workflows/ci.yml` — every push to `main`, every PR

| Job | What it proves |
| --- | --- |
| `luacheck` | Zero warnings under `.luacheckrc`. That file lists every global the addon may touch, so a new warning is usually a leaked global rather than a style nit. |
| `packaging + contract` | `tools/validate.mjs` — the `.toc` and `.pkgmeta` are internally consistent. `tools/vector.mjs` — a `wb1!` payload survives encode → decode unchanged, and the committed `.wb1` fixtures still match. |
| `package (dry run)` | The real packager builds the real zip with uploads switched off, and attaches it as a workflow artifact. |

That artifact matters: **every push to `main` produces a downloadable, correctly
structured zip** under the run's Artifacts. Testers install builds without anyone
cutting a version.

### `.github/workflows/release.yml` — on a `v*` tag, or on demand

Runs `ci.yml` in full first, then hands the repo to
[BigWigsMods/packager](https://github.com/BigWigsMods/packager), which:

1. substitutes `@project-version@` in the `.toc` and `LibDeflate.lua` from the tag,
2. builds `WarbandPro-v1.0.0.zip` with `docs/`, `tools/`, and the dotfiles stripped per `.pkgmeta`,
3. copies `LICENSE` into the zip as `LICENSE.txt`,
4. creates a GitHub Release with the zip attached,
5. uploads to CurseForge, Wago, and WoWInterface, using the matching `## [x.y.z]` section of `CHANGELOG.md` as the release notes.

A site is uploaded to only when **both** its token secret and its `.toc` id are
present. Missing either one logs a warning and skips that site — which is how
this pipeline is useful before the CurseForge project exists.

## Cutting a release

Write the changelog section first. Both paths refuse to release without one,
because a version with empty release notes is what players actually see.

```bash
git tag -a v1.0.0 -m v1.0.0 && git push origin v1.0.0
```

Or, from the browser: **Actions → Release → Run workflow → `1.0.0`**. That path
validates the version string, the changelog section, and tag uniqueness *before*
writing the tag, then tags and pushes it for you.

## What to configure, once

### Repository secrets

Settings → Secrets and variables → Actions:

| Secret | Where it comes from |
| --- | --- |
| `CF_API_KEY` | CurseForge → account settings → API Tokens |
| `WAGO_API_TOKEN` | Wago → account → API keys |
| `WOWI_API_TOKEN` | WoWInterface → settings → API token |

`GITHUB_TOKEN` is issued by Actions itself — nothing to add. No token belongs in
a file in this repo, ever; `tools/validate.mjs` and `.gitignore` assume that.

### Project ids in the `.toc`

The packager reads them from `WarbandPro.toc`, not from `.pkgmeta`. Placeholders
are commented out at the top of that file — uncomment and fill each one as the
project is created:

```
## X-Curse-Project-ID: 000000
## X-Wago-ID: 0000000
## X-WoWI-ID: 00000
```

`tools/validate.mjs` prints a `NOTE` for each id still missing, so the state is
visible in every CI run rather than discovered on release day.

## Versioning

Semver, with the wire format as the thing being versioned:

- **MAJOR** — `wb1!` → `wb2!`. Old strings rejected with "update your addon".
- **MINOR** — a new optional field or capture. The website still reads older bundles.
- **PATCH** — a fix. Payload shape unchanged.

The addon version and the wire version move independently: many addon minors can
ship against `wb1!`. `docs/CONTRACT.md` is the law for the wire half.

## Branching

`main` only, direct push, tag to release. No PR ceremony for a one-maintainer
repo — CI still runs on every push, so the safety net is the same.

## What CI cannot catch

Everything that needs a live client. These stay manual, in `docs/QA.md`:

- Game APIs returning nil out of party, or an instance lock reading empty.
- Taint from reading a secret value mid-session.
- `EditBox` copy limits on the real client.
- `C_Bank` returning nil when you are not at a banker, versus a genuine transient failure.
