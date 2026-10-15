// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=@count.spec. < %t.mlir
// An accumulator and a counter are never specialized on, static as they
// are: each copy would take the next value, one copy per iteration. The
// call of @count, which is on a cycle and so never inlined, keeps its
// constant and runs as a loop.
// CHECK: call @count(%{{.*}}, %{{.*}}) : (i64, !idr.big) -> i64
idr.program @accumulator root(@Main.main) stage(first) {
  idr.func @count(%acc: i64, %n: !idr.big) -> i64 attributes {total} {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<0> {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %one = idr.constant #idr.big<1> : !idr.big
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = idr.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @use(%acc: i64) -> i64 attributes {total} {
    %c100 = idr.constant #idr.big<100> : !idr.big
    %r = idr.call @count(%acc, %c100) : (i64, !idr.big) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = idr.call @use(%x) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
