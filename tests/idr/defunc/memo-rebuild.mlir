// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' < %t.mlir
// A cell that moves into a slot with more labels is rebuilt in the larger
// memo sum, and keeps its state: `running` and `forced` are constructors
// of both sums, so a cell already forced is still forced, holding the same
// value, and the force in @use does not run @one again. Here the cell of
// @one is forced before it is passed where @two's cells go too.
// CHECK-DAG: idr.data @[[A:lazy\$[0-9]+]] box memo labels [@one] {
// CHECK-DAG: idr.data @[[B:lazy\$[0-9]+]] box memo labels [@one, @two] {
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[CELL:.*]] = {{(idr\.)?}}con @[[A]]::@one() : () -> ![[A]]
// CHECK: force %[[CELL]] : ![[A]] -> i64
// CHECK: %[[AS:.*]] = {{(idr\.)?}}match %[[CELL]] : ![[A]] -> (![[B]]) {
// CHECK-NEXT: case @one() {
// CHECK-NEXT: con @[[B]]::@one() : () -> ![[B]]
// CHECK: case @running() {
// CHECK-NEXT: con @[[B]]::@running() : () -> ![[B]]
// CHECK: case @forced(%[[V:[^:]*]]: i64) {
// CHECK-NEXT: con @[[B]]::@forced(%[[V]]) : (i64) -> ![[B]]
// CHECK: call @use(%[[AS]])
module attributes {idr.program} {
  idr.func private @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func private @two() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func private @use(%l: !idr.lazy<i64>) -> i64 {
    %v = idr.force %l : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %a = idr.suspend @one() : () -> !idr.lazy<i64>
    %x = idr.force %a : !idr.lazy<i64> -> i64
    %b = idr.suspend @two() : () -> !idr.lazy<i64>
    %y = idr.call @use(%a) : (!idr.lazy<i64>) -> i64
    %z = idr.call @use(%b) : (!idr.lazy<i64>) -> i64
    %xy = arith.addi %x, %y : i64
    %r = arith.addi %xy, %z : i64
    %w1 = idr.io.put_int signed %r, %w : i64
    return %w1 : !idr.world
  }
}
