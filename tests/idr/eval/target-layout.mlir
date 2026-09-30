// RUN: idris-mlir-opt %s -split-input-file --idr-eval | FileCheck %s
// A cell's components are placed as the module's data layout says, and
// the code that builds a cell, the static data of a constant, the code that
// reads a field and the reading back of a result all agree on it: here an
// i64 is 4-aligned, so it follows the i32 directly, and then 8-aligned,
// after padding. Either way the values come back as they went in.
// CHECK-LABEL: func.func @Prog.main()
// CHECK-NOT: call
// CHECK-DAG: idr.constant #idr.con<@P::@MkP, [5 : i32, 1099511627776, 7 : i8]> : !idr.box<@P>
// CHECK-DAG: arith.constant 1099511627786 : i64
// CHECK-DAG: arith.constant 1099511627788 : i64
// CHECK: return
module attributes {dlti.dl_spec = #dlti.dl_spec<i64 = dense<32> : vector<2xi64>>} {
  idr.data @P box {
    idr.ctor @MkP (i32, i64, i8)
  }
  func.func private @mk(%a: i32, %b: i64, %c: i8) -> !idr.box<@P> attributes {idr.total, idr.effects = #idr.effects<none>} {
    %p = idr.con @P::@MkP(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    return %p : !idr.box<@P>
  }
  func.func private @sum(%p: !idr.box<@P>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.match %p : !idr.box<@P> -> (i64) {
    case @MkP(%a: i32, %b: i64, %c: i8) {
      %x = arith.extsi %a : i32 to i64
      %y = arith.extsi %c : i8 to i64
      %s = arith.addi %x, %b : i64
      %t = arith.addi %s, %y : i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  func.func private @roundTrip(%a: i32, %b: i64, %c: i8) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %p = func.call @mk(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    %r = func.call @sum(%p) : (!idr.box<@P>) -> i64
    return %r : i64
  }
  func.func @Prog.main() -> (!idr.box<@P>, i64, i64) {
    %a = arith.constant 5 : i32
    %b = arith.constant 1099511627776 : i64
    %c = arith.constant 7 : i8
    %p = func.call @mk(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    %k = idr.constant #idr.con<@P::@MkP, [3 : i32, 1099511627776, 9 : i8]> : !idr.box<@P>
    %s = func.call @sum(%k) : (!idr.box<@P>) -> i64
    %m = arith.constant -2 : i32
    %n = arith.constant 12 : i8
    %r = func.call @roundTrip(%m, %b, %n) : (i32, i64, i8) -> i64
    return %p, %s, %r : !idr.box<@P>, i64, i64
  }
}

// -----

// CHECK-LABEL: func.func @Prog.main()
// CHECK-NOT: call
// CHECK-DAG: idr.constant #idr.con<@P::@MkP, [5 : i32, 1099511627776, 7 : i8]> : !idr.box<@P>
// CHECK-DAG: arith.constant 1099511627786 : i64
// CHECK-DAG: arith.constant 1099511627788 : i64
// CHECK: return
module attributes {dlti.dl_spec = #dlti.dl_spec<i64 = dense<64> : vector<2xi64>>} {
  idr.data @P box {
    idr.ctor @MkP (i32, i64, i8)
  }
  func.func private @mk(%a: i32, %b: i64, %c: i8) -> !idr.box<@P> attributes {idr.total, idr.effects = #idr.effects<none>} {
    %p = idr.con @P::@MkP(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    return %p : !idr.box<@P>
  }
  func.func private @sum(%p: !idr.box<@P>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.match %p : !idr.box<@P> -> (i64) {
    case @MkP(%a: i32, %b: i64, %c: i8) {
      %x = arith.extsi %a : i32 to i64
      %y = arith.extsi %c : i8 to i64
      %s = arith.addi %x, %b : i64
      %t = arith.addi %s, %y : i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  func.func private @roundTrip(%a: i32, %b: i64, %c: i8) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %p = func.call @mk(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    %r = func.call @sum(%p) : (!idr.box<@P>) -> i64
    return %r : i64
  }
  func.func @Prog.main() -> (!idr.box<@P>, i64, i64) {
    %a = arith.constant 5 : i32
    %b = arith.constant 1099511627776 : i64
    %c = arith.constant 7 : i8
    %p = func.call @mk(%a, %b, %c) : (i32, i64, i8) -> !idr.box<@P>
    %k = idr.constant #idr.con<@P::@MkP, [3 : i32, 1099511627776, 9 : i8]> : !idr.box<@P>
    %s = func.call @sum(%k) : (!idr.box<@P>) -> i64
    %m = arith.constant -2 : i32
    %n = arith.constant 12 : i8
    %r = func.call @roundTrip(%m, %b, %n) : (i32, i64, i8) -> i64
    return %p, %s, %r : !idr.box<@P>, i64, i64
  }
}
