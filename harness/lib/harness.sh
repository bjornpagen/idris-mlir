# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The glue every run script stands on: the pinned tools, the work
# directory, a command bounded, and the runner (harness/*.idr), which
# computes every check the scripts share and has the glue here start each
# tool it needs (serve). Nothing here decides what a check says: each
# function either starts a tool with its arguments or hands its words to
# the runner, under the name the run scripts call it by.

# The pinned tools: $llvm_bin, $pinned_cc, $idris_mlir (the compiler under
# test, with its frontend $idris_mlir_front beside it), $idris_mlir_opt,
# and $idris2, the pinned stock Idris 2, which the frontend is built by
# and which a test asks about the prelude it checked (pinned_idris).
. "$root/tools/toolchain.sh"
runtests=$root/harness/build/exec/runtests
compile_sh=$root/tools/compile.sh
# The checked runtime, which every program a test runs links: as the
# archive the build made, which a C program links (link_program), and as
# what the build prepared from it (--prepare-runtime), which a compilation
# reads and links (Harness.idr, compileChecked), since a compilation reads
# no archive.
checked_runtime=$dev_prefix/runtime/libidris_rt_checked.a
checked_prepared=$dev_prefix/foreign/idr/idris_rt_checked.o
# The test's own directory, where its fixture files are: a test runs in
# it (harness/one.sh), whether its script is its own `run` or its kind's
# (harness/kinds), so a fixture is named by a path from it (`.`).
here=$(pwd)
# The parameter of one run of a test the runner runs once per parameter,
# the script's second argument (harness/one.sh); empty for any other test.
parameter=${2-}

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# bounded CMD...: CMD, killed with everything it started after step_limit
# seconds, so a hang is a failure. A command that timed out exits 124 and
# says so on stderr, which the caller shows with the rest of its output.
bounded() {
  "$timeout_cmd" -k 5 "$step_limit" "$@"
  bounded_status=$?
  case $bounded_status in
    124 | 137)
      printf '%s\n' "timed out after ${step_limit}s: ${1##*/}" >&2
      return 124 ;;
  esac
  return "$bounded_status"
}

# pinned_idris ARG...: the pinned Idris, bounded, on its own prefix, whose
# prelude and base it checked. The environment's prefix is the frontend's,
# whose TTCs are of another format.
pinned_idris() {
  (IDRIS2_PREFIX=$idris_prefix && export IDRIS2_PREFIX && bounded "$idris2" "$@")
}

# say TEXT...: one line of the test's output, printed as is.
say() {
  printf '%s\n' "$*"
}

# serve MODE ARG...: the runner's MODE (harness/Serve.idr), with the tools
# and places this script holds now, each passed under its name here. The
# runner creates no process, so it asks for each command on a channel:
# its words in the session's argv file, one a line, the variables it runs
# with in its env file, and on `ask` the directory it runs in, its input
# and its two outputs; serve_command starts it, and the answer is its
# status and, for a process a signal ended, the signal's name. The status
# is the runner's.
serve() {
  # A runner that is not there would never open the channel, and the test
  # would wait for its deadline.
  [ -x "$runtests" ] || { say "serve: no runner at $runtests (make runner)"; return 1; }
  serve_dir=$(mktemp -d "$work/serve.XXXXXX") || return 1
  mkfifo "$serve_dir/ask" "$serve_dir/answer" || return 1
  root=$root work=$work llvm_prefix=$llvm_prefix llvm_bin=$llvm_bin pinned_cc=$pinned_cc \
    idris_mlir=$idris_mlir idris_mlir_opt=$idris_mlir_opt idris2=$idris2 idris_prefix=$idris_prefix \
    host_prefix=$host_prefix \
    compile_sh=$compile_sh checked_prepared=$checked_prepared dev_prefix=$dev_prefix \
    runtests=$runtests "$runtests" --serve "$serve_dir" "$@" &
  serve_runner=$!
  while IFS='	' read -r serve_cwd serve_in serve_out serve_err; do
    serve_command "$serve_dir" "$serve_cwd" "$serve_in" "$serve_out" "$serve_err"
    serve_status=$?
    if [ "$serve_status" -gt 128 ]; then
      printf '%s %s\n' "$serve_status" "$(kill -l "$((serve_status - 128))")"
    else
      printf '%s -\n' "$serve_status"
    fi
  done 5>&1 < "$serve_dir/ask" > "$serve_dir/answer"
  wait "$serve_runner"
  serve_status=$?
  rm -rf "$serve_dir"
  return "$serve_status"
}

