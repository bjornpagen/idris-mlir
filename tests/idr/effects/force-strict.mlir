// NEEDS-ACCEPTANCE: the effects idr.force declares before defunctionalization, as test-idr-facts reports what it answers.
// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// Before defunctionalization a force is strict like a call: it runs its
// suspension's code, which may crash or not return, so it may be delayed
// but neither moved, dropped nor merged with another force of the same
// cell, whatever the label it may find; what it may do is known only once
// it is a call of the sum's dispatch.
idr.program @"force-strict" root(@main) stage(higher) {
  idr.func @boom() -> i64 attributes {total} {
    idr.crash "boom"
    ub.unreachable
  }
  idr.func @twice(%t: !idr.lazy<i64>) -> i64 {
    // expected-remark @below {{facts: [delay]}}
    %a = idr.force %t : !idr.lazy<i64> -> i64
    // expected-remark @below {{facts: [delay]}}
    %b = idr.force %t : !idr.lazy<i64> -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  idr.func @main() -> i64 {
    %t = idr.suspend @boom() : () -> !idr.lazy<i64>
    %v = idr.call @twice(%t) : (!idr.lazy<i64>) -> i64
    return %v : i64
  }
}
