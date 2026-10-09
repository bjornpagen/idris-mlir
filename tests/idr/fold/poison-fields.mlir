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
// CHECK-LABEL: func.func @con(
// CHECK: idr.con @Box::@MkBox(
// CHECK-LABEL: func.func @closure(
// CHECK: idr.closure @add(
// CHECK-LABEL: func.func @suspend(
// CHECK: idr.suspend @add(
module {
  idr.data @Box box {
    idr.ctor @MkBox (i64)
  }
  func.func private @add(%k: i64, %x: i64) -> i64 attributes {idr.total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func @con() -> !idr.box<@Box> {
    %p = ub.poison : i64
    %b = idr.con @Box::@MkBox(%p) : (i64) -> !idr.box<@Box>
    return %b : !idr.box<@Box>
  }
  func.func @closure() -> !idr.fn<(i64) -> (i64)> {
    %p = ub.poison : i64
    %f = idr.closure @add(%p) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func @suspend() -> !idr.lazy<i64> {
    %p = ub.poison : i64
    %one = arith.constant 1 : i64
    %t = idr.suspend @add(%p, %one) : (i64, i64) -> !idr.lazy<i64>
    return %t : !idr.lazy<i64>
  }
}

// -----

module attributes {idr.program} {
  idr.data @Box box {
    idr.ctor @MkBox (i64)
  }
  func.func private @wrap(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> !idr.box<@Box> {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %b = idr.con @Box::@MkBox(%y) : (i64) -> !idr.box<@Box>
    return %b : !idr.box<@Box>
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
