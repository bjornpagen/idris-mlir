// RUN: idris-mlir-opt %s --idr-returned-arguments -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=signature=@branch:(i64,i1)->(),signature=@loop:(i64,i64)->(),signature=@region:(i64)->(),signature=@even:(i64,i64)->(),signature=@odd:(i64,i64)->(),signature=@spin:(i64)->i64,signature=@either:(i64,i64,i1)->i64' -o /dev/null
// Which argument each value is is one dataflow over the module: what a
// region branch joins (scf.if, scf.while, scf.execute_region alike), and
// what a call gives back read through its callee, a cycle of calls solved
// from the optimistic start. So idr-returned-arguments drops the result
// of @branch, @loop, @region and of the mutually recursive @even and @odd,
// each an argument on every path. A result only a call that never returns
// gives is no argument, and stays (@spin), as does one that is another
// argument on some path (@either).
module {
  func.func @main(%a: i64, %b: i64, %c: i1, %n: i64) -> i64 {
    %r1 = func.call @branch(%a, %c) : (i64, i1) -> i64
    %r2 = func.call @loop(%r1, %n) : (i64, i64) -> i64
    %r3 = func.call @region(%r2) : (i64) -> i64
    %r4 = func.call @even(%r3, %n) : (i64, i64) -> i64
    %r5 = func.call @either(%r4, %b, %c) : (i64, i64, i1) -> i64
    %r6 = func.call @spin(%r5) : (i64) -> i64
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
