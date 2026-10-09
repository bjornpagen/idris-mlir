#!/bin/sh
# compiler/idris/ is upstream Idris 2's compiler, forked at the gitlink of
# third_party/Idris2 and pruned to what our frontend needs. MODULES lists
# the upstream source files it keeps, relative to src/, one per line.
#
#     tools/extract-idris.sh extract [--force] [PATH...]
#                       copy each kept file (or each PATH, which MODULES
#                       must list) from the pinned commit into the fork
#     tools/extract-idris.sh status
#                       list the fork's deviations from the pinned commit
#     tools/extract-idris.sh diff OLD NEW
#                       upstream's diff between two Idris commits, kept
#                       files only
#
# `extract` refuses to overwrite a file the fork already has, because the
# copies are ours once extracted, and then copies nothing; --force
# overwrites them. Naming PATHs copies only those, as when a re-sync keeps
# a module the fork did not have before. `status` prints one line per file
# that differs from the pinned upstream: `M path` for a kept file we
# changed, `D path` for a kept file missing from the fork, and `A path` for
# a file of the fork that upstream does not have. `diff` prints a patch
# with full blob ids, so `git apply --3way` can merge it into the fork
# (compiler/idris/README.md has the procedure).
#
# Exit status: 0 on success; 1 when git fails or `extract` would overwrite
# a file; 2 on a usage error.

root=$(cd "$(dirname "$0")/.." && pwd)
upstream=$root/third_party/Idris2
fork=$root/compiler/idris
modules=$fork/MODULES

usage() {
  echo "usage: tools/extract-idris.sh extract [--force] [PATH...] | status | diff OLD NEW" >&2
  exit 2
}

fail() {
  echo "error: $*" >&2
  exit 1
}

# The commit the fork tracks: the superproject's staged gitlink, the one
# tools/verify-pins.sh checks the checkout against.
pin() {
  git -C "$root" rev-parse ":third_party/Idris2" 2> /dev/null ||
    fail "cannot read the gitlink of third_party/Idris2"
}

kept() {
  [ -r "$modules" ] || fail "$modules cannot be read"
  grep -v '^[[:space:]]*$' "$modules"
}

case $1 in
  extract)
    shift
    force=false
    if [ "$1" = --force ]; then
      force=true
      shift
    fi
    commit=$(pin) || exit 1
    paths=$(kept) || exit 1
    if [ $# -gt 0 ]; then
      for path in "$@"; do
        case $path in -*) usage ;; esac
        printf '%s\n' "$paths" | grep -qxF -e "$path" || fail "$path is not listed in $modules"
      done
      paths=$*
    fi
    if [ $force = false ]; then
      existing=$(for path in $paths; do
        [ -e "$fork/src/$path" ] && echo "$path"
      done)
      [ -z "$existing" ] ||
        fail "the fork already has these files (--force overwrites them):
$existing"
    fi
    for path in $paths; do
      mkdir -p "$(dirname "$fork/src/$path")" || exit 1
      git -C "$upstream" show "$commit:src/$path" > "$fork/src/$path" ||
        fail "src/$path is not in Idris $commit"
    done
    ;;
  status)
    [ $# -eq 1 ] || usage
    commit=$(pin) || exit 1
    paths=$(kept) || exit 1
    scratch=$(mktemp "${TMPDIR:-/tmp}/extract-idris.XXXXXX") || exit 1
    trap 'rm -f "$scratch"' EXIT
    for path in $paths; do
      if [ ! -e "$fork/src/$path" ]; then
        echo "D $path"
        continue
      fi
      git -C "$upstream" show "$commit:src/$path" > "$scratch" ||
        fail "src/$path is not in Idris $commit"
      cmp -s "$scratch" "$fork/src/$path" || echo "M $path"
    done
    (cd "$fork/src" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) |
      while IFS= read -r path; do
        grep -qxF -e "$path" "$modules" || echo "A $path"
      done
    ;;
  diff)
    [ $# -eq 3 ] || usage
    paths=$(kept) || exit 1
    # The options pin the patch's form against the user's git configuration
    # (colour, external diff drivers, prefixes), which `git apply` needs.
    # shellcheck disable=SC2086 # one argument per kept path
    git -C "$upstream" diff --full-index --no-color --no-ext-diff --no-textconv \
      --src-prefix=a/ --dst-prefix=b/ "$2" "$3" -- $(printf 'src/%s\n' $paths) ||
      fail "git diff $2 $3 failed in third_party/Idris2"
    ;;
  *) usage ;;
esac
