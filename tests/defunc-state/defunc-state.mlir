// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.twice:arg0:[@Main.tick],labels=@Main.twice:arg1:[@Main.tick],labels=@Main.seq:arg0:[@Main.twice],labels=@Main.seq:arg1:[@Main.loop],labels=@Main.run:result:[@Main.done,@Main.seq]' -o /dev/null
// A state monad's shape (tests/state-monad):
// run n = if n == 0 then done else seq twice (loop n), where every value is
// a state transformer of the one type T = i64 -> i64. seq's closure
// captures closures of T, but only of twice and loop, and twice's only of
// tick, so the labels never lead back to seq: each (T, labels) gets its own
// sum, and no closure is left. Keying by the type alone would have called T
// infinite.
idr.program @state root(@Main.main) stage(higher) {
  idr.func @Main.tick(%s: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %t = arith.addi %s, %c1 : i64
    return %t : i64
  }
  idr.func @Main.done(%s: i64) -> i64 attributes {total} {
    return %s : i64
  }
  // twice m k = \s => k (m s), of two ticks.
  idr.func @Main.twice(%m: !idr.fn<(i64) -> (i64)>, %k: !idr.fn<(i64) -> (i64)>, %s: i64) -> i64 attributes {total} {
    %a = idr.apply %m(%s) : !idr.fn<(i64) -> (i64)>
    %b = idr.apply %k(%a) : !idr.fn<(i64) -> (i64)>
    return %b : i64
  }
  // seq m k = \s => k (m s), of a twice and the rest of the loop.
  idr.func @Main.seq(%m: !idr.fn<(i64) -> (i64)>, %k: !idr.fn<(i64) -> (i64)>, %s: i64) -> i64 {
    %a = idr.apply %m(%s) : !idr.fn<(i64) -> (i64)>
    %b = idr.apply %k(%a) : !idr.fn<(i64) -> (i64)>
    return %b : i64
  }
  idr.func @Main.loop(%n: i64, %s: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %r = idr.call @Main.run(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %t = idr.apply %r(%s) : !idr.fn<(i64) -> (i64)>
    return %t : i64
  }
  idr.func @Main.run(%n: i64) -> !idr.fn<(i64) -> (i64)> {
    %twice = idr.constant !idr.fn<(i64) -> (i64)> #idr.closure<@Main.twice, [#idr.closure<@Main.tick, []>, #idr.closure<@Main.tick, []>]>
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %d = idr.closure @Main.done() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %d : !idr.fn<(i64) -> (i64)>
    }
    default(%d0: i64) {
      %l = idr.closure @Main.loop(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
      %q = idr.closure @Main.seq(%twice, %l) : (!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
      idr.yield %q : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %c0 = arith.constant 0 : i64
    %f = idr.call @Main.run(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %s = idr.apply %f(%c0) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
