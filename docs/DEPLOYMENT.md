# Deploying Warband.pro Companion — all sites

This addon ships as **Warband.pro Companion** everywhere, pointing back to https://warband.pro.

## Name law

- **Official name:** Warband.pro Companion
- **Toc Title:** `Warband.pro Companion` (folder stays `WarbandPro` — WoW folder name rule)
- **Package-as:** `WarbandPro` — zip name `WarbandPro-v1.0.0.zip` — WoW will still show "Warband.pro Companion" in addon list because Title in .toc wins.
- **Short slug for managers:** WarbandPro or warband-pro-companion depending on site. CurseForge lets you pick display name independently — set display name to Warband.pro Companion.

Why not rename folder to Companion? Existing installs would duplicate, SavedVariables would orphan, and managers key on folder name. Keeping WarbandPro folder with Companion title is how Altoholic, Rarity Companion etc do it.

## One source, three sites

CI builds one zip, packager uploads to all configured sites on tag `v*`:

- CurseForge (CF) — biggest, needs `X-Curse-Project-ID: 123456` in toc once project exists. Token secret `CF_API_KEY`.
- Wago — needs `X-Wago-ID: abc123`. Token `WAGO_API_TOKEN`.
- WoWInterface (WoWI) — needs `X-WoWI-ID: 12345`. Token `WOWI_API_TOKEN`.

Toc now has placeholders `000000` — replace once you create projects. Release workflow skips a site whose token isn't set, warning not failing — so you can cut v0.1.0 to GitHub Releases before CF exists.

## Create projects (do once)

1. **CurseForge:** New addon → name Warband.pro Companion, category Companion, game WoW Retail. Upload any zip manually first (validates). Copy Project ID from URL or About box → paste into toc `## X-Curse-Project-ID:`. Add `CF_API_KEY` secret in GitHub repo settings Secrets → Actions.

2. **Wago:** New → Addon → name Warband.pro Companion, link GitHub warband-pro/addon, category Utility. Copy slug ID from URL → `X-Wago-ID`. Add `WAGO_API_TOKEN`.

3. **WoWI:** New addon → same name, category warband.pro. Copy ID → `X-WoWI-ID`. Token `WOWI_API_TOKEN`.

Add all as same text `Warband.pro Companion` so managers dedupe.

## What players see

CurseForge / Wago / WoWI pull release notes from `CHANGELOG.md` section `## [1.0.0]` — not commit log. That's what we ship first minute.

README.md first paragraph is what CF shows as short description if no custom page. Ours now opens with:

> Companion addon for warband.pro — the site that answers "who should I play tonight."

And explicit callout block:

> Companion for warband.pro (https://warband.pro) — collects...

So both addon list tooltip (Notes field) and site pages reinforce companion nature.

## Brand assets

- Icon: `Interface\Icons\inv_enchant_voidcrystal` — one face for the addon compartment, the window portrait and the minimap button. A texture already in the client, so no artwork ships. It was a generic bag until 1.5.0; the crystal is distinguishable at 20px on a crowded minimap ring, which a brown bag among brown bags is not.
- Toc Notes shortened to fit 70-char client tooltip: "Companion for warband.pro — gathers bags, bank, warband bank, currencies, lockouts from every alt | warband.pro" — long Notes-enUS has full sentence.
- Minimap button on by default since 1.5.0, alongside AddonCompartment. Hand-built, no LibDBIcon, so "lightweight" still holds — it references `Interface\Icons\inv_enchant_voidcrystal` and `Interface\Minimap\MiniMap-TrackingBorder`, both already in the client. Off with `/warband minimap off`.
- License MIT, vendor LibDeflate zlib notice in Vendor/LibDeflate.lua.

## Release checklist for v1.0.0

- [ ] All CI green (`luacheck .`, `node tools/validate.mjs`, `node tools/vector.mjs` fixtures match)
- [ ] `CHANGELOG.md` has `## [1.0.0]` section written in player-facing language ("gold now updates when you sell", not "fix(scan):...")
- [ ] TOC version still `@project-version@`, Interface bumped if needed (120100 for Midnight 12.1)
- [ ] Project IDs filled in toc once created (000000 → real)
- [ ] Secrets added: CF_API_KEY, WAGO_API_TOKEN, WOWI_API_TOKEN (any missing = site skipped, not failed)
- [ ] Tag: `git tag -a v1.0.0 -m v1.0.0 && git push origin v1.0.0` OR Actions → Release → Run workflow → 1.0.0
- [ ] Verify GitHub Release has zip `WarbandPro-v1.0.0.zip` + notes from changelog
- [ ] Verify CF / Wago / WoWI listings show "Warband.pro Companion" not just WarbandPro, description points to https://warband.pro, external link present
- [ ] After publish, install via CurseForge app / WowUp from each site once to confirm zip loads and `/warband` opens without needing /reload second time.

## Post-launch trim (shipping light)

Packager ignores `docs/`, `tools/`, `.github/`, `.gitignore`, `.luacheckrc`, `.pkgmeta` via `.pkgmeta` ignore — zip contains only: WarbandPro.toc, Lua files, Vendor/LibDeflate.lua, README.md, CHANGELOG.md, LICENSE. Keeps zip <200KB.

Flat root rule per your minimalism: Problem → Install (one paste) → Use (2-3 copy-pastes) → What it catches → Inside 4-6 files — README already shaped that way.

## Framing law

Every public place must say companion, not standalone tracker:

- CF short description: "Companion addon for warband.pro — brings Altoholic + SavedInstances web-readable"
- CF full description: start with "This is the companion addon for warband.pro"
- Wago summary same.
- WoWI description same.
- In-game Notes field: "Companion for warband.pro —"
- On warband.pro site: /addon or /settings/import mentions "install the Warband.pro Companion addon"

No place says "Warband.pro is an addon" — it's the site. Addon is companion.

Source: README.md line 1 says # Warband.pro Companion, toc Title same. Keep them in sync.
