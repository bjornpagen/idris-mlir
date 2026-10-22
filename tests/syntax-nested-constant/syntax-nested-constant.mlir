// RUN: awk 'BEGIN { printf "module attributes {test.nested = "; for (i = 0; i < 100000; i++) printf "["; for (i = 0; i < 100000; i++) printf "]"; print "} {"; print "}" }' > %t.mlir
// RUN: idris-mlir-opt %t.mlir -o %t.out.mlir
// RUN: FileCheck %s < %t.out.mlir
// An attribute nested 100,000 deep parses and prints back on our tools'
// small stack: a parser or printer that recursed on the nesting would
// overflow it, as the pinned mlir-opt's attribute parser does
// (upstream/10-recursive-attribute-parser), which is fixed upstream, not
// hidden by a larger stack.
// CHECK: module attributes {test.nested = {{\[+\]+}}}
