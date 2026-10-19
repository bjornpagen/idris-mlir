# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# %differential, the dialect tests' oracle for what a module means: two
# modules' programs, each compiled from its own stage, run on the same
# inputs, and held to agree (lit_differential).

# lit_pipeline_from STAGE: idris-mlir's pipeline, as --pass-pipeline reads
# it, for a program at STAGE: idr-target, then every step after the one
# that leaves a program at STAGE (IdrPassStages.txt names it, the pass
# whose `sets` is STAGE and whose `requires` is not), as idris-mlir would
# run them on the program it was handed; at `higher`, which no step makes,
# the whole pipeline. Read from the registered pipeline as idris-mlir-opt
# prints it (--dump-pass-pipeline) and from the passes' stages, so it
# follows both. Nothing, and status 1, when either cannot be read.
lit_pipeline_from() {
  lpf_stages=$dev_prefix/foreign/idr/include/idr/IR/IdrPassStages.txt
  [ -f "$lpf_stages" ] || { say "differential: no $lpf_stages, which the build writes"; return 1; }
  if [ ! -f "$work/differential.pipeline" ]; then
    # The dump is printed before the passes run; on an empty module the
    # first step that needs a program then fails, which is no matter here.
    printf 'module {}\n' > "$work/differential.empty.mlir"
    bounded "$idris_mlir_opt" --mlir-disable-threading "$work/differential.empty.mlir" \
      --idr-target --idr-pipeline --dump-pass-pipeline -o /dev/null 2> "$work/differential.dump" > /dev/null
    sed -n '/^Pass Manager with/,/^)$/p' "$work/differential.dump" | sed 1d > "$work/differential.pipeline"
    [ -s "$work/differential.pipeline" ] || { say "differential: idris-mlir-opt printed no pipeline"; show "$work/differential.dump"; return 1; }
  fi
  lpf_from=$(awk -v stage="$1" '
    tolower($2) == stage && tolower($1) != stage { print $3 }' "$lpf_stages")
  # Each nest is kept with the steps kept in it, and left out when none
  # is: a pipeline's text has no empty nest.
  awk -v from="$lpf_from" '
    function add(text, d) { body[d] = body[d] (count[d] ? "," : "") text; count[d]++ }
    BEGIN { depth = 0; count[0] = 0; dropping = (from != "") }
    {
      line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t,]+$/, "", line)
      if (line ~ /\($/) { depth++; head[depth] = line; body[depth] = ""; count[depth] = 0; next }
      if (line == ")") {
        if (count[depth]) add(head[depth] body[depth] ")", depth - 1)
        depth--
        next
      }
      name = line; sub(/\{.*/, "", name)
      if (dropping && name == from) { dropping = 0; next }
      if (dropping && name != "idr-target") next
      add(line, depth)
    }
    END { if (dropping || count[0] != 1) exit 1; print body[0] }' "$work/differential.pipeline"
}

# lit_lowered MODULE NAME: MODULE linked into the program $work/NAME, as
# idris-mlir compiles a module from the stage its program is at (its
# idr.program's `stage`): the rest of the pipeline from that stage
# (lit_pipeline_from) by idris-mlir-opt, then idris-mlir, which takes a
# module of the LLVM dialect alone to LLVM as it is, and the link every
# program gets (lit_cc). A module with no program is that LLVM module
# already. Status 1, and lines that say why, when a step fails.
lit_lowered() {
  ll_stage=$(sed -n 's/.*idr\.program .*stage(\([a-z]*\)).*/\1/p' "$1" | head -n 1)
  ll_module=$1
  if [ -n "$ll_stage" ]; then
    ll_pipeline=$(lit_pipeline_from "$ll_stage") ||
      { say "differential: no pipeline from $ll_stage"; return 1; }
    ll_module=$work/differential.$2.lowered.mlir
    if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$1" --pass-pipeline="$ll_pipeline" \
           -o "$ll_module" > "$work/differential.log" 2>&1; then
      say "differential: ${1##*/} does not lower from $ll_stage"
      show "$work/differential.log"
      return 1
    fi
  fi
  if ! bounded "$idris_mlir" --num-threads=1 -c "$ll_module" -o "$work/differential.$2.o" \
         > "$work/differential.log" 2>&1 ||
     ! lit_cc "$work/differential.$2.o" -o "$work/differential.$2" > "$work/differential.log" 2>&1; then
    say "differential: ${1##*/} does not compile"
    show "$work/differential.log"
    return 1
  fi
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
# programs of the modules BEFORE and AFTER, each compiled from its own
# stage (lit_lowered), mean the same: on every input
# (lit_differential_inputs) both exit with the same status and print the
# same stdout. The module as written is one form of the program, and what
# a pass made of it the other, so a pass that changes what the program
# does fails here on the first input where they differ, which is named:
# `differential: BEFORE and AFTER differ on <input>`, on stderr, with
# both outcomes. Both run under one bound, each input once. Each run is
# also held to what every run of a program this compiler built is held to
# (run_ours): with IDRIS_RT_LIVE=1, a run that ends by main's return
# writes `idris-rt: live cells N` last on its stderr, and N must be 0, so
# a pass that drops a release, or a module that leaks, fails on the first
# input whose run leaves a cell live, named as `differential: <module>
# leaves N cells live on <input>`. A crash or an exit with a status of
# the program's own writes no count and is held to none.
lit_differential() {
  if [ "$#" -ne 2 ]; then
    say "differential: takes two modules, not $#" >&2
    return 2
  fi
  [ -d "$work/differential.in" ] || lit_differential_inputs "$work/differential.in"
  for ld_side in before after; do
    rm -rf "$work/differential.$ld_side.runs"
    mkdir "$work/differential.$ld_side.runs"
  done
  lit_lowered "$1" before >&2 || return 1
  lit_lowered "$2" after >&2 || return 1
  for ld_side in before after; do
    # One bound for every run of a program: each is a process of a few
    # milliseconds, and a hang on any input ends them all.
    if ! bounded sh -c '
        while IFS="	" read -r name what; do
          IDRIS_RT_LIVE=1 "$2" < "$1/$name" > "$3/$name.out" 2> "$3/$name.err"
          echo "$?" > "$3/$name.status"
        done < "$1/list"' sh "$work/differential.in" "$work/differential.$ld_side" \
        "$work/differential.$ld_side.runs" 2>&1; then
      say "differential: the program of ${1##*/} or ${2##*/} did not end on every input" >&2
      return 1
    fi
  done
  while IFS='	' read -r ld_name ld_what; do
    ld_b=$work/differential.before.runs/$ld_name
    ld_a=$work/differential.after.runs/$ld_name
    if ! cmp -s "$ld_b.status" "$ld_a.status" || ! cmp -s "$ld_b.out" "$ld_a.out"; then
      {
        say "differential: ${1##*/} and ${2##*/} differ on $ld_what"
        say "  | ${1##*/}: exit $(cat "$ld_b.status"), stdout:"
        head -c 400 "$ld_b.out" | awk '{ print "  |   " $0 }'
        say "  | ${2##*/}: exit $(cat "$ld_a.status"), stdout:"
        head -c 400 "$ld_a.out" | awk '{ print "  |   " $0 }'
      } >&2
      return 1
    fi
    for ld_run in "$ld_b:$1" "$ld_a:$2"; do
      ld_count=$(tail -n 1 "${ld_run%%:*}.err" | sed -n 's/^idris-rt: live cells \([0-9]*\)$/\1/p')
      if [ -n "$ld_count" ] && [ "$ld_count" != 0 ]; then
        ld_module=${ld_run#*:}
        say "differential: ${ld_module##*/} leaves $ld_count cells live on $ld_what" >&2
        return 1
      fi
    done
  done < "$work/differential.in/list"
}
