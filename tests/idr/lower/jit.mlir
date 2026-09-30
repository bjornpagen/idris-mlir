// RUN: idris-mlir-opt %s --idr-lower=jit=true | FileCheck %s
// In JIT mode (idr-eval's), cells come from the evaluation arena and a
// crash reports to the evaluator; there is no root, so no @main. Every
// function counts a tick of the evaluator's meter when entered, so that a
// call that recurses forever stops, total or not: every evaluation is
// metered.
// CHECK-DAG: llvm.func @idris_rt_arena_alloc(i64) -> !llvm.ptr
// CHECK-DAG: llvm.func @idris_rt_eval_crash(!llvm.ptr, i64) attributes {passthrough = ["noreturn"]}
// CHECK-DAG: llvm.func @idris_rt_eval_tick()
// CHECK-NOT: idris_rt_cell
// CHECK-NOT: @idris_rt_crash(
// CHECK-LABEL: func.func private @pair(
// CHECK-NEXT: llvm.call @idris_rt_eval_tick()
// CHECK-LABEL: func.func private @half(
// CHECK-NEXT: llvm.call @idris_rt_eval_tick()
// CHECK-LABEL: func.func private @sum(
// CHECK-NEXT: llvm.call @idris_rt_eval_tick()
// CHECK: return
// CHECK-NOT: func.func @main
module {
  idr.data @Pair box {
    idr.ctor @P (i64, i64)
  }
  func.func private @pair(%a: i64, %b: i64) -> !idr.box<@Pair> {
    %p = idr.con @Pair::@P(%a, %b) : (i64, i64) -> !idr.box<@Pair>
    return %p : !idr.box<@Pair>
  }
  func.func private @half(%a: i64, %b: i64) -> i64 {
    %q = idr.div %a, %b : i64
    return %q : i64
  }
  func.func private @sum(%a: i64, %b: i64) -> i64 attributes {idr.total} {
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
