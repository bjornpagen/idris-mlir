# The dialect tests' `// RUN:` lines, run without lit and without Python.

# sed_escape TEXT: TEXT as the replacement of a `s|...|...|` command.
sed_escape() {
  printf '%s\n' "$1" | sed 's/[\\|&]/\\&/g'
}

# lit_stage CMD...: one command of a RUN line's pipeline; its failure fails
# the line, as lit's pipefail does.
lit_stage() {
  lit_run "$@"
  lit_stage_status=$?
  [ "$lit_stage_status" -eq 0 ] || say "$1 exited $lit_stage_status" >> "$work/lit.failed"
  return "$lit_stage_status"
}

# lit_run CMD...: a command of a RUN line; an executable is bounded, a
# shell builtin or function is not, since it cannot hang.
lit_run() {
  case $(command -v "$1") in
    /*) bounded "$@" ;;
    *) "$@" ;;
  esac
}

# lit_status N CMD... (`%status N CMD`): CMD exits with exactly status N.
lit_status() {
  lit_expected_status=$1
  shift
  lit_run "$@"
  lit_got_status=$?
  [ "$lit_got_status" -eq "$lit_expected_status" ] && return 0
  say "$1 exited $lit_got_status, expected $lit_expected_status" >&2
  return 1
}

# lit_cc ARG... (`%cc`): the pinned C compiler, which links a program with
# what every program needs, as tools/compile.sh links one: the runtime
# idris-mlir-cc reads, where what a program did not inline resolves, and
# what links a program for the target, GMP among it, since the runtime
# frees a big's limbs (link_program).
lit_cc() {
  link_program "$@" "$("$idris_mlir_cc" --print-runtime)"
}

# lit FILE: the `// RUN:` lines of a dialect test, run as lit's internal
# shell ran them, with no lit and no Python: %s is FILE, %t a path in the
# work directory, %cc the pinned C compiler linking a program as the chain
# does (lit_cc), %runtime the runtime object idris-mlir-cc reads and every
# program links, and `%status N CMD` checks that CMD exits with status N. A
# line fails when any command of its pipelines fails (pipefail); a trailing
# \ continues it on the next RUN line. idris-mlir-opt, idris-mlir-cc and the
# pinned LLVM's FileCheck, not and count come first on PATH, and `echo -n`
# omits the newline.
lit() {
  lit_file=$(cd "$(dirname "$1")" && pwd)/${1##*/}
  lit_runtime=$("$idris_mlir_cc" --print-runtime)
  sed -n 's/^[[:space:]]*\/\/[[:space:]]*RUN:[[:space:]]*//p' "$lit_file" |
    awk '{ sub(/[ \t]+$/, "") }
         /\\$/ { sub(/\\$/, ""); joined = joined $0; next }
         { print joined $0; joined = "" }
         END { if (joined != "") print joined }' > "$work/lit.lines"
  PATH=$root/build/dev/foreign/idr:$llvm_bin:$PATH
  export PATH
  lit_n=0
  while IFS= read -r lit_line; do
    lit_n=$((lit_n + 1))
    lit_command=$(printf '%s\n' "$lit_line" | sed \
      -e "s|%status|lit_status|g" \
      -e "s|%cc|lit_cc|g" \
      -e "s|%runtime|$(sed_escape "$lit_runtime")|g" \
      -e "s|%s|$(sed_escape "$lit_file")|g" \
      -e "s|%t|$(sed_escape "$work/t")|g" \
      -e 's/ | / | lit_stage /g' \
      -e 's/^/lit_stage /')
    : > "$work/lit.failed"
    (
      echo() {
        if [ "${1-}" = -n ]; then shift; printf '%s' "$*"; else printf '%s\n' "$*"; fi
      }
      cd "$work" && eval "$lit_command"
    ) < /dev/null > "$work/lit.out" 2>&1
    lit_line_status=$?
    if [ "$lit_line_status" -eq 0 ] && [ ! -s "$work/lit.failed" ]; then
      say "RUN $lit_n: ok"
    else
      say "RUN $lit_n: failed: $lit_line"
      show "$work/lit.failed" "$work/lit.out"
    fi
  done < "$work/lit.lines"
  [ "$lit_n" -gt 0 ] || say "no RUN lines in ${1##*/}"
}
