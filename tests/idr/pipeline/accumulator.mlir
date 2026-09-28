// RUN: idris-mlir-opt %s --idr-simplify --remarks-filter-missed=idr-specialize > %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK --allow-empty < %t.err
// RUN: idris-mlir-opt %t.mlir --idr-simplify --remarks-filter="idr-(simplify|specialize)" > %t2.mlir 2> %t2.err
// RUN: FileCheck %s --check-prefix=AGAIN < %t2.err
// rule: OPT-PIPE-5, OPT-IDEM-1, ELIM-SPEC-1, ELIM-SPEC-2
// An accumulator through the whole simplify loop: @count is called with a
// constant accumulator and a counter read at runtime. The first call is
// specialized on the accumulator; the clone's own call passes a new constant
// that @count never branches on, so it is generalized to a runtime value
// and calls @count again: one clone, no Missed remark, and a second run
// changes nothing.
// CHECK: module attributes {idr.clone_counts = {count = 1 : i64}, idr.program}
// CHECK-NOT: count$spec$2
// REMARK-NOT: [Missed]
// AGAIN-NOT: [Missed]
// AGAIN: remark: [Passed] idr-simplify | Category:idr-simplify
// AGAIN-SAME: fixpoint: round 1 changed nothing
module attributes {idr.program} {
  func.func private @count(%acc: i64 {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %c0 = arith.constant 0 : i64
    %r = func.call @count(%c0, %n) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
