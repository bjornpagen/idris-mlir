// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// An IORef of functions is an array of rank 0, made with no size and
// written with no index. What a read of it may give is every label that was
// made into it or written over it, the one slot of its element type, which
// the fill and the written value join from wherever they stand among the
// op's operands. The apply of what it read then calls both.
idr.program @"ioref-closure" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %one = arith.constant 1 : i64
    %f = idr.closure @add(%one) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r, %w2 = idr.array.new [], %f, %w1 : !idr.fn<(i64) -> (i64)> -> memref<!idr.fn<(i64) -> (i64)>, #idr.world>
    %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
    %w3 = idr.array.set %r[], %g, %w2 : memref<!idr.fn<(i64) -> (i64)>, #idr.world>, !idr.fn<(i64) -> (i64)>
    %h, %w4 = idr.array.get %r[], %w3 : memref<!idr.fn<(i64) -> (i64)>, #idr.world> -> !idr.fn<(i64) -> (i64)>
    %y = idr.apply %h(%n) : !idr.fn<(i64) -> (i64)>
    %w5 = idr.io.put_sint %y, %w4 : i64
    return %w5 : !idr.world
  }
}
