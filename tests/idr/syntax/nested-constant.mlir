// RUN: awk 'BEGIN { printf "module attributes {test.nested = "; for (i = 0; i < 100000; i++) printf "["; for (i = 0; i < 100000; i++) printf "]"; print "} {"; print "}" }' > %t.mlir
// RUN: idris-mlir-opt %t.mlir -o %t.out.mlir
// RUN: FileCheck %s < %t.out.mlir
// An attribute nested 100,000 deep, which overflows the stack of the
// pinned mlir-opt (upstream/10-recursive-attribute-parser), parses and prints
// back: idris-mlir-opt runs on the runtime's reserved stack.
// CHECK: module attributes {test.nested = {{\[+\]+}}}
