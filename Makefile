# Local lint / build / test / scan, also used by CI (.github/workflows/images.yml).
# Needs: docker with buildx, plus shellcheck and container-structure-test from mise.toml
# (`mise install`). hadolint, trivy, actionlint and gitleaks run from their (digest-pinned) images.
#
#   lefthook install                          # once: pre-commit hook running the lint checks
#   make builder                              # once: docker-container builder for multi-platform/contexts
#   make lint
#   make build test scan IMAGE=php-devcloud PHP=8.4
#   make build test scan IMAGE=ci-tools
#   make build test scan IMAGE=httpd-devcloud
#   make build-all test-all scan-all          # every image: one bake call, then parallel tests/scans
SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c

DOCKER   ?= docker
CST      ?= container-structure-test
BUILDER  ?= p2-images
IMAGE    ?= php-devcloud
PHP      ?= 8.4
# Detected lazily and cached after the first use, so `make build test` asks docker only once.
ifndef PLATFORM
PLATFORM = $(eval PLATFORM := linux/$(shell $(DOCKER) version -f '{{.Server.Arch}}'))$(PLATFORM)
endif

# The PHP matrix, read from docker-bake.hcl so it lives in one place.
ifndef PHP_ALL
PHP_ALL = $(eval PHP_ALL := $(shell $(BUILDX) bake --print php-ci 2>/dev/null | sed -n 's/.*"PHP_VERSION": "\(.*\)".*/\1/p'))$(PHP_ALL)
endif
# Images without a PHP matrix: one bake target each, named after the image (PHP is ignored).
NON_PHP_IMAGES := ci-tools httpd-devcloud
VARIANTS = $(NON_PHP_IMAGES) $(foreach v,$(PHP_ALL),php-ci:$(v) php-devcloud:$(v))

ifneq ($(filter $(IMAGE),$(NON_PHP_IMAGES)),)
TARGET := $(IMAGE)
TAG    ?= local/$(IMAGE):dev
else
TARGET := $(IMAGE)-$(subst .,-,$(PHP))
TAG    ?= local/$(IMAGE):$(PHP)
endif

BUILDX         := $(DOCKER) buildx $(if $(BUILDER),--builder $(BUILDER))
BUILDKIT_IMAGE := moby/buildkit:v0.34.1
HADOLINT_IMAGE := ghcr.io/hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d
TRIVY_IMAGE    := ghcr.io/aquasecurity/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
ACTIONLINT_IMAGE := docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
GITLEAKS_IMAGE := ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
# Stand-in for the bake-provided named contexts when running Dockerfile checks one file at a time
# (`bake --call check` cannot resolve `target:` contexts).
STUB_CONTEXT   := docker-image://docker.io/library/debian:trixie-slim
SCRIPTS         = $(shell find images scripts -type f \( -name '*.sh' -o -path '*/usr/local/bin/*' \))
TRIVY          := $(DOCKER) run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache -v "$(CURDIR):/out" $(TRIVY_IMAGE)
SARIF          ?= trivy.sarif
# Extra flags for `scan`. scan-all fetches the DB once, then scans in parallel with
# --skip-db-update and an in-memory layer cache (the on-disk one takes an exclusive lock).
SCAN_FLAGS     ?=

.PHONY: all builder lint hadolint shellcheck buildcheck repo-lint actionlint gitleaks gitleaks-staged build test scan scan-report scan-sarif build-all test-all scan-all

all: lint build test scan

builder:      ## docker-container builder (bake named contexts + multi-platform need it)
	$(DOCKER) buildx inspect $(BUILDER) >/dev/null 2>&1 || \
	  $(DOCKER) buildx create --name $(BUILDER) --driver docker-container --driver-opt image=$(BUILDKIT_IMAGE)

lint: hadolint shellcheck buildcheck

