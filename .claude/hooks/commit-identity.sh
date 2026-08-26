#!/usr/bin/env bash
# SessionStart hook — every commit in this repo is the maintainer's.
# Registered in .claude/settings.json.
#
# CLAUDE.md, "Commit authorship", has said this since 2026-08-23 and had nothing
# enforcing it: a web session arrives with user.name already set to
# `Claude <noreply@anthropic.com>` GLOBALLY and commit.gpgsign on, and a Stop
# hook then reports every commit here as "Unverified" and instructs the agent to
# amend the author. Repo-local config wins over global, which is why these are
# set with --local.
#
# gpgsign goes off for the same reason the app repo turns it off: the signing
# key is registered to noreply@anthropic.com, so signing a commit authored by
# the maintainer produces a signature that can never verify.
#
# Added 2026-08-26, alongside the removal of `start-on-main.sh` and
# `no-harness-branch-push.sh` — the branch policy went, the authorship rule
# stayed, and this is the app repo's `commit-identity.sh` mirrored here so both
# repos enforce the same one thing.
#
# KNOWN GAP: this only runs when the addon is the session's project directory. A
# session opened at the parent of the app and addon checkouts loads neither
# repo's settings.json and nothing here executes — which is exactly the session
# that wrote this file. That is why CLAUDE.md still carries the git config
# commands as prose.
#
# Always exits 0. A broken hook must never block a turn.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || exit 0
[ -e "$repo/.git" ] || exit 0

# `git -C`, never the ambient cwd. warband-pro/app is usually checked out at a
# sibling path and takes near identical commands; a hook that trusted the
# ambient directory would pin the wrong repo. Same reasoning as
# one-repo-per-commit.sh.
git -C "$repo" config --local user.name "Vocino" 2>/dev/null || true
git -C "$repo" config --local user.email "travis@vocino.com" 2>/dev/null || true
git -C "$repo" config --local commit.gpgsign false 2>/dev/null || true

echo "## Commits here are authored by Vocino <travis@vocino.com>, unsigned."
echo "   \"Unverified\" on GitHub is expected — do not amend the author."
exit 0
