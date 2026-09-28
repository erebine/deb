#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# check-license.sh -- build the packages against a fixture release and fail
# unless every one of them carries the release's copyright file.
#
# Why this exists
# ---------------
# Debian policy requires every binary package to ship
# /usr/share/doc/<package>/copyright, and for these packages that file is not
# written here: it is the debian-copyright asset attached to the
# Erebine/binaries release being packaged, a machine-readable DEP-5 file
# generated from the dependency pins that release's binaries were linked
# from. build.sh downloads it, refuses to build without it, and installs it
# into each package. Three lines of shell, each of which can be deleted
# without anything else in this repository noticing, and the result is a
# package that installs a binary with no statement of its terms.
#
# A grep over build.sh would not settle it -- the question is what comes out
# of dpkg-deb, not what the script appears to say. So this check packages a
# fixture release end to end and looks inside the .deb files:
#
#   - every package declared in build.sh is built,
#   - each carries /usr/share/doc/<package>/copyright and THIRD_PARTY_NOTICES
#     at mode 0644,
#   - each of those is byte-identical to the release asset it came from,
#   - and packaging a release that is missing the copyright asset fails,
#     rather than producing a package without one.
#
# Every directory under packages/ must also appear in build.sh's package
# list: a package added to the tree but not to the loop is never built, and a
# package built from a directory that was deleted fails late.
#
# Nothing here touches the network. The fixture release is written to a
# temporary directory and a stand-in `curl` on PATH serves it, so the check
# does not depend on any Erebine/binaries release or tag existing.
#
# Requires: dpkg-deb (present on the Debian and Ubuntu hosts that build
# these packages, and on the CI runner).
#
# Usage
# -----
#   scripts/check-license.sh              # check the repository
#   scripts/check-license.sh --self-test  # prove the check fails on bad input
#
# Exit status: 0 pass, 1 check failed, 2 usage error.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The licensing metadata every package must carry, as <release asset>:<name
# under /usr/share/doc/<package>/>.
REQUIRED_DOCS=("debian-copyright:copyright" "THIRD_PARTY_NOTICES:THIRD_PARTY_NOTICES")

# Writes a stand-in curl into DIR that serves release assets from
# $FIXTURE_RELEASE and 404s on anything else. It understands only the
# argument shapes build.sh uses.
make_curl_shim() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/curl" <<'SHIM'
#!/usr/bin/env bash
set -u
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
src="${FIXTURE_RELEASE}/${url##*/}"
if [ ! -f "$src" ]; then
  echo "curl: (22) The requested URL returned error: 404" >&2
  exit 22
fi
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
SHIM
  chmod +x "$dir/curl"
}

# Writes a fixture Erebine/binaries release into DIR: the two licensing
# assets and a stub binary per package named in the rest of the arguments.
make_fixture_release() {
  local dir="$1" arch pkg
  shift
  arch="$(uname -m)"
  mkdir -p "$dir"
  cat >"$dir/debian-copyright" <<'DEP5'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: erebine
Source: https://github.com/Erebine/binaries

Files: *
Copyright: 2026 Kevin Carter
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction.
DEP5
  cat >"$dir/THIRD_PARTY_NOTICES" <<'TXT'
THIRD-PARTY NOTICES

Fixture notices for the packaging check.
TXT
  for pkg in "$@"; do
    printf '#!/bin/true\nfixture %s\n' "$pkg" >"$dir/${pkg}-Linux-${arch}"
  done
}

# Prints the package names build.sh loops over, one per line.
#   declared_packages BUILD_SH
declared_packages() {
  sed -n 's/^for pkg in \(.*\); do$/\1/p' "$1" | head -1 | tr ' ' '\n' | grep -v '^$'
}

# Copies the packaging into a scratch tree and runs build.sh there against
# FIXTURE, with the curl shim on PATH. Prints build.sh's output and returns
# its exit status. The repository is never written to.
#   run_packaging ROOT STAGE FIXTURE
run_packaging() {
  local root="$1" stage="$2" fixture="$3"
  mkdir -p "$stage"
  cp -r "$root/build.sh" "$root/packages" "$stage/"
  ( cd "$stage" \
    && PATH="$stage/../bin:$PATH" FIXTURE_RELEASE="$fixture" TAG=v9.9.9 \
       bash ./build.sh ) 2>&1
}

