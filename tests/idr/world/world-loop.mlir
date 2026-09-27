// RUN: not idris-mlir-opt %s --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-WORLD-1
// A world from before a loop, used in its body, is used once per iteration.
// CHECK: idr contract violation: a world value is used twice on one path
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  func.func private @r(%w: !idr.world {idr.quantity = "1"}) -> i64 {
    %c = arith.constant 65 : i32
    %z = arith.constant 0 : i64
    cf.br ^loop(%z : i64)
  ^loop(%n: i64):
    %w1 = idr.io.put_char %c, %w
    cf.br ^loop(%n : i64)
  }
}
