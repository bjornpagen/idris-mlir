# The prelude's coverage. A fixture marked `covers MODULE` is a program
# that uses every definition MODULE of the stock prelude exports at run
# time. Which definitions those are is the pinned Idris's: :browse lists
# them from its checked context, so the list follows the pin and is never
# written down here. Which the program uses is this compiler's: its Core
# (prog.core) names every definition once the frontend has resolved it,
# as MODULE.name, MODULE.(op) and MODULE.Type::Con. And the program's
# output is compared with Chez's as every e2e program's is, so what it
# uses is also what it computes right.
#
# A type, and a definition whose result is a type or an equality (a
# proof), has no run time: it is named apart, as compile-time only, and
# not asked of the program. So is an interface's constructor (MkEq), which
# the pinned Idris names in the interface's :doc: this compiler resolves
# every implementation at compile time, specialising each method call to
# the implementation it is given, so the record is never built (an
# implementation chosen at run time is refused), and the methods' uses are
# what the program's Core shows.

# prelude_exports MODULE: what MODULE exports, one `name<TAB>type` per line,
# an operator with its parentheses, as :browse prints it.
prelude_exports() {
  printf ':browse %s\n:q\n' "$1" |
    (cd "$work" && bounded "$idris2" --no-banner --no-color) 2> "$work/browse.err" |
    awk -v FS=' : ' '
      { sub(/^Main> /, "") }
      NF >= 2 && $1 !~ / / {
        type = substr($0, length($1) + 4)
        print $1 "\t" type
      }'
}

# compile_time_only TYPE: whether a definition of TYPE has no run time: its
# result, after the last arrow outside parentheses, is a type or an
# equality.
compile_time_only() {
  printf '%s\n' "$1" | awk '{
    s = $0
    while (gsub(/\([^()]*\)/, "_", s) > 0) {}
    n = split(s, parts, / -> /)
    result = parts[n]
    exit !(result ~ /(^|[^A-Za-z0-9_])Type$/ || result ~ / = /)
  }'
}

# interface_constructors MODULE NAME...: the constructors of the interfaces
# among the NAMEs that MODULE exports, one per line, as their :doc names
# them, all asked of one session of the pinned Idris.
interface_constructors() {
  ic_module=$1
  shift
  { for ic_name in "$@"; do printf ':doc %s.%s\n' "$ic_module" "$ic_name"; done; printf ':q\n'; } |
    (cd "$work" && bounded "$idris2" --no-banner --no-color) 2> /dev/null |
    awk '
      /^Main> / { inside = ($0 ~ /^Main> interface /) }
      inside && /^  Constructor: / { sub(/^  Constructor: /, ""); print }'
}

# covers_prelude MODULE CORE: every run-time export of MODULE is used by the
# program whose Core is CORE.
covers_prelude() {
  cp_module=$1
  cp_core=$2
  prelude_exports "$cp_module" > "$work/exports"
  if [ ! -s "$work/exports" ]; then
    # :browse prints the same nothing for a module that exports nothing
    # (Prelude.Ops declares only fixities) and for one that does not exist,
    # so the pinned Idris is asked to import it: a module it imports and
    # that lists no export has nothing a program could use. Its --check
    # exits 0 on an error too, so an error is told by what it prints.
    printf 'module Imports\nimport %s\n' "$cp_module" > "$work/Imports.idr"
    (cd "$work" && bounded "$idris2" --no-banner --no-color --check Imports.idr) > "$work/import.out" 2>&1
    if ! grep -q '^Error:' "$work/import.out"; then
      say "prelude $cp_module: exports nothing at run time"
    else
      say "prelude $cp_module: the pinned Idris neither lists an export nor imports the module"
      show "$work/import.out" "$work/browse.err"
    fi
    return
  fi
  # The type formers among the exports, whose interfaces' constructors are
  # compile-time values.
  : > "$work/type-formers"
  while IFS="$(printf '\t')" read -r cp_name cp_type; do
    case $cp_type in *Type) printf '%s\n' "$cp_name" >> "$work/type-formers" ;; esac
  done < "$work/exports"
  # shellcheck disable=SC2046 # one name per line, each a word
  interface_constructors "$cp_module" $(cat "$work/type-formers") > "$work/interface-constructors"
  : > "$work/compile-time"
  : > "$work/missing"
  cp_total=0
  cp_used=0
  while IFS="$(printf '\t')" read -r cp_name cp_type; do
    cp_total=$((cp_total + 1))
    if compile_time_only "$cp_type" || grep -qxF -- "$cp_name" "$work/interface-constructors"; then
      printf '%s\n' "$cp_name" >> "$work/compile-time"
    elif core_uses "$cp_module" "$cp_name" "$cp_core"; then
      cp_used=$((cp_used + 1))
    else
      printf '%s\n' "$cp_name" >> "$work/missing"
    fi
  done < "$work/exports"
  cp_compile=$(wc -l < "$work/compile-time" | tr -d ' ')
  if [ -s "$work/missing" ]; then
    say "prelude $cp_module: $cp_total exports; $cp_used used, these not: $(tr '\n' ' ' < "$work/missing" | sed 's/ $//')"
  else
    say "prelude $cp_module: $cp_total exports, each used ($cp_compile compile-time only: $(tr '\n' ' ' < "$work/compile-time" | sed 's/ $//'))"
  fi
}

# core_uses MODULE NAME CORE: whether CORE names NAME of MODULE: as
# MODULE.name or MODULE.(op) followed by what ends a name in Core, or as a
# constructor, MODULE.Type::name( with the type's arguments in brackets
# after its name and an operator without its parentheses
# (Prelude.Basics.List[Int]::::( is (::)).
core_uses() {
  awk -v module="$1" -v name="$2" '
    # Whether `s` ends in MODULE.Type, after one balanced [...] if it has one.
    function type_of_module(s,    depth, k, c) {
      if (substr(s, length(s), 1) == "]") {
        depth = 0
        for (k = length(s); k > 0; k--) {
          c = substr(s, k, 1)
          if (c == "]") depth++
          else if (c == "[" && --depth == 0) break
        }
        if (k == 0) return 0
        s = substr(s, 1, k - 1)
      }
      return s ~ type_before
    }
    BEGIN {
      operator = substr(name, 1, 1) == "("
      bare = operator ? substr(name, 2, length(name) - 2) : name
      token = module "." (operator ? substr(name, 1, length(name) - 1) : name)
      ends = operator ? ")[{" : "[{( )],:"
      constructor = "::" bare "("
      qualified = module
      gsub(/\./, "\\.", qualified)
      type_before = "(^|[^A-Za-z0-9_.])" qualified "\\.[A-Za-z0-9_'\'']+$"
    }
    {
      line = $0
      rest = line
      while ((i = index(rest, token)) > 0) {
        next_char = substr(rest, i + length(token), 1)
        if (next_char == "" || index(ends, next_char) > 0) { found = 1; exit }
        rest = substr(rest, i + 1)
      }
      rest = line
      while ((i = index(rest, constructor)) > 0) {
        if (type_of_module(substr(rest, 1, i - 1))) { found = 1; exit }
        rest = substr(rest, i + 1)
      }
    }
    END { exit !found }' "$3"
}
