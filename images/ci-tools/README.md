# ci-tools

`ghcr.io/phase2/ci-tools:1`: a general CI job container for repos that don't need PHP. It builds
on [base](../base/README.md) and adds Kubernetes, Helm and AWS tooling.

```yaml
jobs:
  deploy:
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/phase2/ci-tools:1
```

The job runs as uid 1000, so the workspace the runner mounts must be writable by uid 1000. If the
runner's user has a different uid, override it with `options: --user <uid>`.

## Tools

Everything in [base](../base/README.md) (git, git-lfs, jq, rsync, curl, Node 24 with nvm and
yarn 1, and more), plus:

| Tool             | Pinned by           | Source               | Verified with                                               |
| ---------------- | ------------------- | -------------------- | ----------------------------------------------------------- |
| kubectl          | `KUBECTL_VERSION`   | dl.k8s.io            | the release's `.sha256` file                                |
| helm 3           | `HELM_VERSION`      | get.helm.sh          | the release's `.sha256sum` file                             |
| `helm3`          |                     | symlink to `helm`    |                                                             |
| kustomize        | `KUSTOMIZE_VERSION` | GitHub release       | the release's `checksums.txt`                               |
| aws (AWS CLI v2) | `AWSCLI_VERSION`    | awscli.amazonaws.com | PGP signature, checked against AWS's key in `awscli.pubkey` |
| htpasswd         | Debian package      | `apache2-utils`      | apt                                                         |
| tmate            | Debian package      | `tmate`              | apt                                                         |

The `ARG`s are in the `fetch` stage of the [Dockerfile](Dockerfile); Renovate keeps them current.

`aws_completer` is installed next to `aws`. `apache2-utils` also brings `ab`, `htdigest` and the
other Apache helper tools.

## Details worth knowing

- **No privilege escalation.** It runs as `1000:1000`, has no sudo, and the build strips every
  setuid and setgid bit, including from `su`, `passwd` and `mount`. A step that needs root needs a
  different image or a derived one.
- **Helm stays on 3.** Renovate is limited to Helm `<4`, and the `helm3` symlink keeps scripts that
  call `helm3` working.
- **How downloads are verified.** A separate `fetch` stage downloads each tool and checks it against
  the checksum file or signature its project publishes next to the release. Only the verified files
  are copied into the image, owned by root. No checksums are stored in this repo, so a version bump
  is a one-line change.
- **Versioning.** The `1` tag only changes compatibly. Removing a tool or changing the user is a
  breaking change: it bumps `CI_TOOLS_MAJOR` in `docker-bake.hcl` and goes in `CHANGELOG.md`.
  Every build also gets an immutable `1-YYYYMMDD-<sha>` tag for pinning.
- **Entrypoint.** `tini` is PID 1, so signals reach the job's processes and orphaned processes are
  cleaned up. The default command is `bash`.

## Tests

`tests/structure-test.yaml` checks each tool's version, the `helm3` alias, the user, and that no
sudo or setuid binaries exist. It also runs against [php-ci](../php-ci/README.md), which builds on
this image.
