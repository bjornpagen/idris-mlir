// RUN: idris-mlir-opt %s --idr-check-input | FileCheck %s
// rule: IDR-WORLD-1
// A loop that carries the world uses each world once.
// CHECK: cf.br ^bb1
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  func.func private @r(%w: !idr.world {idr.quantity = "1"}) -> i64 {
    %c = arith.constant 65 : i32
    cf.br ^loop(%w : !idr.world)
  ^loop(%v: !idr.world):
    %v1 = idr.io.put_char %c, %v
    cf.br ^loop(%v1 : !idr.world)
  }
}
