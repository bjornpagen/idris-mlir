// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' --implicit-check-not='!idr.fn' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms and the dispatches, as C01's printer and C06's conversion write them.
// Two suspensions of one Lazy slot whose labels return closures of
// different labels: the cell's one forced field holds what either label
// returns, so both labels return into the one slot, the join of their
// labels, and the force gives that slot's sum.
// CHECK: ![[F:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@inc(), @twice(){{.*}}]
// CHECK: ![[L:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, memo [@give.inc(), @give.twice(), @running(), @forced(![[F]])]
// CHECK: idr.func private @give.inc() -> ![[F]]
// CHECK: idr.func private @give.twice() -> ![[F]]
// CHECK-LABEL: idr.func @Main.main(
// CHECK: force %{{.*}} : !idr.box<![[L]]> -> ![[F]]
// CHECK: match %{{.*}} : ![[F]] -> (i64) {
// CHECK: case @inc() {
// CHECK: case @twice() {
module {
  idr.func private @inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @give.inc() -> !idr.fn<(i64) -> i64> attributes {total} {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func private @give.twice() -> !idr.fn<(i64) -> i64> attributes {total} {
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
