// RUN: not idris-mlir-opt %s --idr-check-input 2>&1 | FileCheck %s
// rule: IDR-WORLD-1
// CHECK: idr contract violation: a world value is used twice on one path
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  func.func private @r(%w: !idr.world {idr.quantity = "1"}) -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
