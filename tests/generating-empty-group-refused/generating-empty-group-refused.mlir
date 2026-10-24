// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A tabulation writes one destination or more, a fold folds one
// accumulator or more, and a scan reads one input or more and writes one
// destination or more: an op of these whose group holds no value is
// refused at the op, before any reading of it asks for the group's first
// value. The ops are written in the generic form, since their own form
// cannot write an empty group. In the first program each group holds one
// value: a tabulation fills an array of no axis, a fold of three steps
// starts from it, and a scan of three steps starts from the fold's array,
// and the program verifies. Each program after it writes one of the four
// groups empty and is refused at that op.
idr.program @generates root(@main) stage(first) {
  idr.func @main() {
    %steps = arith.constant 3 : index
    %zero = arith.constant 0 : i64
    %none = tensor.empty() : tensor<i64>
    %init = "idr.array.tabulate"(%none) ({
      "idr.array.yield"(%zero) : (i64) -> ()
    }) : (tensor<i64>) -> tensor<i64>
    %folded = "idr.array.fold_last"(%steps, %init) ({
    ^bb0(%i: index, %acc: i64):
      %w = arith.index_cast %i : index to i64
      %next = arith.addi %acc, %w : i64
      "idr.array.yield"(%next) : (i64) -> ()
    }) : (index, tensor<i64>) -> tensor<i64>
    %dest = tensor.empty() : tensor<3xi64>
    %scanned = "idr.array.scan_last"(%steps, %folded, %dest) <{operandSegmentSizes = array<i32: 1, 1, 1>}> ({
    ^bb0(%i: index, %acc: i64):
      %w = arith.index_cast %i : index to i64
      %next = arith.addi %acc, %w : i64
      "idr.array.yield"(%next) : (i64) -> ()
    }) : (index, tensor<i64>, tensor<3xi64>) -> tensor<3xi64>
    idr.return
  }
}

// -----

idr.program @tabulates root(@main) stage(first) {
  idr.func @main() {
    %zero = arith.constant 0 : i64
    // expected-error @below {{}}
    "idr.array.tabulate"() ({
      "idr.array.yield"(%zero) : (i64) -> ()
    }) : () -> ()
    idr.return
  }
}

// -----

idr.program @folds root(@main) stage(first) {
  idr.func @main() {
    %steps = arith.constant 3 : index
    // expected-error @below {{}}
    "idr.array.fold_last"(%steps) ({
    ^bb0(%i: index):
      "idr.array.yield"() : () -> ()
    }) : (index) -> ()
    idr.return
  }
}

// -----

idr.program @scans_nothing root(@main) stage(first) {
  idr.func @main() {
    %steps = arith.constant 3 : index
    %dest = tensor.empty() : tensor<3xi64>
    // expected-error @below {{}}
    %scanned = "idr.array.scan_last"(%steps, %dest) <{operandSegmentSizes = array<i32: 1, 0, 1>}> ({
    ^bb0(%i: index):
      %w = arith.index_cast %i : index to i64
      "idr.array.yield"(%w) : (i64) -> ()
    }) : (index, tensor<3xi64>) -> tensor<3xi64>
    idr.return
  }
}

// -----

idr.program @scans_into_nothing root(@main) stage(first) {
  idr.func @main() {
    %steps = arith.constant 3 : index
    %zero = arith.constant 0 : i64
    %none = tensor.empty() : tensor<i64>
    %init = "idr.array.tabulate"(%none) ({
      "idr.array.yield"(%zero) : (i64) -> ()
    }) : (tensor<i64>) -> tensor<i64>
    // expected-error @below {{}}
    "idr.array.scan_last"(%steps, %init) <{operandSegmentSizes = array<i32: 1, 1, 0>}> ({
    ^bb0(%i: index, %acc: i64):
      %w = arith.index_cast %i : index to i64
      %next = arith.addi %acc, %w : i64
      "idr.array.yield"(%next) : (i64) -> ()
    }) : (index, tensor<i64>) -> ()
    idr.return
  }
}
