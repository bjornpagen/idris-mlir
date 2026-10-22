# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Acceptance is a property of the program, never of the optimizer: a
# transform an optimization makes is an action of MLIR's action framework
# that only makes the code faster or smaller, and skipped it leaves valid
# IR whose behaviour is the same but for the stack and the heap it needs.
# So every program, compiled again from the module the frontend emitted
# with a drawn set of those actions skipped, is accepted again and holds
# every case its test names, and every refused program is refused again by
# the same rule at the same line. A promise's obligation (an in-place
# rebuild, a tail call's jump, a destination) is no action: it is the
# pipeline's, never skippable, so a verdict that rested on an optimization
# shows here as a verdict that changes.
#
# The set is drawn per test from a seed the run takes from the clock, which
# a failure names and IDRIS_MLIR_ACTIONS_SEED replays: each action tag
# (every action the passes take, as idris-mlir-opt names them,
# `--idr-action-tags`) is left whole, skipped whole, or cut after its first
# few actions.
#
# The skipped pipeline runs in idris-mlir-opt, which keeps upstream's debug
# counter (idris-mlir registers none), on one thread, so the counter meets
# the actions in one order and a seed replays: the registered pipeline from
# the stage the module is at (--idr-target, --idr-pipeline), as
# lib/differential.sh lowers a module.
actions_seed=${IDRIS_MLIR_ACTIONS_SEED:-$(date +%s)}

# drawn_skips: idris-mlir-opt's debug counter of the set drawn from
# actions_seed, as one option; nothing when the draw skips nothing.
drawn_skips() {
  ds_tags=$("$idris_mlir_opt" --idr-action-tags) || return 1
  ds_x=$actions_seed
  ds_counter=
  for ds_tag in $ds_tags; do
    ds_x=$(( (ds_x * 1103515245 + 12345) % 2147483648 ))
    case $(( ds_x % 3 )) in
      1) ds_counter="$ds_counter,$ds_tag-count=0" ;;
      2) ds_counter="$ds_counter,$ds_tag-skip=0,$ds_tag-count=$(( (ds_x / 3) % 8 ))" ;;
    esac
  done
  [ -n "$ds_counter" ] && say "--mlir-debug-counter=${ds_counter#,}"
  return 0
}

# skips_hold FIXTURE MODULE [OPTION]...: the program of FIXTURE, whose
# emitted module is MODULE, lowered again from it with the drawn skips
# and OPTION... (its contracts and stage properties, which idris-mlir-opt
# checks as idris-mlir does), then compiled by idris-mlir and linked with
# the checked runtime as the program compiled with none skipped was, is
# accepted, and on every case of FIXTURE ends as that program ended (the
# same status, stdout and stderr, which e2e_case kept in
# $work/case-runs): the cases' own
# expectations are e2e_case's to hold, so a wrong case is named once.
# Nothing when it holds; otherwise the lines of what differs, under one
# naming the seed, and status 1.
skips_hold() {
  sh_fixture=$1
  sh_module=$2
  shift 2
  if ! sh_counter=$(drawn_skips); then
    say "skipped actions: idris-mlir-opt names no action tags"
    return 1
  fi
  rm -rf "$work/skipped"
  mkdir -p "$work/skipped"
  # shellcheck disable=SC2086 # no counter is no argument
  if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$sh_module" --idr-target --idr-pipeline \
         $sh_counter "$@" -o "$work/skipped/lowered.mlir" > "$work/skipped.out" 2> "$work/skipped.err" ||
     ! bounded "$idris_mlir" "$work/skipped/lowered.mlir" "--runtime=$checked_runtime" \
         -o "$work/skipped/prog" > "$work/skipped.out" 2> "$work/skipped.err"; then
    say "skipped actions (IDRIS_MLIR_ACTIONS_SEED=$actions_seed): not accepted again"
    show "$work/skipped.out" "$work/skipped.err"
    return 1
  fi
  [ -d "$sh_fixture/cases" ] || return 0
  sh_differ=
  for sh_case in "$sh_fixture"/cases/*/; do
    sh_case=${sh_case%/}
    sh_name=${sh_case##*/}
    # A case whose ending could not be read never ran, and is named already.
    [ -f "$work/case-runs/$sh_name.status" ] || continue
    sh_stdin=/dev/null
    [ -f "$sh_case/stdin" ] && sh_stdin=$sh_case/stdin
    run_program skipped-run "$work/skipped/prog" "$sh_stdin"
    if [ "$ran" != "$(cat "$work/case-runs/$sh_name.status")" ] ||
       ! cmp -s "$work/skipped-run.out" "$work/case-runs/$sh_name.out" ||
       ! cmp -s "$work/skipped-run.err" "$work/case-runs/$sh_name.err"; then
      sh_differ="$sh_differ $sh_name"
    fi
  done
  [ -z "$sh_differ" ] && return 0
  say "skipped actions (IDRIS_MLIR_ACTIONS_SEED=$actions_seed): cases end otherwise:$sh_differ"
  return 1
}

# skips_refuse FIXTURE MODULE: the refused program of FIXTURE, whose
# emitted module is MODULE (written whatever the verdict, --emitted),
# lowered again from it with the drawn skips, is refused again as its
# header says (Reject.idr), read off the report idris-mlir-opt writes as
# idris-mlir does (--report): a refusal's rule is the diagnostic's data,
# which only the report holds, and a program the skips let through is
# reported accepted. Nothing when it is; otherwise the lines of the
# comparison, under one naming the seed.
skips_refuse() {
  if ! sr_counter=$(drawn_skips); then
    say "skipped actions: idris-mlir-opt names no action tags"
    return
  fi
  # shellcheck disable=SC2086 # no counter is no argument
  bounded "$idris_mlir_opt" --mlir-disable-threading "$2" --idr-target --idr-pipeline $sr_counter \
    "--report=$work/skipped.report" -o "$work/skipped.mlir" > "$work/skipped.out" 2> "$work/skipped.err"
  cat "$work/skipped.out" "$work/skipped.err" > "$work/skipped.all"
  if ! "$runtests" --reject "$1" "$work/skipped.report" "$work/skipped.all" > "$work/skipped.lines"; then
    say "skipped actions (IDRIS_MLIR_ACTIONS_SEED=$actions_seed): not refused alike"
    sed 's/^/  | /' "$work/skipped.lines"
  fi
}
