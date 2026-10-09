// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=llvm.store
// The force of a memo cell nothing else holds is its only one, so nothing
// is memoized: the captures, or the value, move out, the cell's memory
// goes, and the cell is never written. A cell in a label's state calls the
// label's function directly with its captures after its memory is freed.
// CHECK-LABEL: func.func private @once(
// CHECK: llvm.call @idris_rt_crash(
// CHECK: scf.index_switch
// CHECK: case 0 {
// CHECK: llvm.call @idris_rt_free_cell(
// CHECK: call @one() : () -> i64
// CHECK: case 1 {
// CHECK: %[[X:.*]] = llvm.load
// CHECK: llvm.call @idris_rt_free_cell(
// CHECK: call @plus(%[[X]]) : (i64) -> i64
// CHECK: default {
// CHECK: llvm.load
// CHECK: llvm.call @idris_rt_free_cell(
// CHECK: return
module {
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
  func.func private @once(%t: !idr.excl<!idr.box<@lazy$0>>) -> i64 {
    %v = idr.force %t : !idr.excl<!idr.box<@lazy$0>> -> i64
    return %v : i64
  }
}
