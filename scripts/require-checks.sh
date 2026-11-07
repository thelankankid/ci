#!/usr/bin/env bash
# Require the shared checks on each repo's default branch, with a repository ruleset.
# Run it yourself (it needs your gh login with admin rights): bash scripts/require-checks.sh repo1 repo2 …
#
# The required checks come from each repo's own .github/workflows/ci.yml on its default branch:
# `hygiene / hygiene` when it calls hygiene.yml, and `<job> / check` for every job that calls node-ci.yml
# (a repo can have several, e.g. `node` and `frontend`). A repo with no Node job only requires hygiene.
# Re-running updates the ruleset in place. Rulesets on private repos need GitHub Pro; the script says so if refused.
set -euo pipefail
owner=thelankankid
name="Shared checks"
[ $# -gt 0 ] || { echo "usage: $0 <repo> [repo…]"; exit 2; }
for repo in "$@"; do
  ci=$(gh api "repos/$owner/$repo/contents/.github/workflows/ci.yml" -H "Accept: application/vnd.github.raw" 2>/dev/null || true)
  if [ -z "$ci" ]; then echo "$repo: no .github/workflows/ci.yml, skipped"; continue; fi
  # Job ids are the 2-space-indented keys under `jobs:`; keep those whose `uses:` is a shared workflow.
  contexts=$(awk '
    /^jobs:/ { injobs = 1; next }
    injobs && /^[^ #]/ { injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:/ { job = $1; sub(/:$/, "", job) }
    injobs && /uses: *thelankankid\/ci\/\.github\/workflows\/node-ci\.yml/ { print job " / check" }
    injobs && /uses: *thelankankid\/ci\/\.github\/workflows\/hygiene\.yml/ { print job " / hygiene" }
  ' <<<"$ci")
  if [ -z "$contexts" ]; then echo "$repo: ci.yml calls no shared check, skipped"; continue; fi
  checks=$(printf '%s\n' "$contexts" | sed 's/.*/{ "context": "&" }/' | paste -sd, -)
  body=$(cat <<JSON
{
  "name": "$name",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "required_status_checks",
      "parameters": { "strict_required_status_checks_policy": false, "required_status_checks": [ $checks ] } }
  ]
}
JSON
)
  list=$(printf '%s' "$contexts" | paste -sd, -)
  id=$(gh api "repos/$owner/$repo/rulesets" --jq ".[] | select(.name==\"$name\") | .id" 2>/dev/null || true)
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$owner/$repo/rulesets/$id" --input - <<<"$body" >/dev/null && echo "$repo: updated ($list)"
  else
    gh api -X POST "repos/$owner/$repo/rulesets" --input - <<<"$body" >/dev/null && echo "$repo: created ($list)" \
      || echo "$repo: refused (private repo on a free plan? rulesets there need GitHub Pro)"
  fi
done
