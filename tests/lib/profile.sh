# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The profile fixtures: programs the compiler accepts, and programs it
# rejects, each by one rule, at the right line.

# header FILE FIELD: the value of `-- FIELD: <value>` among the lines of that
# form that start a profile fixture; the status is 1 without one.
header() {
  awk -v field="$2" '
    !/^--[ \t]*(expect|message):/ { exit }
    {
      key = $0; sub(/^--[ \t]*/, "", key); sub(/:.*$/, "", key)
      if (key == field) { value = $0; sub(/^--[ \t]*[a-z]+:[ \t]*/, "", value); found = 1 }
    }
    END { if (found) { print value; exit 0 } exit 1 }' "$1"
}

# profile_prepare FIXTURE: the fixture in $work/fixture, a single file as
# Main.idr.
profile_prepare() {
  mkdir "$work/fixture"
  if [ -d "$1" ]; then
    copy_fixture "$1" "$work/fixture"
  else
    cp "$1" "$work/fixture/Main.idr"
  fi
}

# profile_compile [OPTION]...: $work/fixture/Main.idr to build/exec/Main, with OPTION... and the
# installed packages its `packages` names.
profile_compile() {
  profile_options=
  if [ -f "$work/fixture/packages" ]; then
    for profile_package in $(cat "$work/fixture/packages"); do
      profile_options="$profile_options -p $profile_package"
    done
  fi
  # shellcheck disable=SC2086 # the packages are words
  compile_program $profile_options "$@" "$work/fixture/Main.idr" Main
}

# profile_reject FIXTURE: `tests/reject/<reason>-<desc>/`, a directory holding
# Main.idr and its other modules, whose first
# line is `-- expect: <reason>, line <n>` (and then, optionally,
# `-- message: <text>`, text the refusal holds anywhere in it, whatever
# words surround it), the name starting with <reason>, words joined by
# dashes. It is refused with exit status 3, reported on line n, and leaves
# no artifact.
# Who refuses is the reason, read off the compilation's report, the one
# record of every refusal, whoever made it: a line `verdict: <verdict>`,
# and a line `diagnostic: <severity> <rule> <file:line>` per diagnostic,
# the rule's phrase with each space written `-`. The phrase of one of the
# rules (lib/rules.sh) is this compiler's refusal, the report's only
# error; `idris` is Idris's own, its parser's or its checker's, each error
# a rule of the user-error category and none a rule of ours.
profile_reject() {
  if [ -d "$1" ]; then reject_main=$1/Main.idr; else reject_main=$1; fi
  reject_name=$(fixture_name "$1")
  reject_expect=$(header "$reject_main" expect)
  reject_reason=$(printf '%s\n' "$reject_expect" | sed -n 's/^\(.*\), line \([0-9][0-9]*\)$/\1/p')
  reject_line=$(printf '%s\n' "$reject_expect" | sed -n 's/^\(.*\), line \([0-9][0-9]*\)$/\2/p')
  if [ -z "$reject_reason" ]; then
    say "$reject_name: the first line must be '-- expect: <reason>, line <n>'"
    return
  fi
  if [ ! -f "$rules_list" ]; then
    say "$reject_name: no list of the rules (IdrRules.txt, which the build writes)"
    return
  fi
  if [ "$reject_reason" != idris ] && ! rule_category "$reject_reason" > /dev/null; then
    say "$reject_name: $reject_reason is no rule's phrase"
    return
  fi
  reject_prefix=$(printf '%s' "$reject_reason" | tr ' ' '-')
  case $reject_name in
    "$reject_prefix"*) ;;
    *) say "$reject_name does not start with $reject_prefix"; return ;;
  esac
  profile_prepare "$1"
  profile_compile "--report=$work/report"
  say "compile: exit $compiled"
  cat "$work/compile.out" "$work/compile.err" > "$work/compile.all"
  # The report's errors, `<rule> <file:line>` each, in the order made, and
  # how many are refusals by a rule of ours: Idris's own errors are
  # refusals by the rules of the user-error category.
  sed -n 's/^diagnostic: error //p' "$work/report" > "$work/report.errors" 2> /dev/null
  rule_phrases 'user error' | tr ' ' '-' > "$work/rules.idris"
  reject_count=$(awk 'NR == FNR { idris[$1] = 1; next } !($1 in idris)' "$work/rules.idris" "$work/report.errors" |
    wc -l | tr -d ' ')
  if grep -qx 'verdict: internal' "$work/report" 2> /dev/null; then
    say "$reject_reason: an internal error, not a rejection"
    show "$work/compile.all"
  elif [ "$reject_reason" = idris ]; then
    if [ "$reject_count" -eq 0 ] && [ -s "$work/report.errors" ]; then
      say "idris: its own error, and no rule of ours"
    else
      say "idris: expected Idris's error alone, among $reject_count unsupported errors"
      show "$work/compile.all"
    fi
  elif [ "$(cut -d ' ' -f 1 "$work/report.errors")" = "$reject_prefix" ]; then
    say "unsupported ($reject_reason): the only error"
  else
    say "unsupported ($reject_reason): expected once, among $reject_count unsupported errors"
    show "$work/compile.all"
  fi
  # The first error's line: its location's, after the last `:`; a location
  # in no file (`-`) has none.
  reject_reported=$(awk 'NR == 1 && $2 ~ /:[0-9]+$/ { sub(/.*:/, "", $2); print $2 }' "$work/report.errors")
  if [ "$reject_reported" = "$reject_line" ]; then
    say "line: as the header says"
  else
    say "line: ${reject_reported:-none} reported, the header says $reject_line"
  fi
  if reject_message=$(header "$reject_main" message); then
    if grep -qF -- "$reject_message" "$work/compile.all"; then
      say "message: as the header says"
    else
      say "message: not in the output: $reject_message"
    fi
  fi
  no_artifacts "$work/fixture"
}

