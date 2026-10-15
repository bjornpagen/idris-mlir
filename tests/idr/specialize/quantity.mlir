// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the order of the copy's parameters, the holes of the key left to right (C09).
// A copy's parameter for a runtime leaf of a static shape has the leaf's
// type, so a leaf that fills a linear field stays linear: the pair's first
// field is declared used once, its second any number of times, and the
// copy of @first, which loops and so is never inlined, takes one
// !idr.lin<i64> and one i64. A parameter the copy keeps, the world, keeps
// its type too.
// CHECK: idr.func private @{{first\.spec\.[0-9a-f]+}}(%{{[a-z0-9_]+}}: !idr.lin<i64>, %{{[a-z0-9_]+}}: i64, %{{[a-z0-9_]+}}: i64, %{{[a-z0-9_]+}}: !idr.world
!P = !idr.data<"P", plain [@MkP(!idr.lin<i64>, i64)]>
module {
  // Prints the pair's linear field once its counter is down to 0.
  idr.func private @first(%p: !P, %n: i64, %w: !idr.world) -> !idr.world attributes {total} {
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
  idr.func private @use(%a: !idr.lin<i64>, %b: i64, %n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %p = idr.con @MkP(%a, %b) : (!idr.lin<i64>, i64) -> !P
    %r = idr.call @first(%p, %n, %w) : (!P, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %a = idr.lin.enter %b : !idr.lin<i64>
    %r = idr.call @use(%a, %b, %b, %w1) : (!idr.lin<i64>, i64, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