hadolint:
	$(DOCKER) run --rm -v "$(CURDIR):/repo:ro" -w /repo $(HADOLINT_IMAGE) hadolint --config .hadolint.yaml images/*/Dockerfile

shellcheck:
	shellcheck -x $(SCRIPTS)

buildcheck:   ## BuildKit build checks (docker build --check) for every Dockerfile
	for f in images/*/Dockerfile; do echo "== $$f"; \
	  $(BUILDX) build --call check --build-context base=$(STUB_CONTEXT) \
	    --build-context ci-tools=$(STUB_CONTEXT) --build-context shared=images/_shared "$${f%/Dockerfile}"; done

repo-lint: actionlint gitleaks

actionlint:
	$(DOCKER) run --rm -v "$(CURDIR):/repo:ro" -w /repo $(ACTIONLINT_IMAGE) -color

gitleaks:     ## full git history, plus the working tree (catches uncommitted files)
	if git -C "$(CURDIR)" rev-parse --verify HEAD >/dev/null 2>&1; then \
	  $(DOCKER) run --rm -v "$(CURDIR):/repo:ro" $(GITLEAKS_IMAGE) git /repo --redact --no-banner --exit-code 1; fi
	$(DOCKER) run --rm -v "$(CURDIR):/repo:ro" $(GITLEAKS_IMAGE) dir /repo --redact --no-banner --exit-code 1

gitleaks-staged: ## pre-commit hook: the staged diff only (read on the host, so git worktrees work)
	git -C "$(CURDIR)" diff --cached --no-color --no-ext-diff -U0 | \
	  $(DOCKER) run --rm -i $(GITLEAKS_IMAGE) stdin --redact --no-banner --exit-code 1

build:        ## one variant for one platform, loaded into the local image store as $(TAG)
	$(BUILDX) bake $(TARGET) --set '*.platform=$(PLATFORM)' --set '$(TARGET).tags=$(TAG)' --load

test:
	DOCKER="$(DOCKER)" CST="$(CST)" PLATFORM="$(PLATFORM)" scripts/test-image.sh $(IMAGE) $(TAG)

scan:         ## gate: fixable HIGH/CRITICAL in OS packages
	$(TRIVY) image --quiet --exit-code 1 --pkg-types os --ignore-unfixed --severity HIGH,CRITICAL $(SCAN_FLAGS) $(TAG)

build-all:    ## every variant in one bake call: base and ci-tools build once, variants in parallel. NO_CACHE=1 for a cold build
	$(BUILDX) bake $(NON_PHP_IMAGES) php-ci php-devcloud --set '*.platform=$(PLATFORM)' $(if $(NO_CACHE),--no-cache) \
	  $(foreach i,$(NON_PHP_IMAGES),--set '$(i).tags=local/$(i):dev') \
	  $(foreach v,$(PHP_ALL),--set 'php-ci-$(subst .,-,$(v)).tags=local/php-ci:$(v)' \
	    --set 'php-devcloud-$(subst .,-,$(v)).tags=local/php-devcloud:$(v)') \
	  --load

test-all:     ## `test` for every variant in parallel; prints the logs of failures
	MAKE="$(MAKE)" scripts/each-variant.sh test $(VARIANTS)

scan-all:     ## `scan` for every variant in parallel, after fetching the vulnerability DB once
	$(TRIVY) image --quiet --download-db-only
	SCAN_FLAGS="--skip-db-update --cache-backend memory" MAKE="$(MAKE)" scripts/each-variant.sh scan $(VARIANTS)

scan-report:  ## report only: everything, including vendored Go/npm/PHP dependencies
	$(TRIVY) image --quiet --severity HIGH,CRITICAL $(TAG)

scan-sarif:   ## report only, as SARIF in $(SARIF): fixable HIGH/CRITICAL in every package type (CI uploads it to code scanning)
	$(TRIVY) image --quiet --ignore-unfixed --severity HIGH,CRITICAL --format sarif --output /out/$(SARIF) $(TAG)
