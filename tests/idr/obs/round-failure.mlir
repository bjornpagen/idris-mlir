// RUN: %status 1 idris-mlir-opt %s --idr-simplify -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// A pass of a round that fails fails the simplify loop with its own error,
// and the loop adds none: its round budget did not run out. Here
// idr-specialize, in the first round, has no clone of @apply left, since
// the module holds the last one within its budget. @apply and that clone
// are no_inline, so that the inliner, which runs before it, leaves the
// call it would specialize and the clone it counts.
// CHECK-NOT: error:
// CHECK: error: unsupported (compile-time budget): specializing @apply made more than {{[0-9]+}} clones of it
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @add(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @neg(%x: i64) -> i64 attributes {idr.total} {
    %z = arith.constant 0 : i64
    %y = arith.subi %z, %x : i64
    return %y : i64
  }
  func.func private @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total, no_inline} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  func.func private @apply$spec$1024(%x: i64 {idr.hole = 0 : i64}) -> i64 attributes {idr.clone = #idr.clone<@apply$spec$1024, #idr.spec_key<"apply", [#idr.key_closure<"neg", []>, #idr.key_hole<0>]>>, idr.total, no_inline} {
    %y = func.call @neg(%x) : (i64) -> i64
    return %y : i64
  }
  func.func private @use(%n: i64, %x: i64) -> i64 attributes {idr.total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = func.call @apply(%f, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = func.call @apply$spec$1024(%x) : (i64) -> i64
    %s = func.call @use(%x, %r) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
