// RUN: idris-mlir-opt %s --idr-expect=holds=structured-loops=@done -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=structured-loops=@left -o /dev/null 2> %t.left.err
// RUN: FileCheck %s --check-prefix=LEFT < %t.left.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=structured-loops=@none -o /dev/null 2> %t.none.err
// RUN: FileCheck %s --check-prefix=NONE < %t.none.err
// RUN: idris-mlir-opt %s --idr-expect=holds=structured-loops=@ordered -o /dev/null
// No loop is left that idr-structure-loops structures, and a structured op
// is there. Which loop it structures is the pass's own test: a loop of
// tensor.insert whose body only computes is one (@left); a float fold
// keeps its order, so it stays a loop and the property holds beside it
// (@ordered). A function with no structured op at all fails, so the
// property cannot hold of a module that never had an array loop.
// LEFT: error: expected structured-loops: a loop over an array with a body that only computes is still scf.for in @left
// NONE: error: expected structured-loops: no structured op in @none
#map = affine_map<(d0) -> (d0)>
idr.program @"structured-loops" root(@root) stage(first) {
  idr.func @done(%x: tensor<?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xi64>) outs(%e : tensor<?xi64>) {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %a : i64
      linalg.yield %s : i64
    } -> tensor<?xi64>
    return %y : tensor<?xi64>
  }
  idr.func @left(%x: tensor<?xi64>) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %y = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %e) -> (tensor<?xi64>) {
      %v = tensor.extract %x[%i] : tensor<?xi64>
      %s = arith.addi %v, %v : i64
      %r = tensor.insert %s into %acc[%i] : tensor<?xi64>
      scf.yield %r : tensor<?xi64>
    }
    return %y : tensor<?xi64>
  }
  idr.func @ordered(%x: tensor<?xf64>) -> (tensor<?xf64>, f64) {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %z = arith.constant 0.0 : f64
    %n = tensor.dim %x, %c0 : tensor<?xf64>
    %e = tensor.empty(%n) : tensor<?xf64>
    %y = linalg.generic {indexing_maps = [#map, #map], iterator_types = ["parallel"]}
        ins(%x : tensor<?xf64>) outs(%e : tensor<?xf64>) {
    ^bb0(%a: f64, %b: f64):
      %s = arith.addf %a, %a : f64
      linalg.yield %s : f64
    } -> tensor<?xf64>
    %sum = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %z) -> (f64) {
      %v = tensor.extract %y[%i] : tensor<?xf64>
      %s = arith.addf %acc, %v : f64
      scf.yield %s : f64
    }
    return %y, %sum : tensor<?xf64>, f64
  }
  idr.func @none(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
