#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Profiles one compilation with LLVM's time trace.
#
#     tools/profile.sh [--name NAME] [--] ARGUMENT...
#
# ARGUMENT... are idris-mlir's, as given; it runs in the current directory.
# The idris-mlir is the dev build's (`make build` first), or $IDRIS_MLIR
# when set (a release build's, for timings worth comparing). There is no
# profile build: the trace is the run-time --time-trace every build
# carries, off until asked.
#
# The trace is bench/records/<date>-<commit>-<name>.time-trace.json: the
# UTC time, HEAD (with -dirty when the tree differs from it), and NAME, by
# default the last source argument (.idr, .lidr, .mlir, .mlirbc) without
# its directory and extension, else `compile`. It is Chrome trace JSON:
# open it in Perfetto (ui.perfetto.dev). The twenty entries the
# compilation spent most time in are printed first, the trace's path
# last. The exit status is idris-mlir's, or 1 when no trace was written.
# A trace is not committed (.gitignore); what a measurement found is, as
# a dated record beside it, `bench/records/<date>-<name>.md`.
#
# A trace holds the compilation as one span (`compile`) with the driver's
# phases inside it; a zone for every MLIR pass and analysis, nested and
# dynamic pipelines included, named as -mlir-timing names them, its detail
# the op it ran on; a zone for every pass of LLVM's optimization pipeline
# under `optimize` (the code generator's legacy pipeline is the one span
# `codegen`); and the zones a pass manager runs on its pool threads, each
# thread a track. A `Total <name>` slice sums an entry's runs. Nothing is
# recorded until --time-trace is given: with no trace started a zone is a
# load and a branch, so the build that is profiled is the one shipped.
# The runtime has no zones: it is inlined into every program the
# benchmarks measure, so a program is profiled with the system's sampling
# profiler instead.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

usage() {
  echo "usage: tools/profile.sh [--name NAME] [--] ARGUMENT..." >&2
  exit 2
}

name=
while [ $# -gt 0 ]; do
  case $1 in
    --name) [ $# -ge 2 ] || usage; name=$2; shift 2 ;;
    --name=*) name=${1#--name=}; shift ;;
    --) shift; break ;;
    -h | --help) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage

if [ -z "$name" ]; then
  for argument do
    case $argument in
      -*) ;;
      *.idr | *.lidr | *.mlir | *.mlirbc) name=$argument ;;
    esac
  done
  name=${name##*/}
  name=${name%.*}
fi
name=$(printf '%s' "${name:-compile}" | tr -c 'A-Za-z0-9._-' '-')

compiler=${IDRIS_MLIR:-$idris_mlir}
if [ ! -x "$compiler" ]; then
  echo "error: $compiler is not built; run make build, or set IDRIS_MLIR" >&2
  exit 1
fi

records=$root/bench/records
mkdir -p "$records" || exit 1
commit=$(git -C "$root" rev-parse --short=12 HEAD 2> /dev/null) || commit=unknown
git -C "$root" diff --quiet HEAD -- 2> /dev/null || commit=$commit-dirty
output=$records/$(date -u +%Y-%m-%dT%H%M%SZ)-$commit-$name.time-trace.json

"$compiler" --time-trace="$output" "$@"
status=$?

if [ ! -s "$output" ]; then
  echo "error: no trace was written at $output" >&2
  exit "$([ "$status" -ne 0 ] && echo "$status" || echo 1)"
fi

# The trace's own totals, most time first: name, total milliseconds, and
# how many times it ran.
python3 - "$output" >&2 <<'PY' || true
import json, sys
with open(sys.argv[1]) as f:
    events = json.load(f)["traceEvents"]
totals = [e for e in events if e.get("ph") == "X" and e.get("name", "").startswith("Total ")]
totals.sort(key=lambda e: e.get("dur", 0), reverse=True)
print("top entries by total time:")
for e in totals[:20]:
    count = e.get("args", {}).get("count", "?")
    print(f"  {e['name'][6:]:40} {e.get('dur', 0) / 1000.0:10.2f} ms  x{count}")
PY

echo "$output"
exit "$status"
