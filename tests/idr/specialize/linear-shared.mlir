// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=@first.spec. < %t.mlir
// A call on a static shape moves the shape's leaves into the copy's call.
// Here the pair is read twice, so it outlives each call: a copy taking its
// linear field would use it a second time next to the pair. The pair stays
// a runtime argument of @first, which loops and so is never inlined, and
// the module still verifies after the optimizer.
// CHECK-LABEL: idr.func @Main.main(
// CHECK-COUNT-2: call @first(
!P = !idr.data<"P", plain [@MkP(!idr.lin<i64>, i64)]>
idr.program @"linear-shared" root(@Main.main) stage(first) {
  // Prints the pair's linear field once its counter is down to 0.
  idr.func @first(%p: !P, %n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      %w1 = idr.match %p : !P -> (!idr.world) {
      case @MkP(%a: i64, %b: i64) {
        %v = idr.io.put_int signed %a, %w : i64
        idr.yield %v : !idr.world
      }
      }
      idr.yield %w1 : !idr.world
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %w1 = idr.call @first(%p, %m, %w) : (!P, i64, !idr.world) -> !idr.world
      idr.yield %w1 : !idr.world
    }
    }
    return %r : !idr.world
  }
  idr.func @use(%a: !idr.lin<i64>, %b: i64, %n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %p = idr.con !P @MkP(%a : !idr.lin<i64>, %b : i64)
    %r = idr.call @first(%p, %n, %w) : (!P, i64, !idr.world) -> !idr.world
    %s = idr.call @first(%p, %n, %r) : (!P, i64, !idr.world) -> !idr.world
    return %s : !idr.world
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %a = idr.lin.enter %b : !idr.lin<i64>
    %r = idr.call @use(%a, %b, %b, %w1) : (!idr.lin<i64>, i64, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
