// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@use:arg0:[@one,@twice],forces-nothing=@use,forces-nothing=@Main.main' -o /dev/null
// A choice between two suspensions made at run time, forced later: the
// match's yields reach its result through the region-branch edges
// upstream's interface declares, so the forced cell may be either
// suspension, and both are constructors of the one memo sum of its key,
// whose labels are the two suspended functions. Each force becomes a call
// of the sum's dispatch, so no force is left. An op that does not
// declare how a suspension moves through it is refused by the verifier
// where it is written (verify-flow).
idr.program @"memo-sum" root(@Main.main) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @use(%l: !idr.lazy<i64>) -> i64 {
    %v = idr.force %l : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.match_lit %n : i64 -> (!idr.lazy<i64>) {
    case 65 {
      %a = idr.suspend @one() : () -> !idr.lazy<i64>
      idr.yield %a : !idr.lazy<i64>
    }
    default(%d: i64) {
      %b = idr.suspend @twice(%n) : (i64) -> !idr.lazy<i64>
      idr.yield %b : !idr.lazy<i64>
    }
    }
    %v = idr.call @use(%t) : (!idr.lazy<i64>) -> i64
    %w2 = idr.io.put_sint %v, %w1 : i64
    return %w2 : !idr.world
  }
}