# serve_command DIR CWD INPUT OUTPUT ERROR: the command whose words DIR/argv
# holds, one a line, with the variables DIR/env assigns exported, run in
# CWD with its standard input from INPUT and its outputs to OUTPUT and
# ERROR: a path, `-` for serve's caller's stream, and for ERROR `&` to
# join OUTPUT. Its first word is a function here that bounds what it
# starts (bounded, pinned_idris, lit_line), or a rule's check the run
# script defines.
serve_command() (
  sc_dir=$1 sc_cwd=$2 sc_in=$3 sc_out=$4 sc_err=$5
  while IFS= read -r sc_assignment; do export "$sc_assignment"; done < "$sc_dir/env"
  set --
  while IFS= read -r sc_arg; do set -- "$@" "$sc_arg"; done < "$sc_dir/argv"
  case $sc_out in
    -) exec 6>&5 ;;
    *) exec 6> "$sc_out" ;;
  esac || exit 1
  case $sc_err in
    -) exec 7>&2 ;;
    '&') exec 7>&6 ;;
    *) exec 7> "$sc_err" ;;
  esac || exit 1
  cd "$sc_cwd" || exit 1
  "$@" < "$sc_in" >&6 2>&7 5>&- 6>&- 7>&-
)

# runtime_c CMD ARG...: CMD with ARG... and then the flags a C or C++ source
# that includes idris_rt.h compiles with, one argument per line of the
# file the build writes beside its runtime (runtime/c-flags): the runtime's
# own include directory, then the one its generated ABI header is in. So no
# test spells where the build generates that header.
runtime_c() {
  if [ ! -f "$dev_prefix/runtime/c-flags" ]; then
    printf '%s\n' "no $dev_prefix/runtime/c-flags, which the build writes" >&2
    return 1
  fi
  while IFS= read -r runtime_c_flag; do
    set -- "$@" "$runtime_c_flag"
  done < "$dev_prefix/runtime/c-flags"
  "$@"
}

# run_program NAME EXE INPUT: runs EXE with stdin from INPUT, its stdout
# and stderr in $work/NAME.out and $work/NAME.err, its exit status, as sh
# reports it (128 plus a signal's number for a process a signal ended), in
# $ran. A program this compiler built for a test links the checked runtime
# (compile_checked), which ends a run that returns from main with a cell
# still live as the runtime's internal error: a leak is an ending like any
# other, never a line a test parses.
run_program() {
  bounded "$2" < "$3" > "$work/$1.out" 2> "$work/$1.err"
  ran=$?
}

# The runner's checks, by the names the run scripts call them (Main.idr
# says what each computes). Those that start a tool run through serve;
# compile_program, compile_checked and scale_compile leave the compiler's
# status in $compiled, and its output in $work/compile.out and
# $work/compile.err; spec_check leaves specgen's status in $spec_status;
# runtime_fact leaves the fact's text in $runtime_fact_value, or says
# that the build wrote none and fails; planted_frontend leaves the
# planted frontend in $planted_front and the idris-mlir beside it in
# $planted_compiler.
show() { "$runtests" --show "$@"; }
empty() { "$runtests" --empty "$1" "$2"; }
first_word() { "$runtests" --first-word "$1"; }
package_options() { "$runtests" --package-options "$1"; }
copy_fixture() { serve copy-fixture "$@"; }
compile_program() { serve compile-program "$@"; compiled=$?; }
compile_checked() { serve compile-checked "$@"; compiled=$?; }
link_program() { serve link-program "$@"; }
mlir_check() { serve mlir-check "$@"; }
artifact_files() { "$runtests" --artifact-files "$@"; }
artifact_file() { "$runtests" --artifact-file "$@"; }
artifacts() { "$runtests" --artifacts "$@"; }
no_artifacts() { "$runtests" --no-artifacts "$@"; }
stage_options() { "$runtests" --stage-options "$1"; }
timing_rows() { "$runtests" --timing-rows "$1"; }
rule_phrases() { "$runtests" --rule-phrases ${1+"$1"}; }
e2e_io() { serve e2e-io "$@"; }
sem_case() { serve sem-case "$@"; }
near_neighbour() { serve near-neighbour "$@"; }
profile_reject() { serve profile-reject "$@"; }
registry_shadowed() { serve registry-shadowed "$@"; }
determinism() { serve determinism "$@"; }
determinism_threads() { serve determinism-threads "$@"; }
fuzz() { serve fuzz "$@"; }
fuzz_lazy() { serve fuzz-lazy "$@"; }
lit() { serve lit "$@"; }
lit_fixture() { serve lit-fixture; }
idris_lex() { "$runtests" --idris-lex "$1" "$2"; }
cpp_lex() { "$runtests" --cpp-lex "$@"; }
runtime_fact() {
  runtime_fact_value=$("$runtests" --runtime-fact "$dev_prefix" "$1") || { say "$runtime_fact_value"; return 1; }
}
planted() { serve planted "$1"; }
planted_frontend() {
  serve planted-frontend "$@" || return 1
  { IFS= read -r planted_front; IFS= read -r planted_compiler; } < "$work/planted-frontend"
}
scale_compile() { serve scale-compile "$@"; compiled=$?; }
scale_relation() { serve scale-relation "$@"; }
bench_smoke() { serve bench-smoke "$@"; }
spec_outputs() { "$runtests" --spec-outputs "$1"; }
spec_sources() { serve spec-sources "$@"; }
spec_tree() { serve spec-tree "$@"; }
spec_check() { serve spec-check "$@"; spec_status=$?; }
spec_named() { "$runtests" --spec-named "$work" "$spec_status" "$@"; }
spec_written() { serve spec-written "$@"; }

