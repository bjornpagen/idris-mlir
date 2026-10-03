#!/bin/sh
# Fetches the comparison compilers of the benchmarks (bench/run.sh's MLton,
# Koka and Lean 4 columns) into .toolchain/mlton, .toolchain/koka and
# .toolchain/lean. Nothing is installed outside .toolchain/ (AGENTS.md).
#
#   bench/toolchains.sh [lean] [koka] [mlton]     (default: all three)
#
# Lean 4 and Koka come from the official GitHub release archives, at pinned
# versions, for the host (x86-64 Linux, arm64 macOS), checked against
# pinned SHA-256 sums. MLton on x86-64 Linux is Ubuntu's (Debian's) package
# of a pinned version, checked against its archive's SHA-256 sums and
# unpacked as dpkg would install it; it compiles with the host's gcc and
# GMP (libgmp-dev). MLton publishes no arm64 macOS release archive, so there
# it is Homebrew's (`brew install mlton`), which bench/run.sh finds on PATH;
# `mlton` here checks that it is there.
#
# A toolchain whose provenance.json names the pinned archive is kept. Each
# one is unpacked into a temporary directory and moved into place only when
# complete, so an interrupted run never leaves a half toolchain.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TC=$ROOT/.toolchain
. "$ROOT/tools/host.sh"

say() { printf 'toolchains.sh: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

LEAN_VERSION=4.34.1
KOKA_VERSION=3.2.9
MLTON_VERSION=20210117+dfsg-3
MLTON_POOL=http://archive.ubuntu.com/ubuntu/pool/universe/m/mlton

# The archives for the host, which runs what they hold.
host=$(uname -s)-$(uname -m)
case $host in
  Linux-x86_64)
    LEAN_PLATFORM=linux
    LEAN_SHA256=3013aba02bb8bf31b1cf8c9d956d60fb95bb1c10920dfe91abcaa59cb461ddac
    KOKA_PLATFORM=linux-x64
    KOKA_SHA256=310459831a7c6fa6a0cd8e0e02d6b5b3b36441d5e7ce24168bda016cd2e95eee
    # The packages that hold MLton's files (the `mlton` package itself is
    # only their dependencies), each with its SHA-256.
    MLTON_DEBS="mlton-basis_${MLTON_VERSION}_amd64.deb ded03a2da1bd879aac5f33fa7df956e3ec4ba52b1280bb067c522db635c0eb2e
mlton-compiler_${MLTON_VERSION}_amd64.deb 9e62f2ce17855e1ff2896f236c1b43b297403fafba50ff1fdec6dc81fba60795
mlton-runtime-x86-64-linux-gnu_${MLTON_VERSION}_amd64.deb 4ea8bb535bb3c3dd3ab78b3c795ddc93bd8fffe95fe58ded17ea79076b13a066"
    ;;
  Darwin-arm64)
    LEAN_PLATFORM=darwin_aarch64
    LEAN_SHA256=9019fcd34e93fddf0ecf9d40d28f05a86ba563ac3b701a9c5116ce1c96379360
    KOKA_PLATFORM=macos-arm64
    KOKA_SHA256=b71fe2237b5f6b11116e296497b9756136a6d2a2514dcbf022aa9f620f04c088
    MLTON_DEBS=
    ;;
  *) die "no pinned Lean, Koka or MLton for $host (x86_64 Linux or arm64 macOS)" ;;
esac
LEAN_TOP=lean-$LEAN_VERSION-$LEAN_PLATFORM
LEAN_URL=https://github.com/leanprover/lean4/releases/download/v$LEAN_VERSION/$LEAN_TOP.zip
KOKA_URL=https://github.com/koka-lang/koka/releases/download/v$KOKA_VERSION/koka-v$KOKA_VERSION-$KOKA_PLATFORM.tar.gz

need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required and not on PATH"
  done
}

# have NAME VERSION URL: true when .toolchain/NAME holds VERSION from URL
# already (the host's archive, not another host's).
have() {
  [ -f "$TC/$1/provenance.json" ] &&
    grep -qF "\"version\": \"$2\"" "$TC/$1/provenance.json" &&
    grep -qF "\"url\": \"$3\"" "$TC/$1/provenance.json"
}

check_sum() { # FILE SHA256
  actual=$(sha256 "$1" | cut -d' ' -f1)
  [ -n "$actual" ] || die "$1: no SHA-256"
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

step_lean() {
  if have lean "$LEAN_VERSION" "$LEAN_URL"; then say "lean $LEAN_VERSION present"; return; fi
  need curl unzip
  work=$(mktemp -d "$TC/lean.tmp.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  fetch "$LEAN_URL" "$work/lean.zip" "$LEAN_SHA256"
  top=$LEAN_TOP
  # The archive is about 3 GB unpacked, most of it .olean files of the
  # Lean, Std and Lake libraries. The programs here import only Init, so
  # those are left out; `leanc` still links libLake.a, libStd.a and
  # libLean.a, which are kept.
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

step_koka() {
  if have koka "$KOKA_VERSION" "$KOKA_URL"; then say "koka $KOKA_VERSION present"; return; fi
  need curl tar
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

step_mlton() {
  if [ -z "$MLTON_DEBS" ]; then
    command -v mlton > /dev/null 2>&1 ||
      die "mlton is not on PATH; on macOS it comes from Homebrew: brew install mlton"
    say "mlton from PATH: $(command -v mlton) ($(mlton 2>&1 | head -n 1))"
    return
  fi
  if have mlton "$MLTON_VERSION" "$MLTON_POOL"; then say "mlton $MLTON_VERSION present"; return; fi
  need curl dpkg-deb
  work=$(mktemp -d "$TC/mlton.tmp.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/mlton"
  printf '%s\n' "$MLTON_DEBS" | while read -r deb sum; do
    fetch "$MLTON_POOL/$deb" "$work/$deb" "$sum"
    dpkg-deb -x "$work/$deb" "$work/mlton"
    rm -f "$work/$deb"
  done
  [ -x "$work/mlton/usr/bin/mlton" ] || die "the MLton packages hold no usr/bin/mlton"
  install_dir mlton "$work/mlton" "{
  \"version\": \"$MLTON_VERSION\",
  \"url\": \"$MLTON_POOL\",
  \"packages\": \"$(printf '%s\n' "$MLTON_DEBS" | awk '{ printf "%s%s %s", sep, $1, $2; sep = ", " }')\"
}"
  rm -rf "$work"
  trap - EXIT
}


mkdir -p "$TC"
[ $# -gt 0 ] || set -- lean koka mlton
for t in "$@"; do
  case $t in
    lean) step_lean ;;
    koka) step_koka ;;
    mlton) step_mlton ;;
    *) die "unknown toolchain $t (lean, koka or mlton)" ;;
  esac
done
