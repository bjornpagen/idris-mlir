// RUN: idris-mlir-opt %s --idr-eval --remarks-filter=idr-eval 2> %t.remarks | FileCheck %s
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// A result is worth its call only when its constants are not too large:
// `rep 21 "x"` is a string of 2 MiB, which would take more static data than
// the call it replaces is worth, so the call stays, to run at runtime, with
// a remark that says why. `rep 10 "x"`, 1 KiB, is evaluated.
// CHECK-LABEL: func.func @Prog.main()
// CHECK: call @rep
// CHECK-NOT: call
// CHECK: return
// REMARK-DAG: remark: [Missed] TooLarge {{.*}}Function=rep{{.*}}its results take more than 1048576 bytes of static data
// REMARK-DAG: remark: [Passed] Evaluated {{.*}}Function=rep
module {
  func.func private @rep(%n: i64, %s: !idr.str) -> !idr.str attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      idr.yield %s : !idr.str
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %d = idr.str.append %s, %s
      %t = func.call @rep(%m, %d) : (i64, !idr.str) -> !idr.str
      idr.yield %t : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func @Prog.main() -> (!idr.str, !idr.str) {
    %x = idr.constant "x" : !idr.str
    %big = arith.constant 21 : i64
    %small = arith.constant 10 : i64
    %a = func.call @rep(%big, %x) : (i64, !idr.str) -> !idr.str
    %b = func.call @rep(%small, %x) : (i64, !idr.str) -> !idr.str
    return %a, %b : !idr.str, !idr.str
  }
}
