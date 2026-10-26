# syntax=docker/dockerfile:1.28
# check=error=true
#
# httpd-devcloud: the Apache web container of devcloud preview pods. Serves the docroot of the
# checkout at /var/www and sends .php requests to the php-devcloud FPM sidecar over FastCGI.
# Built through docker-bake.hcl. Not FROM base: Apache needs neither the docker user nor Node.

# The official Apache 2.4 image on Debian trixie. Renovate bumps the 2.4.x tag; the weekly
# no-cache rebuild picks up upstream's rebuilds of it.
ARG HTTPD_IMAGE=docker.io/library/httpd:2.4.69-trixie

FROM ${HTTPD_IMAGE}
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# apt-get upgrade: upstream's Debian packages only refresh when upstream rebuilds, so the weekly
# rebuild applies Debian security fixes itself (Trivy gates the result).
# curl: health checks and debugging from `kubectl exec`. openssl: httpd-foreground generates the
# self-signed certificate for :443 at start, so no private key ships in this public image.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<'EOF'
export DEBIAN_FRONTEND=noninteractive
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends curl openssl
conf=/usr/local/apache2/conf
# The modules docksal/apache enables; project overrides rely on them.
for m in deflate proxy proxy_http proxy_fcgi proxy_connect ssl socache_shmcb rewrite; do
  sed -i -E "s/^#(LoadModule ${m}_module )/\\1/" "${conf}/httpd.conf"
  grep -qE "^LoadModule ${m}_module " "${conf}/httpd.conf"
done
# The generated settings first (httpd-foreground rewrites them at start), then the vhosts.
printf '\n# httpd-devcloud\n%s\n%s\n' 'Include conf/devcloud-runtime.conf' 'Include conf/extra/httpd-devcloud.conf' >> "${conf}/httpd.conf"
rm -rf /var/log/*.log /var/log/apt /tmp/*
EOF

# httpd-foreground replaces upstream's: it rewrites conf/devcloud-runtime.conf from the
# environment, then runs httpd. The shipped copy holds the defaults, so `httpd -t` works without it.
COPY --link rootfs/ /

WORKDIR /var/www
EXPOSE 80 443
# Upstream's STOPSIGNAL SIGWINCH (graceful stop) is inherited.
CMD ["httpd-foreground"]

LABEL org.opencontainers.image.title="httpd-devcloud" \
      org.opencontainers.image.description="Phase2 Apache 2.4 web container for devcloud preview environments (Debian trixie)" \
      org.opencontainers.image.source="https://github.com/phase2/docker-images" \
      org.opencontainers.image.vendor="Phase2" \
      org.opencontainers.image.licenses="MIT"
