#!/bin/sh
# Fetches the comparison compilers of the benchmarks (bench/run.sh's Koka
# and Lean 4 columns) into .toolchain/lean and .toolchain/koka. Nothing is
# installed outside .toolchain/ (AGENTS.md).
#
#   bench/toolchains.sh [lean] [koka]     (default: both)
#
# Lean 4 and Koka come from the official GitHub release archives, at pinned
# versions, checked against pinned SHA-256 sums. MLton is already at
# .toolchain/mlton (bench/README.md).
#
# A toolchain whose provenance.json names the pinned version is kept. Each
# one is unpacked into a temporary directory and moved into place only when
# complete, so an interrupted run never leaves a half toolchain.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TC=$ROOT/.toolchain

LEAN_VERSION=4.34.1
LEAN_URL=https://github.com/leanprover/lean4/releases/download/v$LEAN_VERSION/lean-$LEAN_VERSION-linux.zip
LEAN_SHA256=3013aba02bb8bf31b1cf8c9d956d60fb95bb1c10920dfe91abcaa59cb461ddac

KOKA_VERSION=3.2.9
KOKA_URL=https://github.com/koka-lang/koka/releases/download/v$KOKA_VERSION/koka-v$KOKA_VERSION-linux-x64.tar.gz
KOKA_SHA256=310459831a7c6fa6a0cd8e0e02d6b5b3b36441d5e7ce24168bda016cd2e95eee


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
  # Std and Lake libraries. The programs here import only Init, so those
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


mkdir -p "$TC"
[ $# -gt 0 ] || set -- lean koka
for t in "$@"; do
  case $t in
    lean) lean ;;
    koka) koka ;;
    *) die "unknown toolchain $t (lean or koka)" ;;
  esac
done
