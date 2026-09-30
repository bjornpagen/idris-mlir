# The harness every run script stands on: the pinned tools, the work
# directory, bounded commands, the test's output and the fixture files.

# The pinned tools: $llvm_bin, $pinned_cc, $idris_mlir_cc, $idris_mlir_opt,
# and $idris2, stock Idris 2, the reference implementation.
. "$root/tools/toolchain.sh"
runtests=$root/tests/build/exec/runtests
compile_sh=$root/tools/compile.sh
here=$(pwd)

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# bounded CMD...: CMD, killed with everything it started after step_limit
# seconds, so a hang is a failure. A command that timed out exits 124 and says so on
# stderr, which the caller shows with the rest of its output.
bounded() {
  timeout -k 5 "$step_limit" "$@"
  bounded_status=$?
  case $bounded_status in
    124 | 137)
      printf '%s\n' "timed out after ${step_limit}s: ${1##*/}" >&2
      return 124 ;;
  esac
  return "$bounded_status"
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
# left in it.
copy_fixture() {
  if [ -d "$1" ]; then
    for copy_file in "$1"/* "$1"/.[!.]*; do
      case ${copy_file##*/} in run|expected|output|build) continue ;; esac
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

# fixture_name FIXTURE: its directory or file name, without `.idr`.
fixture_name() {
  if [ -d "$1" ]; then
    fixture_name_dir=$(cd "$1" && pwd)
    say "${fixture_name_dir##*/}"
  else
    fixture_name_file=${1##*/}
    say "${fixture_name_file%.idr}"
  fi
}

# first_word FILE: its first whitespace-separated word.
first_word() {
  awk '{ for (i = 1; i <= NF; i++) { print $i; exit } }' "$1"
}
