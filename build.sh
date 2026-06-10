#!/bin/bash
# SPDX-License-Identifier: MIT
# Build .deb packages from the latest stable Xerotier binaries.
#
# Resolves the latest release of Xerotier/binaries, downloads the Linux
# binaries for this host architecture, and packages them with dpkg-deb.
#
# Env:
#   TAG       release tag to package (default: latest stable release)
#   GH_TOKEN  optional GitHub token for API/download requests
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="Xerotier/binaries"
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

for pkg in xeroctl xerotier-xim-agent xerotier-xem-agent; do
  echo "==> ${pkg}-Linux-${ARCH} (${TAG})"
  stage="$WORK/${pkg}_${VERSION}_${DEB_ARCH}"
  rm -rf "$stage"
  mkdir -p "$stage/DEBIAN" "$stage/usr/bin"
  curl -fSL ${AUTH[@]+"${AUTH[@]}"} -o "$stage/usr/bin/$pkg" \
    "https://github.com/${REPO}/releases/download/${TAG}/${pkg}-Linux-${ARCH}"
  chmod 0755 "$stage/usr/bin/$pkg"
  sed -e "s/@VERSION@/${VERSION}/" -e "s/@ARCH@/${DEB_ARCH}/" \
    "$HERE/packages/$pkg/control" > "$stage/DEBIAN/control"
  install -D -m 0644 "$HERE/LICENSE" "$stage/usr/share/doc/$pkg/copyright"

  # Optional systemd unit, env-file template, and maintainer scripts.
  for unit in "$HERE/packages/$pkg"/*.service; do
    [ -f "$unit" ] || continue
    install -D -m 0644 "$unit" "$stage/usr/lib/systemd/system/$(basename "$unit")"
  done
  for envf in "$HERE/packages/$pkg"/*.env; do
    [ -f "$envf" ] || continue
    install -D -m 0644 "$envf" "$stage/etc/xerotier/$(basename "$envf")"
  done
  if [ -d "$stage/etc" ]; then
    (cd "$stage" && find etc -type f | sed 's|^|/|') > "$stage/DEBIAN/conffiles"
  fi
  for script in postinst prerm postrm; do
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
