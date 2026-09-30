// RUN: idris-mlir-opt %s --idr-eval --remarks-filter=idr-eval 2> %t.remarks | FileCheck %s
// RUN: FileCheck %s --check-prefix=REMARK --implicit-check-not=[Missed] < %t.remarks
// A closure read back from compile-time evaluation is known by its code:
// each function and number of captures has code of its own, and the cell
// holds nothing else that says which, so no count of labels can make one
// read as another. Closures of one function with different captures, and
// of different functions, all come back as what they were.
// CHECK-LABEL: func.func @Prog.main()
// CHECK-NOT: call
// CHECK-DAG: idr.constant #idr.closure<@f, []> : !idr.fn<(i64, i64, i64) -> (i64)>
// CHECK-DAG: idr.constant #idr.closure<@f, [7]> : !idr.fn<(i64, i64) -> (i64)>
// CHECK-DAG: idr.constant #idr.closure<@f, [7, 8]> : !idr.fn<(i64) -> (i64)>
// CHECK-DAG: idr.constant #idr.closure<@g, ["seven"]> : !idr.fn<(i64) -> (i64)>
// CHECK: return
// REMARK: remark: [Passed] Evaluated
module {
  func.func private @f(%a: i64, %b: i64, %x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %s = arith.addi %a, %b : i64
    %r = arith.addi %s, %x : i64
    return %r : i64
  }
  func.func private @g(%s: !idr.str, %x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    return %x : i64
  }
  func.func private @make(%k: i64, %s: !idr.str)
      -> (!idr.fn<(i64, i64, i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>,
          !idr.fn<(i64) -> (i64)>)
      attributes {idr.total, idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %l = arith.addi %k, %one : i64
    %c0 = idr.closure @f() : () -> !idr.fn<(i64, i64, i64) -> (i64)>
    %c1 = idr.closure @f(%k) : (i64) -> !idr.fn<(i64, i64) -> (i64)>
    %c2 = idr.closure @f(%k, %l) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %c3 = idr.closure @g(%s) : (!idr.str) -> !idr.fn<(i64) -> (i64)>
    return %c0, %c1, %c2, %c3
        : !idr.fn<(i64, i64, i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>,
          !idr.fn<(i64) -> (i64)>
  }
  func.func @Prog.main()
      -> (!idr.fn<(i64, i64, i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>,
          !idr.fn<(i64) -> (i64)>) {
    %seven = arith.constant 7 : i64
    %s = idr.constant "seven" : !idr.str
    %c0, %c1, %c2, %c3 = func.call @make(%seven, %s)
        : (i64, !idr.str) -> (!idr.fn<(i64, i64, i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>,
                              !idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)
    return %c0, %c1, %c2, %c3
        : !idr.fn<(i64, i64, i64) -> (i64)>, !idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>,
          !idr.fn<(i64) -> (i64)>
  }
}
