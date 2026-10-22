# syntax=docker/dockerfile:1.28
# check=error=true
#
# base: shared Debian foundation for the Phase2 images. Not published.
# Provides the `docker` user (1000:1000), common CLI utilities, nvm and a default Node.js.
# docker-bake.hcl injects it into other images as the named build context `base`.

ARG DEBIAN_IMAGE=docker.io/library/debian:trixie-slim

FROM ${DEBIAN_IMAGE}
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# apt-update-retry: `apt-get update` with retries, for this image and every image built FROM it.
COPY --link rootfs/ /

ARG USER_NAME=docker
ARG USER_UID=1000
ARG USER_GID=1000

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<'EOF'
# Debian's docker-clean stays: it is inherited, and keeps downstream `apt-get install` layers
# free of downloaded .debs.
# Every image built FROM base inherits the download retries.
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
export DEBIAN_FRONTEND=noninteractive
apt-update-retry
apt-get install -y --no-install-recommends \
  bash-completion ca-certificates curl git git-lfs gnupg jq less nano openssh-client patch perl \
  procps rsync tini unzip xz-utils zip zstd
groupadd --gid "${USER_GID}" "${USER_NAME}"
useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USER_NAME}"
install -d -o "${USER_UID}" -g "${USER_GID}" -m 0755 /var/www
rm -rf /var/log/*.log /var/log/apt /tmp/*
EOF

# nvm is pinned by tag and commit (it publishes no checksum file). `nvm install` verifies
# every Node.js tarball against nodejs.org's SHASUMS256.txt.
# renovate-digest: datasource=github-tags depName=nvm-sh/nvm
ARG NVM_VERSION=v0.40.8
ARG NVM_COMMIT=a885b885fef16fac4bc544188fb25e9e37ae83e8
# renovate: datasource=node-version depName=node versioning=node
ARG NODE_VERSION=24.22.1
# renovate: datasource=npm depName=yarn
ARG YARN_VERSION=1.22.22

ENV NVM_DIR=/home/${USER_NAME}/.nvm

USER ${USER_UID}:${USER_GID}
# hadolint ignore=SC1091,SC2016
RUN <<'EOF'
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${NVM_VERSION}" \
  https://github.com/nvm-sh/nvm.git "${NVM_DIR}"
actual="$(git -C "${NVM_DIR}" rev-parse HEAD)"
if [[ "${actual}" != "${NVM_COMMIT}" ]]; then
  echo "nvm ${NVM_VERSION} resolved to ${actual}, expected ${NVM_COMMIT}" >&2
  exit 1
fi
rm -rf "${NVM_DIR}/.git"
# Installed into every Node.js version nvm installs (matches the old image's behaviour).
echo "yarn@${YARN_VERSION}" > "${NVM_DIR}/default-packages"
. "${NVM_DIR}/nvm.sh"
nvm install "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
nvm cache clear
# Interactive shells get the `nvm` function; non-interactive ones use the default Node via PATH.
printf '\nexport NVM_DIR="%s"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' "${NVM_DIR}" >> "${HOME}/.bashrc"
rm -rf "${HOME}/.npm"
EOF

# Children install packages on top of base; each published image sets its own final USER.
# hadolint ignore=DL3002
USER root
ENV LANG=C.UTF-8 \
    PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}
WORKDIR /var/www

# Inherited by every image; each sets its own title and description.
LABEL org.opencontainers.image.source="https://github.com/phase2/docker-images" \
      org.opencontainers.image.vendor="Phase2" \
      org.opencontainers.image.licenses="MIT"
