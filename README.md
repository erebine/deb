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

Documentation for running the binaries can be found in the
[docs](https://erebine.ai/docs/private-agents).
