// NEEDS-ACCEPTANCE: that idr-effects writes each call's effects with its callee's, that a call then answers from them, and that canonicalize and CSE drop and merge the calls of functions that only compute and keep every other.
// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=effects=@square:none,effects=@boxes:none,effects=@crashes:crash,effects=@partial:diverge,effects=@writes:io,effects=@main:io+crash+diverge -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --cse --canonicalize '--idr-expect=holds=calls-distinct=@main:@square,calls-read=@main:@unused,calls-distinct=@main:@boxes,calls-read=@main:@boxes,call-order=@main:[@crashes,@crashes,@partial,@partial,@writes,@writes]' -o /dev/null
// idr-effects finds what each function may do, once, and writes it on the
// function and on every call of it, as llvm.call holds its memory effects.
// A call answers from the effects it holds, so every pass reads it alone:
// a call of a function that only computes moves across anything, and is
// dead when nothing reads it and one value with an equal call, which
// upstream's dead code removal and CSE then drop and merge; a call that
// performs no IO may be delayed, though it may crash or not return; a call
// that performs IO stays in its place. Every call that may crash, not
// return or perform IO is kept, each one.
!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.program @"call-effects" root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @unused(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func @boxes(%x: i64) -> !Box attributes {total} {
    %b = idr.con !Box @MkBox(%x : i64)
    return %b : !Box
  }
  idr.func @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.divs %x, %y : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }
  idr.func @main(%x: i64, %w: !idr.world) -> (i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world) {
    // expected-remark @below {{facts: [move delay merge]}}
    %a = idr.call @square(%x) : (i64) -> i64
    // expected-remark @below {{facts: [move delay merge]}}
    %b = idr.call @square(%x) : (i64) -> i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %u = idr.call @unused(%x) : (i64) -> i64
    // expected-remark @below {{facts: [move delay merge]}}
    %b1 = idr.call @boxes(%x) : (i64) -> !Box
    // expected-remark @below {{facts: [move delay merge]}}
    %b2 = idr.call @boxes(%x) : (i64) -> !Box
    // expected-remark @below {{facts: [drop move delay merge]}}
    %u2 = idr.call @boxes(%x) : (i64) -> !Box
    // expected-remark @below {{facts: [delay]}}
    %c1 = idr.call @crashes(%x) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %c2 = idr.call @crashes(%x) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %p1 = idr.call @partial(%x) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %p2 = idr.call @partial(%x) : (i64) -> i64
    // expected-remark @below {{facts: []}}
    %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
    // expected-remark @below {{facts: []}}
    %w2 = idr.call @writes(%x, %w1) : (i64, !idr.world) -> !idr.world
    return %a, %b, %b1, %b2, %c1, %c2, %p1, %p2, %w2 : i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
