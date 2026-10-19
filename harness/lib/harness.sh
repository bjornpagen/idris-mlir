# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The harness every run script stands on: the pinned tools, the work
# directory, bounded commands, the test's output and the fixture files.

# The pinned tools: $llvm_bin, $pinned_cc, $idris_mlir (the compiler under
# test, with its frontend $idris_mlir_front beside it), $idris_mlir_opt,
# and $idris2, the pinned stock Idris 2, which the frontend is built by
# and which a test asks about the prelude it checked (pinned_idris).
. "$root/tools/toolchain.sh"
runtests=$root/harness/build/exec/runtests
compile_sh=$root/tools/compile.sh
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
# seconds, so a hang is a failure. A command that timed out exits 124 and says so on
# stderr, which the caller shows with the rest of its output.
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

# show FILE...: files a failure is about, indented.
show() {
  cat "$@" 2> /dev/null | head -n 40 | sed 's/^/  | /'
}

# empty NAME FILE: FILE is empty.
empty() {
  if [ -s "$2" ]; then say "$1: not empty"; show "$2"; else say "$1: empty"; fi
}

# copy_fixture FIXTURE DEST: a fixture file, or the files and module
# directories of a fixture directory but the golden test's own and a build
# left in it, and the cases and the neighbour (near/) the harness reads in
# place.
copy_fixture() {
  if [ -d "$1" ]; then
    for copy_file in "$1"/* "$1"/.[!.]*; do
      case ${copy_file##*/} in run|expected|expected.*|suite|targets|build|cases|near) continue ;; esac
      # A module in a namespace is a file in its directory (Data/Evil.idr).
      if [ -d "$copy_file" ]; then
        cp -Rp "$copy_file" "$2/"
        continue
      fi
      [ -f "$copy_file" ] || continue
      cp -p "$copy_file" "$2/"
    done
  else
    cp -p "$1" "$2/"
  fi
}

# fixture_name FIXTURE: the name of the fixture directory, its test's.
fixture_name() {
  fixture_name_dir=$(cd "$1" && pwd)
  say "${fixture_name_dir##*/}"
}

# package_options DIR: `-p PACKAGE` for each installed package DIR's
# `packages` file names, as words; nothing without the file.
package_options() {
  [ -f "$1/packages" ] || return 0
  for package_name in $(cat "$1/packages"); do printf ' -p %s' "$package_name"; done
}

# first_word FILE: its first whitespace-separated word.
first_word() {
  awk '{ for (i = 1; i <= NF; i++) { print $i; exit } }' "$1"
}

# repeated FILE N OUT: FILE's lines N times over, in OUT: a long input, built
# where the test runs rather than kept in the repository. Status 1, and a
# line that says so, when N is not a count.
repeated() {
  case $2 in
    '' | *[!0-9]*)
      say "input: $2 is not a number of copies"
      return 1 ;;
  esac
  awk -v n="$2" '{ line[NR] = $0 }
    END { for (i = 0; i < n; i++) for (j = 1; j <= NR; j++) print line[j] }' "$1" > "$3"
}
