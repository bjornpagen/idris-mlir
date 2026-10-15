// RUN: sed '/^\/\/ -----/,$d' %s > %t.folds.mlir
// RUN: idris-mlir-opt %t.folds.mlir --canonicalize | FileCheck %s --implicit-check-not=#ub.poison
// RUN: awk '/^\/\/ -----$/ { n = 0; next } { line[++n] = $0 } END { for (i = 1; i <= n; i++) print line[i] }' %s > %t.program.mlir
// RUN: idris-mlir-opt %t.program.mlir --idr-defunctionalize --idr-lower -o /dev/null
// RUN: idris-mlir-opt %t.program.mlir --idr-defunctionalize --canonicalize --idr-lower -o /dev/null
// A constructor, a closure or a suspension of constants folds to a
// constant, but poison is no constant a value can hold: one with a poison
// field stays an op, and no constant holds poison. So an apply no label
// reaches, whose result is the program's poison, can build a value and
// still lower.
// CHECK-LABEL: idr.func @con(
// CHECK: con {{.*}}@MkBox(
// CHECK-LABEL: idr.func @closure(
// CHECK: closure @add(
// CHECK-LABEL: idr.func @suspend(
// CHECK: suspend @add(
!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.program @"poison-fields" root(@root) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @con() -> !idr.box<!Box> {
    %p = ub.poison : i64
    %b = idr.con !idr.box<!Box> @MkBox(%p : i64)
    return %b : !idr.box<!Box>
  }
  idr.func @closure() -> !idr.fn<(i64) -> (i64)> {
    %p = ub.poison : i64
    %f = idr.closure @add(%p) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @suspend() -> !idr.lazy<i64> {
    %p = ub.poison : i64
    %one = arith.constant 1 : i64
    %t = idr.suspend @add(%p, %one) : (i64, i64) -> !idr.lazy<i64>
    return %t : !idr.lazy<i64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.program @"poison-fields" root(@Prog.main) stage(higher) {
  idr.func @wrap(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> !idr.box<!Box> {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %b = idr.con !idr.box<!Box> @MkBox(%y : i64)
    return %b : !idr.box<!Box>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
