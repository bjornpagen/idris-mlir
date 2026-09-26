// RUN: idris-mlir-opt %s --canonicalize --cse | FileCheck %s
// rule: IDR-EFF-2, IDR-IO-1, IDR-IF-2
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  // Identical IO operations are neither merged nor removed, even unused.
  // CHECK-LABEL: func.func @io(
  // CHECK: idr.io.put_char
  // CHECK-NEXT: idr.io.put_char
  // CHECK-NEXT: %ch, %next = idr.io.get_char
  // CHECK-NEXT: %ch_0, %next_1 = idr.io.get_char
  func.func @io(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %w2 = idr.io.put_char %c, %w1
    %x, %w3 = idr.io.get_char %w2
    %y, %w4 = idr.io.get_char %w3
    return %w4 : !idr.world
  }
  func.func private @r(%w: !idr.world {idr.quantity = "1"}) -> i64 attributes {idr.name = "r"} {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
