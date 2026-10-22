# base

The shared Debian foundation for every image in this repo. It is **not published**:
`docker-bake.hcl` passes it to the other images as the named build context `base`
(`contexts = { base = "target:base" }`), so `FROM base` only resolves inside a bake build.

## What it provides

|              |                                                                                        |
| ------------ | -------------------------------------------------------------------------------------- |
| OS           | `debian:trixie-slim`, unpinned, so the weekly no-cache rebuild picks up security fixes |
| User         | `docker`, uid/gid 1000, home `/home/docker`, shell bash                                |
| Project root | `/var/www`, owned by `docker`, and the `WORKDIR`                                       |
| Locale       | `LANG=C.UTF-8`                                                                         |
| Final `USER` | `root`; each published image sets its own                                              |

### Packages

| Area              | Packages                                                               |
| ----------------- | ---------------------------------------------------------------------- |
| Shell             | `bash-completion`, `less`, `nano`, `procps`                            |
| Network and VCS   | `curl`, `ca-certificates`, `git`, `git-lfs`, `openssh-client`, `rsync` |
| Data and archives | `jq`, `patch`, `unzip`, `zip`, `xz-utils`, `zstd`                      |
| Other             | `gnupg`, `perl`, `tini`                                                |

### Node.js

| Tool       | Pinned by                    | Notes                                                                        |
| ---------- | ---------------------------- | ---------------------------------------------------------------------------- |
| nvm        | `NVM_VERSION` + `NVM_COMMIT` | at `NVM_DIR=/home/docker/.nvm`, writable by `docker`                         |
| Node.js 24 | `NODE_VERSION`               | installed by nvm and set as its default; Renovate bumps minor and patch only |
| yarn 1     | `YARN_VERSION`               | listed in nvm's `default-packages`, so every Node that nvm installs gets it  |

### apt-update-retry

`/usr/local/bin/apt-update-retry` runs `apt-get update` up to five times, five seconds apart.
deb.debian.org mirrors occasionally return a 5xx or a hash sum mismatch for `InRelease` while they
sync, and that fails a build. `Acquire::Retries "5"` (also set here) retries single downloads but
not a failed index. Images built `FROM base` call `apt-update-retry` instead of `apt-get update`.

## Details worth knowing

- **Node without nvm.** `PATH` includes the default Node's `bin` directory, so `node`, `npm` and
  `yarn` work in non-interactive shells and `docker exec` without sourcing nvm. Interactive bash
  shells also source `nvm.sh` from `~/.bashrc`, which gives them the `nvm` function.
- **Other Node versions.** `. "$NVM_DIR/nvm.sh" && nvm install` reads a project's `.nvmrc`.
  nvm checks every Node tarball against nodejs.org's `SHASUMS256.txt`.
- **How nvm is pinned.** nvm publishes no checksums, so the build clones the release tag and fails
  unless it resolves to the expected commit (`NVM_COMMIT`). Renovate updates the tag and commit
  together.
- **apt state stays out of layers.** Debian's `docker-clean` hook stays in place, so downloaded
  `.deb` files are removed after each install. Builds mount `/var/cache/apt` and `/var/lib/apt` as
  BuildKit cache mounts, so the package lists don't land in a layer either.
- **Labels.** `org.opencontainers.image.source`, `vendor` and `licenses` are set here and inherited;
  each published image sets its own `title` and `description`.

## Tests

`tests/structure-test.yaml` runs against every published image, because they all build on base.
