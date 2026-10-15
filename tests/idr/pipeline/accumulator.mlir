// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=one-clone=@count -o /dev/null
// RUN: FileCheck %s < %t.mlir
// An accumulator through the optimizer: @count is called with a constant
// Integer accumulator and a counter read at runtime. The accumulator
// changes on every iteration, so it is no static parameter and the call is
// not specialized on it: @count is still called, and no copy of it is
// made.
// CHECK: call @count(
// CHECK-NOT: @count.
idr.program @accumulator root(@Main.main) stage(first) {
  idr.func @count(%acc: !idr.big, %n: i64) -> !idr.big attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.big) {
    case 0 {
      idr.yield %acc : !idr.big
    }
    default {
      %one = idr.constant #idr.big<1> : !idr.big
      %c1 = arith.constant 1 : i64
      %a = idr.big.add %acc, %one
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (!idr.big, i64) -> !idr.big
      idr.yield %x : !idr.big
    }
    }
    return %r : !idr.big
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %zero = idr.constant #idr.big<0> : !idr.big
    %r = idr.call @count(%zero, %n) : (!idr.big, i64) -> !idr.big
    %t = idr.big.show %r
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }
}
