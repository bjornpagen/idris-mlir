// NEEDS-ACCEPTANCE: that idr-returned-arguments drops each result returned as its function's argument through scf.if, scf.while, scf.execute_region and mutual recursion (five), keeps a result only a call that never returns gives and one that is an argument on some paths only, and that every caller uses the argument it passed.
// RUN: idris-mlir-opt %s --idr-returned-arguments --mlir-pass-statistics -o %t.mlir 2> %t.stats
// RUN: FileCheck %s --check-prefix=STATS < %t.stats
// RUN: FileCheck %s < %t.mlir
// Which argument each value is is one dataflow over the module: what a
// region branch joins (scf.if, scf.while, scf.execute_region alike), and
// what a call gives back read through its callee, a cycle of calls solved
// from the optimistic start. A result only a call that never returns gives
// is no argument, and stays, as does one that is another argument on some
// path.
// STATS: IdrReturnedArguments
// STATS: (S) 5 dropped
// CHECK-LABEL: func.func @main
// CHECK: call @branch({{[^)]*}}) : (i64, i1) -> ()
// CHECK: call @loop({{[^)]*}}) : (i64, i64) -> ()
// CHECK: call @region({{[^)]*}}) : (i64) -> ()
// CHECK: call @even({{[^)]*}}) : (i64, i64) -> ()
// CHECK: call @spin({{[^)]*}}) : (i64) -> i64
// CHECK: call @either({{[^)]*}}) : (i64, i64, i1) -> i64
module {
  func.func @main(%a: i64, %b: i64, %c: i1, %n: i64) -> i64 {
    %r1 = func.call @branch(%a, %c) : (i64, i1) -> i64
    %r2 = func.call @loop(%r1, %n) : (i64, i64) -> i64
    %r3 = func.call @region(%r2) : (i64) -> i64
    %r4 = func.call @even(%r3, %n) : (i64, i64) -> i64
    %r5 = func.call @spin(%r4) : (i64) -> i64
    %r6 = func.call @either(%r5, %b, %c) : (i64, i64, i1) -> i64
    return %r6 : i64
  }
  func.func private @branch(%a: i64, %c: i1) -> i64 {
    %r = scf.if %c -> (i64) {
      scf.yield %a : i64
    } else {
      scf.yield %a : i64
    }
    return %r : i64
  }
  func.func private @loop(%a: i64, %n: i64) -> i64 {
    %r:2 = scf.while (%x = %a, %i = %n) : (i64, i64) -> (i64, i64) {
      %c0 = arith.constant 0 : i64
      %go = arith.cmpi sgt, %i, %c0 : i64
      scf.condition(%go) %x, %i : i64, i64
    } do {
    ^bb0(%x2: i64, %i2: i64):
      %one = arith.constant 1 : i64
      %j = arith.subi %i2, %one : i64
      scf.yield %x2, %j : i64, i64
    }
    return %r#0 : i64
  }
  func.func private @region(%a: i64) -> i64 {
    %r = scf.execute_region -> i64 {
      scf.yield %a : i64
    }
    return %r : i64
  }
  func.func private @even(%a: i64, %n: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %zero = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %zero -> (i64) {
      scf.yield %a : i64
    } else {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %o = func.call @odd(%a, %m) : (i64, i64) -> i64
      scf.yield %o : i64
    }
    return %r : i64
  }
  func.func private @odd(%a: i64, %n: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %zero = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %zero -> (i64) {
      scf.yield %a : i64
    } else {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %e = func.call @even(%a, %m) : (i64, i64) -> i64
      scf.yield %e : i64
    }
    return %r : i64
  }
  func.func private @spin(%a: i64) -> i64 {
    %r = func.call @spin(%a) : (i64) -> i64
    return %r : i64
  }
  func.func private @either(%a: i64, %b: i64, %c: i1) -> i64 {
    %r = scf.if %c -> (i64) {
      scf.yield %a : i64
    } else {
      scf.yield %b : i64
    }
    return %r : i64
  }
}
