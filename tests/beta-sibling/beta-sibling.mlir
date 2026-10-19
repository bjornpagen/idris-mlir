// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls=@loop:@apply -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=calls=@loop:@loop -o /dev/null
// Members of one component of calls never inline one another, so that a
// recursion is not unrolled into itself; but a call that hands a member a
// closure built for it, of a function outside the recursion, is beta
// reduction. @apply runs the closure it is given, and main gives it a
// closure of @loop, so its dispatch calls @loop, and @loop, which calls
// @apply with a closure of @inc, is of its component. Inlined, @apply's
// dispatch takes @inc's case and leaves no call of the component: @loop no
// longer calls @apply, and still calls itself.
// STDIN: \0000
// STDIN: \0003
// STDIN: \0144
idr.program @"beta-sibling" root(@Main.main) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @loop(%n: i64) -> i64 {
    %s = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    default(%m: i64) {
      %one = arith.constant 1 : i64
      %c = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
      %a = idr.call @apply(%c, %m) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
      %p = arith.subi %m, %one : i64
      %b = idr.call @loop(%p) : (i64) -> i64
      %t = arith.addi %a, %b : i64
      idr.yield %t : i64
    }
    }
    return %s : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %l = idr.closure @loop() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @apply(%l, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %s = idr.str.show_sint %r : i64
    %w2 = idr.io.put_str %s, %w1
    return %w2 : !idr.world
  }
}
