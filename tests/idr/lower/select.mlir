// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --canonicalize --idr-lower | FileCheck %s
// rule: LOW-SEL-1, LOW-BLOCK-1
// canonicalize merges the two branches into one with an arith.select of
// !idr.str, which lowers to one select per component.
// CHECK-LABEL: func.func private @Prog.main(
// CHECK: arith.select %{{.*}}, %{{.*}}, %{{.*}} : !llvm.ptr
// CHECK: arith.select %{{.*}}, %{{.*}}, %{{.*}} : i64
// CHECK-NOT: !idr.str
module attributes {idr.version = 1 : i64, idr.entry = @Prog.main, idr.entry_kind = "io"} {
  func.func private @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> i64 {
    %c, %w1 = idr.io.get_char %w
    %z = arith.constant 48 : i32
    %b = arith.cmpi ult, %c, %z : i32
    %x = idr.str.lit "low" : !idr.str
    %y = idr.str.lit "high!" : !idr.str
    cf.cond_br %b, ^low, ^high
  ^low:
    cf.br ^join(%x : !idr.str)
  ^high:
    cf.br ^join(%y : !idr.str)
  ^join(%s: !idr.str):
    %w2 = idr.io.put_str %s, %w1
    %r = arith.constant 0 : i64
    return %r : i64
  }
}
