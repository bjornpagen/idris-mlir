# Stock Idris as the oracle of a fixture's value: its Oracle.idr proves
# `Prog.result = <literal>` with Refl, so the stock evaluator agrees with
# the expected stdout, which Main.idr prints; and the generated semantics
# tests, whose Oracle.idr is always `Prog.result = 0`.

# check_oracle FIXTURE: stock Idris checks the fixture's Oracle.idr, so its
# evaluator agrees with the fixture's expectation.
check_oracle() {
  mkdir "$work/oracle"
  copy_fixture "$1" "$work/oracle"
  (cd "$work/oracle" && bounded "$idris2" --no-banner --no-color --no-prelude --check Oracle.idr) > "$work/oracle.log" 2>&1
  check_oracle_status=$?
  if [ "$check_oracle_status" -eq 0 ]; then
    say "oracle: stock idris2 checks Oracle.idr"
  else
    say "oracle: stock idris2 rejects Oracle.idr (exit $check_oracle_status)"
    show "$work/oracle.log"
  fi
}

# oracle_value FIXTURE: the literal of `check : Prog.result = <literal>` in
# its Oracle.idr, which has exactly one `check = Refl`; or a complaint.
oracle_value() {
  oracle_literal=$(sed -n 's/^check[[:space:]]*:[[:space:]]*Prog\.result[[:space:]]*=[[:space:]]*\(-\{0,1\}[0-9][0-9]*\)[[:space:]]*$/\1/p' "$1/Oracle.idr" | head -n 1)
  oracle_refls=$(grep -c '^check[[:space:]]*=[[:space:]]*Refl[[:space:]]*$' "$1/Oracle.idr")
  if [ -z "$oracle_literal" ]; then
    say "Oracle.idr must contain \`check : Prog.result = <integer literal>\`"
    return 1
  fi
  if [ "$oracle_refls" -ne 1 ]; then
    say "Oracle.idr must contain one \`check = Refl\`"
    return 1
  fi
  say "$oracle_literal"
}

# oracle_matches_stdout FIXTURE: when Oracle.idr proves `Prog.result` a
# literal, that literal is the one line of expected-stdout, so the two
# oracles expect the same value. An Oracle.idr that proves something else
# (a string of Main's, say) is checked alone.
oracle_matches_stdout() {
  grep -q '^check[[:space:]]*:[[:space:]]*Prog\.result[[:space:]]*=' "$1/Oracle.idr" || return 0
  oracle_expected=$(oracle_value "$1") || { say "$oracle_expected"; return; }
  if [ "$(cat "$1/expected-stdout" 2> /dev/null)" = "$oracle_expected" ]; then
    say "oracle: proves the value expected-stdout holds"
  else
    say "oracle: proves $oracle_expected, but expected-stdout holds $(cat "$1/expected-stdout" 2> /dev/null)"
  fi
}

# sem_case NAME: the generated semantics test NAME, a fixture whose Prog.idr
# the runner generates (tests/Sem.idr), with a Main.idr that prints
# Prog.result and an Oracle.idr that proves it 0. Stock Idris's evaluator is
# its oracle, the one that matters for the meaning of a primitive, so Chez
# is not run on it (one more backend's arithmetic says nothing new, and the
# 64 programs would add minutes).
sem_case() {
  mkdir "$work/sem"
  if ! "$runtests" --sem-program "$1" > "$work/sem/Prog.idr" 2> "$work/sem.err"; then
    say "no semantics program $1"
    show "$work/sem.err"
    return
  fi
  cat > "$work/sem/Main.idr" <<'MAIN'
module Main

import Prelude
import Prog

main : IO ()
main = printLn Prog.result
MAIN
  cat > "$work/sem/Oracle.idr" <<'ORACLE'
module Oracle

import Builtin
import Prog

check : Prog.result = 0
check = Refl
ORACLE
  echo 0 > "$work/sem/expected-stdout"
  : > "$work/sem/heap-free"
  echo "the generated semantics tests' oracle is stock Idris's evaluator (Oracle.idr)" > "$work/sem/no-chez"
  e2e_io "$work/sem"
}
