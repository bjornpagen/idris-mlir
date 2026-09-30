#!/bin/sh
# nested.sh DEPTH: a module whose one attribute is an array nested DEPTH
# deep, on standard output.
depth=${1:?usage: nested.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "module attributes {test.nested = "
  for (i = 0; i < n; i++) printf "["
  for (i = 0; i < n; i++) printf "]"
  printf "} {\n}\n"
}'
