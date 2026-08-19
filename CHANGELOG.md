# Changelog

Release notes for Warband.pro Companion. The packager sends the section matching the tag to CurseForge, Wago, and WoWInterface verbatim, so this is what players read — not the commit log.

**The release workflow greps for `## [1.0.1]` exactly.** A tag without a matching heading here fails the release before anything is published. Write the section first, then tag.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [semver](https://semver.org/), with the wire format as the thing being versioned:

- **MAJOR** — `wb1!` → `wb2!`. The website rejects old strings with "update your addon".
- **MINOR** — a new optional field or capture. The website still reads older bundles.
- **PATCH** — a fix. Payload shape unchanged.

The wire contract itself is specified in [docs/CONTRACT.md](docs/CONTRACT.md).

## [Unreleased]

## [1.0.1] — 2026-08-19 — wire CurseForge auto packaging

- Set `## X-Curse-Project-ID: 1660174` so BigWigs packager targets the real CurseForge project instead of placeholder 000000. Enables CurseForge automatic packaging via org secret `CF_API_KEY`.
- No code changes, no wire format change, still `wb1!`.

## [1.0.0] — 2026-08-19 — Warband.pro Companion launch

First CurseForge release.

**Warband.pro Companion** — companion addon for warband.pro (https://warband.pro). You play normally, log alts 2..6 through the week with zero extra steps — account-wide `WarbandProDB` GUID-keyed updates silently on login, bag move (.5s throttle), bank open, vault open, mail.

Any char: `/warband` → auto-highlighted box → Ctrl+C copies `wb1!aH...` (multi-char bundle default, 4-7KB for 6 chars, ~26KB with full bag contents). Paste on warband.pro Import (hotkey `i`) → preview 🟢🟡🔴 → Confirm. Missing chars stay ⚪ never, stale just lowers confidence.

What it captures — Altoholic + SavedInstances superset, pruned Midnight 12.1:
- Bags, bank+bags, reagentBank, warbandBank with seenByGuid/tabs
- Gold, currencies with weeklyMax/isAccountWide — Crests, Flightstones, Tender
- Professions skill/max, mail count+goldPending, auctions count+goldHeld
- Lockouts LFR/N/H/M with bosses killed + resetTime, worldBosses
- Keystone level/dungeonID, M+ runs timed/chest, score, weeklyVault raid/mplus/world thresholds
- Consumables rollup for Tonight Plan, per-section seenAt for staleness dots

Trust: no network ever, <200KB for 6 chars, no OnUpdate scanner, copy-only, vanilla Lua no Ace3/LibStub, zero deps except vendored LibDeflate MIT zlib (license in Vendor/LibDeflate.lua header).

Retail Midnight 12.1 only. Works with whatever UI you run.

Then future tags auto-upload via BigWigs packager once Project IDs are set.

[Unreleased]: https://github.com/warband-pro/addon/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/warband-pro/addon/releases/tag/v1.0.1
[1.0.0]: https://github.com/warband-pro/addon/releases/tag/v1.0.0
