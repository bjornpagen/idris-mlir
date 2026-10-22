#!/bin/sh
# nested.sh DEPTH: a module whose one attribute is a builtin array nested
# DEPTH deep, on standard output. `mlir-opt --emit-bytecode` on it numbers
# the attribute before writing it, and at the pin that numbering takes
# native frames per level, so on a small stack (`ulimit -s 256`) a few
# thousand levels overflow it (conjecture on the depth: no overflowing
# depth is measured). The textual parser of nested arrays recurses on the
# same depth unless upstream/10-recursive-attribute-parser is applied,
# which it is before this patch.
depth=${1:?usage: nested.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "module attributes {test.nested = "
  for (i = 0; i < n; i++) printf "["
  for (i = 0; i < n; i++) printf "]"
  printf "} {\n}\n"
}'
