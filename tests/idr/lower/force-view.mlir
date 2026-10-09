// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// The force of a memo cell through a view is one switch on the cell's
// state. A cell in a label's state moves its captures out to the forcer
// and is marked running before the call, so a force of it from inside the
// call finds it running and crashes, as a suspension that forces itself
// does. The label's function is called directly, by name; its value is
// stored in the cell, which is marked forced, and shared with the forcer. A
// forced cell's value is read with no call at all. The memo sum is a box
// of @one and @plus, then running and forced: running is tag 2, so its
// info word is that tag with the thunk kind, 1 << 24.
// CHECK-DAG: llvm.mlir.constant("idris-mlir: a suspension forced itself at Main.idr:9:3\0A")
// CHECK-LABEL: func.func private @view(
// CHECK: llvm.call @idris_rt_crash(
// CHECK: scf.index_switch
// CHECK-NOT: scf.index_switch
// CHECK: case 0 {
// CHECK: llvm.mlir.constant(16777218 : i32)
// CHECK: llvm.store
// CHECK: call @one() : () -> i64
// CHECK: llvm.store
// CHECK: case 1 {
// CHECK: llvm.mlir.constant(16777218 : i32)
// CHECK: llvm.store
// CHECK: call @plus(%{{.*}}) : (i64) -> i64
// CHECK: llvm.store
// CHECK: default {
// CHECK-NOT: call
// CHECK-NOT: scf.index_switch
// CHECK: return
module attributes {idr.program} {
  idr.data @lazy$0 box memo labels [@one, @plus] {
    idr.ctor @one ()
    idr.ctor @plus (i64)
    idr.ctor @running ()
    idr.ctor @forced (i64)
  }
  func.func private @one() -> i64 attributes {idr.total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  func.func private @plus(%x: i64) -> i64 attributes {idr.total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  func.func private @view(%t: !idr.box<@lazy$0>) -> i64 {
    %v = idr.force %t : !idr.box<@lazy$0> -> i64 loc("Main.idr":9:3)
    return %v : i64
  }
  func.func @Main.main() -> i64 {
    %two = arith.constant 2 : i64
    %t = idr.con @lazy$0::@plus(%two) : (i64) -> !idr.box<@lazy$0>
    %v = func.call @view(%t) : (!idr.box<@lazy$0>) -> i64
    return %v : i64
  }
}
