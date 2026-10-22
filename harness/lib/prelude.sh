# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The prelude's coverage. A fixture marked `covers MODULE` is a program
# that uses every definition MODULE of the stock prelude exports at run
# time. Which definitions those are is the pinned Idris's: :browse lists
# them from its checked context, so the list follows the pin and is never
# written down here. Which the program uses is this compiler's: the module
# its frontend hands the driver, the one output it writes, names every
# definition it resolved (module_names): a function by its symbol, its key
# printed (Prelude.Types.List.length[Int]), and by its location, which
# names the definition it is; a saturated method by its instance, suffixed
# (Prelude.Num.fromInteger_Num_Int); a definition the registry lowers to an
# op by that op's location, as a function's names it; and a constructor by
# a type refined to it, after its family, whose label is its type's key
# printed (Prelude.Basics.List[Int] refined to ::). And the program's
# output is held to its cases' expected-stdout as every e2e program's is,
# so what it uses is also what it computes right. A module's exports are
# the definitions it makes itself: one it re-exports is covered in the
# module that defines it.
#
# A type, and a definition whose result is a type or an equality (a
# proof), has no run time: it is named apart, as compile-time only, and
# not asked of the program. So is an interface's constructor (MkEq), which
# the pinned Idris names in the interface's :doc: this compiler resolves
# every implementation at compile time, specialising each method call to
# the implementation it is given, so the record is never built (an
# implementation chosen at run time is refused), and the methods' uses are
# what the program's module shows. Two more kinds are named apart when the
# module does not name them. An escape hatch, which user code may not write, is
# asked of the compiler. A decided exclusion is outside the language
# (threads, collector finalizers). A pointer is a handle of the runtime's,
# so the prelude's pointer operations are not among them: a program uses
# them as it uses any other export. Three of them the registry translates
# to a value, a pointer cast to the handle it is given and the null pointer
# to the null handle, which leaves no call for the module to name: each is used
# when the program's own code calls it. So is an implementation, a hint
# whose body is %search among them, which the pinned Idris's :di names by
# its compile-time tree. The decided exclusions and those three are the
# only names written down here, and a later export is still asked of the
# compiler.

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
  (cd "$work" && pinned_idris --no-banner --no-color) 2> "$work/browse.err" |
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
    (cd "$work" && pinned_idris --ide-mode --source-dir "$prelude_source") 2> "$work/name-at.err" |
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
    (cd "$work" && pinned_idris --no-banner --no-color) 2> /dev/null |
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
    (cd "$work" && pinned_idris --no-banner --no-color) 2> /dev/null |
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
# names NAME (partial, as NAME may be) is refused. Who refuses is read off
# the compilation's report by the runner (`runtests --refused-by`,
# Reject.idr), never its wording: refused, and every error by the rule
# `escape hatch`, which a use of the world is refused by too, at a line of
# the probe, whose only code names NAME. `%foreign`, and `%extern` as a C
# export, are outside the language: not an escape hatch, and not a
# primitive left to implement. A buffer operation is a runtime primitive;
# this check does not see `Data.Buffer`. A probe that finds no such
# refusal leaves its report and output in $work/escape-hatch.evidence,
# which a missing export's line shows.
escape_hatch() {
  eh_dir=$work/probe-$(printf '%s' "$2" | cksum | awk '{ print $1 }')
  mkdir -p "$eh_dir"
  printf 'module Main\n\nimport Prelude\nimport %s\n\npartial\nmain : IO ()\nmain = let 0 probe : (%s) = %s in pure ()\n' \
    "$1" "$3" "$2" > "$eh_dir/Main.idr"
  bounded "$compile_sh" "--report=$eh_dir/report" "$eh_dir/Main.idr" probe > "$eh_dir/out" 2>&1
  if "$runtests" --refused-by "$eh_dir/report" 'escape hatch' Main.idr; then
    return 0
  fi
  {
    say "$2: no escape-hatch refusal; the probe's report and output:"
    show "$eh_dir/report" "$eh_dir/out"
  } >> "$work/escape-hatch.evidence"
  return 1
}

