# Stock Idris as the oracle of a fixture's value: its Oracle.idr, and the
# generated semantics tests, whose Oracle.idr is always `Prog.main = 0`.

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

# oracle_value FIXTURE: the literal of `check : Prog.main = <literal>` in its
# Oracle.idr, which has exactly one `check = Refl`; or a complaint.
oracle_value() {
  oracle_literal=$(sed -n 's/^check[[:space:]]*:[[:space:]]*Prog\.main[[:space:]]*=[[:space:]]*\(-\{0,1\}[0-9][0-9]*\)[[:space:]]*$/\1/p' "$1/Oracle.idr" | head -n 1)
  oracle_refls=$(grep -c '^check[[:space:]]*=[[:space:]]*Refl[[:space:]]*$' "$1/Oracle.idr")
  if [ -z "$oracle_literal" ]; then
    say "Oracle.idr must contain \`check : Prog.main = <integer literal>\`"
    return 1
  fi
  if [ "$oracle_refls" -ne 1 ]; then
    say "Oracle.idr must contain one \`check = Refl\`"
    return 1
  fi
  say "$oracle_literal"
}

# sem_case NAME: the generated semantics test NAME, a v0 fixture whose Prog.idr the
# runner generates (tests/Sem.idr) and whose Oracle.idr proves
# `Prog.main = 0`.
sem_case() {
  mkdir "$work/sem"
  if ! "$runtests" --sem-program "$1" > "$work/sem/Prog.idr" 2> "$work/sem.err"; then
    say "no semantics program $1"
    show "$work/sem.err"
    return
  fi
  cat > "$work/sem/Oracle.idr" <<'ORACLE'
module Oracle

import Builtin
import Prog

check : Prog.main = 0
check = Refl
ORACLE
  e2e_v0 "$work/sem"
}
