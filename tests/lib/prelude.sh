# The prelude's coverage. A fixture marked `covers MODULE` is a program
# that uses every definition MODULE of the stock prelude exports at run
# time. Which definitions those are is the pinned Idris's: :browse lists
# them from its checked context, so the list follows the pin and is never
# written down here. Which the program uses is this compiler's: its Core
# (prog.core) names every definition once the frontend has resolved it,
# by its full name, namespaces and all, as Prelude.Types.List.length[Int](,
# a constructor after its type, as Prelude.Types.(<=>)[...]::MkEquivalence(,
# and a definition the compiler's registry lowers another way in braces
# after what its call became, as add_Nat{Prelude.Types.plus}(. And the
# program's output is held to its expected-stdout as every e2e program's
# is, so what it uses is also what it computes right. A module's exports
# are the definitions it makes itself: one it re-exports is covered in the
# module that defines it.
#
# A type, and a definition whose result is a type or an equality (a
# proof), has no run time: it is named apart, as compile-time only, and
# not asked of the program. So is an interface's constructor (MkEq), which
# the pinned Idris names in the interface's :doc: this compiler resolves
# every implementation at compile time, specialising each method call to
# the implementation it is given, so the record is never built (an
# implementation chosen at run time is refused), and the methods' uses are
# what the program's Core shows. Two more kinds are named apart when Core
# does not name them. An escape hatch, which user code may not write, is
# asked of the compiler. A decided exclusion is outside the language
# (threads, collector finalizers, raw pointers): those names are the only
# ones written down here, and a later export is still asked of the compiler.

# The pinned prelude's source, from which the pinned Idris built the
# prelude it loads: its IDE mode names a definition's module by the file it
# finds for it here.
prelude_source=$root/third_party/Idris2/libs/prelude

# prelude_exports MODULE: what MODULE exports, one `name<TAB>type<TAB>type`
# per line, an operator with its parentheses, as :browse prints it, in its
# order; the second type is the first with its implicits, as Idris prints
# it with showimplicits, which a program can write.
prelude_exports() {
  printf ':browse %s\n:q\n' "$1" | browsed > "$work/browse.plain"
  printf ':set showimplicits\n:browse %s\n:q\n' "$1" | browsed > "$work/browse.implicit"
  if [ "$(wc -l < "$work/browse.plain")" -eq "$(wc -l < "$work/browse.implicit")" ]; then
    cut -f 2 "$work/browse.implicit" | paste "$work/browse.plain" -
  else
    cat "$work/browse.plain"
  fi
}

# browsed: the pinned Idris's REPL on the commands on stdin, the lines of
# their :browse as `name<TAB>type`.
browsed() {
  (cd "$work" && bounded "$idris2" --no-banner --no-color) 2> "$work/browse.err" |
    awk -v FS=' : ' '
      { sub(/^(Main> )+/, "") }
      NF >= 2 && $1 !~ / / {
        type = substr($0, length($1) + 4)
        print $1 "\t" type
      }'
}

