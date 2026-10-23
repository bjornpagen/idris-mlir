// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// An op of upstream's that gives a view of a lent tensor gives an alias of
// the loan, as upstream's alias interface for tensors says of it
// (bufferization's: a slice aliases its source), and that alias is held to
// the loan's rule as the loan itself is. A slice read inside the region of
// the loan's lifetime verifies; a slice given out of that region is
// refused at the op that gives it out, with a note at the loan. The slice
// takes the whole tensor, so the module means the same at every size.
idr.program @loans root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @length(%v: tensor<?xi64>) -> i64 {
    %n = idr.lifetime -> i64 {
    ^bb0(%l: !idr.lifetime<view>):
      %bare = idr.carrier %v in %l : tensor<?xi64>, !idr.lifetime<view>
      %zero = arith.constant 0 : index
      %size = tensor.dim %bare, %zero : tensor<?xi64>
      %whole = tensor.extract_slice %bare[0] [%size] [1] : tensor<?xi64> to tensor<?xi64>
      %again = tensor.dim %whole, %zero : tensor<?xi64>
      %w = arith.index_cast %again : index to i64
      idr.yield %w : i64
    }
    idr.return %n : i64
  }
}

// -----

idr.program @loans root(@main) stage(first) {
  idr.func @main() {
    idr.return
  }
  idr.func @leaks(%v: tensor<?xi64>) -> tensor<?xi64> {
    // expected-error @below {{}}
    %out = idr.lifetime -> tensor<?xi64> {
    ^bb0(%l: !idr.lifetime<view>):
      // expected-note @below {{}}
      %bare = idr.carrier %v in %l : tensor<?xi64>, !idr.lifetime<view>
      %zero = arith.constant 0 : index
      %size = tensor.dim %bare, %zero : tensor<?xi64>
      %whole = tensor.extract_slice %bare[0] [%size] [1] : tensor<?xi64> to tensor<?xi64>
      idr.yield %whole : tensor<?xi64>
    }
    idr.return %out : tensor<?xi64>
  }
}
