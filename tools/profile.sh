#!/bin/sh
# Profiles one compilation with Tracy.
#
#     tools/profile.sh [--memory] [--name NAME] [--] ARGUMENT...
#
# ARGUMENT... are idris-mlir's, as given; it runs in the current directory.
# The idris-mlir is the profile preset's (CMakePresets.json), which this
# builds first: configured into build/profile once, then brought up to date.
# With --memory it is a separate build, build/profile-memory, configured
# with IDRIS_MLIR_PROFILE_MEMORY=ON, whose tools also put every allocation
# on the timeline; that costs every allocation a lock while the capture is
# connected, so a profile of time is taken without it.
#
# Tracy's capture tool starts first and keeps trying to connect to the
# compile, on localhost and a port of this run's (TRACY_PORT), so the
# capture begins as soon as the compile's profiler listens, and a compile
# that is killed or crashes keeps what it sent: the capture saves when the
# connection drops. The compile runs with TRACY_NO_EXIT=1, so it does not
# exit before the capture has every event. Ctrl-C stops the compile; the
# capture still saves.
#
# The capture is bench/profiles/<date>-<commit>-<name>.tracy: the UTC time,
# HEAD (with -dirty when the tree differs from it), and NAME, by default the
# last source argument (.idr, .lidr, .mlir, .mlirbc) without its directory
# and extension, else `compile`.
# Open it with Tracy's profiler of the same release (third_party/tracy).
# The capture's path is printed last. The exit status is idris-mlir's, or 1
# when no capture was saved.
#
# The capture tool is $TRACY_CAPTURE, by default .toolchain/tracy/bin/
# tracy-capture, built from third_party/tracy/capture. IDRIS_MLIR_PROFILE_PORT
# chooses the port.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

usage() {
  echo "usage: tools/profile.sh [--memory] [--name NAME] [--] ARGUMENT..." >&2
  exit 2
}

memory=OFF
name=
while [ $# -gt 0 ]; do
  case $1 in
    --memory) memory=ON; shift ;;
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

capture=${TRACY_CAPTURE:-$toolchain/tracy/bin/tracy-capture}
if [ ! -x "$capture" ]; then
  echo "error: Tracy's capture tool is not at $capture; build it from third_party/tracy/capture (make bootstrap), or set TRACY_CAPTURE" >&2
  exit 1
fi

# The build. Configured once; later runs only bring it up to date, as
# `make build` does for the dev preset.
"$root/tools/verify-pins.sh" cmake ninja llvm sysroot || exit 1
if [ "$memory" = ON ]; then
  build=$root/build/profile-memory
else
  build=$root/build/profile
fi
if [ ! -f "$build/CMakeCache.txt" ]; then
  (cd "$root" && "$cmake" --preset profile -B "$build" \
    "-DIDRIS_MLIR_IDRIS_PREFIX=$checkout_prefix" "-DIDRIS_MLIR_PROFILE_MEMORY=$memory") || exit 1
fi
"$cmake" --build "$build" || exit 1
compiler=$build/foreign/idr/idris-mlir
# idris-mlir runs the frontend beside it, the one `make build` builds.
frontend=$root/compiler/build/exec/idris-mlir-front
if [ -x "$frontend" ]; then
  ln -sfn "$frontend" "$build/foreign/idr/idris-mlir-front"
else
  echo "warning: $frontend is not built (make build); an Idris source cannot be compiled" >&2
fi

profiles=$root/bench/profiles
mkdir -p "$profiles" || exit 1
commit=$(git -C "$root" rev-parse --short=12 HEAD 2> /dev/null) || commit=unknown
git -C "$root" diff --quiet HEAD -- 2> /dev/null || commit=$commit-dirty
output=$profiles/$(date -u +%Y-%m-%dT%H%M%SZ)-$commit-$name.tracy
port=${IDRIS_MLIR_PROFILE_PORT:-$((20000 + $$ % 20000))}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-profile.XXXXXX") || exit 1
log=$scratch/capture.log
capture_pid=
cleanup() {
  [ -n "$capture_pid" ] && kill "$capture_pid" 2> /dev/null
  rm -rf "$scratch"
}
trap cleanup EXIT

# The capture prints its progress over one line; it goes to a log, which
# is shown only when the capture fails.
"$capture" -a 127.0.0.1 -p "$port" -o "$output" > "$log" 2>&1 &
capture_pid=$!

# A trapped signal is not inherited: Ctrl-C stops the compile, and this
# script goes on to wait for the capture to save.
interrupted=0
trap 'interrupted=1' INT TERM
TRACY_NO_EXIT=1 TRACY_PORT=$port "$compiler" "$@"
status=$?
[ "$interrupted" = 1 ] && echo "interrupted: saving what the compile sent" >&2

# A compile that exits normally has waited for the capture to connect; one
# that was stopped or crashed before it did leaves the capture waiting for
# a connection that will not come.
connected() { grep -q 'Timer resolution' "$log"; }
waited=0
while ! connected && kill -0 "$capture_pid" 2> /dev/null && [ "$waited" -lt 5 ]; do
  sleep 1
  waited=$((waited + 1))
done
if ! connected; then
  echo "error: the compile ended before the capture connected (is $compiler a profile build?)" >&2
  exit "$([ "$status" -ne 0 ] && echo "$status" || echo 1)"
fi

# The connection closed when the compile exited; the capture writes the
# file and exits. A signal interrupts wait, not the capture.
while kill -0 "$capture_pid" 2> /dev/null; do
  wait "$capture_pid"
done
capture_pid=

if [ ! -s "$output" ]; then
  tr '\r' '\n' < "$log" >&2
  echo "error: the capture saved nothing at $output" >&2
  exit "$([ "$status" -ne 0 ] && echo "$status" || echo 1)"
fi
tr '\r' '\n' < "$log" | grep -E '^(Frames|Time span|Zones|Trace size)' >&2
echo "$output"
exit "$status"
