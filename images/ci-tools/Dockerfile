# syntax=docker/dockerfile:1.28
# check=error=true
#
# ci-tools: general CI job container (GitHub Actions `container:` on self-hosted runners).
# base + kubectl, helm, kustomize, aws, htpasswd and tmate. Runs as uid 1000, no sudo, no setuid.
# Built through docker-bake.hcl (`FROM base` is the named context of the internal base image).

# ---------------------------------------------------------------------------
# fetch: download each tool and verify it against the checksum file (or PGP
# signature) its project publishes alongside the release. base already has
# curl, gnupg and unzip.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base AS fetch
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ARG TARGETARCH

# renovate: datasource=github-releases depName=kubernetes/kubernetes extractVersion=^v(?<version>.*)$
ARG KUBECTL_VERSION=1.37.1
# renovate: datasource=github-releases depName=helm/helm extractVersion=^v(?<version>.*)$
ARG HELM_VERSION=3.22.1
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/v(?<version>.*)$
ARG KUSTOMIZE_VERSION=5.8.3
# renovate: datasource=github-tags depName=aws/aws-cli
ARG AWSCLI_VERSION=2.38.5

COPY awscli.pubkey /tmp/awscli.pubkey

WORKDIR /tmp/dl
RUN <<'EOF'
get() { curl -fsSL --retry 5 --retry-all-errors --proto '=https' -o "$2" "$1"; }
case "${TARGETARCH}" in
  amd64) AWS_ARCH=x86_64 ;;
  arm64) AWS_ARCH=aarch64 ;;
  *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;;
esac
BIN=/out/usr/local/bin
mkdir -p "${BIN}" /out/opt

# kubectl: <file>.sha256 holds the bare digest
base="https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"
get "${base}" kubectl
get "${base}.sha256" kubectl.sha256
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --strict -c -
install -m 0755 kubectl "${BIN}/kubectl"

# helm: <file>.sha256sum holds "<digest>  <file>"
f="helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"
get "https://get.helm.sh/${f}" "${f}"
get "https://get.helm.sh/${f}.sha256sum" "${f}.sha256sum"
sha256sum --strict -c "${f}.sha256sum"
tar -xzf "${f}" --strip-components=1 -C "${BIN}" "linux-${TARGETARCH}/helm"
ln -s helm "${BIN}/helm3"   # for callers that invoke `helm3`

# kustomize: one checksums.txt per release
rel="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}"
f="kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz"
get "${rel}/${f}" "${f}"
get "${rel}/checksums.txt" kustomize-checksums.txt
grep -E "  ${f}\$" kustomize-checksums.txt | sha256sum --strict -c -
tar -xzf "${f}" -C "${BIN}" kustomize

# AWS CLI v2: installer verified with AWS's published PGP key (awscli.pubkey)
export GNUPGHOME=/tmp/gnupg && mkdir -m 700 "${GNUPGHOME}"
gpg --batch --quiet --import /tmp/awscli.pubkey
gpg --batch --with-colons --fingerprint | grep -q '^fpr:::::::::FB5DB77FD5C118B80511ADA8A6310ACC4672475C:$'
get "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" awscli.zip
get "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip.sig" awscli.zip.sig
gpg --batch --verify awscli.zip.sig awscli.zip
unzip -q awscli.zip
./aws/install --install-dir /opt/aws-cli --bin-dir /tmp/aws-bin
mv /opt/aws-cli /out/opt/aws-cli
ln -s /opt/aws-cli/v2/current/bin/aws "${BIN}/aws"
ln -s /opt/aws-cli/v2/current/bin/aws_completer "${BIN}/aws_completer"

# The final stage strips setuid/setgid before this tree is copied in; strip it here too.
find /out -perm /6000 -type f -exec chmod a-s {} +
EOF

# ---------------------------------------------------------------------------
# ci-tools
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base AS ci-tools
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# apache2-utils: htpasswd for deploy scripts; tmate: interactive debugging of CI jobs.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-update-retry
apt-get install -y --no-install-recommends apache2-utils tmate
# No privilege escalation paths: strip every setuid/setgid bit (passwd, chsh, su, mount, ...).
find / -xdev -perm /6000 -type f -exec chmod a-s {} +
rm -rf /var/log/*.log /var/log/apt /tmp/*
EOF

# Release archives carry their builders' uids; everything lands root-owned.
COPY --link --chown=0:0 --from=fetch /out/ /

USER 1000:1000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]

LABEL org.opencontainers.image.title="ci-tools" \
      org.opencontainers.image.description="Phase2 CI job container: git, node/nvm, kubectl, helm, kustomize, aws (Debian trixie-slim)"
