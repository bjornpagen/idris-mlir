#!/bin/sh
# Finds the action of one tag that changes what a program does.
#
#     tools/bisect.sh SOURCE TAG [STDIN]
#
# SOURCE is the contract text idris-mlir-cc compiles (a .mlir file), or an
# Idris program, which tools/compile.sh compiles first, in a copy of the
# .idr files of its directory, for the text it emits. TAG names a kind of
# action (idr-eval-call, idr-specialize-clone, idr-raise, or MLIR's own,
# such as apply-pattern). STDIN is the program's input (default: none).
#
# The reference is the program compiled with --no-eval, which leaves every
# closed call to runtime. MLIR's debug counter
# (-mlir-debug-counter=TAG-skip=0,TAG-count=N) lets the first N actions of
# TAG happen and skips the rest, and a skipped action leaves the IR as it
# was. The program compiled so is run, and what it prints and its exit
# status are compared with the reference's. With no action it must behave
# as the reference, and with every action it must not; a binary search finds
# the N at which it first differs: action N changes the program, given the
# N - 1 before it. That action's IR unit, the op it transforms, comes from a
# compilation that logs the actions of TAG (-log-actions-to).
#
# Every compilation, link and run is bounded by BISECT_LIMIT seconds (300 by
# default). IDRIS_MLIR_CC names the idris-mlir-cc to bisect (by default the
# one `make build` makes), IDRIS_MLIR the idris-mlir that tools/compile.sh
# runs. Exit status: 0 when the action is found; 1 when there is none to
# find (the
# program behaves as the reference, or already differs with no action of
# TAG); 2 on a usage error or when the reference cannot be built.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
idris_mlir_cc=${IDRIS_MLIR_CC:-$idris_mlir_cc}
limit=${BISECT_LIMIT:-300}

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
[ -x "$idris_mlir_cc" ] || { echo "bisect: no $idris_mlir_cc; run make build" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-bisect.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 2' HUP INT TERM

bounded() {
  timeout -k 5 "$limit" "$@"
}

# The contract text: SOURCE, or what tools/compile.sh leaves of the program:
# build/exec/<output>.mlir for an IO program, build/ttc/*/<module>.mlir for
# a `main : Int` one.
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
    if ! bounded env "IDRIS_MLIR=${IDRIS_MLIR:-$root/compiler/build/exec/idris-mlir}" \
        "$root/tools/compile.sh" "$work/src/$file" "$work/program" > "$work/compile.log" 2>&1; then
      echo "bisect: $source does not compile:" >&2
      sed 's/^/  | /' "$work/compile.log" >&2
      exit 2
    fi
    mlir=$work/src/build/exec/program.mlir
    [ -f "$mlir" ] ||
      mlir=$(find "$work/src/build/ttc" -type f -name "${file%.*}.mlir" 2> /dev/null | sort | head -n 1)
    [ -n "$mlir" ] && [ -f "$mlir" ] ||
      { echo "bisect: tools/compile.sh left no contract text for $source" >&2; exit 2; }
    ;;
esac

# outcome NAME FLAG...: the contract text compiled by idris-mlir-cc with
# FLAGs and linked as the -o flow links it, run on STDIN; in NAME.outcome,
# its exit status and what it printed, or how its compilation failed.
outcome() {
  outcome_name=$1
  shift
  bounded "$idris_mlir_cc" "$mlir" -o "$work/$outcome_name.o" "$@" > "$work/$outcome_name.cc" 2>&1
  outcome_status=$?
  if [ "$outcome_status" -ne 0 ]; then
    printf 'idris-mlir-cc exits %s: %s\n' "$outcome_status" \
      "$(grep -m 1 'error' "$work/$outcome_name.cc")" > "$work/$outcome_name.outcome"
    return
  fi
  if ! bounded "$pinned_cc" --target="$("$idris_mlir_cc" --print-target-triple)" -fuse-ld=lld -static-pie \
      -Wl,--gc-sections -Wl,--icf=all "$work/$outcome_name.o" -o "$work/$outcome_name" -lgmp \
      > "$work/$outcome_name.ld" 2>&1; then
    printf 'the link fails\n' > "$work/$outcome_name.outcome"
    return
  fi
  bounded "$work/$outcome_name" < "$input" > "$work/$outcome_name.out" 2> /dev/null
  printf 'exit %s\n' "$?" > "$work/$outcome_name.outcome"
  cat "$work/$outcome_name.out" >> "$work/$outcome_name.outcome"
  rm -f "$work/$outcome_name" "$work/$outcome_name.o" "$work/$outcome_name.out"
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

outcome reference --no-eval
case $(first reference) in
  exit*) ;;
  *)
    echo "bisect: with --no-eval, $(first reference); there is no reference" >&2
    sed 's/^/  | /' "$work/reference.cc" >&2
    exit 2
    ;;
esac

# Compiled normally, every action happens, and the counter counts them.
outcome all "-mlir-debug-counter=$tag-skip=-1" -mlir-print-debug-counter
total=$(sed -n "s/^$tag *: {\\([0-9][0-9]*\\),.*/\\1/p" "$work/all.cc" | tail -n 1)
if [ -z "$total" ]; then
  echo "bisect: idris-mlir-cc reported no count of $tag:" >&2
  sed 's/^/  | /' "$work/all.cc" >&2
  exit 2
fi
echo "bisect: $total actions of $tag; with --no-eval: $(first reference)"
if same all; then
  echo "bisect: with every action the program does as with --no-eval; nothing to find"
  exit 1
fi
outcome none "$(counter 0)"
if ! same none; then
  echo "bisect: with no action of $tag the program already differs ($(first none)); it is not $tag"
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
    echo "bisect: with $middle actions: as with --no-eval"
  else
    bad=$middle
    cp "$work/probe.outcome" "$work/bad.outcome"
    echo "bisect: with $middle actions: $(first probe)"
  fi
done

echo "bisect: action $bad of $tag changes the program"
echo "  with --no-eval, and with the first $good actions: $(first reference)"
echo "  with the first $bad actions: $(first bad)"
diff "$work/reference.outcome" "$work/bad.outcome" | head -n 20 | sed 's/^/  | /'
echo "  reproduce: idris-mlir-cc $mlir -o program.o $(counter "$bad")"

# The IR unit of that action: the one op it transforms, in a log of the
# actions of TAG only, each op printed in its function, with its location.
bounded "$idris_mlir_cc" "$mlir" -o "$work/logged.o" "-log-actions-to=$work/actions.log" \
  "--log-actions-tags=$tag" -mlir-print-local-scope -mlir-print-debuginfo > "$work/logged.cc" 2>&1
echo "action $bad of $tag:"
awk -v n="$bad" '
  /^\[thread [^]]*\] (begins|skipping) / { k++; on = (k == n) }
  /^\[thread [^]]*\] completed / { on = 0 }
  on { print "  " $0 }
' "$work/actions.log"
exit 0
