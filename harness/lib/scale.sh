# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The scale fixtures (harness/Scale.idr) compiled at a size and at twice
# it, and held to the relation between the two. A scale test sources this
# after testutils.sh. The larger fixture's compilation is the longest step
# any test takes, so a scale test gives each step two minutes before
# sourcing testutils.sh; every step is still bounded.

# scale_source FIXTURE: the file the fixture is printed into, by what it
# is: Idris source for the frontend, a module of the dialect otherwise.
scale_source() {
  case $1 in
    nesting-source) say Main.idr ;;
    *) say scale.mlir ;;
  esac
}

# scale_compile FIXTURE FACTOR [OPTION]...: the fixture printed at its size
# times FACTOR and compiled whole with OPTION..., its report and time trace
# beside it in $work/FIXTURE.FACTOR.{report,trace}; the exit in $compiled.
scale_compile() {
  scale_dir=$work/$1.$2
  scale_file=$scale_dir/$(scale_source "$1")
  mkdir -p "$scale_dir"
  if ! bounded "$runtests" --scale-print "$1" "$2" > "$scale_file" 2> "$work/print.err"; then
    say "$1 at factor $2: the fixture is not printed"
    show "$work/print.err"
    compiled=1
    return
  fi
  scale_fixture=$1
  scale_factor=$2
  shift 2
  compile_program "--report=$work/$scale_fixture.$scale_factor.report" \
    "--time-trace=$work/$scale_fixture.$scale_factor.trace" "$@" "$scale_file" scale
}

# scale_relation FIXTURE: compiled at its size and at twice it, both
# accepted, every statistic and zone count at twice the size within the
# relation of its count at the size, each solve's work and each pass's
# footprint read among them (Scale.idr, scaleCheck).
scale_relation() {
  for scale_at in 1 2; do
    scale_compile "$1" "$scale_at"
    if [ "$compiled" -ne 0 ]; then
      say "$1 at factor $scale_at: compile exit $compiled"
      show "$work/compile.out" "$work/compile.err"
      return
    fi
  done
  bounded "$runtests" --scale-check "$work/$1.1.report" "$work/$1.1.trace" \
    "$work/$1.2.report" "$work/$1.2.trace"
}
