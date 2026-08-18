# docs index

These docs are meant to be coding reference until we ship light — then trim to just README.

- [CONTRACT.md](CONTRACT.md) — wb1! wire format law, bundle shape, versioning, security caps. Contract + vectors must pass CI.
- [TESTING.md](TESTING.md) — layered testing strategy: offline luacheck + busted pure + contract vector round-trip, then 5-min manual pass scripted to be screenshot-parseable for AI.
- [CI.md](CI.md) — packager, .pkgmeta minimal, GitHub Actions on tag v* for CurseForge/Wago, changelog from conventional commits.
- [QA.md](QA.md) — copy-paste manual checklist for release, 5-min per char, BugSack + taint + warbank shared test + memory.
- [RESEARCH-REFERENCE.md](RESEARCH-REFERENCE.md) — Midnight 12.0+ modern best practices checklist from Midnight template repos (Interface 120001, no Ace3, Compartment, Secret Values/CLEU, C_Container/C_Bank, LibDeflate export pattern).
- [.luacheckrc.example](.luacheckrc.example) — whitelisting WoW API globals we touch, copy to root when we make .luacheckrc.
- contract/vectors/v1-min.json — minimal golden vector for CI round-trip.

How to use as AI coder:

1. Read RESEARCH-REFERENCE.md then CONTRACT.md then TESTING.md.
2. Pure functions first (Bundle, Export, consumables math, freshness dots) → they have offline tests.
3. Impure (Scan, Instances, Store) → leave stub returns, document expected WoW API nil edge cases from TESTING.md edge list.
4. UI last, using native widgets only.
5. Run luacheck, contract vector check before push.
6. Human runs QA.md checklist, pastes result format back to you (PASS/FAIL lines) so you can iterate without seeing game.

When shipping light: keep README + CONTRACT.md reference link, delete docs/ minus CONTRACT excerpt, remove Luacheck example and dot files not needed.
