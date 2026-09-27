#!/bin/sh
# Fetches the comparison toolchains of the memory gate (docs/plan.md 4.4)
# into .toolchain/lean, .toolchain/koka and .toolchain/go. Nothing is
# installed outside .toolchain/ (AGENTS.md).
#
#   bench/gate/toolchains.sh [lean] [koka] [go]     (default: all three)
#
# - Lean 4 and Koka: the official GitHub release archives, at pinned
#   versions, checked against pinned SHA-256 sums.
# - Go: the Ubuntu 24.04 (noble) packages, fetched with `apt-get download`
#   and unpacked with `dpkg -x`; the .deb files are checked against the
#   SHA-256 sums of the archive's package index.
# - MLton is already at .toolchain/mlton (bench/README.md).
#
# A toolchain whose provenance.json names the pinned version is kept. Each
# one is unpacked into a temporary directory and moved into place only when
# complete, so an interrupted run never leaves a half toolchain.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TC=$ROOT/.toolchain

LEAN_VERSION=4.34.1
LEAN_URL=https://github.com/leanprover/lean4/releases/download/v$LEAN_VERSION/lean-$LEAN_VERSION-linux.zip
LEAN_SHA256=3013aba02bb8bf31b1cf8c9d956d60fb95bb1c10920dfe91abcaa59cb461ddac

KOKA_VERSION=3.2.9
KOKA_URL=https://github.com/koka-lang/koka/releases/download/v$KOKA_VERSION/koka-v$KOKA_VERSION-linux-x64.tar.gz
KOKA_SHA256=310459831a7c6fa6a0cd8e0e02d6b5b3b36441d5e7ce24168bda016cd2e95eee

GO_SERIES=1.24
GO_VERSION=1.24.13-2~24.04.1
GO_GO_DEB=golang-$GO_SERIES-go_${GO_VERSION}_amd64.deb
GO_GO_SHA256=424df1cf9aad9486ec0df41302bf4f17253921067ab674b7137331eeeaa2a4bc
GO_SRC_DEB=golang-$GO_SERIES-src_${GO_VERSION}_all.deb
GO_SRC_SHA256=63cf1ea70a853175560358486f000b56fd303b2aa459c4aba4541b8e3a63ae90
# Used only when apt-get download cannot find the pinned version.
GO_POOL=http://archive.ubuntu.com/ubuntu/pool/universe/g/golang-$GO_SERIES

say() { printf 'toolchains.sh: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required and not on PATH"
  done
}

# have NAME VERSION: true when .toolchain/NAME holds VERSION already.
have() {
  [ -f "$TC/$1/provenance.json" ] &&
    grep -q "\"version\": \"$2\"" "$TC/$1/provenance.json"
}

check_sum() { # FILE SHA256
  actual=$(sha256sum "$1" | cut -d' ' -f1)
  [ "$actual" = "$2" ] || die "$1: sha256 $actual, expected $2"
}

fetch() { # URL FILE SHA256
  say "fetching $1"
  curl -sSfL --retry 3 -o "$2" "$1" || die "cannot fetch $1"
  check_sum "$2" "$3"
}

# install NAME STAGED PROVENANCE-JSON: moves STAGED to .toolchain/NAME.
install_dir() {
  printf '%s\n' "$3" > "$2/provenance.json"
  rm -rf "$TC/$1"
  mv "$2" "$TC/$1"
  say "$1 ready in .toolchain/$1"
}

