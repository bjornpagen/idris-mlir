// RUN: %status 1 bash -c 'ulimit -v 3000000; exec idris-mlir-opt %s --mlir-disable-threading --idr-eval' > %t.out 2> %t.err
// RUN: FileCheck %s < %t.err
// rule: EVAL-1
// A total evaluation runs to completion with no fuel and no limit of its
// own; when the machine refuses the memory it needs (here, an address space
// of 3 GB for a list of 10^9 cells), the call is the error EVAL-1.
// CHECK: exhausted.mlir:{{[0-9]+}}:10: error: unsupported (EVAL-1): the machine could not finish evaluating @range, which is total: the machine refused memory or stack
// CHECK-NEXT: %l = func.call @range(%n)
module {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  func.func @Prog.main() -> !idr.box<@List> {
    %n = arith.constant 1000000000 : i64
    %l = func.call @range(%n) : (i64) -> !idr.box<@List>
    return %l : !idr.box<@List>
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, idr.effect = "pure"} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@List>) {
    case 0 {
      %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @range(%m) : (i64) -> !idr.box<@List>
      %c = idr.con @List::@Cons(%n, %rest) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
}
