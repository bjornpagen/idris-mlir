# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The programs the compiler rejects, each by one rule, at the right line,
# and the registry's refusal of an entry whose definition is not the one it
# names.

# header FILE FIELD: the value of `-- FIELD: <value>` among the lines of that
# form that start a refused program; the status is 1 without one. Only
# whether a neighbour carries one is asked here (near_neighbour); the
# header's meaning is the runner's (Reject.idr).
header() {
  awk -v field="$2" '
    !/^--[ \t]*(expect|message):/ { exit }
    {
      key = $0; sub(/^--[ \t]*/, "", key); sub(/:.*$/, "", key)
      if (key == field) { value = $0; sub(/^--[ \t]*[a-z]+:[ \t]*/, "", value); found = 1 }
    }
    END { if (found) { print value; exit 0 } exit 1 }' "$1"
}

# profile_prepare FIXTURE: the fixture directory's files in $work/fixture.
profile_prepare() {
  mkdir "$work/fixture"
  copy_fixture "$1" "$work/fixture"
}

# profile_compile [OPTION]...: $work/fixture/Main.idr to build/exec/Main, with OPTION... and the
# installed packages its `packages` names.
profile_compile() {
  # shellcheck disable=SC2046 # the packages are words
  compile_program $(package_options "$work/fixture") "$@" "$work/fixture/Main.idr" Main
}

# profile_reject FIXTURE: a directory holding Main.idr and its other
# modules, whose first line is `-- expect: <rule>, line <n>` (and then,
# optionally, `-- message: <text>`, text the refusal holds anywhere in it,
# whatever words surround it). It is refused, by that rule alone, reported
# on line n, and leaves no artifact. The header and the compilation's
# report are read once, each into its record, and compared by the runner
# (`runtests --reject`, Reject.idr): the rule one of the specification's,
# the report's every error with its rule, Idris's own errors the rules of
# their category. Nothing here reads the report's text. The module the
# frontend emitted, which the compiler writes whatever its verdict
# (--emitted), is then refused again with a drawn set of the optimizations'
# actions skipped (skips_refuse, lib/actions.sh): a refusal is the
# program's, never the optimizer's.
profile_reject() {
  profile_prepare "$1"
  profile_compile "--report=$work/report" "--emitted=$work/emitted.mlirbc"
  say "compile: exit $compiled"
  cat "$work/compile.out" "$work/compile.err" > "$work/compile.all"
  if ! "$runtests" --reject "$1" "$work/report" "$work/compile.all"; then
    show "$work/compile.all"
  fi
  no_artifacts "$work/fixture"
  skips_refuse "$1" "$work/emitted.mlirbc"
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
# entry: refused by the hook rule alone, as its report says (read by the
# runner, `runtests --refused-by`, Reject.idr), with a message that names
# the entry, what it expects and what was found, and leave no artifact.
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
  compile_program "$@" "--report=$work/$rs_case.report" "$work/$rs_case/Main.idr" prog
  say "$rs_key broken: exit $compiled"
  if "$runtests" --refused-by "$work/$rs_case.report" hook &&
     grep -qF "the registry's entry $rs_key (" "$work/compile.out" "$work/compile.err" &&
     grep -q "expects .*, but found " "$work/compile.out" "$work/compile.err"; then
    say "$rs_key broken: the error shows the entry, what it expects and what was found"
  else
    say "$rs_key broken: no hook error for the entry"
    show "$work/$rs_case.report" "$work/compile.out" "$work/compile.err"
  fi
  no_artifacts "$work/$rs_case"
}
