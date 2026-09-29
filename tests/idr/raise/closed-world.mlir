// RUN: idris-mlir-opt %s --idr-simplify > %t.mlir
// RUN: FileCheck %s < %t.mlir
// The IO loop of io-loop.mlir, called with a literal. The call of the loop
// breaker @countdown is closed, and stays a call: raising gives it the
// world, which carries no value to specialize around, so the raised call
// is closed too, and the partial loop is not unrolled at compile time one
// clone per count; it runs as a loop.
// CHECK-LABEL: func.func @Main.main(
// CHECK-SAME: %[[W:[a-z0-9_]+]]: !idr.world
// CHECK: %[[C3:.*]] = arith.constant 3 : i64
// CHECK: call @[[C:countdown\$raise\$[0-9]+]](%[[C3]], %[[W]])
// CHECK: func.func private @[[C]](
// CHECK: func.call @[[C]](
// CHECK-NOT: $spec$
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit tag 0 ()
  }
  idr.data @IORes {
    idr.ctor @MkIORes tag 0 (!idr.data<@Unit>, !idr.world)
  }
  idr.data @IO {
    idr.ctor @MkIO tag 0 (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
  }
  func.func private @countdown(%n: i64) -> !idr.data<@IO> attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.data<@IO>) {
    case 0 {
      %k = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %io = idr.con @IO::@MkIO(%k_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>) -> !idr.data<@IO>
      idr.yield %io : !idr.data<@IO>
    }
    default {
      %p = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %then = idr.closure @next(%n) : (i64) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
      %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %then_lin = idr.lin.enter %then : !idr.lin<!idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>>
      %k = idr.closure @bind(%p_lin, %then_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>, !idr.lin<!idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %io = idr.con @IO::@MkIO(%k_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>) -> !idr.data<@IO>
      idr.yield %io : !idr.data<@IO>
    }
    }
    return %r : !idr.data<@IO>
  }
  func.func private @next(%n: i64, %u: !idr.data<@Unit>) -> !idr.data<@IO> {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %a = func.call @countdown(%m) : (i64) -> !idr.data<@IO>
    return %a : !idr.data<@IO>
  }
  func.func private @bind(%a: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>, %k: !idr.lin<!idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>>, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %a_use = idr.lin.use %a : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %r = idr.apply %a_use(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %u = idr.field %r[@MkIORes, 0] : !idr.data<@IORes> -> !idr.data<@Unit>
    %w1 = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
    %k_use = idr.lin.use %k : !idr.lin<!idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>>
    %io = idr.apply %k_use(%u) : !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %f_lin = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %s : !idr.data<@IORes>
  }
  func.func private @put(%n: i64, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w1) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func private @done(%w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.data<@IORes> {
    %n = arith.constant 3 : i64
    %a = func.call @countdown(%n) : (i64) -> !idr.data<@IO>
    %f_lin = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
}
