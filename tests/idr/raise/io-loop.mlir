// RUN: idris-mlir-opt %s --idr-simplify > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-tail-loops | FileCheck %s --check-prefix=LOOP
// An IO loop, in the shape Emit gives it: @countdown, a loop breaker,
// returns the action `put n >>= \_ => countdown (n - 1)`, where @bind runs
// its first action, then applies the function it is given and runs the
// action that returns, and @Main.main runs the action it gets. The call of
// @countdown in @Main.main is applied at once to a world through the field
// of MkIO, so it calls a clone that takes the world. In the clone, the
// apply meets the closure of each region and becomes a call of @bind; the
// next round inlines @bind, @put and @next into the clone, which exposes
// the call of @countdown that @next makes, applied the same way: it calls
// the clone itself. The loop is a self tail call with no closure left,
// which idr-tail-loops makes an scf.while, and which allocates nothing.
// CHECK-LABEL: func.func @Main.main(
// CHECK: %{{.*}}, %[[W:.*]] = idr.io.get_byte
// CHECK: call @[[C:countdown\$raise\$[0-9]+]](%{{.*}}, %[[W]]) : (i64, !idr.world) -> !idr.data<@IORes>
// CHECK: func.func private @[[C]](
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64 {{.*}}, %[[W0:[a-z0-9_]+]]: !idr.world {{.*}}) -> !idr.data<@IORes>
// CHECK-SAME: no_inline
// CHECK: default {
// CHECK: %[[W1:.*]] = idr.io.put_int signed %[[N]], %[[W0]] : i64
// CHECK: %[[R:.*]] = func.call @[[C]](%{{.*}}, %[[W1]])
// CHECK-NEXT: idr.yield %[[R]]
// CHECK-NOT: idr.closure
// CHECK-NOT: idr.apply
// CHECK-NOT: func.func private @countdown(
// CHECK-NOT: func.func private @bind(
// LOOP: func.func private @countdown$raise${{[0-9]+}}(
// LOOP: scf.while
// LOOP-NOT: call @countdown$raise$
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
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = func.call @countdown(%n) : (i64) -> !idr.data<@IO>
    %f_lin = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %r = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
}
