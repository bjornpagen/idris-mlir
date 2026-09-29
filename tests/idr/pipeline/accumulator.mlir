// RUN: idris-mlir-opt %s --idr-simplify --remarks-filter-missed=idr-specialize > %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK --allow-empty < %t.err
// RUN: idris-mlir-opt %t.mlir --idr-simplify --remarks-filter="idr-(simplify|specialize)" > %t2.mlir 2> %t2.err
// RUN: FileCheck %s --check-prefix=AGAIN < %t2.err
// An accumulator through the whole simplify loop: @count is called with a
// constant Integer accumulator and a counter read at runtime. The first call
// is specialized on the accumulator (a machine number never is, but an
// Integer is static); the clone's own call passes a new constant that @count
// never branches on, so it is generalized to a runtime value and calls
// @count again: one clone, no Missed remark, and a second run changes
// nothing.
// CHECK: idr.clone_counts = {count = 1 : i64}
// REMARK-NOT: [Missed]
// AGAIN-NOT: [Missed]
// AGAIN: remark: [Passed] idr-simplify | Category:idr-simplify
// AGAIN-SAME: fixpoint: round 1 changed nothing
module attributes {idr.program} {
  func.func private @count(%acc: !idr.big {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}) -> !idr.big attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (!idr.big) {
    case 0 {
      idr.yield %acc : !idr.big
    }
    default {
      %one = idr.constant #idr.big<"1"> : !idr.big
      %c1 = arith.constant 1 : i64
      %a = idr.big.add %acc, %one
      %m = arith.subi %n, %c1 : i64
      %x = func.call @count(%a, %m) : (!idr.big, i64) -> !idr.big
      idr.yield %x : !idr.big
    }
    }
    return %r : !idr.big
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %zero = idr.constant #idr.big<"0"> : !idr.big
    %r = func.call @count(%zero, %n) : (!idr.big, i64) -> !idr.big
    %t = idr.big.show %r
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }
}
