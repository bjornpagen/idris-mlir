// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// An IO action is a closure in a constructor (MkIO). When the result of a
// call is projected and applied at once, the projection moves with the
// apply: in the clone of @greet it meets the constant action of one region
// and the constructor of the other, and both fold to a call of the
// closure's function. The clone is total, as its callee and every function
// it applies are; it is effectful as its callee is. Where
// what a tail applies is not known here (@same returns its parameter), the
// clone applies the field it reads, and is not total.
// CHECK-LABEL: func.func private @twice(
// CHECK-SAME: %[[IO:[a-z0-9_]+]]: !idr.data<@IO>, %[[V:[a-z0-9_]+]]: !idr.world
// CHECK-NEXT: %[[S:.*]] = call @[[SAME:same\$raise\$[0-9]+]](%[[IO]], %[[V]])
// CHECK-NEXT: return %[[S]]
// CHECK-LABEL: func.func @Main.main(
// CHECK-SAME: %[[W:[a-z0-9_]+]]: !idr.world
// CHECK: %[[C:.*]], %[[W1:.*]] = idr.io.get_byte %[[W]]
// CHECK: %[[N:.*]] = arith.extui %[[C]]
// CHECK-NEXT: %[[R:.*]] = call @[[GREET:greet\$raise\$[0-9]+]](%[[N]], %[[W1]]) : (i64, !idr.world) -> !idr.data<@IORes>
// CHECK-NEXT: return %[[R]]
// CHECK: func.func private @[[SAME]](
// CHECK-SAME: %[[X:[a-z0-9_]+]]: !idr.data<@IO> {{.*}}, %[[Y:[a-z0-9_]+]]: !idr.world {{.*}}) -> !idr.data<@IORes>
// CHECK-SAME: idr.effects = #idr.effects<none>
// CHECK-NOT: idr.total
// CHECK-NEXT: %[[F:.*]] = idr.field %[[X]][@MkIO, 0]
// CHECK-NEXT: %[[Z:.*]] = idr.apply %[[F]](%[[Y]])
// CHECK-NEXT: return %[[Z]]
// CHECK: func.func private @[[GREET]](
// CHECK-SAME: %[[A:[a-z0-9_]+]]: i64 {{.*}}, %[[B:[a-z0-9_]+]]: !idr.world {{.*}}) -> !idr.data<@IORes>
// CHECK-SAME: idr.effects = #idr.effects<io>{{.*}}idr.total
// CHECK: case 0 {
// CHECK-NEXT: %[[D:.*]] = func.call @done(%[[B]])
// CHECK-NEXT: idr.yield %[[D]] : !idr.data<@IORes>
// CHECK: default {
// CHECK-NEXT: %[[P:.*]] = func.call @put(%[[A]], %[[B]])
// CHECK-NEXT: idr.yield %[[P]] : !idr.data<@IORes>
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
  func.func private @put(%n: i64, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.effects = #idr.effects<io>, idr.total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w1) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func private @done(%w: !idr.world) -> !idr.data<@IORes> attributes {idr.effects = #idr.effects<none>, idr.total} {
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func private @greet(%n: i64) -> !idr.data<@IO> attributes {idr.effects = #idr.effects<io>, idr.total} {
    %done = idr.constant #idr.con<@IO::@MkIO, [#idr.closure<@done, []>]> : !idr.data<@IO>
    %r = idr.match_lit %n : i64 -> (!idr.data<@IO>) {
    case 0 {
      idr.yield %done : !idr.data<@IO>
    }
    default {
      %k = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %io = idr.con @IO::@MkIO(%k) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
      idr.yield %io : !idr.data<@IO>
    }
    }
    return %r : !idr.data<@IO>
  }
  func.func private @same(%io: !idr.data<@IO>) -> !idr.data<@IO> attributes {idr.effects = #idr.effects<none>, idr.total} {
    return %io : !idr.data<@IO>
  }
  func.func private @twice(%io: !idr.data<@IO>, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.effects = #idr.effects<none>, idr.total} {
    %a = func.call @same(%io) : (!idr.data<@IO>) -> !idr.data<@IO>
    %f = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.data<@IORes> attributes {idr.effects = #idr.effects<io>} {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = func.call @greet(%n) : (i64) -> !idr.data<@IO>
    %f = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %r = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
}
