# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, and nothing
# compiles it a second time: a compile is seconds, and there are hundreds
# of fixtures. What holds of each pass, that it keeps the quantities Idris
# proved and the rest of its contracts, and the promises every compiled
# program keeps (its tail calls jumps, its cycles on frame stacks, its
# in-place rebuilds made, its frames limited), the compilation checks as
# the pass runs (--idr-contracts), and its verifier after every pass; what
# is checked here is what it left. universal prints them as one line.

# universal FIXTURE MODULE OPTIONS OBJECT...: what holds of every
# compilation, as one line: every function of the emitted module MODULE is
# reached from its root (reached); the objects OBJECT... import nothing a
# program may not (object_imports); and the program, compiled again from
# MODULE with a drawn set of the optimizations' actions skipped and the
# options OPTIONS (one per line, in that file), is accepted and holds its
# cases again (skips_hold). One line, `universal: holds`, when all hold;
# otherwise the lines of the checks, and status 1. A check added to every
# compilation is added here, and no transcript changes.
universal() {
  u_fixture=$1
  u_module=$2
  u_options=$3
  shift 3
  u_failed=
  reached "$u_module" > "$work/universal.log" 2>&1 || u_failed=yes
  object_imports "$@" >> "$work/universal.log" || u_failed=yes
  # shellcheck disable=SC2046 # one option per line, none with a space
  skips_hold "$u_fixture" "$u_module" $(cat "$u_options") >> "$work/universal.log" || u_failed=yes
  if [ -n "$u_failed" ]; then
    cat "$work/universal.log"
    return 1
  fi
  say "universal: holds"
}

# reached MODULE: every function of the emitted module MODULE is reached
# from its root by the symbols the functions reached before it name, so
# the frontend writes no function the program never calls; idr-expect's
# errors, one line for each function that is not, on its output.
reached() {
  bounded "$idris_mlir_opt" --mlir-disable-threading "$1" --idr-expect=holds=reached -o /dev/null
}