# decided_exclusion FULL: whether FULL is outside the language, by the
# decision on threads and collector finalizers. The only names written
# down in this check. A name that is not one of these is asked of the
# program and, if its module does not name it, of the compiler.
decided_exclusion() {
  case $1 in
    Prelude.IO.fork | Prelude.IO.prim__fork | Prelude.IO.threadWait | Prelude.IO.prim__threadWait | \
    Prelude.IO.onCollect | Prelude.IO.onCollectAny)
      return 0 ;;
  esac
  return 1
}

# implementations NAME...: the full NAMEs that are implementations, one
# per line, all asked of one session of the pinned Idris: :di prints a
# definition's compile-time tree, and an implementation's is one interface
# record, built by its constructor (MkSemigroup (...)) or named where it
# was defined (Num implementation at ...), a hint whose body is %search
# among them. This compiler resolves every implementation at compile
# time and never builds the record, so the module names only the saturated
# calls it typed, each by its own instance: an implementation is used
# when the program's own code names it, as a registry value is.
implementations() {
  { for im_name in "$@"; do printf ':di %s\n' "$im_name"; done; printf ':q\n'; } |
    (cd "$work" && pinned_idris --no-banner --no-color) 2> /dev/null |
    awk -v names="$*" '
      BEGIN { n = split(names, asked, " ") }
      /^Main> / { current = asked[++i] }
      /^Compile time tree: (Mk[A-Z][A-Za-z0-9_.]*([ (]|$)|.* implementation at )/ { print current }'
}

# registry_value FULL: whether the registry translates a call of FULL to a
# value, which leaves no call for the module to name: a pointer cast is the
# identity on the handle it is given (prim__castPtr, prim__forgetPtr), and
# so are replace and rewrite__impl on the value they transport, applied to
# it or not; the null pointer is the null handle, a literal
# (prim__getNullAnyPtr). The
# registry's hooks are the compiler's Idris source, which this check
# cannot ask, so these names are written down, as the decided exclusions
# are; an export the registry gives another hook is still asked of the
# module.
registry_value() {
  case $1 in
    PrimIO.prim__castPtr | PrimIO.prim__forgetPtr | PrimIO.prim__getNullAnyPtr | \
      Builtin.replace | Builtin.rewrite__impl)
      return 0 ;;
  esac
  return 1
}

