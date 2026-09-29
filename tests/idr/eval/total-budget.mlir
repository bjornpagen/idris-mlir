// RUN: bash -c 'ulimit -v 3000000; exec idris-mlir-opt %s --mlir-disable-threading --idr-eval --remarks-filter=idr-eval' > %t.mlir 2> %t.remarks
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// A call of total code runs metered too, with the larger budget of total
// code. One that cannot finish within it (a list of a billion cells, in an
// address space of 3 GB) stays, to run at runtime, with a Missed remark.
// CHECK-LABEL: func.func @Prog.main(
// CHECK: call @range
// REMARK: [Missed] Unfinished {{.*}}Function=range{{.*}}within the budget of total code
module {
  idr.data @List box {
    idr.ctor @Nil tag 0 ()
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>)
  }
  func.func @Prog.main() -> !idr.box<@List> {
    %n = arith.constant 1000000000 : i64
    %l = func.call @range(%n) : (i64) -> !idr.box<@List>
    return %l : !idr.box<@List>
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, idr.effects = #idr.effects<none>} {
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
