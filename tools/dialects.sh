#!/bin/sh
# The Idris side's vocabulary of the dialects Emit writes, the contract's:
# two modules per dialect, generated from the dialect's ODS by
# idris-mlir-tblgen: its syntax, compiler/src/IdrisMLIR/Syntax/<Name>.idr
# (-gen-idris-syntax: its enums, and its types and attributes, which
# IdrisMLIR.MLIR's types and attributes hold), and its ops,
# compiler/src/IdrisMLIR/Dialect/<Name>.idr (-gen-idris-dialect: the
# builders of its ops, the printer of each op's declarative syntax, and its
# primitives, over its syntax).
#
#     tools/dialects.sh generate   write each module that changed (make build)
#     tools/dialects.sh check      say whether each module is current
#
# With `typecheck` after either, the generator is make typecheck's
# idris-mlir-tblgen, and mlir-tblgen and MLIR's ODS are those of the
# TableGen-only LLVM/MLIR its bootstrap step builds and the patched tree it
# reads (tools/bootstrap.sh typecheck), where stage 2 is not built. The
# records are the same, so are the modules and their fingerprints.
#
# The modules are checked in, so that the Idris build needs no other step
# and a change of ODS shows as a change of the Idris it means. Each ends
# with the fingerprint of what it was generated from (the records the pinned
# mlir-tblgen reads from the dialect's ODS file, and the generator's source)
# and of the text above it. `check` needs no build: a module whose first
# fingerprint is not that of its ODS and the generator now is stale, one
# whose second is not that of its text was edited, and `make build` writes
# either again.
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
generator_source=$root/foreign/idr/tools/idris-mlir-tblgen.cpp
src=$root/compiler/src/IdrisMLIR

usage() {
  echo "usage: tools/dialects.sh generate|check [typecheck]" >&2
  exit 2
}
[ $# -eq 1 ] || [ $# -eq 2 ] || usage
case $1 in generate | check) ;; *) usage ;; esac
# mlir_tblgen, and the include directories of MLIR's ODS (mlir_include)
# and of LLVM's (llvm_include): one installed tree in stage 2's prefix, the
# source tree's two in the typecheck build's.
case ${2-} in
  '')
    mlir_tblgen=$llvm_bin/mlir-tblgen
    mlir_include=${llvm_bin%/bin}/include
    llvm_include=$mlir_include
    ;;
  typecheck)
    typecheck_build=$(stamp_field "$typecheck_toolchain" llvm_build)
    typecheck_tree=$(stamp_field "$typecheck_toolchain" tree)
    if [ -z "$typecheck_build" ] || [ -z "$typecheck_tree" ]; then
      echo "tools/dialects.sh: no typecheck build; run: tools/bootstrap.sh typecheck" >&2
      exit 1
    fi
    mlir_tblgen=$typecheck_build/bin/mlir-tblgen
    mlir_include=$typecheck_tree/mlir/include
    llvm_include=$typecheck_tree/llvm/include
    idris_mlir_tblgen=$typecheck_tblgen
    ;;
  *) usage ;;
esac
# Without mlir-tblgen no record is read, so say which step builds it.
if [ ! -x "$mlir_tblgen" ]; then
  case ${2-} in
    '') step='make bootstrap' ;;
    typecheck) step='tools/bootstrap.sh typecheck (make typecheck)' ;;
  esac
  echo "tools/dialects.sh: $mlir_tblgen is missing; $step builds it" >&2
  exit 1
fi

# The contract's dialects (idris-mlir parses a module of these and
# builtin's ops), each with its module's name and the ODS file of its ops:
# ours, or the pinned MLIR's.
dialects() {
  cat << EOF
idr Idr $root/foreign/idr/include/idr/IR/IdrOps.td
builtin Builtin $mlir_include/mlir/IR/BuiltinOps.td
arith Arith $mlir_include/mlir/Dialect/Arith/IR/ArithOps.td
math Math $mlir_include/mlir/Dialect/Math/IR/MathOps.td
ub UB $mlir_include/mlir/Dialect/UB/IR/UBOps.td
memref MemRef $mlir_include/mlir/Dialect/MemRef/IR/MemRefOps.td
EOF
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-dialects.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

# fingerprint ODS: the checksum of the records mlir-tblgen reads from ODS,
# followed by the generator's source.
fingerprint() {
  "$mlir_tblgen" -I "$mlir_include" -I "$llvm_include" -I "$root/foreign/idr/include" "$1" \
    > "$work/records" 2> "$work/records.err" || {
    echo "tools/dialects.sh: mlir-tblgen cannot read $1:" >&2
    cat "$work/records.err" >&2
    exit 1
  }
  cat "$work/records" "$generator_source" | cksum | awk '{ print $1 "-" $2 }'
}

# text_fingerprint FILE: the checksum of a module's text.
text_fingerprint() {
  cksum < "$1" | awk '{ print $1 "-" $2 }'
}

# Each dialect's two modules, as generator:directory: its syntax, and its
# ops, which import the syntax.
modules="syntax:Syntax dialect:Dialect"

status=0
dialects > "$work/dialects"
while read -r name module ods; do
  expected=$(fingerprint "$ods") || exit 1
  for pair in $modules; do
    generator=${pair%%:*}
    directory=${pair#*:}
    path=$src/$directory/$module.idr
    out=$work/$directory-$module.idr
    if [ "$1" = generate ]; then
      mkdir -p "$src/$directory"
      "$idris_mlir_tblgen" "-gen-idris-$generator" "-idris-dialect=$name" \
        "-idris-module=IdrisMLIR.$directory.$module" \
        "-idris-syntax-module=IdrisMLIR.Syntax.$module" -I "$mlir_include" -I "$llvm_include" \
        -I "$root/foreign/idr/include" "$ods" -o "$out" || exit 1
      printf -- '-- fingerprint: %s %s\n' "$expected" "$(text_fingerprint "$out")" >> "$out"
      if ! cmp -s "$out" "$path"; then
        mv "$out" "$path" || exit 1
        echo "tools/dialects.sh: wrote IdrisMLIR.$directory.$module"
      fi
    else
      recorded=$(sed -n 's/^-- fingerprint: //p' "$path" 2> /dev/null)
      sed '/^-- fingerprint: /d' "$path" > "$work/text" 2> /dev/null
      if [ ! -f "$path" ]; then
        echo "IdrisMLIR.$directory.$module: missing (make build writes it)"
        status=1
      elif [ "${recorded% *}" != "$expected" ]; then
        echo "IdrisMLIR.$directory.$module: stale (make build writes it again)"
        status=1
      elif [ "${recorded##* }" != "$(text_fingerprint "$work/text")" ]; then
        echo "IdrisMLIR.$directory.$module: edited by hand (make build writes it again)"
        status=1
      else
        echo "IdrisMLIR.$directory.$module: current"
      fi
    fi
  done
done < "$work/dialects"

# No module of either directory is left from a dialect the contract dropped.
for pair in $modules; do
  directory=${pair#*:}
  for path in "$src/$directory"/*.idr; do
    [ -f "$path" ] || continue
    module=${path##*/}
    module=${module%.idr}
    if ! awk -v m="$module" '$2 == m { found = 1 } END { exit !found }' "$work/dialects"; then
      echo "IdrisMLIR.$directory.$module: of no dialect of the contract"
      status=1
    fi
  done
done
exit "$status"