# profile_accept FIXTURE: `tests/accept/<desc>/`, a directory holding Main.idr
# and its other modules: it compiles with every artifact written. With an
# expected-stdout or an expected-exit beside it, it also runs, printing
# that stdout (none without the file) and exiting with that status (0
# without the file), with nothing on stderr. What holds of every
# compilation holds of it (universal), read off its dumps.
profile_accept() {
  accept_fixture=$(cd "$1" && pwd)
  profile_prepare "$accept_fixture"
  accept_dumps=$work/fixture/build/exec/Main.dump
  # shellcheck disable=SC2046 # the dump options are words
  profile_compile $(dump_options "$accept_dumps")
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/fixture" Main
  # shellcheck disable=SC2046 # one path per object, none with a space
  universal "$(artifact_file "$work/fixture" Main module)" "$accept_dumps" \
    $(artifact_files "$work/fixture" Main objects)
  [ -f "$accept_fixture/expected-stdout" ] || [ -f "$accept_fixture/expected-exit" ] || return 0
  run_ours accept "$work/fixture/build/exec/Main" /dev/null
  accept_exit=0
  [ -f "$accept_fixture/expected-exit" ] && accept_exit=$(first_word "$accept_fixture/expected-exit")
  if [ "$ran" -eq "$accept_exit" ]; then
    say "run: exit status as expected"
  else
    say "run: exit $ran, expected $accept_exit"
  fi
  : > "$work/accept.expected"
  [ -f "$accept_fixture/expected-stdout" ] && cp "$accept_fixture/expected-stdout" "$work/accept.expected"
  if cmp -s "$work/accept.expected" "$work/accept.out"; then
    say "stdout: as expected"
  else
    say "stdout: differs from expected-stdout"
    diff "$work/accept.expected" "$work/accept.out" | head -n 20 | sed 's/^/  | /'
  fi
  empty stderr "$work/accept.err"
}

# registry_shadowed KEY CASE SOURCE MODULE NAME EDIT MAIN [OPTION...]: an
# input the registry's validation refuses, for its entry KEY. The fixture
# $work/CASE holds MAIN as its Main.idr and, as its own module MODULE (a
# path such as System/Clock.idr), the pinned SOURCE (a path under the
# repository) with one edit to NAME, the definition the entry resolves to:
# `shape` gives its first declaration a leading argument that every use
# fills by default, so the module still checks but NAME has another shape;
# `gone` takes away the paragraph that holds its last declaration (its
# documentation, modifiers and clauses, up to a blank line), for an entry
# that names a definition and fixes no shape.
# The validation reads only the loaded context, so the fixture's own module
# is what it meets. Compiled with OPTION..., the program must stop at the
# entry, with the hook rule, the entry, what it expects and what was found,
# and leave no artifact.
registry_shadowed() {
  rs_key=$1
  rs_case=$2
  rs_source=$root/$3
  rs_module=$4
  rs_name=$5
  rs_edit=$6
  rs_main=$7
  shift 7
  mkdir -p "$work/$rs_case/$(dirname "$rs_module")"
  printf '%s\n' "$rs_main" > "$work/$rs_case/Main.idr"
  case $rs_edit in
    shape)
      awk -v name="$rs_name" '
        !done && ($1 == name || ($1 == "%extern" && $2 == name)) && index($0, name " : ") {
          i = index($0, name " : ") + length(name " : ")
          $0 = substr($0, 1, i - 1) "{default MkUnit shadowed : Unit} -> " substr($0, i)
          done = 1
        }
        { print }
        END { if (!done) exit 1 }' "$rs_source" > "$work/$rs_case/$rs_module" ;;
    gone)
      awk -v name="$rs_name" '
        NR == FNR {
          if (/^[[:space:]]*$/) start = FNR + 1
          if ($1 == name && $2 == ":") { from = start; at = FNR }
          next
        }
        FNR == from { gone = 1 }
        gone && FNR > at && /^[[:space:]]*$/ { gone = 0 }
        !gone { print }
        END { if (!at) exit 1 }' "$rs_source" "$rs_source" > "$work/$rs_case/$rs_module" ;;
  esac || { say "$rs_key broken: $rs_name not found in $3"; return; }
  compile_program "$@" "$work/$rs_case/Main.idr" prog
  say "$rs_key broken: exit $compiled"
  if grep -qF "unsupported (hook): the registry's entry $rs_key (" "$work/compile.out" "$work/compile.err" &&
     grep -q "expects .*, but found " "$work/compile.out" "$work/compile.err"; then
    say "$rs_key broken: the error shows the entry, what it expects and what was found"
  else
    say "$rs_key broken: no hook error for the entry"
    show "$work/compile.out" "$work/compile.err"
  fi
  no_artifacts "$work/$rs_case"
}
