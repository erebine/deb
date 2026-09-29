#!/bin/bash
# SPDX-License-Identifier: MIT
# Build .deb packages from the latest stable Erebine binaries.
#
# Resolves the latest release of Erebine/binaries, downloads the Linux
# binaries for this host architecture, and packages them with dpkg-deb.
#
# Env:
#   TAG       release tag to package (default: latest stable release)
#   GH_TOKEN  optional GitHub token for API/download requests
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="Erebine/binaries"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) DEB_ARCH=amd64 ;;
  aarch64) DEB_ARCH=arm64 ;;
  *) echo "unsupported architecture: $ARCH"; exit 1 ;;
esac

AUTH=()
[ -n "${GH_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")

if [ -z "${TAG:-}" ]; then
  TAG="$(curl -fsSL ${AUTH[@]+"${AUTH[@]}"} \
    "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "$TAG" ] || { echo "could not resolve the latest release tag"; exit 1; }
VERSION="${TAG#v}"

WORK="$HERE/build"
mkdir -p "$WORK"

# The release's generated licensing metadata, installed into every package:
# debian-copyright is the machine-readable DEP-5 copyright file Erebine/platform
# generates from the dependency pins THIS tag's binaries were linked from, and
# THIRD_PARTY_NOTICES is the notices text its header refers to. Both are
# attached to every release beside the binaries, so the packaged copyright can
# never describe a different dependency set than the binary it ships with.
# Releases cut before the licensing change carry neither; packaging one fails
# here rather than producing a package with no copyright file.
COPYRIGHT="$WORK/debian-copyright"
NOTICES="$WORK/THIRD_PARTY_NOTICES"
for asset in debian-copyright THIRD_PARTY_NOTICES; do
  curl -fSL ${AUTH[@]+"${AUTH[@]}"} -o "$WORK/$asset" \
    "https://github.com/${REPO}/releases/download/${TAG}/${asset}" \
    || { echo "release ${TAG} has no ${asset} asset: it predates the generated"; \
         echo "licensing metadata. Package a release that carries it."; exit 1; }
done

for pkg in erectl erebine-eim-agent erebine-eem-agent; do
  echo "==> ${pkg}-Linux-${ARCH} (${TAG})"
  stage="$WORK/${pkg}_${VERSION}_${DEB_ARCH}"
  rm -rf "$stage"
  mkdir -p "$stage/DEBIAN" "$stage/usr/bin"
  curl -fSL ${AUTH[@]+"${AUTH[@]}"} -o "$stage/usr/bin/$pkg" \
    "https://github.com/${REPO}/releases/download/${TAG}/${pkg}-Linux-${ARCH}"
  chmod 0755 "$stage/usr/bin/$pkg"
  sed -e "s/@VERSION@/${VERSION}/" -e "s/@ARCH@/${DEB_ARCH}/" \
    "$HERE/packages/$pkg/control" > "$stage/DEBIAN/control"
  install -D -m 0644 "$COPYRIGHT" "$stage/usr/share/doc/$pkg/copyright"
  install -D -m 0644 "$NOTICES" "$stage/usr/share/doc/$pkg/THIRD_PARTY_NOTICES"

  # Optional systemd unit, env-file template, and maintainer scripts.
  for unit in "$HERE/packages/$pkg"/*.service; do
    [ -f "$unit" ] || continue
    install -D -m 0644 "$unit" "$stage/usr/lib/systemd/system/$(basename "$unit")"
  done
  for envf in "$HERE/packages/$pkg"/*.env; do
    [ -f "$envf" ] || continue
    install -D -m 0644 "$envf" "$stage/etc/erebine/$(basename "$envf")"
  done
  if [ -d "$stage/etc" ]; then
    (cd "$stage" && find etc -type f | sed 's|^|/|') > "$stage/DEBIAN/conffiles"
  fi
  for script in preinst postinst prerm postrm; do
    if [ -f "$HERE/packages/$pkg/$script" ]; then
      install -m 0755 "$HERE/packages/$pkg/$script" "$stage/DEBIAN/$script"
    fi
  done

  dpkg-deb --build --root-owner-group "$stage" \
    "$WORK/${pkg}_${VERSION}_${DEB_ARCH}.deb"
  rm -rf "$stage"
done

echo "==> packages:"
ls "$WORK"/*.deb
