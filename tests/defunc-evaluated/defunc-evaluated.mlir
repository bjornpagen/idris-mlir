// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls=@closureHeld:@add,forces-nothing=@closureHeld,forces-nothing=@suspensionHeld,labels=@use:arg0:[@later],forces-nothing=@use,forces-nothing=@Main.main' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=calls=@closureHeld:@add,forces-nothing=@closureHeld,forces-nothing=@suspensionHeld,labels=@use:arg0:[@later],forces-nothing=@use,forces-nothing=@Main.main' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@use:arg0:[@later,@one]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected calls: @closureHeld {{.*}}@add
// BEFORE-DAG: expected forces-nothing: {{.*}}@closureHeld
// BEFORE-DAG: expected forces-nothing: {{.*}}@suspensionHeld
// BEFORE-DAG: expected labels: @use {{.*}}
// BEFORE-DAG: expected forces-nothing: {{.*}}@use
// BEFORE-DAG: expected forces-nothing: {{.*}}@Main.main
// An evaluated suspension, `idr.delay %value`, is a cell already forced:
// it names no label, and holds its value in the forced state of its cell,
// which every cell of its lazy type shares. Its key has a memo sum like
// any lazy key, the delay becomes that sum's forced constructor holding
// the value, and each force of it is a call of the sum's dispatch, so no
// force is left.
// - @closureHeld: the value is a closure, whose labels flow into the
//   forced state and back out at the force, so the apply of what the force
//   gives is a dispatch that calls @add.
// - @suspensionHeld: the value is a suspension, whose cell's labels flow
//   into the outer cell's forced state; forcing the forced value is a
//   force of a cell of the inner memo sum.
// - @use: an evaluated suspension and one of @later reach the one slot,
//   so they share @later's memo sum, since lazy sets are unified: the
//   evaluated one is built forced in it, never rebuilt.
// - @Main.main forces an evaluated suspension of its own.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
idr.program @evaluated root(@Main.main) stage(higher) types #idr.types<> {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @later(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @closureHeld(%n: i64) -> i64 {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %t = idr.delay %f : !idr.fn<(i64) -> (i64)> -> !idr.lazy<!idr.fn<(i64) -> (i64)>>
    %g = idr.force %t : !idr.lazy<!idr.fn<(i64) -> (i64)>> -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %g(%n) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @suspensionHeld() -> i64 {
    %s = idr.suspend @one() : () -> !idr.lazy<i64>
    %t = idr.delay %s : !idr.lazy<i64> -> !idr.lazy<!idr.lazy<i64>>
    %u = idr.force %t : !idr.lazy<!idr.lazy<i64>> -> !idr.lazy<i64>
    %v = idr.force %u : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @use(%l: !idr.lazy<i64>) -> i64 {
    %v = idr.force %l : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = idr.call @closureHeld(%n) : (i64) -> i64
    %b = idr.call @suspensionHeld() : () -> i64
    %now = idr.delay %n : i64 -> !idr.lazy<i64>
    %s = idr.suspend @later(%n) : (i64) -> !idr.lazy<i64>
    %x = idr.call @use(%now) : (!idr.lazy<i64>) -> i64
    %y = idr.call @use(%s) : (!idr.lazy<i64>) -> i64
    %m = idr.delay %n : i64 -> !idr.lazy<i64>
    %z = idr.force %m : !idr.lazy<i64> -> i64
    %ab = arith.addi %a, %b : i64
    %xy = arith.addi %x, %y : i64
    %abxy = arith.addi %ab, %xy : i64
    %r = arith.addi %abxy, %z : i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
