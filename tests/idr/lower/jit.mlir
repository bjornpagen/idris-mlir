// RUN: idris-mlir-opt %s --idr-lower=jit=true | FileCheck %s
// rule: LOW-JIT-1
// In JIT mode (idr-eval's), cells come from the evaluation arena and a
// crash reports to the evaluator; there is no root, so no @main.
// CHECK-DAG: llvm.func @idris_rt_arena_alloc(i64) -> !llvm.ptr
// CHECK-DAG: llvm.func @idris_rt_eval_crash(!llvm.ptr, i64) attributes {passthrough = ["noreturn"]}
// CHECK-NOT: idris_rt_cell
// CHECK-NOT: @idris_rt_crash(
// CHECK-NOT: func.func @main
module {
  idr.data @Pair box {
    idr.ctor @P tag 0 (i64, i64) {quantities = ["w", "w"]}
  }
  func.func private @pair(%a: i64, %b: i64) -> !idr.box<@Pair> {
    %p = idr.con @Pair::@P(%a, %b) : (i64, i64) -> !idr.box<@Pair>
    return %p : !idr.box<@Pair>
  }
  func.func private @half(%a: i64, %b: i64) -> i64 {
    %q = idr.div %a, %b : i64
    return %q : i64
  }
}
