// RUN: idris-mlir-opt %s --idr-eval | idris-mlir-opt | FileCheck %s
// `mk 60` is a tree of 2^61 - 1 constructors with 61 distinct ones, each
// the two-fold parent of the one below. Evaluation reads each cell once and
// sends the result as bytecode, which writes each distinct part once, and
// the printed module names each large part once: the whole compilation is
// the size of the 61 distinct parts. Sharing lost anywhere on the way
// would make it take longer than the test may.
// CHECK: #[[P:idr_value[0-9]*]] = #idr.con<@T::@N, [#[[C:idr_value[0-9]*]], #[[C]]]>
// CHECK-LABEL: func.func @Prog.main()
// CHECK-NOT: call
// CHECK: idr.constant #idr_value
module {
  idr.data @T box {
    idr.ctor @L ()
    idr.ctor @N (!idr.box<@T>, !idr.box<@T>)
  }
  func.func private @mk(%n: i64) -> !idr.box<@T> attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@T>) {
    case 0 {
      %l = idr.con @T::@L() : () -> !idr.box<@T>
      idr.yield %l : !idr.box<@T>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = func.call @mk(%m) : (i64) -> !idr.box<@T>
      %c = idr.con @T::@N(%t, %t) : (!idr.box<@T>, !idr.box<@T>) -> !idr.box<@T>
      idr.yield %c : !idr.box<@T>
    }
    }
    return %r : !idr.box<@T>
  }
  func.func @Prog.main() -> !idr.box<@T> {
    %n = arith.constant 60 : i64
    %t = func.call @mk(%n) : (i64) -> !idr.box<@T>
    return %t : !idr.box<@T>
  }
}
