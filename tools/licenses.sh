#!/bin/sh
# Every source file names its license on its first line:
# ours 0BSD, a port Apache-2.0 WITH LLVM-exception with its upstream
# copyright kept, the Idris fork BSD-3-Clause. This script is the one
# place that knows the sets:
#
#   tools/licenses.sh           check: list in-scope files with no (or a
#                               wrong) SPDX line; exit 1 if any
#   tools/licenses.sh --apply   write the missing lines (ours and the
#                               fork's; a port is never written by this
#                               script, it arrives with its header)
#
# In scope, ours: foreign/ and runtime/ C++ (.cpp, .h, .td, .c),
# compiler/src/ and libs/ Idris (.idr), tests/ Idris outside the
# fixture trees, tools/*.sh. Out of scope, listed not skipped
# silently: test fixtures (tests/idr, tests/programs and their kin --
# a header would change expected output), the generated dialect
# modules (compiler/src/IdrisMLIR/Syntax/ and Dialect/, written by
# idris-mlir-tblgen on every build; their generator is ours and in
# scope), third_party/, build/, sources/. The fork:
# compiler/idris/**/*.idr.
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

apply=0
[ "${1:-}" = --apply ] && apply=1

ours=$(find foreign runtime -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.td' -o -name '*.c' \) | sort)
ours="$ours
$(find compiler/src libs -type f -name '*.idr' -not -path 'compiler/src/IdrisMLIR/Syntax/*' -not -path 'compiler/src/IdrisMLIR/Dialect/*' | sort)
$(find tests -maxdepth 2 -type f -name '*.idr' | sort)
$(find tools -maxdepth 1 -type f -name '*.sh' | sort)"
fork=$(find compiler/idris -type f -name '*.idr' | sort)

header_for() {
  # $1 file, $2 identifier, $3 copyright holder
  case $1 in
    *.idr) printf -- '-- SPDX-License-Identifier: %s\n-- Copyright (c) %s\n' "$2" "$3" ;;
    *.sh) printf '# SPDX-License-Identifier: %s\n# Copyright (c) %s\n' "$2" "$3" ;;
    *) printf '// SPDX-License-Identifier: %s\n// Copyright (c) %s\n' "$2" "$3" ;;
  esac
}

# check_or_apply LIST IDENTIFIER HOLDER
bad=0
check_or_apply() {
  list=$1 id=$2 holder=$3
  for f in $list; do
    if grep -q 'SPDX-License-Identifier:' "$f"; then
      grep -q "SPDX-License-Identifier: $id" "$f" ||
        grep -q 'SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception' "$f" ||
        { echo "$f: unexpected identifier"; bad=1; }
      continue
    fi
    if [ "$apply" -eq 0 ]; then
      echo "$f: no SPDX line"
      bad=1
      continue
    fi
    tmp=$f.lic-tmp
    case $f in
      *.sh)
        head -n 1 "$f" > "$tmp"
        header_for "$f" "$id" "$holder" >> "$tmp"
        tail -n +2 "$f" >> "$tmp"
        ;;
      *)
        header_for "$f" "$id" "$holder" > "$tmp"
        cat "$f" >> "$tmp"
        ;;
    esac
    # Back through the file itself, so its mode (a script's
    # executable bit) survives the rewrite.
    cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

check_or_apply "$ours" 0BSD '2026 Bjorn Pagen'
check_or_apply "$fork" BSD-3-Clause '2020 Edwin Brady'

# The full text of every identifier in use is in LICENSES/.
for text in 0BSD Apache-2.0 LLVM-exception BSD-3-Clause; do
  [ -s "LICENSES/$text.txt" ] || { echo "LICENSES/$text.txt: missing"; bad=1; }
done

if [ "$apply" -eq 1 ] && [ "$bad" -eq 0 ]; then
  echo "licenses: SPDX lines written"
elif [ "$bad" -eq 0 ]; then
  echo "licenses: every in-scope file names its licence"
fi
exit "$bad"
