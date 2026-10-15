// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-effects, idr.func(idr-structure-loops))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@crashes,counted-loop=@world,counted-loop=@calls,counted-loop=@sumf -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@sumi,structured-loops=@pureCall -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=structured-loops=@crashes -o /dev/null
// A loop's form is its body's effects: a body that only computes is a
// structured op, and any other stays the frontend's loop, in order. A
// body that may crash (a guard), that performs output on a world of its
// own, or that calls a function that may crash keeps its scf.for, so its
// effects happen in index order. A fold is a reduction only when its
// combiner is one integer op, whose law is the op's: an integer sum is
// one, through a read of its array at the induction variable, and a float
// sum is not, so it stays a loop in index order and its result is the
// same on every target. A call of a function that only computes is
// computing, and its loop is structured.
module {
  idr.func private @pure(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @mayCrash(%x: i64) -> i64 attributes {total} {
    %c = idr.check.nonzero %x, "division by zero" : i64
    %y = idr.div signed %x, %c : i64
    return %y : i64
  }
  idr.func private @crashes(%x: tensor<?xi64>, %d: i64) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %n = tensor.dim %x, %c0 : tensor<?xi64>
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %v = tensor.extract %x[%i] : tensor<?xi64>
      %c = idr.check.nonzero %v, "division by zero" : i64
      %q = idr.div signed %d, %c : i64
      %a1 = tensor.insert %q into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func private @world(%n: index) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %w = idr.world.new
      %w1 = idr.io.put_int signed %x, %w : i64
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func private @calls(%n: index) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %y = idr.call @mayCrash(%x) : (i64) -> i64
      %a1 = tensor.insert %y into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func private @sumf(%v: tensor<?xf64>) -> f64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0.0 : f64
    %n = tensor.dim %v, %c0 : tensor<?xf64>
    %s = scf.for %j = %c0 to %n step %c1 iter_args(%acc = %zero) -> (f64) {
      %x = tensor.extract %v[%j] : tensor<?xf64>
      %t = arith.addf %acc, %x : f64
      scf.yield %t : f64
    }
    return %s : f64
  }
  idr.func private @sumi(%v: tensor<?xi64>) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %n = tensor.dim %v, %c0 : tensor<?xi64>
    %s = scf.for %j = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %x = tensor.extract %v[%j] : tensor<?xi64>
      %t = arith.addi %acc, %x : i64
      scf.yield %t : i64
    }
    return %s : i64
  }
  idr.func private @pureCall(%n: index) -> tensor<?xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %y = idr.call @pure(%x) : (i64) -> i64
      %a1 = tensor.insert %y into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
}
