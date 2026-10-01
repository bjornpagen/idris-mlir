# Determinism: the same program compiles to the same bytes.

# determinism FLOW FIXTURE: two compilations of the fixture give
# byte-identical .core, .mlir, object and executable, and dump the same
# module after every step of the pipeline. FLOW is `v0`, a `main : Int`
# program in Prog.idr, or `io`, an IO program in Main.idr with the
# installed packages its `packages` names.
determinism() {
  mkdir "$work/det"
  copy_fixture "$2" "$work/det"
  det_packages=
  if [ -f "$2/packages" ]; then
    for det_package in $(cat "$2/packages"); do det_packages="$det_packages -p $det_package"; done
  fi
  for det_round in 1 2; do
    rm -rf "$work/det/build"
    if [ "$1" = v0 ]; then
      compile_program --int --directive dump-mlir "$work/det/Prog.idr" "$work/det/build/exec/Prog"
      det_core=$(find "$work/det/build" -type f -name Prog.core | sort | head -n 1)
      det_mlir=$(find "$work/det/build" -type f -name Prog.mlir | sort | head -n 1)
      det_object=$work/det/build/exec/Prog.o
      det_executable=$work/det/build/exec/Prog
      det_dumps=$work/det/build/exec/Prog.dump
    else
      # shellcheck disable=SC2086 # the packages are words
      compile_program --io $det_packages --directive dump-mlir "$work/det/Main.idr" prog
      det_core=$work/det/build/exec/prog.core
      det_mlir=$work/det/build/exec/prog.mlir
      det_object=$work/det/build/exec/prog.o
      det_executable=$work/det/build/exec/prog
      det_dumps=$work/det/build/exec/prog.dump
    fi
    say "compile $det_round: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      return
    fi
    mkdir "$work/round$det_round" "$work/round$det_round/dumps"
    cp "$det_core" "$work/round$det_round/core" 2> /dev/null
    cp "$det_mlir" "$work/round$det_round/mlir" 2> /dev/null
    cp "$det_object" "$work/round$det_round/object" 2> /dev/null
    cp "$det_executable" "$work/round$det_round/executable" 2> /dev/null
    cp "$det_dumps"/[0-9]*-*.mlir "$work/round$det_round/dumps/" 2> /dev/null
  done
  for det_kind in core mlir object executable; do
    if [ ! -f "$work/round1/$det_kind" ] || [ ! -f "$work/round2/$det_kind" ]; then
      say "$det_kind: missing"
    elif cmp -s "$work/round1/$det_kind" "$work/round2/$det_kind"; then
      say "$det_kind: identical"
    else
      say "$det_kind: differs between two compilations"
    fi
  done
  det_differ=
  det_count=0
  for det_name in $( (ls "$work/round1/dumps"; ls "$work/round2/dumps") | sort -u); do
    det_count=$((det_count + 1))
    cmp -s "$work/round1/dumps/$det_name" "$work/round2/dumps/$det_name" || det_differ="$det_differ $det_name"
  done
  if [ "$det_count" -eq 0 ]; then
    say "dumps: none"
  elif [ -n "$det_differ" ]; then
    say "dumps: differ between two compilations:$det_differ"
  else
    say "dumps: identical after every step"
  fi
}
