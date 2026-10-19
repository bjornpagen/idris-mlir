// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@use:arg0:[@one,@two],forces-nothing=@use,forces-nothing=@Main.main' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@use:arg0:[@one,@two],forces-nothing=@use,forces-nothing=@Main.main' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@use:arg0:[@two]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected labels: @use {{.*}}
// BEFORE-DAG: expected forces-nothing: {{.*}}@use
// BEFORE-DAG: expected forces-nothing: {{.*}}@Main.main
// STDIN:
// A memo cell is shared, so the cells that may reach one slot share one
// memo sum: lazy sets are unified, never coerced. Here the cell of @one is
// forced before it is passed where @two's cell goes too: both are built in
// the one sum of both labels, which @use's parameter holds, and the cell
// is passed as it is.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
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
    %w1 = idr.io.put_sint %r, %w : i64
    return %w1 : !idr.world
  }
}
