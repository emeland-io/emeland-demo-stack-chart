# syntax=docker/dockerfile:1

# Stage 1: bake test-gitsensor-target as a bare repository
FROM alpine/git:2.45.2 AS repo-builder
ARG GITSENSOR_TARGET_REF=main
ARG GITSENSOR_TARGET_REPO=https://github.com/emeland-io/test-gitsensor-target.git

RUN git clone --depth 1 --branch "${GITSENSOR_TARGET_REF}" "${GITSENSOR_TARGET_REPO}" /tmp/src \
  && git clone --bare /tmp/src /srv/git/test-gitsensor-target.git

# Stage 2: SSH git server (git-shell, fixed host keys)
FROM debian:bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# git-shell must be a valid login shell
RUN git_shell="$(command -v git-shell)" \
  && grep -qxF "$git_shell" /etc/shells 2>/dev/null || echo "$git_shell" >> /etc/shells \
  && useradd --system --create-home --home-dir /home/git --shell "$git_shell" git \
  && mkdir -p /home/git/.ssh /srv/git \
  && chmod 700 /home/git/.ssh \
  && chown -R git:git /home/git /srv/git

# Deterministic host keys per image build (document fingerprint in chart README)
RUN mkdir -p /etc/ssh \
  && ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" \
  && ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" \
  && ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | tee /etc/ssh/ssh_host_ed25519_key.fingerprint

COPY --from=repo-builder /srv/git/test-gitsensor-target.git /srv/git/test-gitsensor-target.git
RUN chown -R git:git /srv/git

RUN printf '%s\n' \
  'Port 22' \
  'ListenAddress 0.0.0.0' \
  'HostKey /etc/ssh/ssh_host_ed25519_key' \
  'HostKey /etc/ssh/ssh_host_rsa_key' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  'ChallengeResponseAuthentication no' \
  'UsePAM no' \
  'PermitRootLogin no' \
  'AllowUsers git' \
  'AuthorizedKeysFile .ssh/authorized_keys' \
  'PidFile /var/run/sshd.pid' \
  > /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
