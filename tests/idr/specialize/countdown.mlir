// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize --idr-expect=holds=one-clone=@loop -o /dev/null
// NEEDS-ACCEPTANCE: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
// loop n f x = if n == 0 then x else loop (n - 1) f (f x), called as
// loop 5 f x with f a closure that captures a value read at run time. The
// closure is passed unchanged along the recursion, so the copy is keyed on
// it once and calls itself; the count goes down at every step, so it keys
// nothing: one copy, not one per step, and no count of steps decides it.
idr.program @countdown root(@Main.main) stage(higher) {
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
    %n = arith.constant 5 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @loop(%n, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
