// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A function's body is one block, which its region holds: the one producer
// of a second block, the inliner taking in a callee that never returns,
// leaves the rest of the caller unreachable, and each site that inlines
// erases it, so no pass meets two. Every function of the program is
// defined in it, so a function with no block has no body.

idr.program @"two-blocks" root(@root) stage(first) {
  // expected-error @+1 {{region #0 ('body') failed to verify constraint: region with 1 blocks}}
  idr.func @never(%x: i64) -> i64 {
    idr.crash "no"
    ub.unreachable
  ^rest:
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"two-blocks" root(@root) stage(first) {
  // expected-error @+1 {{region #0 ('body') failed to verify constraint: region with 1 blocks}}
  idr.func @declared(%x: i64) -> i64
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
