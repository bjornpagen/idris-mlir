// RUN: mkdir -p %t.kept %t.evaluated
// RUN: idris-mlir-cc %s --check --dump-after=idr-simplify --dump-dir=%t.kept -mlir-debug-counter=idr-eval-call-count=0 -mlir-print-debug-counter 2> %t.kept.err
// RUN: cat %t.kept/*-idr-simplify.mlir | FileCheck %s --check-prefix=KEPT
// RUN: FileCheck %s --check-prefix=COUNTED < %t.kept.err
// RUN: idris-mlir-cc %s --check --dump-after=idr-simplify --dump-dir=%t.evaluated
// RUN: cat %t.evaluated/*-idr-simplify.mlir | FileCheck %s --check-prefix=EVALUATED
// RUN: idris-mlir-cc %s --check --no-eval -mlir-debug-counter=idr-eval-call-count=0 -mlir-print-debug-counter 2> %t.no-eval.err
// RUN: FileCheck %s --check-prefix=NOEVAL < %t.no-eval.err
// RUN: idris-mlir-cc %s -o %t.o -mlir-debug-counter=idr-eval-call-count=0
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s --check-prefix=OUT
// Replacing a closed call by its results is the action idr-eval-call. With
// MLIR's debug counter at 0, every such action is skipped: the call of
// @fact stays in the module (it is evaluated, and not replaced), and runs
// at runtime to the same result. Without the counter it is replaced. With
// --no-eval the pass never runs, so the counter counts no action, and the
// two handlers of the compilation work together.
// KEPT: func.call @fact(
// COUNTED: idr-eval-call{{ +}}: {{[{][1-9][0-9]*}},0,0}
// EVALUATED-NOT: @fact
// EVALUATED: 3628800
// NOEVAL: idr-eval-call{{ +}}: {0,0,0}
// OUT: 3628800
module attributes {idr.program} {
  func.func private @fact(%n: i64) -> i64 attributes {idr.total, no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = func.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = func.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
}
