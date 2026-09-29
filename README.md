# Erebine.ai Debian Packages

<div style="text-align: center;">
<img src="https://erebine.ai/erebine-ogimage.png" alt="Project Logo" width="50%">
</div>

A high-performance, accelerated intelligence platform.

This repository builds Debian/Ubuntu packages for the prebuilt Erebine
binaries: the `erectl` CLI, the EIM inference agent, and the EEM
execution agent. The build pulls the latest stable binaries for this
host's architecture from the
[Erebine/binaries](https://github.com/Erebine/binaries) releases, and
every package declares the runtime libraries it needs, so installation
resolves dependencies the traditional way.

## Getting Started

Build the packages, then install them with apt:

``` shell
./build.sh
sudo apt install -y ./build/*.deb
```

* The first command downloads the latest stable binaries and builds one
  .deb per binary into `build/`.
* The second command installs the packages; apt resolves the library
  dependencies automatically.

To package a specific release instead of the latest, set `TAG`:

``` shell
TAG=v0.0.1 ./build.sh
```

Prebuilt packages are attached to this repository's
[releases](https://github.com/erebine/deb/releases). Each one is also
published under an unversioned filename that always resolves to the newest
release, so installing does not start with looking a version up:

``` shell
curl -fLO https://github.com/erebine/deb/releases/latest/download/erectl_amd64.deb
sudo apt install -y ./erectl_amd64.deb
```

The architecture stays in that name, so the unversioned filename can never
resolve to a package built for another machine. The versioned filename
(`erectl_2.0.0_amd64.deb`) is attached to the same release for pinning to a
specific version.

## Licensing

Each package's `/usr/share/doc/<package>/copyright` is not kept in this
repository. It is the `debian-copyright` asset attached to the
Erebine/binaries release being packaged: a machine-readable DEP-5 file
generated from the dependency pins that release's binaries were linked
from, so it can never describe a different dependency set than the binary
beside it. The release's `THIRD_PARTY_NOTICES` is installed next to it.

`build.sh` downloads both for the tag it is packaging and fails if either
is missing, so a release cut before the generated metadata existed cannot
produce a package with no copyright file.

## Packages

| Package | Binary | Dependencies |
| --- | --- | --- |
| `erectl` | `/usr/bin/erectl` | libzstd1, libcurl4, ca-certificates |
| `erebine-eim-agent` | `/usr/bin/erebine-eim-agent` | libzmq5, libsodium23, libzstd1 |
| `erebine-eem-agent` | `/usr/bin/erebine-eem-agent` | libzmq5, libsodium23, libzstd1, libcurl4, ca-certificates |

## Services

The agent packages install systemd units. Set the join key (and for
EEM the router URL and registration name) in the env file, then enable
the service:

``` shell
sudoedit /etc/erebine/eim-agent.env
sudo systemctl enable --now erebine-eim-agent

sudoedit /etc/erebine/eem-agent.env
sudo systemctl enable --now erebine-eem-agent
```

Both services run as the `erebine` system user (created on install)
and keep state under `/var/lib/erebine`. The agents enroll on first
start using the join key from their env file.

### Widening the EEM sandbox

The EEM unit runs its tools in a sandbox: `ProtectHome=yes`,
`ProtectSystem=strict` with only `/var/lib/erebine` writable, and
`NoNewPrivileges=yes`. Tools cannot read `/home`, write anywhere else,
or use `sudo`. To give a workspace more room, add a drop-in rather than
editing the unit, which a package upgrade replaces:

``` shell
sudo systemctl edit erebine-eem-agent
```

``` ini
[Service]
ProtectHome=read-only
ReadWritePaths=/srv/repos
```

``` shell
sudo systemctl restart erebine-eem-agent
```

`ReadWritePaths=` in a drop-in adds to the paths the unit already
allows. `sudo systemctl revert erebine-eem-agent` removes the drop-in.

Documentation for running the binaries can be found in the
[docs](https://erebine.ai/docs/private-agents).
