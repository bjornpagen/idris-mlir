// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@go -o /dev/null
// NEEDS-ACCEPTANCE: that the boundary analysis settles the cycle of @go's calls, so its result is no copy at any level of the recursion.
// A recursive function over a value array, no linear thread: each call
// writes one element of the array it is given and gives the result of
// its own call back. The boundary analysis reads a function on a cycle of
// calls with the others until what each may read and write of its
// operands is settled, so @go's call of itself is known to write only the
// buffer it is given and to give back that buffer; nothing reads the
// array after the call, and no level copies it.
idr.program @"recursive-value" root(@root) stage(first) {
  idr.func @go(%a: tensor<?xi64>, %k: i64) -> tensor<?xi64> attributes {total} {
    %r = idr.match_lit %k : i64 -> (tensor<?xi64>) {
    case 0 {
      idr.yield %a : tensor<?xi64>
    }
    default {
      %one = arith.constant 1 : i64
      %j = arith.subi %k, %one : i64
      %i = arith.index_cast %j : i64 to index
      %t = tensor.insert %k into %a[%i] : tensor<?xi64>
      %n = idr.call @go(%t, %j) : (tensor<?xi64>, i64) -> tensor<?xi64>
      idr.yield %n : tensor<?xi64>
    }
    }
    return %r : tensor<?xi64>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c8 = arith.constant 8 : index
    %eight = arith.constant 8 : i64
    %zero = arith.constant 0 : i64
    %e = tensor.empty(%c8) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c8 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %zero into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %r = idr.call @go(%t, %eight) : (tensor<?xi64>, i64) -> tensor<?xi64>
    %v = tensor.extract %r[%c1] : tensor<?xi64>
    return %v : i64
  }
}
