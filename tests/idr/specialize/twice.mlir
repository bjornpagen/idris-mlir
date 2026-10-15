// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: that the call is specialized on both shapes, as the key composes them.
// One pair passed as both arguments of @sumN, which loops and so is never
// inlined: the copy takes the pair's leaves once per parameter, and the
// pair, which nothing else reads, goes with the call it fed, once.
// CHECK-LABEL: idr.func @Main.main(
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: call @{{sumN\.spec\.[0-9a-f]+}}(
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @twice root(@Main.main) stage(first) {
  idr.func @sumN(%p: !P, %q: !P, %n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %a = idr.field %p : !P @MkP[0] -> i64
      %b = idr.field %q : !P @MkP[1] -> i64
      %s = arith.addi %a, %b : i64
      idr.yield %s : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @sumN(%p, %q, %m) : (!P, !P, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @use(%a: i64, %b: i64) -> i64 {
    %p = idr.con !P @MkP(%a : i64, %b : i64)
    %r = idr.call @sumN(%p, %p, %a) : (!P, !P, i64) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %r = idr.call @use(%b, %b) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