# Runs every check under ROOT. Prints one line per check and returns 0 when
# all of them pass.
check_tree() {
  local root="$1" failed=0 tmp pkg

  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "FAIL dpkg-deb is not installed; the packaging check cannot run"
    return 1
  fi

  if [ ! -f "$root/build.sh" ]; then
    echo "FAIL build.sh: missing"
    return 1
  fi

  if [ -s "$root/LICENSE" ]; then
    echo "ok   LICENSE: present and non-empty"
  else
    echo "FAIL LICENSE: missing or empty"
    failed=1
  fi

  # Every packages/ directory must be built, and every built package must
  # have a directory. Either mismatch ships or omits a package silently.
  local declared on_disk
  declared="$(declared_packages "$root/build.sh" | sort)"
  on_disk="$(cd "$root/packages" && ls -d */ 2>/dev/null | sed 's|/$||' | sort)"
  if [ "$declared" = "$on_disk" ]; then
    echo "ok   build.sh: builds every directory under packages/"
  else
    echo "FAIL build.sh: package list and packages/ disagree"
    diff <(printf '%s\n' "$declared") <(printf '%s\n' "$on_disk") \
      | sed 's/^/     /' || true
    failed=1
  fi
  if [ -z "$declared" ]; then
    echo "FAIL build.sh: no package list found"
    return 1
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  make_curl_shim "$tmp/bin"

  # The real packaging, against a fixture release that has everything.
  local fixture="$tmp/release" out
  # shellcheck disable=SC2086
  make_fixture_release "$fixture" $declared
  if ! out="$(run_packaging "$root" "$tmp/stage" "$fixture")"; then
    echo "FAIL packaging a complete release failed"
    printf '%s\n' "$out" | sed 's/^/     /'
    return 1
  fi
  echo "ok   packaging: build.sh completed against a fixture release"

  for pkg in $declared; do
    local deb
    deb="$(find "$tmp/stage/build" -maxdepth 1 -name "${pkg}_*.deb" | head -1)"
    if [ -z "$deb" ]; then
      echo "FAIL $pkg: no .deb was produced"
      failed=1
      continue
    fi
    local entry asset name
    for entry in "${REQUIRED_DOCS[@]}"; do
      asset="${entry%%:*}"
      name="${entry##*:}"
      # grep reads the whole listing. With -q it exits at the first match,
      # dpkg-deb dies of SIGPIPE, and pipefail reports a present file as
      # missing.
      if ! dpkg-deb -c "$deb" \
           | grep -E "^-rw-r--r-- .*\./usr/share/doc/${pkg}/${name}$" >/dev/null; then
        echo "FAIL $pkg: /usr/share/doc/$pkg/$name is missing or not mode 0644"
        dpkg-deb -c "$deb" | grep -F "/usr/share/doc/$pkg/" | sed 's/^/     /' || true
        failed=1
        continue
      fi
      rm -rf "$tmp/x"
      dpkg-deb -x "$deb" "$tmp/x"
      if diff -q "$fixture/$asset" "$tmp/x/usr/share/doc/$pkg/$name" >/dev/null; then
        echo "ok   $pkg: /usr/share/doc/$pkg/$name is the release's $asset"
      else
        echo "FAIL $pkg: /usr/share/doc/$pkg/$name is not the release's $asset"
        failed=1
      fi
    done
  done

  # A release without the copyright asset must fail the build, not produce
  # packages that have no copyright file. This is the guard build.sh states
  # and the README promises.
  local short="$tmp/release-no-copyright"
  cp -r "$fixture" "$short"
  rm -f "$short/debian-copyright"
  rm -rf "$tmp/stage-short"
  if run_packaging "$root" "$tmp/stage-short" "$short" >/dev/null 2>&1; then
    echo "FAIL build.sh packaged a release with no debian-copyright asset"
    failed=1
  elif find "$tmp/stage-short/build" -name '*.deb' 2>/dev/null | grep -q .; then
    echo "FAIL build.sh produced a .deb from a release with no debian-copyright"
    failed=1
  else
    echo "ok   build.sh: refuses a release with no debian-copyright asset"
  fi

  local file
  for file in "$root/build.sh" "$root/README.md" "$root/LICENSE" \
              "$root"/packages/*/control; do
    [ -f "$file" ] || continue
    if LC_ALL=C grep -q '[^[:print:][:space:]]' "$file"; then
      echo "FAIL ${file#"$root"/}: non-ASCII bytes"
      failed=1
    fi
  done

  return "$failed"
}

# Sabotages copies of the repository and proves the check notices. Each case
# is a change someone could plausibly make: the copyright install dropped,
# the notices install dropped, a build that tolerates a release with no
# copyright asset, a package directory left out of the loop, and the file
# installed unreadable.
self_test() {
  local tmp status=0 case_name
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "self-test FAIL dpkg-deb is not installed"
    return 1
  fi

  local good="$tmp/good"
  mkdir -p "$good"
  cp -r "$REPO_ROOT/build.sh" "$REPO_ROOT/packages" "$REPO_ROOT/LICENSE" "$good/"

  if check_tree "$good" >/dev/null; then
    echo "self-test ok   the packaging as it stands passes"
  else
    echo "self-test FAIL the packaging as it stands should pass"
    check_tree "$good" || true
    status=1
  fi

  for case_name in no-copyright-install no-notices-install \
                   tolerates-missing-copyright package-not-in-loop \
                   copyright-not-readable; do
    local bad="$tmp/$case_name"
    cp -r "$good" "$bad"
    case "$case_name" in
      no-copyright-install)
        sed -i '/doc\/\$pkg\/copyright/d' "$bad/build.sh" ;;
      no-notices-install)
        sed -i '/doc\/\$pkg\/THIRD_PARTY_NOTICES/d' "$bad/build.sh" ;;
      tolerates-missing-copyright)
        # Both belts cut at once: the fetch guard no longer exits, and the
        # install no longer fails the build. Cutting only one is not a bad
        # input -- set -e and the failing install stop the build anyway --
        # so the regression worth catching is the package that is produced
        # with no copyright file at all.
        sed -i -e 's/; exit 1; }/; }/' \
               -e 's|\(install -D -m 0644 "$COPYRIGHT" "$stage/usr/share/doc/$pkg/copyright"\)|\1 2>/dev/null \|\| true|' \
               "$bad/build.sh" ;;
      package-not-in-loop)
        mkdir -p "$bad/packages/erebine-extra"
        printf 'Package: erebine-extra\n' >"$bad/packages/erebine-extra/control" ;;
      copyright-not-readable)
        sed -i 's|install -D -m 0644 "$COPYRIGHT"|install -D -m 0600 "$COPYRIGHT"|' \
          "$bad/build.sh" ;;
    esac
    if check_tree "$bad" >/dev/null 2>&1; then
      echo "self-test FAIL $case_name should fail"
      status=1
    else
      echo "self-test ok   $case_name fails"
    fi
  done
  return "$status"
}

case "${1:-}" in
  "") check_tree "$REPO_ROOT" ;;
  --self-test) self_test ;;
  *) echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
