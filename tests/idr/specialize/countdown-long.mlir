// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize --idr-expect=holds=one-clone=@loop -o /dev/null
// NEEDS-ACCEPTANCE: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
// countdown.mlir's loop, called as loop 1000000 f x: the count is no key
// position however large it is, so the copies are as few as for 5: one,
// keyed on the closure, calling itself.
idr.program @"countdown-long" root(@Main.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %k : i64
    return %y : i64
  }
  idr.func @loop(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @loop(%m, %f, %y) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %n = arith.constant 1000000 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @loop(%n, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
