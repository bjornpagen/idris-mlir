# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# %differential, the dialect tests' oracle for what a module means: two
# modules' programs, each compiled from its own stage, run on the same
# inputs, and held to agree (lit_differential).

# lit_lowered MODULE NAME [COUNTER]: MODULE linked into the program
# $work/differential.NAME/prog, as idris-mlir compiles a module from the
# stage its program is at: the registered pipeline from that stage, which
# the tool reads off the program (--idr-pipeline), then idris-mlir, which
# takes a module of the LLVM dialect alone to LLVM as it is, linked with
# the checked runtime. COUNTER, when given, is MLIR's debug counter over
# the actions the pipeline's passes take. Status 1, and lines that say
# why, when a step fails.
lit_lowered() {
  ll_dir=$work/differential.$2
  mkdir -p "$ll_dir"
  # shellcheck disable=SC2086 # no counter is no argument
  if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$1" --idr-target --idr-pipeline ${3:+"$3"} \
         -o "$ll_dir/lowered.mlir" > "$work/differential.log" 2>&1; then
    say "differential: ${1##*/} does not lower"
    show "$work/differential.log"
    return 1
  fi
  if ! bounded "$idris_mlir" --num-threads=1 -c "$ll_dir/lowered.mlir" -o "$ll_dir/prog.o" \
         > "$work/differential.log" 2>&1 ||
     ! link_program "$ll_dir/prog.o" -o "$ll_dir/prog" "$checked_runtime" > "$work/differential.log" 2>&1; then
    say "differential: ${1##*/} does not compile"
    show "$work/differential.log"
    return 1
  fi
}

# The debug counter that skips every action of every optimization: an
# optimization's transforms only make code faster or smaller, so with all
# of them skipped the program is the reference the optimized one must
# agree with, sharing with it only the passes the pipeline needs. The
# tags are every action's the passes take, as idris-mlir-opt names them
# (`--idr-action-tags`).
lit_unoptimized_counter() {
  luc_tags=$("$idris_mlir_opt" --idr-action-tags) || return 1
  luc_counter=
  for luc_tag in $luc_tags; do luc_counter="$luc_counter,$luc_tag-count=0"; done
  [ -n "$luc_counter" ] && say "--mlir-debug-counter=${luc_counter#,}"
}

# lit_differential_inputs DIR: the inputs %differential runs both programs
# on, one file each in DIR, and DIR/list naming them in order, each with
# how a failure names it: the fixture's own, when it declares them, one
# per `// STDIN: <text>` line, the input being <text> with the escapes
# printf's %b reads (\n, \\, \0NNN); otherwise the empty input and then
# every one-byte input, 0x00 to 0xff.
lit_differential_inputs() {
  mkdir "$1"
  : > "$1/list"
  if grep -q '^[[:space:]]*//[[:space:]]*STDIN:' "$lit_file"; then
    ldi_n=0
    sed -n 's/^[[:space:]]*\/\/[[:space:]]*STDIN:[[:space:]]\{0,1\}//p' "$lit_file" |
      while IFS= read -r ldi_text; do
        ldi_n=$((ldi_n + 1))
        printf '%b' "$ldi_text" > "$1/$ldi_n"
        printf '%s\t%s\n' "$ldi_n" "'$ldi_text'" >> "$1/list"
      done
  else
    : > "$1/empty"
    printf 'empty\tthe empty input\n' >> "$1/list"
    ldi_byte=0
    while [ "$ldi_byte" -le 255 ]; do
      ldi_hex=$(printf '%02x' "$ldi_byte")
      # shellcheck disable=SC2059 # the format is the byte's octal escape
      printf "\\$(printf '%03o' "$ldi_byte")" > "$1/$ldi_hex"
      printf '%s\tthe byte 0x%s\n' "$ldi_hex" "$ldi_hex" >> "$1/list"
      ldi_byte=$((ldi_byte + 1))
    done
  fi
}

# lit_differential BEFORE AFTER (`%differential BEFORE AFTER`): the
# programs of the modules BEFORE and AFTER mean the same: on every input
# (lit_differential_inputs) both end alike, the same status, the same
# stdout and the same stderr, so two crashes of different causes or sites
# differ, and a run that leaks a cell ends as the checked runtime's
# internal error, which differs from a clean return. BEFORE is lowered with
# every optimization's actions skipped (lit_unoptimized_counter), so the
# reference shares no optimization with the program under test; AFTER as
# the pipeline lowers it. A pass that changes what the program does fails
# on the first input where they differ, which is named: `differential:
# BEFORE and AFTER differ on <input>`, on stderr, with both outcomes. Both
# programs are named `prog`, so the runtime's lines name them alike.
lit_differential() {
  if [ "$#" -ne 2 ]; then
    say "differential: takes two modules, not $#" >&2
    return 2
  fi
  [ -d "$work/differential.in" ] || lit_differential_inputs "$work/differential.in"
  for ld_side in before after; do
    rm -rf "$work/differential.$ld_side" "$work/differential.$ld_side.runs"
    mkdir "$work/differential.$ld_side.runs"
  done
  if ! ld_counter=$(lit_unoptimized_counter); then
    say "differential: idris-mlir-opt names no action tags" >&2
    return 1
  fi
  lit_lowered "$1" before "$ld_counter" >&2 || return 1
  lit_lowered "$2" after >&2 || return 1
  for ld_side in before after; do
    # One bound for every run of a program: each is a process of a few
    # milliseconds, and a hang on any input ends them all.
    if ! bounded sh -c '
        while IFS="	" read -r name what; do
          "$2" < "$1/$name" > "$3/$name.out" 2> "$3/$name.err"
          echo "$?" > "$3/$name.status"
        done < "$1/list"' sh "$work/differential.in" "$work/differential.$ld_side/prog" \
        "$work/differential.$ld_side.runs" 2>&1; then
      say "differential: the program of ${1##*/} or ${2##*/} did not end on every input" >&2
      return 1
    fi
  done
  while IFS='	' read -r ld_name ld_what; do
    ld_b=$work/differential.before.runs/$ld_name
    ld_a=$work/differential.after.runs/$ld_name
    if ! cmp -s "$ld_b.status" "$ld_a.status" || ! cmp -s "$ld_b.out" "$ld_a.out" ||
       ! cmp -s "$ld_b.err" "$ld_a.err"; then
      {
        say "differential: ${1##*/} and ${2##*/} differ on $ld_what"
        for ld_run in "$ld_b:$1" "$ld_a:$2"; do
          ld_module=${ld_run#*:}
          say "  | ${ld_module##*/}: exit $(cat "${ld_run%%:*}.status"), stdout and stderr:"
          head -c 400 "${ld_run%%:*}.out" | awk '{ print "  |   " $0 }'
          head -c 400 "${ld_run%%:*}.err" | awk '{ print "  |   ! " $0 }'
        done
      } >&2
      return 1
    fi
  done < "$work/differential.in/list"
}
