#!/usr/bin/env bash
# PreToolUse hook — nothing from `warband-pro/app` is ever committed here.
# Registered in .claude/settings.json.
#
# This repo is public. It is MIT licensed, its source is on GitHub, and the
# packager ships it to CurseForge and Wago on every tag. `warband-pro/app` is
# not: it holds Battle.net and Discord client secrets, a session signing key,
# Cloudflare account and D1 database ids, and a wiki whose own contract says
# credentials and unpublished ids never enter it. A file that crosses from
# there to here is published, and publishing is not something a later commit
# undoes — the tag is already out, and CurseForge has already mirrored it.
#
# The vector is not carelessness with secrets. It is that both repos are
# checked out side by side in one session, at sibling paths, with near
# identical git commands run against each. On 2026-08-24 a session doing exactly
# that ran two commands intended for this repo while the shell was still in the
# app's directory — a `git pull` and a `git branch -d`. Neither did harm: one
# was redundant, the other errored. The same slip one line later, between a
# `git add -A` and a `git commit`, commits the app's working tree here.
#
# So the check is not "did someone paste a secret", it is "does this repo's
# index contain a file that does not belong to this repo". That question has a
# bounded answer, because this addon has a flat root and a short list of
# directories — see CLAUDE.md, "Flat root, fewest moving parts".
#
# ALLOWLIST, NOT DENYLIST. A denylist has to predict what the app might send;
# this one only has to describe what this repo is. `src/`, `.wiki/`,
# `migrations/`, `package.json`, `wrangler.jsonc`, `.dev.vars` and everything
# else over there fails it without being named.
#
# It reads THIS repo's index regardless of which directory the command ran in,
# which is the whole point: the failure being guarded is a command executing
# against the wrong repo, so a check that trusts the command's own cwd would
# be blind exactly when it matters.
#
# Never let a broken hook block a turn: any unexpected condition exits 0.
set -uo pipefail

event="$(cat 2>/dev/null || true)"
[ -n "$event" ] || exit 0

# Bash tool calls only. Nothing else runs a commit.
case "$event" in
  *'"tool_name"'*'"Bash"'*) ;;
  *) exit 0 ;;
esac

case "$event" in
  *'git commit'*) ;;
  *) exit 0 ;;
esac

# This repo, found from the hook's own location rather than from the session's
# project dir: a session with both repos open has two project roots, and this
# hook is only ever about one of them.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || exit 0
[ -d "$here/.git" ] || exit 0

staged="$(git -C "$here" diff --cached --name-only 2>/dev/null)" || exit 0
[ -n "$staged" ] || exit 0

# What belongs in this repo. Everything the addon actually is: Lua at the flat
# root, the .toc and the bindings that load it, packaging and lint config, the
# four docs directories, and the licence and readmes.
alien=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    # Directories this repo owns.
    docs/*|tools/*|Vendor/*|.github/*|.claude/*) continue ;;
    # The addon itself, flat at the root — and flat means flat. A `.lua` under
    # some directory this repo does not own is not "a Lua file", it is a
    # directory this repo does not own; `tools/` and `Vendor/` are already
    # allowed above, so nothing legitimate reaches here with a slash in it.
    *.lua|*.toc|*.xml) case "$path" in */*) ;; *) continue ;; esac ;;
  esac
  case "$path" in
    .luacheckrc|.pkgmeta|.editorconfig|.gitignore|.gitattributes) continue ;;
    LICENSE|LICENSE.txt|README.md|CHANGELOG.md|CLAUDE.md|AGENTS.md) continue ;;
  esac
  alien="$alien  $path
"
done <<EOF
$staged
EOF

if [ -n "$alien" ]; then
  cat >&2 <<MSG
Refusing to commit: files staged here do not belong to this repository.

$alien
This is \`warband-pro/addon\`, and it is public — MIT on GitHub, shipped to
CurseForge and Wago on every tag. \`warband-pro/app\` is not, and it holds
Battle.net and Discord secrets, a session signing key, Cloudflare account and
D1 ids, and a wiki that is private by contract. Publishing is a one-way door:
a later commit does not un-ship a release.

The usual cause is a command running against the wrong checkout — both repos
sit at sibling paths and take near identical git commands. Check where you are:

    pwd
    git -C "$here" diff --cached --name-only

Then unstage what is not this addon's, and commit it in the repo it came from:

    git -C "$here" restore --staged <path>

One change, one repo. See CLAUDE.md, "Never mix the two repositories".
MSG
  exit 2
fi

# The other direction of the same risk: a file that legitimately lives here,
# carrying a value that does not.
#
# Names alone are not the check — docs/APP-IMPORT.md is allowed to say
# BNET_CLIENT_ID exists, and a hook that blocked on the word would be turned
# off within a day. This matches an *assignment of something value-shaped*, and
# skips the placeholder forms, which is the same test scripts/lint-wiki.js in
# the app repo already makes against its own wiki.
secrets="$(git -C "$here" diff --cached -U0 2>/dev/null |
  grep -nE '^\+' |
  grep -nEi '(BNET|DISCORD)_(CLIENT_SECRET|BOT_TOKEN)|AUTH_SECRET|SESSION_SECRET|CLOUDFLARE_API_TOKEN' |
  grep -vE '(your-|<|\$\{|\$[A-Z]|example|placeholder|xxx|\.\.\.)' |
  grep -E '[:=][[:space:]]*.?[A-Za-z0-9_-]{16,}' || true)"

if [ -n "$secrets" ]; then
  cat >&2 <<MSG
Refusing to commit: a staged line looks like a real credential.

$secrets

This repo is public and this addon has no credentials of its own — it makes no
network calls at all (CLAUDE.md, "No network calls. Ever."), so there is
nothing here that legitimately needs one. If this is a placeholder, write it in
a form that reads as one; if it is real, it belongs in the app's .dev.vars,
which is gitignored there and must never be copied here.
MSG
  exit 2
fi

exit 0
