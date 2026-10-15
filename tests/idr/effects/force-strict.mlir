// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// NEEDS-ACCEPTANCE: the effects R02 declares on idr.force before defunctionalization (M12).
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
    %a = idr.force %t {expect.facts = "delay"} : !idr.lazy<i64> -> i64
    %b = idr.force %t {expect.facts = "delay"} : !idr.lazy<i64> -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  idr.func @main() -> i64 {
    %t = idr.suspend @boom() : () -> !idr.lazy<i64>
    %v = idr.call @twice(%t) : (!idr.lazy<i64>) -> i64
    return %v : i64
  }
}
