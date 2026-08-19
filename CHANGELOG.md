# Changelog

Release notes for Warband.pro Companion. The packager sends the section matching the tag to CurseForge, Wago, and WoWInterface verbatim, so this is what players read — not the commit log.

**The release workflow greps for `## [1.0.0]` exactly.** A tag without a matching heading here fails the release before anything is published. Write the section first, then tag.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [semver](https://semver.org/), with the wire format as the thing being versioned:

- **MAJOR** — `wb1!` → `wb2!`. The website rejects old strings with "update your addon".
- **MINOR** — a new optional field or capture. The website still reads older bundles.
- **PATCH** — a fix. Payload shape unchanged.

The wire contract itself is specified in [docs/CONTRACT.md](docs/CONTRACT.md).

## [Unreleased]

### Added

- **Warband.pro Companion** — Companion addon for warband.pro (https://warband.pro). Collects bags, bank, warband bank, gold, currencies, professions, mail, auctions, instance lockouts, keystone, and weekly vault from every alt you log.
- Account-wide snapshot store, keyed by character GUID, updated silently on login and on bag / bank / vault activity.
- `wb1!` bundle export — canonical JSON, raw deflate, base64url — and the `/warband` panel that hands it to your clipboard for warband.pro Import.
- MIT license, and an automated release pipeline: GitHub Actions → GitHub Release → CurseForge / Wago / WoWInterface as "Warband.pro Companion".

[Unreleased]: https://github.com/warband-pro/addon/commits/main
