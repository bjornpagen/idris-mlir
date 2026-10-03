#!/bin/sh
# The Idris side's vocabulary of the dialects Emit writes, the contract's:
# one module per dialect, compiler/src/IdrisMLIR/Dialect/<Name>.idr,
# generated from the dialect's ODS by idris-mlir-tblgen -gen-idris-dialect.
#
#     tools/dialects.sh generate   write each module that changed (make build)
#     tools/dialects.sh check      say whether each module is current
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
mlir_include=${llvm_bin%/bin}/include
generator_source=$root/foreign/idr/tools/idris-mlir-tblgen.cc
modules=$root/compiler/src/IdrisMLIR/Dialect

usage() {
  echo "usage: tools/dialects.sh generate|check" >&2
  exit 2
}
[ $# -eq 1 ] || usage
case $1 in generate | check) ;; *) usage ;; esac

# The contract's dialects (idris-mlir-cc parses a module of these and
# builtin's ops), each with its module's name and the ODS file of its ops:
# ours, or the pinned MLIR's.
dialects() {
  cat << EOF
idr Idr $root/foreign/idr/include/idr/IdrOps.td
builtin Builtin $mlir_include/mlir/IR/BuiltinOps.td
func Func $mlir_include/mlir/Dialect/Func/IR/FuncOps.td
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
  "$llvm_bin/mlir-tblgen" -I "$mlir_include" -I "$root/foreign/idr/include" "$1" \
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

status=0
dialects > "$work/dialects"
while read -r name module ods; do
  path=$modules/$module.idr
  expected=$(fingerprint "$ods") || exit 1
  if [ "$1" = generate ]; then
    mkdir -p "$modules"
    "$idris_mlir_tblgen" -gen-idris-dialect "-idris-dialect=$name" \
      "-idris-module=IdrisMLIR.Dialect.$module" -I "$mlir_include" \
      -I "$root/foreign/idr/include" "$ods" -o "$work/$module.idr" || exit 1
    printf -- '-- fingerprint: %s %s\n' "$expected" "$(text_fingerprint "$work/$module.idr")" \
      >> "$work/$module.idr"
    if ! cmp -s "$work/$module.idr" "$path"; then
      mv "$work/$module.idr" "$path" || exit 1
      echo "tools/dialects.sh: wrote IdrisMLIR.Dialect.$module"
    fi
  else
    recorded=$(sed -n 's/^-- fingerprint: //p' "$path" 2> /dev/null)
    sed '/^-- fingerprint: /d' "$path" > "$work/text" 2> /dev/null
    if [ ! -f "$path" ]; then
      echo "IdrisMLIR.Dialect.$module: missing (make build writes it)"
      status=1
    elif [ "${recorded% *}" != "$expected" ]; then
      echo "IdrisMLIR.Dialect.$module: stale (make build writes it again)"
      status=1
    elif [ "${recorded##* }" != "$(text_fingerprint "$work/text")" ]; then
      echo "IdrisMLIR.Dialect.$module: edited by hand (make build writes it again)"
      status=1
    else
      echo "IdrisMLIR.Dialect.$module: current"
    fi
  fi
done < "$work/dialects"

# No module of the directory is left from a dialect the contract dropped.
for path in "$modules"/*.idr; do
  [ -f "$path" ] || continue
  module=${path##*/}
  module=${module%.idr}
  if ! awk -v m="$module" '$2 == m { found = 1 } END { exit !found }' "$work/dialects"; then
    echo "IdrisMLIR.Dialect.$module: of no dialect of the contract"
    status=1
  fi
done
exit "$status"
