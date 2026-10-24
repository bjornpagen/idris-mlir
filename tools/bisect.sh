#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Finds the action of one tag that changes what a program does.
#
#     tools/bisect.sh SOURCE TAG [STDIN]
#
# SOURCE is the contract text idris-mlir compiles (a .mlir file), or an
# Idris program, which tools/compile.sh compiles first, in a copy of the
# .idr files of its directory, for the text it emits. TAG names a kind of
# action (idr-specialize-clone, idr-raise, or MLIR's own, such as
# apply-pattern). STDIN is the program's input (default: none).
#
# MLIR's debug counter (-mlir-debug-counter=TAG-skip=0,TAG-count=N) lets
# the first N actions of TAG happen and skips the rest, and a skipped action
# leaves the IR as it was. idris-mlir takes no counter, since a skipped
# action changes what is compiled and it has one pipeline; idris-mlir-opt
# runs that pipeline with the counter, and idris-mlir compiles and links the
# module it lowered. Each program compiled so is run, and what it prints
# and its exit status are compared with those of the reference, the
# program compiled with no action of TAG. With every action it must not
# behave as the reference; a binary search finds the N at which it first
# differs: action N changes the program, given the N - 1 before it. That
# action's IR unit, the op it transforms, comes from a compilation that logs
# the actions of TAG (-log-actions-to). Every compilation runs the passes on
# one thread, so the actions of TAG happen in the same order in each and N
# names the same action in all of them.
#
# Every compilation (with its link) and run is bounded by 300 seconds. The
# idris-mlir and idris-mlir-opt it bisects are those `make build` makes.
# idris-mlir-opt, which lowers, prints the op a diagnostic is about;
# idris-mlir prints it only with --mlir-print-op-on-diagnostic. Exit status: 0
# when the action is found; 1 when there is none to find (with every action
# the program behaves as the reference); 2 on a usage error or when the
# reference cannot be built.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

usage() {
  echo "usage: tools/bisect.sh SOURCE TAG [STDIN]" >&2
  exit 2
}

[ $# -ge 2 ] && [ $# -le 3 ] || usage
source=$1
tag=$2
input=${3:-/dev/null}
[ -f "$source" ] || { echo "bisect: $source: no such file" >&2; exit 2; }
[ -r "$input" ] || { echo "bisect: $input: cannot be read" >&2; exit 2; }
case $tag in
  '' | *[!a-z0-9-]*) echo "bisect: $tag is not an action tag" >&2; exit 2 ;;
esac
for tool in "$idris_mlir" "$idris_mlir_opt"; do
  [ -x "$tool" ] || { echo "bisect: no $tool; run make build" >&2; exit 2; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-bisect.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 2' HUP INT TERM

[ -n "$timeout_cmd" ] || { echo "bisect: $timeout_missing" >&2; exit 2; }
bounded() {
  "$timeout_cmd" -k 5 300 "$@"
}

# The contract text: SOURCE, or what tools/compile.sh leaves of the program,
# build/exec/<output>.mlir.
case $source in
  *.mlir) mlir=$(cd "$(dirname "$source")" && pwd)/${source##*/} ;;
  *)
    directory=$(cd "$(dirname "$source")" && pwd)
    mkdir "$work/src" || exit 2
    (cd "$directory" && find . -path ./build -prune -o -type f -name '*.idr' -print) |
      while IFS= read -r file; do
        mkdir -p "$work/src/$(dirname "$file")" && cp "$directory/$file" "$work/src/$file"
      done
    file=${source##*/}
    echo "bisect: compiling $source" >&2
    if ! bounded "$root/tools/compile.sh" "$work/src/$file" "$work/program" > "$work/compile.log" 2>&1; then
      echo "bisect: $source does not compile:" >&2
      sed 's/^/  | /' "$work/compile.log" >&2
      exit 2
    fi
    mlir=$work/src/build/exec/program.mlir
    [ -f "$mlir" ] ||
      { echo "bisect: tools/compile.sh left no contract text for $source" >&2; exit 2; }
    ;;
esac

# outcome NAME FLAG...: the contract text lowered by idris-mlir's pipeline in
# idris-mlir-opt with FLAGs (the counter's), then compiled and linked by
# idris-mlir, which takes a lowered module as it is, run on STDIN; in
# NAME.outcome, its exit status and what it printed, or which tool failed
# and how.
outcome() {
  outcome_name=$1
  shift
  outcome_tool=idris-mlir-opt
  bounded "$idris_mlir_opt" --mlir-disable-threading "$mlir" --idr-pipeline "$@" \
    -o "$work/$outcome_name.lowered.mlir" > "$work/$outcome_name.log" 2>&1
  outcome_status=$?
  if [ "$outcome_status" -eq 0 ]; then
    outcome_tool=idris-mlir
    bounded "$idris_mlir" "$work/$outcome_name.lowered.mlir" -o "$work/$outcome_name" \
      >> "$work/$outcome_name.log" 2>&1
    outcome_status=$?
  fi
  if [ "$outcome_status" -ne 0 ]; then
    printf '%s exits %s: %s\n' "$outcome_tool" "$outcome_status" \
      "$(grep -m 1 'error' "$work/$outcome_name.log")" > "$work/$outcome_name.outcome"
    return
  fi
  bounded "$work/$outcome_name" < "$input" > "$work/$outcome_name.out" 2> /dev/null
  printf 'exit %s\n' "$?" > "$work/$outcome_name.outcome"
  cat "$work/$outcome_name.out" >> "$work/$outcome_name.outcome"
  rm -f "$work/$outcome_name" "$work/$outcome_name.o" "$work/$outcome_name.out" \
    "$work/$outcome_name.lowered.mlir"
}

# same NAME: NAME did what the reference did.
same() {
  cmp -s "$work/$1.outcome" "$work/reference.outcome"
}

# first NAME: the first line of what NAME did.
first() {
  head -n 1 "$work/$1.outcome"
}

counter() {
  printf '%s\n' "-mlir-debug-counter=$tag-skip=0,$tag-count=$1"
}

outcome reference "$(counter 0)"
case $(first reference) in
  exit*) ;;
  *)
    echo "bisect: reference $(first reference); there is no reference" >&2
    sed 's/^/  | /' "$work/reference.log" >&2
    exit 2
    ;;
