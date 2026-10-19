// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=specialized-once=@iter})' -o /dev/null
// iter f n x = if n == 0 then f x else iter (\y => f (f y)) (n - 1) x: the
// closure grows on every iteration, so f is no fixed parameter: the
// entering call keys the closure it is given once, and the recursion keys
// nothing of the closure it grows, so the copy calls @iter itself and no
// copy is made for a call in another; specializing on each would make a
// copy per iteration. Each function carries the location Emit gives it,
// its definition's name, by which a copy names what it was made from.
idr.program @growing root(@Main.main) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  } loc("inc")
  idr.func @twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  } loc("twice")
  idr.func @iter(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default(%d: i64) {
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @iter(%g, %m, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  } loc("iter")
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @iter(%f, %x, %x) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  } loc("Main.main")
}
