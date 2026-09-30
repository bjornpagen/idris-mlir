// RUN: idris-mlir-opt %s --idr-simplify | FileCheck %s
// The result of a call used once in each region of a match, applied there
// through the field of MkIO, is raised in each: the call moves into the
// regions (only one runs, so it still runs once) and meets its apply, so
// each region calls the clone that takes the world, and the clone is
// shared, as its key is the callee and the elimination. In @Main.main the
// world each region applies differs, output having been done in one; the
// call, which is total and does no IO, moves past that output.
// CHECK-LABEL: func.func @Main.main(
// CHECK: idr.match_lit
// CHECK: case 0 {
// CHECK-NEXT: %[[A:.*]] = func.call @[[C:greet\$raise\$[0-9]+]](%{{.*}}, %{{.*}}) : (i64, !idr.world) -> !idr.data<@IORes>
// CHECK-NEXT: idr.yield %[[A]]
// CHECK: default {
// CHECK: %[[W:.*]] = idr.io.put_int
// CHECK-NEXT: %[[B:.*]] = func.call @[[C]](%{{.*}}, %[[W]]) : (i64, !idr.world) -> !idr.data<@IORes>
// CHECK-NEXT: idr.yield %[[B]]
// CHECK-NOT: idr.apply
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit ()
  }
  idr.data @IORes {
    idr.ctor @MkIORes (!idr.data<@Unit>, !idr.world)
  }
  idr.data @IO {
    idr.ctor @MkIO (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
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
  func.func private @greet(%n: i64) -> !idr.data<@IO> attributes {idr.effects = #idr.effects<none>, idr.total, no_inline} {
    %done = idr.constant #idr.con<@IO::@MkIO, [#idr.closure<@done, []>]> : !idr.data<@IO>
    %r = idr.match_lit %n : i64 -> (!idr.data<@IO>) {
    case 0 {
      idr.yield %done : !idr.data<@IO>
    }
    default {
      %k = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %io = idr.con @IO::@MkIO(%k_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>) -> !idr.data<@IO>
      idr.yield %io : !idr.data<@IO>
    }
    }
    return %r : !idr.data<@IO>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.data<@IORes> attributes {idr.effects = #idr.effects<io>} {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = func.call @greet(%n) : (i64) -> !idr.data<@IO>
    %r = idr.match_lit %n : i64 -> (!idr.data<@IORes>) {
    case 0 {
      %f_lin = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      idr.yield %s : !idr.data<@IORes>
    }
    default {
      %w2 = idr.io.put_int signed %n, %w1 : i64
      %f_lin = idr.field %a[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
      %s = idr.apply %f(%w2) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
      idr.yield %s : !idr.data<@IORes>
    }
    }
    return %r : !idr.data<@IORes>
  }
}
