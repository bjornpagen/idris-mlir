// NEEDS-ACCEPTANCE: that skipping every idr-contify-move action leaves the module as it was, and that idr-contify changes it otherwise.
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-contify --mlir-disable-threading -mlir-debug-counter=idr-contify-move-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-contify -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
// idr-contify is an optimization: each move of a function into its one
// call is an action, and with every move skipped the pass leaves the
// module exactly as no pass does.
idr.program @contify root(@root) stage(higher) {
  idr.func @step(%n: i64, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.call @step.case1(%done, %n, %acc) : (i1, i64, i64) -> i64
    return %r : i64
  }
  idr.func @step.case1(%done: i1, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = idr.call @twice(%acc) : (i64) -> i64
      %s = idr.call @step(%m, %a) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @twice(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @named(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @lonely(%x: i64) -> i64 {
    %y = idr.call @lonely(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : i64
    %n = arith.constant 7 : i64
    %t = idr.call @twice(%n) : (i64) -> i64
    %f = idr.closure @named() : () -> !idr.fn<(i64) -> (i64)>
    %g = idr.call @named(%t) : (i64) -> i64
    %v = idr.apply %f(%g) : !idr.fn<(i64) -> (i64)>
    %r = idr.call @step(%v, %c0) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w : i64
    return %w2 : !idr.world
  }
}
