#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The frontend compiled by itself: the stages of self-hosting, after the
# optimized build (`make build PRESET=release`) and the fork installed into
# the frontend's prefix (`make self` makes both first).
#
#     tools/self.sh [STAGE]
#
# A stage is two programs, run one after the other, each alone: the
# frontend, which compiles compiler/src to a module and its Core, and then
# idris-mlir, which compiles that module to an executable, idris-mlir-front.
# Each half has its own time, its own peak memory and its own limit, and
# the module stays when the pipeline fails: idris-mlir never writes or
# removes a module it is given, so the pipeline half can be run again on
# it by hand. Stage 1's frontend is the one the build made (Idris built
# it; it runs on Chez); stage N's, after it, is the idris-mlir-front stage
# N-1 made. The pipeline is the optimized build's idris-mlir in every
# stage: the self compile is a production compile of the largest program
# the compiler has, and the dev build, which the tests run, is not
# optimized.
#
# Each stage compiles a fresh copy of compiler/src, at the one path
# build/self/src, against the same prefix, so that nothing differs between
# two stages but the frontend, and no TTC one stage wrote is loaded by the
# next. Stage N keeps, in build/self/stageN/:
#   idris-mlir-front.mlirbc, idris-mlir-front.core
#                        the frontend's module and Core
#   frontend-timing      the frontend's phases (its --timing)
#   frontend-stdout, frontend-stderr
#   frontend-kib         the most memory the frontend held resident, in KiB
#   ttc/                 build/self/src/build as the frontend left it: the
#                        TTCs of compiler/src
#   pipeline-stdout, pipeline-stderr
#                        idris-mlir's; the stderr ends with its phases'
#                        times (-mlir-timing)
#   pipeline-kib         the most memory idris-mlir held resident, in KiB
#   idris-mlir-front     the executable
#
# STAGE (default 3) is the last stage made. At 3, stages 2 and 3 must be
# the same, byte for byte: the executable, its module, its Core and every
# TTC. Stage 1 is compared with nothing: its frontend runs on Chez.
#
# `tools/self.sh 1` is the frontend's record on the self compile and then
# the pipeline's on its module, in build/self/stage1 (self-hosting's S1
# and S3).
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

[ -n "$timeout_cmd" ] || { echo "error: $timeout_missing, so a stage could hang" >&2; exit 1; }

# Each half is stopped after its limit, in seconds, so that a half that
# does not end (a translation that grows without bound) cannot hold the
# machine for hours. The frontend's is about five times the 345 s the self
# compile's frontend took on Chez (bench/records/2026-10-17-self-growth.md,
# measured on the typecheck machine), and debt for stages 2 and 3: the
# frontend idris-mlir compiles has never run.
frontend_limit=1800
# The pipeline has never run on the self module, so stage 1's pipeline
# half, the census, runs with no limit (timeout's 0): a run cut short
# records nothing, and a limit is set from what the census measures. The
# later stages' limit is debt until that record exists.
stage1_pipeline_limit=0
pipeline_limit=7200

last=${1:-3}
self=$root/build/self
mkdir -p "$self"

# half NAME LIMIT CMD...: CMD, half NAME of stage $n, under its own
# peak_memory and timeout: stopped after LIMIT seconds and killed 10 s
# later if it has not ended (the grace harness/testutils.sh gives every test
# run). Its output is $out/NAME-stdout and $out/NAME-stderr, the most
# memory it held resident $out/NAME-kib. It prints how it ended; one that
# failed ends the run, with the last 30 lines of its stderr.
half() {
  half_name=$1
  half_limit=$2
  shift 2
  half_started=$(date +%s)
  peak_memory "$out/$half_name-kib" "$timeout_cmd" -k 10 "$half_limit" "$@" \
    > "$out/$half_name-stdout" 2> "$out/$half_name-stderr"
  half_status=$?
  echo "stage $n: $half_name exit $half_status in $(($(date +%s) - half_started)) s, peak $(cat "$out/$half_name-kib" 2> /dev/null) KiB"
  if [ "$half_status" -ne 0 ]; then
    # timeout's status when the limit stopped CMD (124) or, after the
    # grace, killed it (137). A kill from elsewhere (Linux's OOM killer) is
    # 137 too; the seconds on the line above tell the two apart.
    case $half_status in
      124 | 137) echo "timed out after ${half_limit}s" >&2 ;;
    esac
    tail -30 "$out/$half_name-stderr" >&2
    exit 1
  fi
}

# stage N: the frontend on a fresh copy of compiler/src, its TTCs kept,
# then the pipeline on the module it wrote.
stage() {
  n=$1
  out=$self/stage$n
  # Stage 1's frontend is the one input of the chain the run does not
  # make: the build's.
  if [ "$n" -eq 1 ]; then
    front=$self_idris_mlir_front
    limit=$stage1_pipeline_limit
  else
    front=$self/stage$((n - 1))/idris-mlir-front
    limit=$pipeline_limit
  fi
  echo "==> stage $n: ${front#"$root"/}, then ${self_idris_mlir#"$root"/}"
  # The fresh copy, or the run stops: cp -R into a directory that is still
  # there would copy into it, beside what an earlier stage left.
  rm -rf "$out" "$self/src" &&
    mkdir -p "$out" &&
    cp -R "$root/compiler/src" "$self/src" &&
    rm -rf "$self/src/build" &&
    cd "$self/src" || exit 1
  half frontend "$frontend_limit" "$front" --prefix "$checkout_prefix" \
    -p idris-compiler -p idris-mlir-spec -p mlir-hash \
    --timing "$out/frontend-timing" --core "$out/idris-mlir-front.core" \
    -o "$out/idris-mlir-front.mlirbc" IdrisMLIR/Frontend/Driver.idr
  cp -R "$self/src/build" "$out/ttc" || exit 1
  half pipeline "$limit" "$self_idris_mlir" --num-threads="$ncpu" -mlir-timing \
    "$out/idris-mlir-front.mlirbc" -o "$out/idris-mlir-front"
}

n=1
while [ "$n" -le "$last" ]; do
  stage "$n"
  n=$((n + 1))
done

if [ "$last" -ge 3 ]; then
  for artifact in idris-mlir-front idris-mlir-front.mlirbc idris-mlir-front.core; do
    cmp "$self/stage2/$artifact" "$self/stage3/$artifact" ||
      { echo "error: stage 2 and stage 3 differ in $artifact" >&2; exit 1; }
  done
  diff -rq "$self/stage2/ttc" "$self/stage3/ttc" ||
    { echo "error: stage 2 and stage 3 differ in ttc" >&2; exit 1; }
  echo "stage 2 = stage 3: self-hosting holds"
fi
