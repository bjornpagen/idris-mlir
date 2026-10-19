// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-effects,idr.func(idr-structure-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@sumi,structured-loops=@pureCall,structured-loops=@crashes -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@world,counted-loop=@calls,counted-loop=@sumf -o /dev/null
// An array op's form is its region's effects: a region that does nothing
// beyond compute and crash is a structured op, whose crash is the program's
// end wherever it happens; one that performs output in the world's order,
// or calls a function that may, is an ordered loop nest, so its effects
// happen in index order. A fold is a reduction only when its combiner is
// one integer op, whose law is the op's: an integer sum is one, and a float
// sum is not, so it is a loop in index order and its result is the same on
// every target. A call of a function that only computes is computing.
idr.program @ordered root(@root) stage(first) {
  idr.func @pure(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %w1 = idr.io.put_sint %x, %w : i64
    return %w1 : !idr.world
  }
  idr.func @crashes(%n: index, %d: i64) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %g = idr.check.nonzero %d, "division by zero" : i64
      %q = idr.divs %x, %g : i64
      idr.array.yield %q : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @pureCall(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %y = idr.call @pure(%x) : (i64) -> i64
      idr.array.yield %y : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @world(%n: index, %w: !idr.world) -> (tensor<?xi64>, !idr.world) {
    %t, %w1 = idr.tabulate_io [%n], %w {
    ^bb0(%i: index, %v: !idr.world):
      %x = arith.index_cast %i : index to i64
      %v1 = idr.io.put_sint %x, %v : i64
      idr.array.yield %x, %v1 : i64, !idr.world
    } : tensor<?xi64>
    return %t, %w1 : tensor<?xi64>, !idr.world
  }
  idr.func @calls(%n: index, %w: !idr.world) -> (tensor<?xi64>, !idr.world) {
    %t, %w1 = idr.tabulate_io [%n], %w {
    ^bb0(%i: index, %v: !idr.world):
      %x = arith.index_cast %i : index to i64
      %v1 = idr.call @writes(%x, %v) : (i64, !idr.world) -> !idr.world
      idr.array.yield %x, %v1 : i64, !idr.world
    } : tensor<?xi64>
    return %t, %w1 : tensor<?xi64>, !idr.world
  }
  idr.func @sumi(%x: tensor<?xi64>, %n: index) -> tensor<i64> {
    %zero = arith.constant 0 : i64
    %z = tensor.from_elements %zero : tensor<i64>
    %s = idr.fold_last %z [%n] {
    ^bb0(%i: index, %acc: i64):
      %e = tensor.extract %x[%i] : tensor<?xi64>
      %a = arith.addi %acc, %e : i64
      idr.array.yield %a : i64
    } : tensor<i64> -> tensor<i64>
    return %s : tensor<i64>
  }
  idr.func @sumf(%x: tensor<?xf64>, %n: index) -> tensor<f64> {
    %zero = arith.constant 0.0 : f64
    %z = tensor.from_elements %zero : tensor<f64>
    %s = idr.fold_last %z [%n] {
    ^bb0(%i: index, %acc: f64):
      %e = tensor.extract %x[%i] : tensor<?xf64>
      %a = arith.addf %acc, %e : f64
      idr.array.yield %a : f64
    } : tensor<f64> -> tensor<f64>
    return %s : tensor<f64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
