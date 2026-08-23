#!/usr/bin/env bash
# PreToolUse hook — never push a `claude/*` branch to origin.
# Registered in .claude/settings.json.
#
# This exists because a pushed harness branch cannot be un-pushed from inside a
# Claude Code web session. Deleting a remote ref is refused twice over:
#
#   git push origin --delete <branch>
#     -> POST /warband-pro/<repo>/git-receive-pack  HTTP/1.1 403 Forbidden
#        then git prints "the remote end hung up unexpectedly", which is its
#        generic message for "the server closed the connection", not evidence
#        of a hang. Reading it as a proxy timeout is what sent a previous
#        session looking for a flake that was never there.
#
#   DELETE /repos/:owner/:repo/git/refs/heads/<branch>
#     -> 403 {"message":"Write access to this GitHub API path is not permitted
#        through this proxy."}
#
# and the GitHub MCP server exposes `create_branch` with no delete counterpart.
# Creating, updating and force-updating refs all succeed; only deletion is
# refused, on every branch, every time. It is a platform guardrail, not a bug,
# so there is nothing to retry and nothing to wait out.
#
# The consequence is asymmetric and easy to miss: pushing a harness branch is a
# one-way door. This repo is where that was learned. Until 2026-08-23 it had no
# CLAUDE.md, so a session took the harness branch assignment at face value,
# pushed `claude/lucid-curie-r4yp8g`, merged it, and then could not take it
# back — leaving a stale label pointing at main's own commit. The same agent,
# the same day, in `warband-pro/app`, read that repo's contract and pushed only
# `main`.
#
# So the only control that works is the one before the push. The Git section of
# CLAUDE.md now says to switch to `main`; this is the same instruction at the
# moment it is being violated, since the absence of that prose is what cost the
# branch in the first place.
#
# Blocks the push only. Local `claude/*` branches are fine — worktree branches
# are supposed to be created, merged and deleted locally, and never leave the
# machine.
#
# Never let a broken hook block a turn: any unexpected condition exits 0.
set -uo pipefail

event="$(cat 2>/dev/null || true)"
[ -n "$event" ] || exit 0

# Bash tool calls only. Anything else is not a shell command and cannot push.
case "$event" in
  *'"tool_name"'*'"Bash"'*) ;;
  *) exit 0 ;;
esac

# No jq. It is not installed on the maintainer's machine, and a hook that
# depends on a tool that is not there fails open every time — which is
# indistinguishable from a hook that passes. Scanning the raw event text is
# enough to answer "is this a push that names a claude/ ref", and erring
# toward a false positive is the safe direction: the fix is to push `main`,
# which is what the contract wanted anyway.
case "$event" in
  *'git push'*|*'git -C '*' push'*) ;;
  *) exit 0 ;;
esac

case "$event" in
  *'claude/'*) ;;
  *) exit 0 ;;
esac

# A delete is the one push of a claude/ ref that is not the mistake this hook
# is guarding — it is the attempted cleanup. Name why it cannot work, so the
# session reports the branch instead of retrying the 403 or calling it a flake.
case "$event" in
  *'--delete'*|*'push origin :'*|*' :refs/heads/'*)
    cat >&2 <<'MSG'
Remote branch deletion is blocked for this session and will always return 403 —
at the git layer (git-receive-pack) and at the GitHub API layer (the agent
proxy refuses the write). There is no MCP tool for it either. Do not retry it,
and do not report it as a proxy hang or a flake.

Leave the branch and say so plainly in your reply: the maintainer can delete it
from the GitHub UI in one click. Then make sure you are not adding another —
commit to `main`, per the Git section of CLAUDE.md.
MSG
    exit 2
    ;;
esac

cat >&2 <<'MSG'
Refusing to push a `claude/*` branch to origin.

This repo commits straight to `main` (CLAUDE.md, "Git"), and a harness branch
assignment is a default, not the maintainer's instruction. Pushing one is a
one-way door: remote ref deletion returns 403 from inside this session at both
the git and the GitHub API layers, so the branch becomes a permanent stale
label that only the maintainer can clear from the GitHub UI.

Do this instead:

    git checkout main
    git push -u origin main

and say in your reply that you switched off the harness branch.
MSG
exit 2
