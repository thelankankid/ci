#!/usr/bin/env bash
# Set up an Ubuntu 24.04 host as thelankankid's CI runner host (README.md): Docker, the runner image, and
# TLK_RUNNERS runner services, each taking one job in a fresh container. Run as root from a checkout of this repo:
#
#   runner/install.sh
#
# Before it: the GitHub App's private key in /etc/tlk-runner/app.pem and its id as TLK_APP_ID in
# /etc/tlk-runner/runner.env (core-infra's cloud-init writes both). Safe to run again: it rebuilds the image and
# restarts the runners, which picks up a new pin of this repo.
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
TLK_ORG=thelankankid
TLK_APP_ID=
TLK_APP_KEY=/etc/tlk-runner/app.pem
TLK_LABELS=tlk
TLK_GROUP_ID=1
TLK_RUNNERS=3
TLK_IMAGE=tlk-runner:local
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

echo "== the App can mint runner configs"
install -d -m 755 "$lib"
install -m 755 "$here/jitconfig" "$here/run" "$lib/"
"$lib/jitconfig" "tlk-$(hostname -s)-check-$(date +%s)" /tmp >/dev/null # registers nothing until a runner uses it
echo "ok"

echo "== image"
docker build -q -t "$TLK_IMAGE" "$here" >/dev/null
echo "$TLK_IMAGE built"

echo "== services"
install -m 644 "$here/tlk-runner@.service" "$here/tlk-runner-prune.service" "$here/tlk-runner-prune.timer" \
  /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now tlk-runner-prune.timer >/dev/null
# Stop runners beyond TLK_RUNNERS (after lowering it), then (re)start the rest.
for unit in $(systemctl list-units --all --plain --no-legend 'tlk-runner@*.service' | awk '{print $1}'); do
  n=${unit#tlk-runner@}; n=${n%.service}
  if [ "$n" -gt "$TLK_RUNNERS" ]; then systemctl disable --now "$unit" >/dev/null; fi
done
for n in $(seq 1 "$TLK_RUNNERS"); do
  systemctl enable "tlk-runner@$n" >/dev/null 2>&1
  systemctl restart "tlk-runner@$n"
done
echo "$TLK_RUNNERS runners started; they show as idle under the org's Settings → Actions → Runners"
