# warband.pro — Companion Addon (Claude Code)

`AGENTS.md` is the contract. Read it and `docs/README.md` before changing
anything. This file exists so Claude Code resolves the same contract, plus the
Claude-specific tooling below.

## Claude-specific tooling

- Permissions: `.claude/settings.json` — allow covers the Verify commands
  (`luacheck`, `lua5.1`, `tools/validate.mjs`, `tools/vector.mjs`,
  `tools/slop.mjs`, `tools/released.mjs`), the `lua5.1`/`luacheck` toolchain
  install, read-only git commands plus `add`/`commit`/`push`, and read-only
  GitHub MCP servers. `ask` covers `git tag`, tag pushes and workflow
  dispatch. `deny` covers force-push, ref delete, `reset --hard`, `clean` and
  `stash`.
- Hooks: `PreToolUse` runs
  [`.claude/hooks/one-repo-per-commit.sh`](.claude/hooks/one-repo-per-commit.sh),
  which refuses a commit whose staged files are not this addon's and refuses
  lines that look like real credentials.
- Release dispatch is the workflow (`Actions → Release`), not a tag push from
  a session — tag pushes are refused (403) the same way ref deletes are.
