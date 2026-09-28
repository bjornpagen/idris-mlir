// RUN: idris-mlir-opt %s --idr-simplify="clone-limit=8 skip-unregistered=true" --remarks-filter-missed=idr-specialize > %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK < %t.err
// RUN: idris-mlir-opt %t.mlir --idr-simplify="clone-limit=8 skip-unregistered=true" --remarks-filter="idr-(simplify|specialize)" > %t2.mlir 2> %t2.err
// RUN: FileCheck %s --check-prefix=AGAIN < %t2.err
// rule: OPT-PIPE-5, OPT-IDEM-1, ELIM-SPEC-1
// An accumulator that would specialize forever, through the whole simplify
// loop: each round inlines the last clone and specializes the call it
// exposes on the next constant. The clone limit ends it: the loop reaches a
// fixpoint with one Missed remark, and a second run changes nothing (and
// reports no Missed remark: the stopped call is marked).
// Note: idr-eval (the lowering package) is not in this branch yet, so the
// round runs without it (skip-unregistered, which only tests set).
// CHECK: module attributes {idr.clone_counts = {count = 8 : i64}, idr.program}
// CHECK: call @count(%{{.*}}) {idr.spec_stopped}
// REMARK: remark: [Missed] idr-specialize | Category:idr-specialize
// REMARK-SAME: specialization of @count stopped: the clone limit of 8 clones of @count is reached
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
