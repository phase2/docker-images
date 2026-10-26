# docker buildx bake definitions for every image in images/.
#   docker buildx bake --print                       # inspect
#   docker buildx bake php-devcloud-8-4 --load \
#     --set '*.platform=linux/arm64'                 # one variant, local
# CI publishes through docker/github-builder bake.yml (one target per call); it sets the
# registry tags itself, so the tags here are for local builds.

variable "REGISTRY"       { default = "ghcr.io/phase2" }
variable "PHP_VERSIONS"   { default = ["8.3", "8.4", "8.5"] }
# Bump on breaking ci-tools changes (e.g. a removed tool) and record them in CHANGELOG.md.
variable "CI_TOOLS_MAJOR" { default = "1" }

group "default" {
  targets = ["ci-tools", "httpd-devcloud", "php-ci", "php-devcloud"]
}

target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
}

# Internal foundation (docker user, common utilities, nvm + Node.js). Not published.
target "base" {
  inherits = ["_common"]
  context  = "images/base"
}

target "ci-tools" {
  inherits = ["_common"]
  context  = "images/ci-tools"
  contexts = { base = "target:base" }
  tags     = ["${REGISTRY}/ci-tools:${CI_TOOLS_MAJOR}"]
}

# Apache for devcloud pods. FROM the official httpd image, not base; one tag, the Apache minor.
target "httpd-devcloud" {
  inherits = ["_common"]
  context  = "images/httpd-devcloud"
  tags     = ["${REGISTRY}/httpd-devcloud:2.4"]
}

target "php-ci" {
  name     = "php-ci-${replace(php, ".", "-")}"
  matrix   = { php = PHP_VERSIONS }
  inherits = ["_common"]
  context  = "images/php-ci"
  contexts = {
    ci-tools = "target:ci-tools"
    shared   = "images/_shared"
  }
  args = { PHP_VERSION = php }
  tags = ["${REGISTRY}/php-ci:${php}"]
}

target "php-devcloud" {
  name     = "php-devcloud-${replace(php, ".", "-")}"
  matrix   = { php = PHP_VERSIONS }
  inherits = ["_common"]
  context  = "images/php-devcloud"
  contexts = {
    base   = "target:base"
    shared = "images/_shared"
  }
  args = { PHP_VERSION = php }
  tags = ["${REGISTRY}/php-devcloud:${php}"]
}
