# Runner host

One Ubuntu 24.04 VM that runs the private repos' jobs instead of GitHub's paid runners. core-infra creates it
(Hetzner, Terraform) and runs `install.sh` from cloud-init.

thelankankid is a personal account, so there are no org-wide runners: a runner belongs to one repo. A dispatcher
watches the private repos for queued jobs labelled `tlk` and starts a runner for that repo, **one job in a fresh
container**, at most `TLK_RUNNERS` at a time. Nothing a job leaves behind reaches the next. The VM is never on the
tailnet; a job that needs it (netlab) joins for itself, as on GitHub's runners.

| File | What |
| --- | --- |
| `Dockerfile` | The job image: GitHub's runner image (pinned by digest) plus the AWS CLI, Docker Compose, `gh`, `make`, `zip`, `rsync`, `xz`, `ssh` |
| `dispatch` | Polls for queued jobs, starts a one-job runner per job, removes runners whose job went away |
| `tlk-dispatch.service` | Keeps the dispatcher running |
| `tlk-runner-prune.*` | Every 4 hours, removes what jobs left in Docker |
| `install.sh` | Sets it all up; safe to run again |

## How a job runs

1. A private repo's job asks for `runs-on: tlk` (through `vars.CI_RUNNER`).
2. Within `TLK_POLL` seconds (10) the dispatcher sees it queued, asks GitHub for a single-use runner config for that
   repo (JIT: it takes one job and is then removed) and starts `tlk-runner:local` with it.
3. The runner takes the job, runs it and exits; the container goes with it.
4. A runner with no job after `TLK_IDLE` seconds (600: its job was cancelled) is removed and unregistered.

Requests carry the last ETag, and GitHub doesn't count an unchanged answer (304) against the App's rate limit, so
polling every 10 seconds is cheap.

What a job gets:

- The host's Docker (hygiene's actionlint and gitleaks, service containers). The workspace is at the same path on
  the host and in the container, so `docker run -v "$PWD:…"` works. A service container's ports are on
  `host.docker.internal`, not `localhost`.
- `NET_ADMIN` and `/dev/net/tun`, so `tailscale/github-action` can join the tailnet for that job.
- Not most tools GitHub's `ubuntu-latest` image preinstalls (Terraform, language runtimes beyond Python, browsers):
  use the `setup-*` actions, or add the tool to the `Dockerfile`.

## Set it up

1. **A GitHub App** on your account: Settings → Developer settings → GitHub Apps → New GitHub App. Untick
   "Webhook: Active"; any homepage URL. Repository permissions: **Administration: read and write** (registering a
   repo's runner needs it) and **Actions: read** (to see queued jobs); Metadata: read comes with them. "Only on this
   account". Create it, note the App ID, generate a private key (`.pem`).
2. **Install it** (the App's page → Install App) on **only the private repos** that will use the runner. The
   dispatcher also skips public repos; GitHub's runners are free for them, and a public repo must never reach this one.
3. **The VM:** core-infra's Terraform writes the key to `/etc/tlk-runner/app.pem` and `TLK_APP_ID` to
   `/etc/tlk-runner/runner.env`, clones this repo at a pinned commit and runs `runner/install.sh`. By hand on any
   Ubuntu 24.04 machine: do the same as root.
4. **Send a repo's jobs to it:** the repo variable `CI_RUNNER=tlk`
   (`gh variable set CI_RUNNER -b tlk -R thelankankid/<repo>`). Its workflows read
   `runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}`; deleting the variable sends them back to GitHub's runners.

## Run it

| To | Do |
| --- | --- |
| Watch it | `journalctl -u tlk-dispatch -f`; the repo's Settings → Actions → Runners shows its runner during a job |
| See running jobs | `docker ps --filter label=tlk.repo` |
| Change limits | `TLK_RUNNERS`, `TLK_POLL`, `TLK_IDLE`, `TLK_REPOS` (only these repos) in `/etc/tlk-runner/runner.env`, then `systemctl restart tlk-dispatch` |
| Update the image | bump this repo's pin in core-infra; the VM is rebuilt from scratch (it holds no state) |
| Stop sending a repo's jobs | delete its `CI_RUNNER` variable; queued jobs keep the runner they were queued for |

## Security

- Only private repos' code runs here. Every job can use the host's Docker, which is as good as root on the VM.
- The VM holds one secret, the App key. With Administration write on the repos it's installed on, it could change
  their settings, so: install the App only on the repos that use the runner, keep the VM for this alone, and rotate the
  key (the App's page) if the VM is ever in doubt. Each job's container gets only its own single-use runner config.
- No inbound ports: the dispatcher and the runners call GitHub. core-infra's firewall allows outbound only.
- `unattended-upgrades` keeps Ubuntu patched.
