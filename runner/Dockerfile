# The image every tlk runner container starts from: GitHub's own runner image plus the tools jobs expect that it
# lacks. Built on the host by install.sh; a fresh container per job, so nothing a job installs outlives it.
# Pinned by digest; Dependabot bumps it (.github/dependabot.yml).
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

USER root
# nodejs: actions that wrap a tool in a Node script call `node` from PATH (hashicorp/setup-terraform's wrapper);
# GitHub's image has it. setup-node still puts a job's chosen version first.
# gh from GitHub's signed apt repository: Ubuntu's lags behind GitHub's API.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl docker-compose-v2 gnupg make nodejs openssh-client rsync xz-utils zip; \
    install -d -m 755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*
# AWS CLI v2, as on GitHub's runners (deploys, backups, netlab). Pinned by version and SHA-256; the hashes are of
# the zips whose PGP signatures check against the AWS CLI key (FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C).
ARG AWSCLI_VERSION=2.42.5
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) arch=x86_64 sum=7694a5b0bdd31ddccdbe9c103849cfe1a2aa4b4768e803a50ae94610aa970800 ;; \
      arm64) arch=aarch64 sum=57cb17bdd0327a5685a12d3255b7a3b223f639f566e934ef3d2fa4557bd71675 ;; \
    esac; \
    curl -fsSLo /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWSCLI_VERSION}.zip"; \
    echo "${sum}  /tmp/awscli.zip" | sha256sum -c -; \
    unzip -q /tmp/awscli.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscli.zip
USER runner

# Kept by the host's prune timer.
LABEL tlk-runner=1
CMD ["/home/runner/run.sh"]
