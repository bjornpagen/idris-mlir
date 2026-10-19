// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=folds-balanced,returns=@folds:"abc"/"abc"/""/#idr.big<-123456789012345678901234567890>,returns=@more:"cba"/#idr.big<98765432109876543210>' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(canonicalize)),idr-expect{holds=folds-balanced})' -o /dev/null
// The folders own what the runtime returns and release each reference once,
// also when an operation returns one of its arguments with one more
// reference: appending the empty string, reversing an empty one. No fold
// leaves a cell live. The count is per fold, whatever thread folds: the
// last run folds the two functions on the pool's threads and checks on the
// main one, which shows that folding elsewhere does not fail the check. No
// folder leaks, so no fixture shows a leak on another thread being seen.
idr.program @balanced root(@root) stage(first) {
  idr.func @folds() -> (!idr.str, !idr.str, !idr.str, !idr.big) {
    %e = idr.constant !idr.str ""
    %x = idr.constant !idr.str "abc"
    %a = idr.str.append %e, %x
    %b = idr.str.append %x, %e
    %r = idr.str.reverse %e
    %big = idr.constant !idr.big #idr.big<123456789012345678901234567890>
    %n = idr.big.neg %big
    return %a, %b, %r, %n : !idr.str, !idr.str, !idr.str, !idr.big
  }

  idr.func @more() -> (!idr.str, !idr.big) {
    %x = idr.constant !idr.str "abc"
    %r = idr.str.reverse %x
    %big = idr.constant !idr.big #idr.big<-98765432109876543210>
    %n = idr.big.neg %big
    return %r, %n : !idr.str, !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