lean() {
  if have lean "$LEAN_VERSION"; then say "lean $LEAN_VERSION present"; return; fi
  need curl unzip sha256sum
  work=$(mktemp -d "$TC/lean.tmp.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  fetch "$LEAN_URL" "$work/lean.zip" "$LEAN_SHA256"
  top=lean-$LEAN_VERSION-linux
  # The archive is 3.3 GB unpacked, 2.9 GB of it .olean files of the Lean,
  # Std and Lake libraries. The gate's programs import only Init, so those
  # are left out; `leanc` still links libLake.a, libStd.a and libLean.a,
  # which are kept.
  (cd "$work" && unzip -q lean.zip -x "$top/lib/lean/Lean/*" "$top/lib/lean/Std/*" \
     "$top/lib/lean/Lake/*" "$top/src/*" "$top/bin/lake" "$top/bin/cadical" \
     "$top/bin/leanchecker")
  rm -f "$work/lean.zip"
  install_dir lean "$work/$top" "{
  \"version\": \"$LEAN_VERSION\",
  \"url\": \"$LEAN_URL\",
  \"sha256\": \"$LEAN_SHA256\",
  \"omitted\": \"lib/lean/{Lean,Std,Lake}/ (.olean files), src/, bin/{lake,cadical,leanchecker}\"
}"
  rm -rf "$work"
  trap - EXIT
}

koka() {
  if have koka "$KOKA_VERSION"; then say "koka $KOKA_VERSION present"; return; fi
  need curl tar sha256sum
  work=$(mktemp -d "$TC/koka.tmp.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  fetch "$KOKA_URL" "$work/koka.tar.gz" "$KOKA_SHA256"
  mkdir "$work/koka"
  tar xzf "$work/koka.tar.gz" -C "$work/koka"
  install_dir koka "$work/koka" "{
  \"version\": \"$KOKA_VERSION\",
  \"url\": \"$KOKA_URL\",
  \"sha256\": \"$KOKA_SHA256\"
}"
  rm -rf "$work"
  trap - EXIT
}

go_toolchain() {
  if have go "$GO_VERSION"; then say "go $GO_VERSION present"; return; fi
  need dpkg sha256sum
  work=$(mktemp -d "$TC/go.tmp.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  for pkg in "golang-$GO_SERIES-go=$GO_VERSION:$GO_GO_DEB:$GO_GO_SHA256" \
             "golang-$GO_SERIES-src=$GO_VERSION:$GO_SRC_DEB:$GO_SRC_SHA256"; do
    spec=${pkg%%:*}; rest=${pkg#*:}; deb=${rest%%:*}; sum=${rest#*:}
    say "apt-get download $spec"
    mkdir "$work/deb"
    if ! (cd "$work/deb" && apt-get download "$spec" >/dev/null 2>&1); then
      need curl
      url=$GO_POOL/$(printf '%s' "$deb" | sed 's/~/%7e/g')
      say "apt-get download failed; fetching $url"
      curl -sSfL --retry 3 -o "$work/deb/$deb" "$url" || die "cannot fetch $url"
    fi
    # apt-get may escape characters of the version in the file name, so the
    # one file it wrote is taken whatever its name.
    set -- "$work"/deb/*.deb
    [ $# -eq 1 ] && [ -f "$1" ] || die "no single .deb for $spec in $work/deb"
    check_sum "$1" "$sum"
    dpkg -x "$1" "$work/go"
    rm -rf "$work/deb"
  done
  [ -x "$work/go/usr/lib/go-$GO_SERIES/bin/go" ] || die "unexpected layout in $GO_GO_DEB"
  install_dir go "$work/go" "{
  \"version\": \"$GO_VERSION\",
  \"packages\": [\"$GO_GO_DEB\", \"$GO_SRC_DEB\"],
  \"sha256\": [\"$GO_GO_SHA256\", \"$GO_SRC_SHA256\"],
  \"goroot\": \"usr/lib/go-$GO_SERIES\"
}"
  rm -rf "$work"
  trap - EXIT
}

mkdir -p "$TC"
[ $# -gt 0 ] || set -- lean koka go
for t in "$@"; do
  case $t in
    lean) lean ;;
    koka) koka ;;
    go) go_toolchain ;;
    *) die "unknown toolchain $t (lean, koka or go)" ;;
  esac
done
