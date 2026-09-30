// RUN: idris-mlir-opt %s --idr-specialize --symbol-dce --idr-expect=holds=no-closures > %t.mlir
// RUN: FileCheck %s < %t.mlir
// An IO action is linear: the result of @greet enters a linear position and
// is used at once before its field is applied. The pair only moves the
// action in and out, so the apply is still the call's one consumer: the
// call and the apply become a call of a raised clone that takes the world,
// and in it the apply meets the closures @greet builds.
// CHECK-LABEL: func.func @Main.main(
// CHECK: call @{{greet\$raise\$[0-9]+}}(
module attributes {idr.program} {
  idr.data @IORes {
    idr.ctor @MkIORes (i64, !idr.world)
  }
  idr.data @IO {
    idr.ctor @MkIO (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
  }
  func.func private @put(%n: i64, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %r = idr.con @IORes::@MkIORes(%n, %w1) : (i64, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func private @greet(%n: i64) -> !idr.data<@IO> attributes {idr.total} {
    %k = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %io = idr.con @IO::@MkIO(%k_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.data<@IORes> {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %io = func.call @greet(%n) : (i64) -> !idr.data<@IO>
    %in = idr.lin.enter %io : !idr.lin<!idr.data<@IO>>
    %out = idr.lin.use %in : !idr.lin<!idr.data<@IO>>
    %f_lin = idr.field %out[@MkIO, 0] : !idr.data<@IO> -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %f = idr.lin.use %f_lin : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %r = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
}
