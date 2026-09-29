// RUN: idris-mlir-opt %s --idr-effects --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A callee that only builds an IO action performs no IO when it runs,
// although idr-effects finds it effectful: it makes closures of @put, which
// writes. @actions builds `put x *> ...` for each element of a list, as
// for_ does over a list known only at runtime; its call is raised across
// the output between it and the apply that runs its action, and the raised
// call takes the world that output leaves. @mixed also applies a closure it
// is given, which may do anything, so its call stays where it is.
// CHECK-LABEL: func.func private @run(
// CHECK: %[[B:.*]] = call @mixed(
// CHECK: %[[W1:.*]] = idr.io.put_int signed
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_int signed %{{.*}}, %[[W1]]
// CHECK-NEXT: %[[F:.*]] = idr.field %[[B]][@MkIO, 0]
// CHECK-NEXT: %[[R:.*]] = idr.apply %[[F]](%[[W2]])
// CHECK-NEXT: %[[W3:.*]] = idr.field %[[R]][@MkIORes, 1]
// CHECK-NEXT: %[[W4:.*]] = idr.io.put_int signed %{{.*}}, %[[W3]]
// CHECK-NEXT: %{{.*}} = call @actions$raise$[[N:[0-9]+]](%{{.*}}, %[[W4]])
// CHECK-NOT: idr.apply
// CHECK: func.func private @actions$raise$[[N]](
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit tag 0 ()
  }
  idr.data @IORes {
    idr.ctor @MkIORes tag 0 (!idr.data<@Unit>, !idr.world)
  }
  idr.data @IO {
    idr.ctor @MkIO tag 0 (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>)
  }
  idr.data @L box {
    idr.ctor @Nil tag 0 ()
    idr.ctor @Cons tag 1 (i64, !idr.box<@L>)
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
  // Runs %a, then %b.
  func.func private @then(%a: !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, %b: !idr.data<@IO>, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %r = idr.apply %a(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %w1 = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
    %f = idr.field %b[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %s : !idr.data<@IORes>
  }
  func.func private @actions(%xs: !idr.box<@L>) -> !idr.data<@IO> attributes {idr.total} {
    %io = idr.match %xs : !idr.box<@L> -> (!idr.data<@IO>) {
    case @Nil() {
      %k = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %a = idr.con @IO::@MkIO(%k) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
      idr.yield %a : !idr.data<@IO>
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %rest = func.call @actions(%t) : (!idr.box<@L>) -> !idr.data<@IO>
      %p = idr.closure @put(%h) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %k = idr.closure @then(%p, %rest) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.data<@IO>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %a = idr.con @IO::@MkIO(%k) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
      idr.yield %a : !idr.data<@IO>
    }
    }
    return %io : !idr.data<@IO>
  }
  func.func private @mixed(%g: !idr.fn<(i64) -> (!idr.data<@IO>)>, %n: i64) -> !idr.data<@IO> attributes {idr.total} {
    %b = idr.apply %g(%n) : !idr.fn<(i64) -> (!idr.data<@IO>)>
    %p = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %k = idr.closure @then(%p, %b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.data<@IO>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %a = idr.con @IO::@MkIO(%k) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %a : !idr.data<@IO>
  }
  func.func private @run(%xs: !idr.box<@L>, %g: !idr.fn<(i64) -> (!idr.data<@IO>)>, %n: i64, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %b = func.call @mixed(%g, %n) : (!idr.fn<(i64) -> (!idr.data<@IO>)>, i64) -> !idr.data<@IO>
    %a = func.call @actions(%xs) : (!idr.box<@L>) -> !idr.data<@IO>
    %w1 = idr.io.put_int signed %n, %w : i64
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %f = idr.field %b[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %r = idr.apply %f(%w2) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %w3 = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
    %w4 = idr.io.put_int signed %n, %w3 : i64
    %g2 = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %s = idr.apply %g2(%w4) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %s : !idr.data<@IORes>
  }
  func.func @Main.main() -> i64 {
    %c0 = arith.constant 0 : i64
    return %c0 : i64
  }
}
