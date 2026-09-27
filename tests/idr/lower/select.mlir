// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --canonicalize --idr-lower | FileCheck %s
// rule: LOW-SEL-1
// canonicalize turns the inner scf.if into an arith.select of !idr.str,
// which lowers to one select per component.
// CHECK-LABEL: func.func private @Prog.main(
// CHECK: arith.select %{{.*}}, %{{.*}}, %{{.*}} : !llvm.ptr
// CHECK: arith.select %{{.*}}, %{{.*}}, %{{.*}} : i64
// CHECK-NOT: !idr.str
module attributes {idr.version = 1 : i64, idr.entry = @Prog.main, idr.entry_kind = "io"} {
  func.func private @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> i64 attributes {idr.name = "main"} {
    %c, %w1 = idr.io.get_char %w
    %z = arith.constant 48 : i32
    %b = arith.cmpi ult, %c, %z : i32
    %s = scf.if %b -> !idr.str {
      %x = idr.str.lit "low" : !idr.str
      scf.yield %x : !idr.str
    } else {
      %y = idr.str.lit "high!" : !idr.str
      scf.yield %y : !idr.str
    }
    %w2 = idr.io.put_str %s, %w1
    %r = arith.constant 0 : i64
    return %r : i64
  }
}
