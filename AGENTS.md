# AGENTS.md

How to work in thelankankid/ci: the reusable GitHub Actions workflows every thelankankid repo calls. Read
[README.md](README.md) first.

## Rules

- **Pin everything.** Every `uses:` is a full commit SHA with a `# vX.Y.Z` comment; every Docker image is pinned by
  digest. The hygiene check enforces the first in every repo, this one included.
- **No secrets here.** This repo is public. A workflow that needs a secret declares it under
  `workflow_call.secrets` and the calling repo passes its own.
- **Least privilege.** Top-level `permissions: contents: read`; a job asks for more only when it needs it.
- **Stable check names.** Repos require `<job> / check` (usually `node / check`) and `hygiene / hygiene` on `main`. Renaming a job breaks
  every ruleset, so don't, or update `scripts/require-checks.sh` and re-run it everywhere in the same change.
- **Compatible changes.** Callers pin a commit, so an incompatible change only lands when each repo bumps. Add the
  new input with a default first; remove the old one after every repo has moved.
- **Plain and short** comments and docs, sentence case.
