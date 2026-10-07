# Shared by tests/upstream-idris/run and tests/upstream-idris/one.
# The upstream suite is third_party/Idris2/tests: each test is a directory
# with a run script that receives the compiler as $1 (upstream's own
# testutils.sh). This compiler is that compiler for the groups that are
# programs over the prelude and base. Chez, invoked as the stock idris2,
# is the oracle for a program's output. A check or a REPL session is the
# same frontend, so the oracle there is the stock compiler's transcript.

# language_group NAME: NAME is a group whose tests are that language
# (prelude, base, the language checks under idris2/, and the programs
# upstream runs on every backend). Printed one per line with no argument.
language_group() {
  language_groups='prelude
base
allbackends
allschemes
typedd-book
idris2/basic
idris2/builtin
idris2/casetree
idris2/coverage
idris2/data
idris2/error
idris2/evaluator
idris2/failing
idris2/false
idris2/interface
idris2/linear
idris2/literate
idris2/misc
idris2/operators
idris2/perf
idris2/reflection
idris2/reg
idris2/termination
idris2/total
idris2/warning
idris2/with'
  if [ $# -eq 0 ]; then
    printf '%s\n' "$language_groups"
    return 0
  fi
  printf '%s\n' "$language_groups" | grep -qx "$1"
}

# outside_reason GROUP: why a whole upstream group is not this language,
# or nothing when the group is run test by test.
outside_reason() {
  case $1 in
    chez | node | refc | racket | gambit | codegen | vmcode)
      printf '%s\n' "other backend" ;;
    contrib | linear)
      printf '%s\n' "not a commitment" ;;
    ideMode | cli | ttimp | idris2/pkg | idris2/repl | idris2/interactive | \
      idris2/mkdoc | idris2/api | idris2/schemeeval | idris2/debug)
      printf '%s\n' "compiler interface" ;;
    templates)
      printf '%s\n' "template" ;;
  esac
}

# ident_in FILE NAME: NAME is an identifier in FILE, lexed source or a
# script, not a prefix of a longer name.
ident_in() {
  grep -qE "(^|[^A-Za-z0-9_'])$2([^A-Za-z0-9_']|\$)" "$1"
}

# skip_reason DIR: why DIR's program is outside the language, or nothing.
# Threads, collector finalizers, raw pointers, unsafePerformIO in the
# test's own source, network, and the packages this compiler does not
# implement. The scan is the source with comments and strings removed
# (tests/lib/idris-lex.sh) plus the run script's package flags.
skip_reason() {
  skip_dir=$1
  skip_code=$(mktemp "${TMPDIR:-/tmp}/idris-mlir-upstream.XXXXXX") || return 1
  : > "$skip_code"
  find "$skip_dir" \( -name build -o -name prefix \) -prune -o -type f \
    \( -name '*.idr' -o -name '*.lidr' -o -name '*.yaff' \) -print |
    while IFS= read -r skip_file; do
      idris_lex code "$skip_file" >> "$skip_code"
    done
  if [ -f "$skip_dir/run" ]; then
    sed 's/[[:space:]]*#.*//' "$skip_dir/run" >> "$skip_code"
  fi
  skip_found=
  if ident_in "$skip_code" fork || ident_in "$skip_code" forkIO ||
     ident_in "$skip_code" threadWait || ident_in "$skip_code" prim__fork ||
     ident_in "$skip_code" prim__threadWait ||
     grep -qE 'import[[:space:]]+(public[[:space:]]+)?System\.Concurrency' "$skip_code"; then
    skip_found=threads
  elif ident_in "$skip_code" onCollect || ident_in "$skip_code" onCollectAny; then
    skip_found=finalizer
  elif ident_in "$skip_code" prim__castPtr || ident_in "$skip_code" prim__forgetPtr ||
       ident_in "$skip_code" prim__nullPtr || ident_in "$skip_code" prim__nullAnyPtr ||
       ident_in "$skip_code" prim__getNullAnyPtr || ident_in "$skip_code" prim__getString ||
       ident_in "$skip_code" getEnv; then
    skip_found="raw pointer"
  elif ident_in "$skip_code" unsafePerformIO; then
    skip_found=unsafePerformIO
  elif ident_in "$skip_code" Network ||
       grep -qE '(^|[^A-Za-z0-9_])-p[[:space:]]+network([^A-Za-z0-9_]|$)' "$skip_code"; then
    skip_found=network
  elif grep -qE '(^|[^A-Za-z0-9_])-p[[:space:]]+(contrib|linear|test)([^A-Za-z0-9_]|$)' "$skip_code" ||
       grep -qE 'import[[:space:]]+(public[[:space:]]+)?(Contrib|Linear)([^A-Za-z0-9_.]|$)' "$skip_code"; then
    skip_found="not a commitment"
  fi
  rm -f "$skip_code"
  printf '%s\n' "$skip_found"
}

# rejection_skip TEXT: threads, finalizer or raw pointer when the compiler
# already refused the program with that reason, which is not a failure of
# a program outside the language. unsafePerformIO comes back as
# unsupported (world).
rejection_skip() {
  case $1 in
    *'unsupported (threads)'*) printf '%s\n' threads ;;
    *'unsupported (finalizer)'*) printf '%s\n' finalizer ;;
    *'unsupported (raw pointer)'*) printf '%s\n' "raw pointer" ;;
    *'unsupported (world)'*unsafePerformIO* | *unsafePerformIO*'unsupported (world)'*)
      printf '%s\n' unsafePerformIO ;;
  esac
}

# one_line TEXT: TEXT as a single field, truncated.
one_line() {
  printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ *$//' | cut -c 1-220
}
