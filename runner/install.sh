#!/usr/bin/env bash
# Set up an Ubuntu 24.04 host as thelankankid's CI runner host (README.md): Docker, the runner image, and the
# dispatcher, which starts a one-job runner in a fresh container for each queued job. Run as root from a checkout of
# this repo:
#
#   runner/install.sh
#
# Before it: the GitHub App's private key in /etc/tlk-runner/app.pem and its id as TLK_APP_ID in
# /etc/tlk-runner/runner.env (core-infra's cloud-init writes both). Safe to run again: it rebuilds the image and
# restarts the dispatcher; jobs already running finish.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
conf=/etc/tlk-runner
lib=/usr/local/lib/tlk-runner

echo "== packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  ca-certificates curl jq openssl docker.io docker-buildx unattended-upgrades >/dev/null
systemctl enable --now docker >/dev/null

echo "== config"
install -d -m 700 "$conf"
if [ ! -f "$conf/runner.env" ]; then
  cat >"$conf/runner.env" <<'ENV'
TLK_OWNER=thelankankid
TLK_APP_ID=
TLK_APP_KEY=/etc/tlk-runner/app.pem
TLK_LABELS=tlk
TLK_RUNNERS=3
TLK_IMAGE=tlk-runner:local
TLK_POLL=10
TLK_IDLE=600
TLK_REPOS=
ENV
fi
chmod 600 "$conf/runner.env"
set -a
# shellcheck disable=SC1091
. "$conf/runner.env"
set +a
[ -n "${TLK_APP_ID:-}" ] || { echo "set TLK_APP_ID in $conf/runner.env" >&2; exit 1; }
[ -s "$TLK_APP_KEY" ] || { echo "put the GitHub App's private key in $TLK_APP_KEY" >&2; exit 1; }
chmod 600 "$TLK_APP_KEY"

install -d -m 755 "$lib"
install -m 755 "$here/dispatch" "$lib/"

echo "== image"
docker build -q -t "$TLK_IMAGE" "$here" >/dev/null
echo "$TLK_IMAGE built"

echo "== services"
install -m 644 "$here/tlk-dispatch.service" "$here/tlk-runner-prune.service" "$here/tlk-runner-prune.timer" \
  /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now tlk-runner-prune.timer >/dev/null
systemctl enable tlk-dispatch >/dev/null 2>&1
systemctl restart tlk-dispatch
sleep 15
if journalctl -u tlk-dispatch --since "-20s" | grep -q 'poll failed'; then
  echo "the dispatcher can't reach GitHub with the App: journalctl -u tlk-dispatch" >&2
  exit 1
fi
echo "dispatching, up to $TLK_RUNNERS runners: journalctl -u tlk-dispatch -f"
