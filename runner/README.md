# Runner host

One Ubuntu 24.04 VM that runs thelankankid's private-repo jobs instead of GitHub's paid runners. It runs
`TLK_RUNNERS` runners (default 3), each taking **one job in a fresh container** and then starting over, so nothing
a job leaves behind reaches the next. The VM itself is never on the tailnet; a job that needs it (netlab) joins for
itself, as GitHub's runners do. core-infra creates the VM (Hetzner, Terraform) and runs `install.sh` from cloud-init.

| File | What |
| --- | --- |
| `Dockerfile` | The job image: GitHub's runner image (pinned by digest) plus `gh`, `make`, `zip`, `rsync`, `xz`, `ssh` |
| `jitconfig` | Mints a single-use runner config with the GitHub App's key; the key stays on the host |
| `run` | One runner, one job: fresh workspace, fresh config, fresh container |
| `tlk-runner@.service` | Keeps runner N going (`tlk-runner@1` … `@3`) |
| `tlk-runner-prune.*` | Every 4 hours, removes what jobs left in Docker |
| `install.sh` | Sets it all up; safe to run again |

## How a job runs

1. `tlk-runner@N` runs `run N`. It empties `/srv/tlk-runner/N` and asks GitHub for a JIT config (a runner that takes
   one job and is then removed), labelled `tlk`, in runner group `TLK_GROUP_ID` (1 is the org's Default group).
2. It starts `tlk-runner:local` with that config. The runner takes a job, runs it and exits; the container goes with
   it, and systemd starts the next.
3. Jobs get the host's Docker (hygiene's actionlint and gitleaks, service containers). The workspace is mounted at the
   same path on the host and in the container, so `docker run -v "$PWD:…"` works. A service container's ports are on
   `host.docker.internal`, not `localhost`.
4. Containers get `NET_ADMIN` and `/dev/net/tun` so `tailscale/github-action` can join the tailnet for one job.

## Set it up

1. **A GitHub App** on the thelankankid org: Settings → Developer settings → GitHub Apps → New. No webhook,
   no callback URL. One permission: **Organization → Self-hosted runners: read and write**. Create it, generate a private
   key, install it on the org (any repo selection; it uses no repo permission). Keep the App ID and the `.pem`.
2. **Keep public repos off it.** Settings → Actions → Runner groups → Default: "Allow public repositories" stays
   unchecked (the default). Public repos (ci, casso) run on GitHub's runners, which are free for them.
3. **The VM:** core-infra's Terraform writes the key to `/etc/tlk-runner/app.pem` and `TLK_APP_ID` to
   `/etc/tlk-runner/runner.env`, clones this repo at a pinned commit and runs `runner/install.sh`. By hand on any
   Ubuntu 24.04 machine: do the same as root.
4. **Send jobs to it:** an org variable `CI_RUNNER=tlk`. Every repo's `ci.yml` reads
   `runs-on: ${{ vars.CI_RUNNER || 'ubuntu-latest' }}`. Deleting the variable sends everything back to GitHub's runners.

## Run it

| To | Do |
| --- | --- |
| See the runners | org Settings → Actions → Runners (idle ones are waiting for a job), or `systemctl status 'tlk-runner@*'` |
| Read a runner's log | `journalctl -u tlk-runner@1 -n 50` |
| Change how many | `TLK_RUNNERS` in `/etc/tlk-runner/runner.env`, then `install.sh` again |
| Update the image | bump this repo's pin in core-infra; the VM is rebuilt from scratch (it holds no state) |
| Stop sending jobs | delete the `CI_RUNNER` org variable; queued jobs keep the runner they were queued for |

## Security

- Only private repos' code runs here. Every job can use the host's Docker, which is as good as root on the VM, so
  the VM holds nothing but the App key, and that key can only register runners. A job can't use it to read code.
- No inbound ports: the runners poll GitHub. core-infra's firewall allows outbound only.
- `unattended-upgrades` keeps Ubuntu patched.
