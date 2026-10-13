// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// A state monad's shape (tests/programs/basic/state-monad):
// run n = if n == 0 then done else seq twice (loop n), where every value is
// a state transformer of the one type T = i64 -> i64. seq's closure
// captures closures of T, but only of twice and loop, and twice's only of
// tick, so the labels never lead back to seq: each (T, labels) gets its own
// sum, and no closure is left. Keying by the type alone would have called T
// infinite.
// CHECK: idr.data @[[F0:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.tick ()
// CHECK-NEXT: }
// CHECK: idr.data @[[F1:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.twice (![[F0]], ![[F0]])
// CHECK-NEXT: }
// CHECK: idr.data @[[F2:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.loop (i64)
// CHECK-NEXT: }
// CHECK: idr.data @[[F3:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.done ()
// CHECK-NEXT: idr.ctor @Main.seq (![[F1]], ![[F2]])
// CHECK-NEXT: }
// CHECK-NOT: !idr.fn
// CHECK-NOT: {{(idr\.| )closure }}
// CHECK-NOT: {{(idr\.| )apply }}
// CHECK-LABEL: idr.func private @Main.twice(
// CHECK-SAME: %{{.*}}: ![[F0]], %{{.*}}: ![[F0]], %{{.*}}: i64) -> i64
// CHECK-LABEL: idr.func private @Main.seq(
// CHECK-SAME: %{{.*}}: ![[F1]], %{{.*}}: ![[F2]], %{{.*}}: i64) -> i64
// CHECK: match %{{.*}} : ![[F1]] -> (i64) {
// CHECK-NEXT: case @Main.twice(%{{.*}}: ![[F0]], %{{.*}}: ![[F0]]) {
// CHECK: match %{{.*}} : ![[F2]] -> (i64) {
// CHECK-NEXT: case @Main.loop(%{{.*}}: i64) {
// CHECK-LABEL: idr.func private @Main.run(
// CHECK-SAME: -> ![[F3]]
// CHECK: constant #idr.con<@[[F1]]::@Main.twice, [#idr.con<@[[F0]]::@Main.tick, []>, #idr.con<@[[F0]]::@Main.tick, []>]> : ![[F1]]
// CHECK: con @[[F3]]::@Main.done() : () -> ![[F3]]
// CHECK: con @[[F2]]::@Main.loop(%{{.*}}) : (i64) -> ![[F2]]
// CHECK: con @[[F3]]::@Main.seq(%{{.*}}, %{{.*}}) : (![[F1]], ![[F2]]) -> ![[F3]]
module attributes {idr.program} {
  idr.func private @Main.tick(%s: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %t = arith.addi %s, %c1 : i64
    return %t : i64
  }
  idr.func private @Main.done(%s: i64) -> i64 attributes {total} {
    return %s : i64
  }
  // twice m k = \s => k (m s), of two ticks.
  idr.func private @Main.twice(%m: !idr.fn<(i64) -> (i64)>, %k: !idr.fn<(i64) -> (i64)>, %s: i64) -> i64 attributes {total} {
    %a = idr.apply %m(%s) : !idr.fn<(i64) -> (i64)>
    %b = idr.apply %k(%a) : !idr.fn<(i64) -> (i64)>
    return %b : i64
  }
  // seq m k = \s => k (m s), of a twice and the rest of the loop.
  idr.func private @Main.seq(%m: !idr.fn<(i64) -> (i64)>, %k: !idr.fn<(i64) -> (i64)>, %s: i64) -> i64 {
    %a = idr.apply %m(%s) : !idr.fn<(i64) -> (i64)>
    %b = idr.apply %k(%a) : !idr.fn<(i64) -> (i64)>
    return %b : i64
  }
  idr.func private @Main.loop(%n: i64, %s: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %r = idr.call @Main.run(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %t = idr.apply %r(%s) : !idr.fn<(i64) -> (i64)>
    return %t : i64
  }
  idr.func private @Main.run(%n: i64) -> !idr.fn<(i64) -> (i64)> {
    %twice = idr.constant #idr.closure<@Main.twice, [#idr.closure<@Main.tick, []>, #idr.closure<@Main.tick, []>]> : !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %d = idr.closure @Main.done() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %d : !idr.fn<(i64) -> (i64)>
    }
    default {
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
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
