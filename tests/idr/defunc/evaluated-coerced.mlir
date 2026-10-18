// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// An evaluated suspension holds its value and names no label: it is a cell
// already forced. It shares the one memo sum of every cell that reaches
// the slots it reaches, here @later's, since lazy sets are unified, and it
// is built forced in that sum, never rebuilt and never taken for a move
// that does not run: only a key no value ever reaches gives poison.
idr.program @"evaluated-coerced" root(@Main.main) stage(higher) {
  idr.func @later(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @use(%l: !idr.lazy<i64>) -> i64 {
    %v = idr.force %l : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %now = idr.delay %n : i64 -> !idr.lazy<i64>
    %s = idr.suspend @later(%n) : (i64) -> !idr.lazy<i64>
    %a = idr.call @use(%now) : (!idr.lazy<i64>) -> i64
    %b = idr.call @use(%s) : (!idr.lazy<i64>) -> i64
    %r = arith.addi %a, %b : i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
