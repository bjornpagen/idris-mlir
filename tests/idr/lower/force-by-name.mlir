// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=llvm.store
// A label that is `by_name` runs at every force, so the effect it reaches
// happens wherever its value is demanded: the cell keeps its captures and
// is never written. The label's function takes its capture owned, so the
// forcer gives it a reference of its own.
// CHECK-LABEL: func.func private @loud(
// CHECK: scf.index_switch
// CHECK: case 0 {
// CHECK: %[[S:.*]] = llvm.load
// CHECK: llvm.call @idris_rt_inc(%[[S]])
// CHECK: call @shout(%[[S]]) : (!llvm.ptr) -> i64
// CHECK: return
module {
  idr.data @lazy$0 box memo labels [@shout] {
    idr.ctor @shout (!idr.str) by_name
    idr.ctor @running ()
    idr.ctor @forced (i64)
  }
  func.func private @shout(%s: !idr.own<!idr.str>) -> i64 attributes {idr.total} {
    %w = idr.world.new
    %v = idr.borrow %s : !idr.own<!idr.str>
    %w1 = idr.io.put_str %v, %w
    idr.drop %s : !idr.own<!idr.str>
    %c = arith.constant 1 : i64
    return %c : i64
  }
  func.func private @loud(%t: !idr.box<@lazy$0>) -> i64 {
    %v = idr.force %t : !idr.box<@lazy$0> -> i64
    return %v : i64
  }
}
