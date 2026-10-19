# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect tests' `// RUN:` lines, run without lit and without Python.

# sed_escape TEXT: TEXT as the replacement of a `s|...|...|` command.
sed_escape() {
  printf '%s\n' "$1" | sed 's/[\\|&]/\\&/g'
}

# lit_stage CMD...: one command of a RUN line's pipeline; its failure fails
# the line, as lit's pipefail does. A command that is to fail (lit_fails)
# says itself how it did not.
lit_stage() {
  lit_run "$@"
  lit_stage_status=$?
  case $1 in
    lit_status | lit_not) ;;
    *) [ "$lit_stage_status" -eq 0 ] || say "$1 exited $lit_stage_status" >> "$work/lit.failed" ;;
  esac
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

# lit_expected_failures CMD...: the idr-expect properties CMD asks for, one
# name per line, from `--idr-expect=holds=...` or `idr-expect{holds=...}`
# in its arguments (a pass pipeline among them); nothing for any other
# command.
lit_expected_failures() {
  printf '%s\n' "$@" | awk '
    { line = $0
      while (match(line, /idr-expect(=|\{)holds=[^ }]*/)) {
        list = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        sub(/^idr-expect(=|\{)holds=/, "", list)
        n = split(list, request, ",")
        for (i = 1; i <= n; i++) { name = request[i]; sub(/=.*/, "", name); if (name != "") print name }
      } }'
}

# lit_fails WANT CMD...: CMD fails as WANT says: `any`, any status from 1
# to 123 (a crash, a timeout, a command that could not run is no such
# failure), as `not` asks; or exactly the status WANT, as `%status WANT`
# asks. A command that asks idr-expect for properties and is to fail must
# fail by one of them: its stderr names `expected <property>:` for one, so
# a module that never parsed, or a pass that broke before the properties
# ran, is not the failure the line states. CMD's stderr passes through, so
# a line's redirection of it still works.
lit_fails() {
  lit_want=$1
  shift
  lit_err=$(mktemp "$work/lit-err.XXXXXX") || return 1
  lit_run "$@" 2> "$lit_err"
  lit_got=$?
  cat "$lit_err" >&2
  case $lit_want in
    any)
      if [ "$lit_got" -eq 0 ] || [ "$lit_got" -gt 123 ]; then
        say "$1 exited $lit_got, expected a failure" >> "$work/lit.failed"
        return 1
      fi ;;
    *)
      if [ "$lit_got" -ne "$lit_want" ]; then
        say "$1 exited $lit_got, expected $lit_want" >> "$work/lit.failed"
        return 1
      fi ;;
  esac
  [ "$lit_got" -ne 0 ] || return 0
  lit_properties=$(lit_expected_failures "$@")
  [ -n "$lit_properties" ] || return 0
  for lit_property in $lit_properties; do
    grep -qF "expected $lit_property:" "$lit_err" && return 0
  done
  say "$1 exited $lit_got, but no property it asks for failed:" $lit_properties >> "$work/lit.failed"
  return 1
}

# lit_status N CMD... (`%status N CMD`): CMD exits with exactly status N.
lit_status() {
  lit_fails "$@"
}

# lit_not CMD... (`not CMD`): CMD fails.
lit_not() {
  lit_fails any "$@"
}

