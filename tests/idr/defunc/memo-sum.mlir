// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' --implicit-check-not='{{(idr\.| )suspend }}' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms and the dispatches, as C01's printer and C06's conversion write them.
// A Lazy value picked at runtime and forced later: its type's key becomes a
// memo sum, a box, so that every reference sees one cell. It has a
// constructor per label, named after the label's function, whose fields
// are the captures, then `running`, the state of a cell its force is
// computing, and `forced`, with the value. Its `labels` name the label
// functions, which nothing else names once each suspension is a
// constructor. The force keeps its op and takes the box; nothing lazy is
// left.
// CHECK: ![[L:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, memo [@one(), @twice(i64), @running(), @forced(i64)]
// CHECK-LABEL: idr.func @Main.main(
// CHECK: match_lit %{{.*}} : i64 -> (!idr.box<![[L]]>) {
// CHECK: con !idr.box<![[L]]> @one()
// CHECK: con !idr.box<![[L]]> @twice(%{{.*}} : i64)
// CHECK: force %{{.*}} : !idr.box<![[L]]> -> i64
idr.program @"memo-sum" root(@Main.main) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.match_lit %n : i64 -> (!idr.lazy<i64>) {
    case 65 {
      %a = idr.suspend @one() : () -> !idr.lazy<i64>
      idr.yield %a : !idr.lazy<i64>
    }
    default {
      %b = idr.suspend @twice(%n) : (i64) -> !idr.lazy<i64>
      idr.yield %b : !idr.lazy<i64>
    }
    }
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
