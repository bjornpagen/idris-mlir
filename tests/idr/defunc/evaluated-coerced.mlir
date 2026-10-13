// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not=ub.poison --implicit-check-not='!idr.lazy' < %t.mlir
// A lazy key that only an evaluated suspension reaches has no label, but a
// value is in it: the cell is already forced. Moved into a slot that a
// suspension reaches too, it is rebuilt in that slot's sum, state by state,
// like any cell, and never taken for a move that does not run: only a key
// no value ever reaches gives poison.
// CHECK-DAG: idr.data @[[E:lazy\$[0-9]+]] box memo labels [] {
// CHECK-DAG: idr.data @[[F:lazy\$[0-9]+]] box memo labels [@later] {
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[NOW:.*]] = {{(idr\.)?}}con @[[E]]::@forced(%{{.*}}) : (i64) -> ![[E]]
// CHECK: %[[AS:.*]] = {{(idr\.)?}}match %[[NOW]] : ![[E]] -> (![[F]]) {
// CHECK-DAG: con @[[F]]::@running() : () -> ![[F]]
// CHECK-DAG: con @[[F]]::@forced(%{{.*}}) : (i64) -> ![[F]]
// CHECK: call @use(%[[AS]])
module attributes {idr.program} {
  idr.func private @later(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func private @use(%l: !idr.lazy<i64>) -> i64 {
    %v = idr.force %l : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %now = idr.delay : !idr.lazy<i64> {
      idr.yield %n : i64
    }
    %s = idr.suspend @later(%n) : (i64) -> !idr.lazy<i64>
    %a = idr.call @use(%now) : (!idr.lazy<i64>) -> i64
    %b = idr.call @use(%s) : (!idr.lazy<i64>) -> i64
    %r = arith.addi %a, %b : i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