# lit_unnamed LINE LATER: the command of the RUN line LINE that is to fail
# (`not CMD`, `%status 1 CMD`) without naming the failure it expects, or
# nothing when every such command names one. LATER is the text of the RUN
# lines after LINE. A failure is named when the line checks which one it
# is: CMD is a decision (diff, cmp, grep, test, ls: status 1 is the answer
# no); CMD is idris-mlir under `%status` (its status is its verdict: 1 an
# internal error, 2 a usage error, 3 a refusal); CMD runs
# -verify-diagnostics; CMD asks idr-expect for properties (lit_fails then
# requires one of them to fail); CMD's stderr is piped on (`2>&1 |`); or
# CMD writes its stderr or a report (`2> FILE`, `--report=FILE`) to a file
# the rest of the line or a later line reads.
# Anything else would pass on any failure of CMD, a module that never
# parsed included.
lit_unnamed() {
  lit_check_line=$1 lit_check_later=$2 awk '
    function reads_later(file, k,    rest, j) {
      rest = ""
      for (j = k + 1; j <= n; j++) rest = rest " " seg[j]
      return index(rest " " ENVIRON["lit_check_later"], file) > 0
    }
    BEGIN {
      s = ENVIRON["lit_check_line"]
      n = 0; cur = ""; q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { cur = cur c; if (c == q) q = ""; continue }
        if (c == "\047" || c == "\"") { q = c; cur = cur c; continue }
        if (c == "|" || c == ";" || (c == "&" && substr(s, i + 1, 1) == "&")) {
          if (c == "&" || substr(s, i + 1, 1) == "|") { i++; c = c c }
          seg[++n] = cur; sep[n] = c; cur = ""; continue
        }
        cur = cur c
      }
      seg[++n] = cur; sep[n] = ""
      for (k = 1; k <= n; k++) {
        m = split(seg[k], w, " ")
        if (w[1] == "not") cmd = w[2]
        else if (w[1] == "%status" && w[2] == "1") cmd = w[3]
        else continue
        sub(/^.*\//, "", cmd)
        if (cmd ~ /^(diff|cmp|grep|test|ls)$/) continue
        if (w[1] == "%status" && cmd == "idris-mlir") continue
        if (index(seg[k], "-verify-diagnostics")) continue
        if (seg[k] ~ /idr-expect(=|\{)holds=/) continue
        if (seg[k] ~ /2>&1/ && sep[k] == "|") continue
        named = 0
        rest = seg[k]
        while (match(rest, /(2>[ ]*|--report=)[^ &]+/)) {
          file = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          sub(/^(2>[ ]*|--report=)/, "", file)
          if (reads_later(file, k)) named = 1
        }
        if (named) continue
        sub(/^ +/, "", seg[k]); sub(/ +$/, "", seg[k])
        print seg[k]
        exit
      }
    }'
}

# lit_stages: the command on stdin with each stage of its top-level
# pipelines run by lit_stage: at its start and after each `|` outside
# quotes, so a pipe inside a quoted `sh -c` or awk program stays its own.
lit_stages() {
  awk '{
    s = $0; out = "lit_stage "; q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q != "") { out = out c; if (c == q) q = ""; continue }
      if (c == "\047" || c == "\"") { q = c; out = out c; continue }
      if (c == "|" && substr(s, i + 1, 1) != "|" && substr(s, i - 1, 1) != "|" && substr(s, i - 1, 1) != ">") {
        out = out "| lit_stage"
        continue
      }
      out = out c
    }
    print out
  }'
}