# source_calls FULL FIXTURE: whether the program's own code, the Idris files
# of FIXTURE with comments and strings left out (idris_lex), names the
# definition of full name FULL, bare or qualified by any tail of its
# namespace (Bool.Semigroup.Any for Prelude.Interfaces.Bool.Semigroup.Any).
# For a registry value that is a call: one applied to less than all its
# arguments would be the definition itself, whose body the program cannot
# run.
source_calls() {
  sc_bare=${1##*.}
  sc_rest=${1%.*}
  sc_alts=
  while [ -n "$sc_rest" ]; do
    sc_alts="$sc_alts|$(printf '%s' "$sc_rest" | sed 's/\./\\./g')\\."
    case $sc_rest in
      *.*) sc_rest=${sc_rest#*.} ;;
      *) sc_rest= ;;
    esac
  done
  sc_alts=${sc_alts#|}
  find "$2" -name build -prune -o -name '*.idr' -print > "$work/covers-sources"
  while IFS= read -r sc_file; do
    if idris_lex code "$sc_file" |
       grep -qE "(^|[^A-Za-z0-9_'.])(${sc_alts})?$sc_bare([^A-Za-z0-9_']|\$)"; then
      return 0
    fi
  done < "$work/covers-sources"
  return 1
}

# covers_prelude MODULE PROGRAM FIXTURE: every run-time export of MODULE
# is used by the program whose module, as its frontend wrote it, is the
# bytecode PROGRAM, and whose source is FIXTURE's.
covers_prelude() {
  cp_module=$1
  cp_program=$2
  cp_fixture=$3
  if [ -z "$cp_program" ] || ! module_names "$cp_program" > "$work/module-names"; then
    say "prelude $cp_module: the program's module cannot be read"
    show "$work/module-names.err"
    return
  fi
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
    (cd "$work" && pinned_idris --no-banner --no-color --check Imports.idr) > "$work/import.out" 2>&1
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
    elif module_uses "$cp_full" "$work/module-names"; then
      cp_used=$((cp_used + 1))
    else
      printf '%s\t%s\n' "$cp_full" "$cp_implicit" >> "$work/unused"
    fi
  done < "$work/own"
  # What the module does not name may be a decided exclusion, a registry value
  # the program's code calls, or an escape hatch; anything else is missing.
  # The exclusion is recognized by name, so a probe is not asked to compile
  # a program that reaches it.
  : > "$work/escape-hatches"
  : > "$work/decided"
  : > "$work/missing"
  # shellcheck disable=SC2046 # one name per line, each a word
  implementations $(cut -f 1 "$work/unused") > "$work/implementations"
  while IFS="$(printf '\t')" read -r cp_full cp_implicit; do
    if decided_exclusion "$cp_full"; then
      printf '%s\n' "$cp_full" >> "$work/decided"
    elif (registry_value "$cp_full" || grep -qxF -- "$cp_full" "$work/implementations") && source_calls "$cp_full" "$cp_fixture"; then
      cp_used=$((cp_used + 1))
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
    [ -f "$work/escape-hatch.evidence" ] && cat "$work/escape-hatch.evidence"
  else
    say "prelude $cp_module: $cp_total exports, each used$cp_apart)"
  fi
}

# names_in MODULE FILE: the full names in FILE, one per line, each without
# MODULE's prefix, on one line.
names_in() {
  awk -v prefix="$1." 'index($0, prefix) == 1 { $0 = substr($0, length(prefix) + 1) } { printf "%s%s", sep, $0; sep = " " }' "$2"
}

# module_names PROGRAM: every name the bytecode module PROGRAM holds, one
# per line, read off its text as idris-mlir-opt prints it with its
# locations: each symbol (@Main.main, @"Prelude.Types.List.length[Int]"),
# each location's name ("Prelude.Types.List.length"(...)), and each
# constructor a type is refined to, after its family's label, as
# `<label>::<constructor>`. A family is printed by the alias its
# definition names (#List = #idr.family<"Prelude.Basics.List[Int]" ...>)
# or inline; the refinement follows it, after its index terms if it has
# any (!idr.data<#List @Nil>, !idr.data<#Vect[n] @"::">). The module is
# read as the printer writes it, so no name of it is guessed: a string, a
# family's angle brackets and an arrow are told apart as tokens.
module_names() {
  bounded "$idris_mlir_opt" --mlir-print-debuginfo "$1" -o "$work/module-names.mlir" \
    2> "$work/module-names.err" || return 1
  awk '
    function emit(s) { if (!(s in seen)) { seen[s] = 1; print s } }
    function unescape(s,    out, k, c) {
      out = ""
      for (k = 1; k <= length(s); k++) {
        c = substr(s, k, 1)
        if (c == "\\" && k < length(s)) { k++; c = substr(s, k, 1) }
        out = out c
      }
      return out
    }
    # A name read as a symbol: the refinement it is when a family waits
    # for one.
    function symbol(s) {
      emit(s)
      if (waiting == 1) emit(label "::" s)
      waiting = 0
    }
    {
      line = $0
      n = length(line)
      defining = ""
      if (match(line, /^#[A-Za-z0-9_$.-]+ = #idr\.family</))
        defining = substr(line, 2, index(line, " ") - 2)
      i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (instring) {
          if (c == "\\") { text = text c substr(line, i + 1, 1); i += 2; continue }
          if (c != "\"") { text = text c; i++; continue }
          instring = 0
          s = unescape(text)
          after = substr(line, i + 1, 1)
          if (kind == "symbol") symbol(s)
          else if (kind == "label") {
            labels[depth] = s
            if (defining != "") { aliases[defining] = s; defining = "" }
          } else {
            if (kind == "location" || after == "(") emit(s)
            waiting = 0
          }
          i++
          continue
        }
        if (waiting == 2) {
          if (c == "[") brackets++
          else if (c == "]" && --brackets == 0) waiting = 1
          i++
          continue
        }
        if (c == "\"") {
          instring = 1
          text = ""
          if (i > 1 && substr(line, i - 1, 1) == "@") kind = "symbol"
          else if (expecting) { kind = "label"; expecting = 0 }
          else if (i > 4 && substr(line, i - 4, 4) == "loc(") kind = "location"
          else kind = "string"
          i++
          continue
        }
        if (c == "@") {
          if (match(substr(line, i + 1), /^[A-Za-z_][A-Za-z0-9_$.]*/)) {
            symbol(substr(line, i + 1, RLENGTH))
            i += 1 + RLENGTH
          } else i++
          continue
        }
        if (substr(line, i, 12) == "#idr.family<") {
          depth++
          families[depth] = 1
          expecting = 1
          waiting = 0
          i += 12
          continue
        }
        if (c == "#") {
          waiting = 0
          if (match(substr(line, i + 1), /^[A-Za-z0-9_$.-]+/)) {
            name = substr(line, i + 1, RLENGTH)
            i += 1 + RLENGTH
            if ((name in aliases) && substr(line, i, 2) != " =") { label = aliases[name]; waiting = 1 }
          } else i++
          continue
        }
        if (c == "-" && substr(line, i + 1, 1) == ">") { waiting = 0; i += 2; continue }
        if (c == "<") { depth++; families[depth] = 0; waiting = 0; i++; continue }
        if (c == ">") {
          if (depth > 0 && families[depth]) { label = labels[depth]; waiting = 1 }
          else waiting = 0
          if (depth > 0) depth--
          i++
          continue
        }
        if (c == "[" && waiting == 1) { waiting = 2; brackets = 1; i++; continue }
        if (c != " " && c != "\t") waiting = 0
        i++
      }
    }' "$work/module-names.mlir"
}

# module_uses NAME NAMES: whether NAMES (module_names) names the definition
# of full name NAME: as NAME whole, or with its key arguments after it in
# brackets, or `;` and the hash a key printed in part ends with; as a
# saturated method's instance, NAME with its instance suffixed after an
# underscore (Prelude.Num.fromInteger_Num_Int), an operator's inside its
# parentheses (Prelude.Num.(-_Neg_Int)); or as a constructor,
# NS.Type::name, the type one name or an operator in parentheses with its
# arguments in brackets after it, NS the constructor's namespace, and an
# operator without its parentheses (Prelude.Basics.List[Int]:::: is (::)).
module_uses() {
  awk -v full="$1" '
    # Whether `s` ends in NS.Type, after one balanced [...] if it has one,
    # and the hash an instance whose print drops part of its identity
    # carries after it (`;` and hexadecimal digits).
    function type_of_space(s,    depth, k, c) {
      sub(/;[0-9a-f]+$/, "", s)
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
      return s ~ type_whole
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
      constructor = "::" bare
      qualified = space
      gsub(/[][\\.^$*+?(){}|]/, "\\\\&", qualified)
      type_whole = "^" qualified "\\.([A-Za-z0-9_'\'']+|\\([^()]*\\))$"
      escaped = full
      gsub(/[][\\.^$*+?(){}|]/, "\\\\&", escaped)
      escaped_bare = bare
      gsub(/[][\\.^$*+?(){}|]/, "\\\\&", escaped_bare)
      whole = "^" escaped "([[;].*)?$"
      suffixed = "^" qualified "\\.\\(" escaped_bare "_[A-Za-z0-9_.$]+\\)([[;].*)?$"
      if (!closed) suffixed = "^" escaped "_[A-Za-z0-9_.$]+([[;].*)?$"
    }
    $0 ~ whole || $0 ~ suffixed { found = 1; exit }
    length($0) > length(constructor) && substr($0, length($0) - length(constructor) + 1) == constructor &&
      type_of_space(substr($0, 1, length($0) - length(constructor))) { found = 1; exit }
    END { exit !found }' "$2"
}
