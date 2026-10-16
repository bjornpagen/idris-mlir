// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// Two suspensions of one Lazy slot whose labels return closures of
// different labels: the cell's one forced field holds what either label
// returns, so both labels return into the one slot, the join of their
// labels, and the force gives that slot's sum.
idr.program @"memo-forced-join" root(@Main.main) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @give.inc() -> !idr.fn<(i64) -> i64> attributes {total} {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func @give.twice() -> !idr.fn<(i64) -> i64> attributes {total} {
    %f = idr.closure @twice() : () -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.match_lit %n : i64 -> (!idr.lazy<!idr.fn<(i64) -> i64>>) {
    case 65 {
      %a = idr.suspend @give.inc() : () -> !idr.lazy<!idr.fn<(i64) -> i64>>
      idr.yield %a : !idr.lazy<!idr.fn<(i64) -> i64>>
    }
    default {
      %b = idr.suspend @give.twice() : () -> !idr.lazy<!idr.fn<(i64) -> i64>>
      idr.yield %b : !idr.lazy<!idr.fn<(i64) -> i64>>
    }
    }
    %f = idr.force %t : !idr.lazy<!idr.fn<(i64) -> i64>> -> !idr.fn<(i64) -> i64>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> i64>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
