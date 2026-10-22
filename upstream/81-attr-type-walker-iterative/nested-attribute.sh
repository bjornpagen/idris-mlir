#!/bin/sh
# nested-attribute.sh DEPTH: a module whose function holds, in an attribute,
# a reference to a private function nested in builtin arrays DEPTH deep, on
# standard output. `mlir-opt -symbol-dce` on it looks for the uses of the
# private function, which walks the attribute with AttrTypeWalker down to
# the reference; at the pin that walk takes native frames per level, so on
# a small stack (`ulimit -s 256`) a few thousand levels overflow it
# (conjecture on the depth: no overflowing depth is measured). The textual
# parser and printer of nested arrays recurse on the same depth unless
# upstream/10-recursive-attribute-parser is applied, which it is before
# this patch; the patch's unit test isolates the walk and the replacement.
depth=${1:?usage: nested-attribute.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "module {\n"
  printf "  func.func private @used()\n"
  printf "  func.func @user() attributes {test.nested = "
  for (i = 0; i < n; i++) printf "["
  printf "@used"
  for (i = 0; i < n; i++) printf "]"
  printf "} {\n    return\n  }\n}\n"
}'
