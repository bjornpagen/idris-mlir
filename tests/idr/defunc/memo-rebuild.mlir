// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the memo sum's printed form.
// A memo cell is shared, so the cells that may reach one slot share one
// memo sum: lazy sets are unified, never coerced. Here the cell of @one is
// forced before it is passed where @two's cell goes too: both are built in
// the one sum of both labels, the cell is passed as it is, and keeps its
// state, so the force in @use does not run @one again. No cell is rebuilt.
// CHECK: ![[M:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, memo [@one(), @two(), @running(), @forced(i64)]
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[CELL:.*]] = {{(idr\.)?}}con !idr.box<![[M]]> @one()
// CHECK: force %[[CELL]] : !idr.box<![[M]]> -> i64
// CHECK-NOT: case @running
// CHECK: call @use(%[[CELL]])
idr.program @"memo-rebuild" root(@Main.main) stage(higher) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @two() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @use(%l: !idr.lazy<i64>) -> i64 {
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