# lit FILE: the `// RUN:` lines of a dialect test, run as lit's internal
# shell ran them, with no lit and no Python: %s is FILE, %t a path in the
# work directory, %cc the pinned C compiler linking a program as the chain
# does (lit_cc), %runtime the runtime object idris-mlir reads and every
# program links, `%status N CMD` checks that CMD exits with status N, and
# `%differential BEFORE AFTER` that two modules' programs mean the same
# on every input (lit_differential). A
# `%%` stays as it is, never read as the start of one of these, so an awk
# program's printf can write a `%` of the module it prints. A line fails
# when any command of its pipelines fails (pipefail); a trailing \
# continues it on the next RUN line. The lines run in order, and the first
# that fails ends the test, as with lit: a later line reads what an earlier
# one wrote, so it would check nothing, and is reported as not run. A
# command that is to fail (`not CMD`, `%status 1 CMD`) must name the
# failure it expects (lit_unnamed), and then fails only that way
# (lit_fails). idris-mlir-opt, idris-mlir and the pinned LLVM's FileCheck
# and count come first on PATH, `echo -n` omits the newline, and `timeout`
# is coreutils' (tools/host.sh), which bounds itself. Every idris-mlir-opt
# that is to succeed reads its input back from the generic form and from
# bytecode before any pass (--verify-roundtrip) and checks each pass's
# contracts as it runs (--idr-contracts); one that is to fail does not, so
# that it fails for the reason its line names.
lit() {
  lit_file=$(cd "$(dirname "$1")" && pwd)/${1##*/}
  # The runtime is idris-mlir's (make build), asked for only by a test
  # that names it.
  lit_runtime=
  if grep -q '%runtime' "$lit_file"; then lit_runtime=$("$idris_mlir" --print-runtime); fi
  sed -n 's/^[[:space:]]*\/\/[[:space:]]*RUN:[[:space:]]*//p' "$lit_file" |
    awk '{ sub(/[ \t]+$/, "") }
         /\\$/ { sub(/\\$/, ""); joined = joined $0; next }
         { print joined $0; joined = "" }
         END { if (joined != "") print joined }' > "$work/lit.lines"
  PATH=$dev_prefix/foreign/idr:$llvm_bin:$PATH
  export PATH
  lit_n=0
  lit_failed_at=
  while IFS= read -r lit_line; do
    lit_n=$((lit_n + 1))
    if [ -n "$lit_failed_at" ]; then
      say "RUN $lit_n: not run, as RUN $lit_failed_at failed"
      continue
    fi
    lit_later=$(sed "1,${lit_n}d" "$work/lit.lines")
    lit_unnamed_command=$(lit_unnamed "$lit_line" "$lit_later")
    if [ -n "$lit_unnamed_command" ]; then
      say "RUN $lit_n: failed: $lit_line"
      say "  | names no failure: \`$lit_unnamed_command\` passes on any failure of its command"
      lit_failed_at=$lit_n
      continue
    fi
    lit_command=$(printf '%s\n' "$lit_line" | sed \
      -e 's/%%/@LIT_PERCENT@/g' \
      -e 's/idris-mlir-opt /idris-mlir-opt --verify-roundtrip --idr-contracts /g' | sed -E \
      -e 's/(^|[|&;(][[:space:]]*)not idris-mlir-opt --verify-roundtrip --idr-contracts /\1not idris-mlir-opt /g' \
      -e 's/(%status [1-9][0-9]* )idris-mlir-opt --verify-roundtrip --idr-contracts /\1idris-mlir-opt /g' \
      -e 's/(^|[|&;(][[:space:]]*)not (diff|cmp|grep) /\1%status 1 \2 /g' \
      -e 's/(^|[|&;(][[:space:]]*)not /\1lit_not /g' | sed \
      -e "s|%status|lit_status|g" \
      -e "s|%differential|lit_differential|g" \
      -e "s|%cc|lit_cc|g" \
      -e "s|%runtime|$(sed_escape "$lit_runtime")|g" \
      -e "s|%s|$(sed_escape "$lit_file")|g" \
      -e "s|%t|$(sed_escape "$work/t")|g" \
      -e 's/@LIT_PERCENT@/%%/g' | lit_stages)
    : > "$work/lit.failed"
    (
      echo() {
        if [ "${1-}" = -n ]; then shift; printf '%s' "$*"; else printf '%s\n' "$*"; fi
      }
      timeout() {
        "$timeout_cmd" "$@"
      }
      cd "$work" && eval "$lit_command"
    ) < /dev/null > "$work/lit.out" 2>&1
    lit_line_status=$?
    if [ "$lit_line_status" -eq 0 ] && [ ! -s "$work/lit.failed" ]; then
      say "RUN $lit_n: ok"
    else
      say "RUN $lit_n: failed: $lit_line"
      show "$work/lit.failed" "$work/lit.out"
      lit_failed_at=$lit_n
    fi
  done < "$work/lit.lines"
  [ "$lit_n" -gt 0 ] || say "no RUN lines in ${1##*/}"
}

# lit_fixture: the dialect fixture the test's directory is, its one .mlir
# file, its RUN lines run by lit: the one line of fixture.expected
# (harness/kinds) when every one holds, else lit's account of each line.
# Beside the module there is only what the runner reads of any test (a
# suite or a targets file): a fixture is its module, so anything else is
# a file no check reads.
lit_fixture() {
  lit_fixture_module=
  lit_fixture_unread=
  for lit_fixture_file in * .[!.]*; do
    [ -e "$lit_fixture_file" ] || continue
    case $lit_fixture_file in
      *.mlir) lit_fixture_module=$lit_fixture_file ;;
      suite | targets) ;;
      *) lit_fixture_unread="$lit_fixture_unread $lit_fixture_file" ;;
    esac
  done
  if [ -n "$lit_fixture_unread" ]; then
    say "fixture: files no check reads:$lit_fixture_unread"
    return
  fi
  lit "$lit_fixture_module" > "$work/lit.transcript"
  if grep -qv '^RUN [0-9]*: ok$' "$work/lit.transcript"; then
    cat "$work/lit.transcript"
  else
    say "RUN lines: each holds"
  fi
}

# lit_cc ARG... (`%cc`): the pinned C compiler, which links a program with
# what every program needs, as tools/compile.sh links one: the runtime
# idris-mlir reads, where what a program did not inline resolves, and
# what links a program for the target, GMP among it, since the runtime
# frees a big's limbs (link_program).
lit_cc() {
  link_program "$@" "$("$idris_mlir" --print-runtime)"
}
