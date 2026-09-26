// RUN: idris-mlir-opt %s --idr-check-input | FileCheck %s
// rule: IDR-WORLD-1, IDR-TY-5
// One use in each branch of a match is one use on each path.
// CHECK: scf.if
module attributes {idr.version = 1 : i64, idr.entry = @r, idr.entry_kind = "io"} {
  func.func private @r(%w: !idr.world {idr.quantity = "1"}) -> i64 attributes {idr.name = "r"} {
    %c = arith.constant 65 : i32
    %b = arith.constant true
    %z = arith.constant 0 : i64
    %v = scf.if %b -> i64 {
      %w1 = idr.io.put_char %c, %w
      scf.yield %z : i64
    } else {
      %w2 = idr.io.put_char %c, %w
      scf.yield %z : i64
    }
    return %v : i64
  }
}