esac

# Compiled normally, every action happens, and the counter counts them.
outcome all "-mlir-debug-counter=$tag-skip=-1" -mlir-print-debug-counter
total=$(sed -n "s/^$tag *: {\\([0-9][0-9]*\\),.*/\\1/p" "$work/all.log" | tail -n 1)
if [ -z "$total" ]; then
  echo "bisect: idris-mlir-opt reported no count of $tag:" >&2
  sed 's/^/  | /' "$work/all.log" >&2
  exit 2
fi
echo "bisect: $total actions of $tag; with none: $(first reference)"
if same all; then
  echo "bisect: with every action the program does as with none; nothing to find"
  exit 1
fi

# With `good` actions the program does as the reference does, and with `bad`
# it does what bad.outcome holds.
good=0
bad=$total
cp "$work/all.outcome" "$work/bad.outcome"
while [ $((bad - good)) -gt 1 ]; do
  middle=$(((good + bad) / 2))
  outcome probe "$(counter "$middle")"
  if same probe; then
    good=$middle
    echo "bisect: with $middle actions: as with none"
  else
    bad=$middle
    cp "$work/probe.outcome" "$work/bad.outcome"
    echo "bisect: with $middle actions: $(first probe)"
  fi
done

echo "bisect: action $bad of $tag changes the program"
echo "  with the first $good actions: $(first reference)"
echo "  with the first $bad actions: $(first bad)"
diff "$work/reference.outcome" "$work/bad.outcome" | head -n 20 | sed 's/^/  | /'
echo "  reproduce: idris-mlir-opt --mlir-disable-threading $mlir --idr-pipeline \\"
echo "    $(counter "$bad") -o lowered.mlir && idris-mlir lowered.mlir -o program"

# The IR unit of that action: the one op it transforms, in a log of the
# actions of TAG only, each op printed in its function, with its location.
# idris-mlir runs the pipeline idris-mlir-opt ran and narrows the log to one
# tag (--log-actions-tags), which idris-mlir-opt cannot.
bounded "$idris_mlir" --mlir-disable-threading -c "$mlir" -o "$work/logged.o" \
  "-log-actions-to=$work/actions.log" \
  "--log-actions-tags=$tag" -mlir-print-local-scope -mlir-print-debuginfo > "$work/logged.log" 2>&1
echo "action $bad of $tag:"
awk -v n="$bad" '
  /^\[thread [^]]*\] (begins|skipping) / { k++; on = (k == n) }
  /^\[thread [^]]*\] completed / { on = 0 }
  on { print "  " $0 }
' "$work/actions.log"
exit 0
