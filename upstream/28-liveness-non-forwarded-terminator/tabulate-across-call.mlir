// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An array tabulated in a private function and read by its caller's callee:
// remove-dead-values must keep each element the region yields.
idr.program @t root(@root) stage(first) types #idr.types<> {
  idr.func @squares(%n: index) -> tensor<?xi64> {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %y = arith.muli %x, %x : i64
      idr.array.yield %y : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @first(%x: tensor<?xi64>) -> i64 {
    %c1 = arith.constant 1 : index
    %e = tensor.extract %x[%c1] : tensor<?xi64>
    return %e : i64
  }
  idr.func @root() -> i64 {
    %c3 = arith.constant 3 : index
    %t = idr.call @squares(%c3) : (index) -> tensor<?xi64>
    %e = idr.call @first(%t) : (tensor<?xi64>) -> i64
    return %e : i64
  }
}