# prelude_definitions NAMES: every definition the pinned Idris has under
# one of the bare NAMES (one per line, as :browse prints them), one
# `full name<TAB>module` per line. :browse prints a name without its
# namespace, so a name it lists twice (List.length and String.length) is
# two definitions; IDE mode's name-at lists every definition of a bare
# name with its full name and its location, which the checked context
# keeps as the module that defined it, and which IDE mode prints as that
# module's file in the pinned source. Only an operator that begins with a
# dot, (.) or (.:), is out of name-at's reach, which reads `.` as a
# projection: :di prints its full name, and its module is the one that
# defines the rest of its namespace.
prelude_definitions() {
  awk '
    /^\(\./ { next }
    {
      n = $0
      if (n ~ /^\(.*\)$/) n = substr(n, 2, length(n) - 2)
      gsub(/\\/, "\\\\", n)
      gsub(/"/, "\\\"", n)
      printf "((:name-at \"%s\") %d)\n", n, NR
    }' "$1" |
    (cd "$work" && bounded "$idris2" --ide-mode --source-dir "$prelude_source") 2> "$work/name-at.err" |
    awk -v source="$prelude_source/" '
      /^[0-9a-f]+\(:return \(:ok \(/ {
        s = $0
        while (match(s, /\("([^"\\]|\\.)*" \(:filename "([^"\\]|\\.)*"\)/)) {
          item = substr(s, RSTART + 2, RLENGTH - 4)
          s = substr(s, RSTART + RLENGTH)
          q = index(item, "\" (:filename \"")
          full = substr(item, 1, q - 1)
          file = substr(item, q + 14)
          gsub(/\\"/, "\"", full)
          gsub(/\\\\/, "\\", full)
          module = "?"
          if (index(file, source) == 1 && file ~ /\.idr$/) {
            module = substr(file, length(source) + 1, length(file) - length(source) - 4)
            gsub(/\//, ".", module)
          }
          print full "\t" module
        }
      }' > "$work/named-at"
  grep '^(\.' "$1" | awk '{ print ":di " $0 } END { print ":q" }' |
    (cd "$work" && bounded "$idris2" --no-banner --no-color) 2> /dev/null |
    awk -v names="$1" -v named="$work/named-at" '
      function space(full,    k) {
        if (substr(full, length(full), 1) == ")") k = index(full, ".(")
        else { k = length(full); while (k > 0 && substr(full, k, 1) != ".") k-- }
        return substr(full, 1, k - 1)
      }
      BEGIN {
        while ((getline n < names) > 0) if (n ~ /^\(\./) asked[n] = 1
        FS = "\t"
        while ((getline line < named) > 0) {
          split(line, f, "\t")
          s = space(f[1])
          if (!(s in of)) of[s] = f[2]
          else if (of[s] != f[2]) of[s] = "?"
        }
        FS = " "
      }
      {
        line = $0
        sub(/^Main> /, "", line)
        sub(/^[01] /, "", line)
        if (line ~ / /) next
        for (n in asked)
          if (length(line) > length(n) + 1 && substr(line, length(line) - length(n)) == "." n)
            print line "\t" ((space(line) in of) ? of[space(line)] : "?")
      }' >> "$work/named-at"
  cat "$work/named-at"
}

# own_exports MODULE EXPORTS DEFINITIONS: EXPORTS (prelude_exports) with
# each line's definition, one `full name<TAB>module<TAB>type<TAB>type` per
# line in :browse's order. :browse lists the visible definitions whose
# namespace is MODULE's or within it, sorted by full name as Idris orders
# names: the name, then its namespace innermost component first. So the
# copies of a name pair off with its definitions in that order. A line no
# definition pairs with has its full name `?`, and a definition left over
# (one :browse does not list) its module.
own_exports() {
  awk -F '\t' -v module="$1" '
    function last(full,    k) {
      if (substr(full, length(full), 1) == ")") return substr(full, index(full, ".(") + 1)
      k = length(full)
      while (k > 0 && substr(full, k, 1) != ".") k--
      return substr(full, k + 1)
    }
    {
      name = last($1)
      space = substr($1, 1, length($1) - length(name) - 1)
      if (space != module && index(space, module ".") != 1) next
      n = split(space, part, ".")
      key = ""
      for (i = n; i > 0; i--) key = key part[i] "\001"
      print name "\t" key "\t" $1 "\t" $2
    }' "$3" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 > "$work/candidates"
  awk -F '\t' -v candidates="$work/candidates" '
    BEGIN {
      while ((getline line < candidates) > 0) {
        split(line, c, "\t")
        count[c[1]]++
        full[c[1], count[c[1]]] = c[3]
        home[c[1], count[c[1]]] = c[4]
      }
    }
    {
      name = ($1 ~ /^\./) ? "(" $1 ")" : $1
      i = ++taken[name]
      if (i <= count[name]) print full[name, i] "\t" home[name, i] "\t" $2 "\t" $3
      else print "?\t?\t" $2 "\t" $3
    }
    END {
      for (name in count)
        for (i = taken[name] + 1; i <= count[name]; i++) print full[name, i] "\t?\t?\t?"
    }' "$2"
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

# interface_constructors NAME...: the constructors of the interfaces among
# the full NAMEs, one full name per line, as their :doc names them (in the
# interface's namespace), all asked of one session of the pinned Idris.
interface_constructors() {
  { for ic_name in "$@"; do printf ':doc %s\n' "$ic_name"; done; printf ':q\n'; } |
    (cd "$work" && bounded "$idris2" --no-banner --no-color) 2> /dev/null |
    awk -v names="$*" '
      BEGIN { n = split(names, asked, " ") }
      /^Main> / {
        i++
        inside = ($0 ~ /^Main> interface /)
        space = asked[i]
        sub(/\.[^.]*$/, "", space)
      }
      inside && /^  Constructor: / { sub(/^  Constructor: /, ""); print space "." $0 }'
}

# escape_hatch MODULE NAME TYPE: whether the compiler under test refuses
# NAME of MODULE, of TYPE as the pinned Idris prints it with its implicits,
# in user code as an escape hatch or as a use of the world. The compiler is
# the one record of what user code may not write (Idris's %unsafe flag, the
# spellings and the world operations its registry forbids, the primitives
# of believe_me and idris_crash), so it is asked: a program whose main only
# names NAME (partial, as NAME may be) is refused, and what it refuses is
# NAME itself, as `the escape hatch NAME`, `NAME` or `uses NAME`. Not what
# NAME reaches, and not NAME as `%foreign NAME` or `%extern NAME`.
# `%foreign`, and `%extern` as a C export, are outside the language: not
# an escape hatch, and not a primitive left to implement. A buffer
# operation is a runtime primitive; this check does not see `Data.Buffer`.
escape_hatch() {
  eh_dir=$work/probe-$(printf '%s' "$2" | cksum | awk '{ print $1 }')
  mkdir -p "$eh_dir"
  printf 'module Main\n\nimport Prelude\nimport %s\n\npartial\nmain : IO ()\nmain = let 0 probe : (%s) = %s in pure ()\n' \
    "$1" "$3" "$2" > "$eh_dir/Main.idr"
  bounded env "IDRIS_MLIR=$idris_mlir" "$compile_sh" "$eh_dir/Main.idr" probe > "$eh_dir/out" 2>&1
  awk -v full="$2" '
      BEGIN { bare = full; sub(/^.*\./, "", bare) }
      match($0, /unsupported \((escape hatch|world)\): /) {
        what = substr($0, RSTART + RLENGTH)
        sub(/ \(reached through .*$/, "", what)
        found = what == "the escape hatch " full || what == "the escape hatch " bare ||
                what == bare || what == "uses " full
        exit
      }
      END { exit !found }' "$eh_dir/out"
}

# decided_exclusion FULL: whether FULL is outside the language, by the
# decision on threads, collector finalizers and raw pointers. The only
# names written down in this check. A name that is not one of these is
# asked of the program and, if Core does not name it, of the compiler.
decided_exclusion() {
  case $1 in
    Prelude.IO.fork | Prelude.IO.prim__fork | Prelude.IO.threadWait | Prelude.IO.prim__threadWait | \
    Prelude.IO.onCollect | Prelude.IO.onCollectAny | Prelude.IO.prim__getString | \
    PrimIO.prim__castPtr | PrimIO.prim__forgetPtr | PrimIO.prim__nullPtr | \
    PrimIO.prim__nullAnyPtr | PrimIO.prim__getNullAnyPtr)
      return 0 ;;
  esac
  return 1
}

# covers_prelude MODULE CORE: every run-time export of MODULE is used by the
# program whose Core is CORE.
covers_prelude() {
  cp_module=$1
  cp_core=$2
  prelude_exports "$cp_module" > "$work/exports"
  awk -F '\t' '{ print $1 }' "$work/exports" | sort -u > "$work/export-names"
  prelude_definitions "$work/export-names" > "$work/definitions"
  own_exports "$cp_module" "$work/exports" "$work/definitions" > "$work/paired"
  if grep -q '^?' "$work/paired" || cut -f 2 "$work/paired" | grep -qx '?'; then
    say "prelude $cp_module: the pinned Idris's exports and definitions do not pair off"
    grep -n '?' "$work/paired" | head -n 20 | sed 's/^/  | /'
    return
  fi
  # A definition of another module, which this module re-exports, is
  # covered where it is defined.
  awk -F '\t' -v module="$cp_module" '$2 == module { print $1 "\t" $3 "\t" $4 }' "$work/paired" > "$work/own"
  cp_others=$(awk -F '\t' -v module="$cp_module" '$2 != module' "$work/paired" | wc -l | tr -d ' ')
  if [ ! -s "$work/own" ]; then
    # :browse prints the same nothing for a module that exports nothing
    # (Prelude.Ops declares only fixities) and for one that does not exist,
    # so the pinned Idris is asked to import it: a module it imports and
    # that lists no export of its own has nothing a program could use. Its
    # --check exits 0 on an error too, so an error is told by what it
    # prints.
    printf 'module Imports\nimport %s\n' "$cp_module" > "$work/Imports.idr"
    (cd "$work" && bounded "$idris2" --no-banner --no-color --check Imports.idr) > "$work/import.out" 2>&1
    if grep -q '^Error:' "$work/import.out"; then
      say "prelude $cp_module: the pinned Idris neither lists an export nor imports the module"
      show "$work/import.out" "$work/browse.err"
    elif [ "$cp_others" -eq 0 ]; then
      say "prelude $cp_module: exports nothing at run time"
    else
      say "prelude $cp_module: exports nothing of its own; its $cp_others exports are other modules', each left to the module that defines it"
    fi
    return
  fi
  # The type formers among the exports, whose interfaces' constructors are
  # compile-time values.
  awk -F '\t' '$2 ~ /Type$/ { print $1 }' "$work/own" > "$work/type-formers"
  # shellcheck disable=SC2046 # one name per line, each a word
  interface_constructors $(cat "$work/type-formers") > "$work/interface-constructors"
  : > "$work/compile-time"
  : > "$work/unused"
  cp_total=0
  cp_used=0
  while IFS="$(printf '\t')" read -r cp_full cp_type cp_implicit; do
    cp_total=$((cp_total + 1))
    if compile_time_only "$cp_type" || grep -qxF -- "$cp_full" "$work/interface-constructors"; then
      printf '%s\n' "$cp_full" >> "$work/compile-time"
    elif core_uses "$cp_full" "$cp_core"; then
      cp_used=$((cp_used + 1))
    else
      printf '%s\t%s\n' "$cp_full" "$cp_implicit" >> "$work/unused"
    fi
  done < "$work/own"
  # What Core does not name may be a decided exclusion or an escape hatch;
  # anything else is missing. The exclusion is recognized by name, so a
  # probe is not asked to compile a program that reaches it.
  : > "$work/escape-hatches"
  : > "$work/decided"
  : > "$work/missing"
  while IFS="$(printf '\t')" read -r cp_full cp_implicit; do
    if decided_exclusion "$cp_full"; then
      printf '%s\n' "$cp_full" >> "$work/decided"
    elif [ -n "$cp_implicit" ] && escape_hatch "$cp_module" "$cp_full" "$cp_implicit"; then
      printf '%s\n' "$cp_full" >> "$work/escape-hatches"
    else
      printf '%s\n' "$cp_full" >> "$work/missing"
    fi
  done < "$work/unused"
  cp_compile=$(wc -l < "$work/compile-time" | tr -d ' ')
  cp_apart=" ($cp_compile compile-time only: $(names_in "$cp_module" "$work/compile-time")"
  cp_hatches=$(wc -l < "$work/escape-hatches" | tr -d ' ')
  if [ "$cp_hatches" -eq 1 ]; then
    cp_apart="$cp_apart; 1 escape hatch, which user code may not write: $(names_in "$cp_module" "$work/escape-hatches")"
  elif [ "$cp_hatches" -gt 1 ]; then
    cp_apart="$cp_apart; $cp_hatches escape hatches, which user code may not write: $(names_in "$cp_module" "$work/escape-hatches")"
  fi
  cp_decided=$(wc -l < "$work/decided" | tr -d ' ')
  if [ "$cp_decided" -eq 1 ]; then
    cp_apart="$cp_apart; 1 decided exclusion, which is outside the language this compiler implements: $(names_in "$cp_module" "$work/decided")"
  elif [ "$cp_decided" -gt 1 ]; then
    cp_apart="$cp_apart; $cp_decided decided exclusions, which are outside the language this compiler implements: $(names_in "$cp_module" "$work/decided")"
  fi
  if [ -s "$work/missing" ]; then
    say "prelude $cp_module: $cp_total exports; $cp_used used, these not: $(names_in "$cp_module" "$work/missing")$cp_apart)"
  else
    say "prelude $cp_module: $cp_total exports, each used$cp_apart)"
  fi
}

# names_in MODULE FILE: the full names in FILE, one per line, each without
# MODULE's prefix, on one line.
names_in() {
  awk -v prefix="$1." 'index($0, prefix) == 1 { $0 = substr($0, length(prefix) + 1) } { printf "%s%s", sep, $0; sep = " " }' "$2"
}

# core_uses NAME CORE: whether CORE names the definition of full name NAME:
# as NAME followed by what ends a name in Core, the brace that closes the
# definition a lowered primitive stands for among them (anything after an
# operator's or a projection's closing parenthesis), or as a constructor,
# NS.Type::name( with the type's arguments in brackets after its name, NS
# the constructor's namespace, the type one name or an operator in
# parentheses, and an operator without its parentheses
# (Prelude.Basics.List[Int]::::( is (::)).
core_uses() {
  awk -v full="$1" '
    # Whether `s` ends in NS.Type, after one balanced [...] if it has one.
    function type_of_space(s,    depth, k, c) {
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
      if (substr(full, length(full), 1) == ")") {
        k = index(full, ".(")
        bare = substr(full, k + 2, length(full) - k - 2)
        closed = 1
      } else {
        k = length(full)
        while (k > 0 && substr(full, k, 1) != ".") k--
        bare = substr(full, k + 1)
      }
      space = substr(full, 1, k - 1)
      ends = "[{}( )],:"
      constructor = "::" bare "("
      qualified = space
      gsub(/[][\\.^$*+?(){}|]/, "\\\\&", qualified)
      type_before = "(^|[^A-Za-z0-9_.])" qualified "\\.([A-Za-z0-9_'\'']+|\\([^()]*\\))$"
    }
    {
      line = $0
      at = 0
      while ((i = index(substr(line, at + 1), full)) > 0) {
        at += i
        before = at > 1 ? substr(line, at - 1, 1) : ""
        next_char = substr(line, at + length(full), 1)
        if (before !~ /[A-Za-z0-9_.]/ && (closed || next_char == "" || index(ends, next_char) > 0)) { found = 1; exit }
      }
      at = 0
      while ((i = index(substr(line, at + 1), constructor)) > 0) {
        at += i
        if (type_of_space(substr(line, 1, at - 1))) { found = 1; exit }
      }
    }
    END { exit !found }' "$2"
}
