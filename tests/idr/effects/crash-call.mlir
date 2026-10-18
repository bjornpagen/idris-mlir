// NEEDS-ACCEPTANCE: that a call of a function whose only effect is crash declares what an inline crash declares, the IO write among it, so both answer alike and both stay before the output that follows them.
// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=crashes-before-output=@calls,crashes-before-output=@inline -o /dev/null
// A crash ends the program's output: it writes the IO resource as well as
// the crash resource, so nothing moves output across it. A call of a
// function that may crash and do nothing else declares the same, from the
// one table of what each effect is: it may be delayed, as an inline crash
// may, but no output moves before it, and it moves before no output.
idr.program @"crash-call" root(@root) stage(first) {
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @calls(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
    // expected-remark @below {{facts: [delay]}}
    %y = idr.call @crashes(%x) effects<crash> : (i64) -> i64
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    return %y, %w1 : i64, !idr.world
  }
  idr.func @inline(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
    // expected-remark @below {{facts: [delay]}}
    %y = idr.check.nonzero %x, "division by zero" : i64
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    return %y, %w1 : i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
