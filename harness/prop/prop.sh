# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The runtime's property programs (prop.h): each is built as a program is
# linked, with no C++ library, and runs with its report (the classes of
# the cases each property drew) in the test's work directory, never in its
# transcript or in the tree. A run script sources this after testutils.sh:
#
#     . "$root/harness/prop/prop.sh"

# prop_build SOURCE OUTPUT: the property program SOURCE, compiled against
# prop.h and compiler-rt's FuzzedDataProvider and linked with the runtime
# archive the build made, as link_program links a program; the compiler's
# output in $work/prop-cc.log. Says OUTPUT's name and `built`, or `does not
# build` and the log; status 0 when built.
prop_build() {
  if runtime_c link_program -std=c++2c -fno-exceptions -fno-rtti -O1 \
      -I"$root/harness/prop" -I"$toolchain/llvm-project/compiler-rt/include" \
      "$1" "$dev_prefix/runtime/libidris_rt.a" -o "$2" > "$work/prop-cc.log" 2>&1; then
    say "${2##*/}: built"
  else
    say "${2##*/}: does not build"
    show "$work/prop-cc.log"
    return 1
  fi
}

# prop_run PROGRAM ARG...: PROGRAM with ARG... on this run's seed
# (prop_seed), bounded, writing its report to the work directory
# ($work/report), then again with --mutants (prop.h): each check with its
# own mutant planted. Prints each run's stdout as it is, each line of its
# stderr as `  stderr | <line>`, then PROGRAM's name and its exit status;
# when either run failed, the seed, and how the test replays it.
prop_run() {
  if ! prop_run_seed=$(prop_seed); then
    say "${1##*/}: no seed: /dev/urandom does not read"
    return 1
  fi
  bounded "$@" --seed "$prop_run_seed" --report "$work/report" > "$work/prop-run.out" 2> "$work/prop-run.err"
  prop_run_status=$?
  cat "$work/prop-run.out"
  sed 's/^/  stderr | /' "$work/prop-run.err"
  say "${1##*/}: exit $prop_run_status"
  bounded "$@" --seed "$prop_run_seed" --mutants > "$work/prop-mutants.out" 2> "$work/prop-mutants.err"
  prop_mutants_status=$?
  cat "$work/prop-mutants.out"
  sed 's/^/  stderr | /' "$work/prop-mutants.err"
  say "${1##*/} --mutants: exit $prop_mutants_status"
  if [ "$prop_run_status" -ne 0 ] || [ "$prop_mutants_status" -ne 0 ]; then
    say "  | seed $prop_run_seed: IDRIS_PROP_SEED=$prop_run_seed make test only=${here##*/} replays this run"
  fi
}

# prop_seed: the seed of this run, IDRIS_PROP_SEED when it is set (a
# failure's replay), else 64 fresh bits from /dev/urandom, so that each run
# draws cases no run before it drew; the transcript of a run that holds
# names no seed.
prop_seed() {
  if [ -n "${IDRIS_PROP_SEED:-}" ]; then
    printf '%s\n' "$IDRIS_PROP_SEED"
  else
    prop_seed_bits=$(od -An -N8 -tu8 /dev/urandom) || return 1
    printf '%s\n' $prop_seed_bits
  fi
}
