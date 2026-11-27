# The image every tlk runner container starts from: GitHub's own runner image plus the few tools jobs expect that it
# lacks. Built on the host by install.sh; a fresh container per job, so nothing a job installs outlives it.
# Pinned by digest; Dependabot bumps it (.github/dependabot.yml).
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

USER root
# gh from GitHub's signed apt repository: Ubuntu's lags behind GitHub's API.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg make openssh-client rsync xz-utils zip; \
    install -d -m 755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*
USER runner

# Kept by the host's prune timer.
LABEL tlk-runner=1
CMD ["/home/runner/run.sh"]
