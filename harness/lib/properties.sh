# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, and nothing
# compiles it a second time: a compile is seconds, and there are hundreds
# of fixtures. What holds of each pass, that it keeps the quantities Idris
# proved and the rest of its contracts, the compilation checks as the pass
# runs (--idr-contracts); what is checked here is what it left. universal
# prints them as one line.

# dumps_verify DUMPS: idris-mlir-opt parses every module the compilation
# dumped (the steps its checks read) again, and its verifier accepts it.
dumps_verify() {
  dv_failed=
  for dv_dump in $(step_dumps "$1"); do
    if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$dv_dump" -o /dev/null > "$work/opt.log" 2>&1; then
      say "dumps: ${dv_dump##*/} does not parse and verify"
      show "$work/opt.log"
      dv_failed=yes
    fi
  done
  [ -z "$dv_failed" ] || return 1
  say "dumps: parse and verify"
}

# universal DUMPS OBJECT...: what holds of every compilation, as one line:
# the objects OBJECT... import nothing a program may not (object_imports),
# and every module the compilation dumped in DUMPS parses and verifies
# again (dumps_verify). One line, `universal: holds`, when all hold;
# otherwise the lines of the checks, and status 1. A check added to every
# compilation is added here, and no transcript changes.
universal() {
  universal_dumps=$1
  shift
  universal_failed=
  object_imports "$@" > "$work/universal.log" || universal_failed=yes
  dumps_verify "$universal_dumps" >> "$work/universal.log" || universal_failed=yes
  if [ -n "$universal_failed" ]; then
    cat "$work/universal.log"
    return 1
  fi
  say "universal: holds"
}
