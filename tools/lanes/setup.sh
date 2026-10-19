#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# tools/lanes/setup.sh LANE: a clone of idris-mlir on main for one lane of
# parallel work (tools/lanes/README.md), at ../idris-mlir-lanes/LANE beside
# this checkout, sharing this checkout's toolchain (.toolchain, linked) and
# its submodules' objects. No branches: the clone commits on main and
# pushes to origin main, after git pull --rebase. Run again, it brings the
# clone up to date.
set -e
main=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
lanes=$(dirname "$main")/idris-mlir-lanes
[ -n "$1" ] || { echo "usage: tools/lanes/setup.sh LANE" >&2; exit 2; }
dir=$lanes/$1
if [ ! -d "$dir/.git" ]; then
  mkdir -p "$lanes"
  git clone -q "$(git -C "$main" remote get-url origin)" "$dir"
fi
cd "$dir"
git checkout -q main
git pull -q --rebase origin main
[ -e .toolchain ] || ln -s "$main/.toolchain" .toolchain
for path in third_party/Idris2 third_party/gmp third_party/simdutf third_party/fast_float third_party/snmalloc third_party/ryu; do
  git config "submodule.$path.url" "$main/$path"
done
git -c protocol.file.allow=always submodule update --init -q third_party/Idris2 third_party/gmp third_party/simdutf third_party/fast_float third_party/snmalloc third_party/ryu
git config user.name "$(git -C "$main" config user.name)"
git config user.email "$(git -C "$main" config user.email)"
echo "lane $1 ready at $dir"