# A RUN line of a dialect test (Lit.idr), as lit's internal shell ran it,
# with no lit and no Python: the runner rewrites the line, and lit_line
# runs it with these functions as its commands. idris-mlir-opt,
# idris-mlir and the pinned LLVM's FileCheck and count come first on PATH,
# `echo -n` omits the newline, and `timeout` is coreutils' (tools/host.sh),
# which bounds itself.

# lit_line FILE LINE: the rewritten RUN line LINE of the dialect test FILE.
lit_line() {
  lit_file=$1
  PATH=$dev_prefix/foreign/idr:$llvm_bin:$PATH
  export PATH
  echo() {
    if [ "${1-}" = -n ]; then shift; printf '%s' "$*"; else printf '%s\n' "$*"; fi
  }
  timeout() {
    "$timeout_cmd" "$@"
  }
  eval "$2"
}

# lit_run CMD...: a command of a RUN line; an executable is bounded, a
# shell builtin or function is not, since it cannot hang.
lit_run() {
  case $(command -v "$1") in
    /*) bounded "$@" ;;
    *) "$@" ;;
  esac
}

# lit_stage CMD...: one command of a RUN line's pipeline; its failure fails
# the line, as lit's pipefail does. A command that is to fail says itself
# how it did not.
lit_stage() {
  lit_run "$@"
  lit_stage_status=$?
  case $1 in
    lit_status | lit_not) ;;
    *) [ "$lit_stage_status" -eq 0 ] || printf '%s exited %s\n' "$1" "$lit_stage_status" >> "$work/lit.failed" ;;
  esac
  return "$lit_stage_status"
}

# lit_fails WANT CMD...: CMD, its stderr passed through, held by the runner
# to fail as WANT says (`runtests --lit-fails`, Lit.idr); a failure not as
# stated is a line of $work/lit.failed.
lit_fails() {
  lit_want=$1
  shift
  lit_err=$(mktemp "$work/lit-err.XXXXXX") || return 1
  lit_run "$@" 2> "$lit_err"
  lit_got=$?
  cat "$lit_err" >&2
  "$runtests" --lit-fails "$lit_want" "$lit_got" "$lit_err" "$@" >> "$work/lit.failed"
}

# lit_status N CMD... (`%status N CMD`): CMD exits with exactly status N.
lit_status() {
  lit_fails "$@"
}

# lit_not CMD... (`not CMD`): CMD fails.
lit_not() {
  lit_fails any "$@"
}

# lit_cc ARG... (`%cc`): the pinned C compiler, which links a program with
# what every program needs, as tools/compile.sh links one: the runtime
# idris-mlir reads, where what a program did not inline resolves, and
# what links a program for the target, GMP among it, since the runtime
# frees a big's limbs (link_program).
lit_cc() {
  link_program "$@" "$("$idris_mlir" --print-runtime)"
}

# lit_differential BEFORE AFTER (`%differential BEFORE AFTER`): the two
# modules' programs end alike on every input (Lit.idr).
lit_differential() {
  serve lit-differential "$lit_file" "$@"
}
