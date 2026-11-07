# thelankankid/ci

The CI every thelankankid repo shares. Each repo keeps a short `ci.yml` that calls these reusable workflows,
pinned to a commit of this repo, so a fix here reaches every repo through one Dependabot bump instead of a dozen
hand edits. The same idea as [Casso](https://github.com/thelankankid/casso) for the UI.

Public on purpose: workflows hold no secrets (each repo passes its own), and public repos such as Casso can only
call workflows from a public repo.

## The workflows

| Workflow | What it runs | Check name in a calling repo |
| --- | --- | --- |
| [`node-ci.yml`](.github/workflows/node-ci.yml) | `npm ci`, `npm run check`, `npm audit --omit=dev` (high and up) | `node / check` |
| [`hygiene.yml`](.github/workflows/hygiene.yml) | actionlint, every action pinned to a full SHA, gitleaks on the tree | `hygiene / hygiene` |
| [`claude.yml`](.github/workflows/claude.yml) | `@claude` on PRs and issues, owner only | (not a check) |

`node-ci.yml` takes `working-directory` (default `.`), `node-version` (default `22`), `script` (default `check`)
and `audit-level` (default `high`; `none` skips the audit).

## Using it in a repo

1. Give the repo an `npm run check` that runs whatever applies there: lint, typecheck, tests, build.
2. Copy [`templates/ci.yml`](templates/ci.yml), [`templates/claude.yml`](templates/claude.yml) and
   [`templates/dependabot.yml`](templates/dependabot.yml) into `.github/`, replacing `SHA` with this repo's current
   commit on `main`.
3. Keep repo-specific jobs (Terraform plans, rule tests, version checks) as extra jobs in the same `ci.yml`.
4. Once the repo is green, require the checks on `main`: `bash scripts/require-checks.sh <repo>`. It reads the
   repo's `ci.yml` and requires what it runs (`<job> / check` per Node job, `hygiene / hygiene`) (needs your `gh`
   login; rulesets on private repos need GitHub Pro).

## Changing a workflow

Change it here in a PR (this repo runs its own hygiene check), merge, then let Dependabot open the bump in each
repo, or bump the SHA by hand. A change that would break callers (a renamed input, a new required script) gets a
note in the PR and lands in every repo before the old behaviour is removed. Tool images (actionlint, gitleaks) are
pinned by digest; bump them deliberately.
