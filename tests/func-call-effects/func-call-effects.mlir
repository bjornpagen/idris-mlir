// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// What a call may do is the effects it holds, as llvm.call holds its memory
// effects: never less than its callee's, which its verifier holds, and by
// default everything. Every pass, upstream's dead code removal and CSE
// among them, reads them off the call alone: a call of a function that only
// computes is dead when nothing reads it, moves across anything and is one
// value with an equal call; one that may crash may still be delayed; one
// that holds the default may do anything, though its callee may do less,
// since a stale value says too much, never too little.
idr.program @"call-effects" root(@main) stage(first) {
  idr.func effects<none> @pure(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @unknown(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 3 : i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %a = idr.call @pure(%c) effects<none> : (i64) -> i64
    // expected-remark @below {{facts: []}}
    %b = idr.call @unknown(%c) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %d = idr.call @crashes(%c) effects<crash> : (i64) -> i64
    // expected-remark @below {{facts: []}}
    %e = idr.call @pure(%c) : (i64) -> i64
    return %c : i64
  }
}
