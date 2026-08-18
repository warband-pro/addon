# CI / packaging / release — WarbandPro

Goal: nightly nothing you do, tagged release ships to CF/Wago/WI.

## CI layers (GitHub Actions)

### ci.yml — on push

- luacheck . — fail if >0 warnings
- checks: validate .toc syntax Interface required, all files listed exist, folder base matches toc base
- contract vectors round-trip test (node + pako decode vs LibDeflate encode) — we test 1-min, 1-full, 1-bundle6. Must identity decode identical.
- optional busted pure tests `tests/spec_*.lua` if we add them (lua 5.1)

### packager.yml — on tag v*

Uses BigWigsMods/packager per modern Midnight template: CI/CD via that tool for CF/Wago/WI.

`.pkgmeta` at root:
```
package-as: WarbandPro
externals:
  Libs/LibDeflate: url=https://github.com/SafeteeWoW/LibDeflate, latest
```

But we prefer manual vendoring one-file LibDeflate to avoid external fetching flake. So .pkgmeta minimal.

On tag v* push, action builds zip with `@project-version@` replaced from tag, strips .git, docs/*.md except README trimmed, compress.

Artifacts: WarbandPro-v1.0.0.zip visible in Releases.

### Release flow

- `v1.0.0` style tags, semver.org: MAJOR break (wb1! → wb2!), MINOR additive field (web still reads old), PATCH fix.
- Changelog generated from conventional commits `fix:` `feat:` `docs:` — we follow same flat lowercased style you use outside (hooks/cm-msg no em dash → reject).
- CI copies README trimmed for CurseForge Description (first 3000 chars).

## Versioning of wire

- Patch: addon Version 1.0.1 shape same, web not change.
- Minor: new optional field added addon, web must still accept old (backcompat). Bump addon patch too.
- Major: break — rename prefix wb2!, old string rejected with "update your addon - get v2" in web import UI.

## Secrets

- CF_API_TOKEN, WAGO_API_TOKEN, WOWI_API_TOKEN stored in GitHub secrets.
- Token never in repo .env.

## Branching

Main only, direct push as you do for warband.pro polish lane. No PRs needed for fast iterate. Tag for release only.

## What CI cannot catch (hence manual QA)

- Real game API nil returning when out of party, instance lock nil.
- TaintLog secret value reading causing taint in session.
- EditBox copy limit on real client vs Classic difference.
- Warband Bank C_Bank returning nil when not at banker vs sometimes temporary failure.

Cover those in docs/QA.md checklist.
