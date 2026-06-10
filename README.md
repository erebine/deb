# Xerotier.ai Debian Packages

<div style="text-align: center;">
<img src="https://xerotier.ai/xerotier-ogimage.png" alt="Project Logo" width="50%">
</div>

A high-performance, accelerated intelligence platform.

This repository builds Debian/Ubuntu packages for the prebuilt Xerotier
binaries: the `xeroctl` CLI, the XIM inference agent, and the XEM
execution agent. The build pulls the latest stable binaries for this
host's architecture from the
[Xerotier/binaries](https://github.com/Xerotier/binaries) releases, and
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
| `xeroctl` | `/usr/bin/xeroctl` | libzstd1, libcurl4, ca-certificates |
| `xerotier-xim-agent` | `/usr/bin/xerotier-xim-agent` | libzmq5, libsodium23, libzstd1 |
| `xerotier-xem-agent` | `/usr/bin/xerotier-xem-agent` | libzmq5, libsodium23, libzstd1, libcurl4, ca-certificates |

## Services

The agent packages install systemd units. Set the join key (and for
XEM the router URL and registration name) in the env file, then enable
the service:

``` shell
sudoedit /etc/xerotier/xim-agent.env
sudo systemctl enable --now xerotier-xim-agent

sudoedit /etc/xerotier/xem-agent.env
sudo systemctl enable --now xerotier-xem-agent
```

Both services run as the `xerotier` system user (created on install)
and keep state under `/var/lib/xerotier`. The agents enroll on first
start using the join key from their env file.

Documentation for running the binaries can be found in the
[docs](https://xerotier.ai/docs/private-agents).
