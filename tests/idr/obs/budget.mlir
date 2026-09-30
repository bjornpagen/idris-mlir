// RUN: %status 1 idris-mlir-opt %s --idr-simplify=max-rounds=1 -o %t.1.mlir 2> %t.1.err
// RUN: FileCheck %s --check-prefix=BUDGET < %t.1.err
// RUN: idris-mlir-opt %s --idr-simplify --remarks-filter-passed=idr-simplify -o %t.2.mlir 2> %t.2.err
// RUN: FileCheck %s --check-prefix=FIXPOINT < %t.2.err
// The rounds of the simplify loop are bounded by construction, and the
// round budget asserts it: a module that still changes after max-rounds
// rounds is a user error that names the budget, at the module (idris-mlir-cc
// exits 3, as for every `unsupported` reason). This one needs more than one
// round, as the first inlines @twice; the default budget is enough.
// BUDGET: budget.mlir:[[@LINE+4]]:1: error: unsupported (compile-time budget): idr-simplify did not reach a fixpoint in 1 rounds
// FIXPOINT: fixpoint: round {{[2-9]|[1-9][0-9]}} changed nothing
// BUDGET-NOT: error
// FIXPOINT-NOT: error
module attributes {idr.program} {
  func.func private @twice(%x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = func.call @twice(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
