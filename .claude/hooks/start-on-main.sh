#!/usr/bin/env bash
# SessionStart hook — begin the session on a current `main`, before anything
# reads a line of code. Registered in .claude/settings.json.
#
# This performs steps 1 and 2 of the path in CLAUDE.md ("The Path") rather than
# asking for them, because asking is what has been failing.
#
# TWO FAILURES, AND ONLY ONE OF THEM WAS EVER WRITTEN DOWN.
#
# The known one: a harness starts the session on a `claude/*` branch, work
# begins there, and the switch to `main` happens after the fact — so the work is
# redone. CLAUDE.md has said "switch to main anyway" since 2026-08-23, and it is
# reactive prose: it is read after the first edit, not before.
#
# The unknown one is worse, because following that instruction exactly still
# lands you in the past. This container clones the repo, creates local `main`
# from `origin/main` as it stood at clone time, and then creates the harness
# branch from a NEWER `origin/main`. Measured at the start of the session that
# wrote this file:
#
#   claude/code-sync-workflow-tfe42z  89ed6e9   <- the true tip
#   origin/main                       89ed6e9
#   main                              30a1597   <- 12 commits behind
#
# So `git checkout main` alone is a checkout of a 12-commit-old tree, and every
# symptom follows from it: the Lua you edit is not the Lua on `main`, a luacheck
# warning you chase was fixed a week ago, and `tools/vector.mjs` compares your
# fixtures against an older contract. Nothing in this repo's contract has ever
# said to fetch. That is the actual bug.
#
# WHAT IT WILL NOT DO. It never discards the maintainer's work, so it refuses to
# act rather than reaching for `reset`, `stash` or `checkout -f`, and it merges
# only `--ff-only`. A dirty tree, a diverged `main` or a branch the maintainer
# made on purpose all end in a report, not a repair.
#
# It finds the repo from its own path, not from the session's cwd or project
# dir. This is the same reasoning one-repo-per-commit.sh states at length: a
# session with `warband-pro/app` open beside this one has two roots at sibling
# paths, and a check that trusted the ambient one would be pointed at the wrong
# repo exactly when it matters. A sync is worse than a check in that position —
# it would `checkout` and `merge` over there. Every command below names the repo
# with `git -C`, which is what CLAUDE.md asks of a human for the same reason.
#
# Always exits 0. A broken hook must never block a turn, and a *silent* broken
# hook is worse than none — so anything it cannot do, it says.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || exit 0
[ -e "$repo/.git" ] || exit 0

g() { git -C "$repo" "$@"; }

# `timeout` keeps an unreachable origin from spending the hook's whole budget;
# if coreutils is not there, run the fetch bare rather than skipping it.
fetch() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 20 git -C "$repo" fetch --quiet origin main 2>/dev/null
  else
    g fetch --quiet origin main 2>/dev/null
  fi
}

# "1 commit", not "1 commits". A hook nobody proof-reads is a hook whose
# output stops being read.
commits() { if [ "$1" = 1 ]; then echo "1 commit"; else echo "$1 commits"; fi; }

path_reminder() {
  echo
  echo "The path, every session — CLAUDE.md, \"The Path\":"
  echo "  1. be on main   2. pull before working   3. commit to main   4. push only when asked"
}

branch="$(g symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
dirty="$(g status --porcelain 2>/dev/null || true)"

echo "## Session start — putting you on a current \`main\`."
echo

# --- Step 1: be on main --------------------------------------------------

if [ -z "$branch" ]; then
  echo "   HEAD is DETACHED. Nothing was changed. Get onto main first:"
  echo "       git -C $repo checkout main && git -C $repo pull origin main"
  path_reminder
  exit 0
fi

case "$branch" in
  main) ;;
  claude/*)
    # A plain `checkout` is offered rather than tested for safety first, because
    # git is the better authority on whether it is safe: it refuses outright if
    # the move would clobber an edit, and otherwise carries the edit across
    # intact. Nothing is discarded either way. An earlier draft refused up front
    # on any dirty tree and a single untracked scratch file was enough to block
    # the sync — a check that cries wolf gets deleted, and then the real failure
    # is unguarded again.
    if g checkout --quiet main 2>/dev/null; then
      echo "   Was on \`$branch\` (harness default) -> switched to \`main\`."
      echo "   Say so in your reply. Never push \`$branch\`: a pushed harness branch"
      echo "   cannot be deleted from a web session, and a hook refuses it."
      branch=main
    else
      echo "   On \`$branch\` and git REFUSED to switch — it will not move these without"
      echo "   losing them, and they are not mine to move:"
      echo "$dirty" | sed 's/^/       /'
      echo "   Decide what they are, then get onto main. Do not start work here:"
      echo "       git -C $repo status && git -C $repo checkout main"
      path_reminder
      exit 0
    fi
    ;;
  *)
    echo "   On \`$branch\`, which is neither \`main\` nor a harness branch — left alone,"
    echo "   because the maintainer may have made it on purpose. This repo commits to"
    echo "   \`main\` (CLAUDE.md, \"Git\"); confirm before working here."
    path_reminder
    exit 0
    ;;
esac

# --- Step 2: pull before working -----------------------------------------

if ! fetch; then
  echo "   COULD NOT REACH origin. \`main\` may be well behind — this checkout starts"
  echo "   stale by design. Re-run before trusting anything you read:"
  echo "       git -C $repo pull origin main"
  path_reminder
  exit 0
fi

behind="$(g rev-list --count main..origin/main 2>/dev/null || echo 0)"
ahead="$(g rev-list --count origin/main..main 2>/dev/null || echo 0)"

if [ "$behind" != 0 ] && [ "$ahead" != 0 ]; then
  echo "   \`main\` has DIVERGED from origin: $ahead local, $behind remote. Not merging that"
  echo "   for you — resolve it before working, and say what you found."
elif [ "$behind" != 0 ]; then
  if g merge --ff-only --quiet origin/main 2>/dev/null; then
    echo "   Pulled: \`main\` fast-forwarded $(commits "$behind") to $(g rev-parse --short HEAD)."
  else
    echo "   \`main\` is $(commits "$behind") behind and the fast-forward was refused"
    echo "   (usually uncommitted changes in the way). Do not work from this tree:"
    echo "       git -C $repo status && git -C $repo pull origin main"
  fi
elif [ "$ahead" != 0 ]; then
  echo "   \`main\` is $(commits "$ahead") AHEAD of origin — committed but never pushed."
  echo "   This container is ephemeral; unpushed work dies with it. Step 4 says push"
  echo "   when asked, so ask: name the commits and offer to push them."
  g log --oneline "origin/main..main" 2>/dev/null | sed 's/^/       /'
else
  echo "   Pulled: \`main\` already current with origin at $(g rev-parse --short HEAD)."
fi

[ -n "$dirty" ] && {
  echo "   Working tree is NOT clean — these were here before you started:"
  echo "$dirty" | sed 's/^/       /'
  echo "   They are the maintainer's. Never reset, stash or discard them; commit by"
  echo "   explicit path rather than \`git add -A\`."
}

path_reminder
exit 0
