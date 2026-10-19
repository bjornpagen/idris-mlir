// RUN: idris-mlir-opt %s --idr-effects --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// What the dialect answers about an op is reported at the op, as a remark,
// and stated where the test expects it, not as a mark the IR under test
// carries: an output may be neither dropped, moved, delayed nor merged; a
// call of a function that only computes, which idr-effects writes on the
// call, may be all four.
idr.program @facts root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    %x = arith.constant 3 : i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %unused = idr.call @square(%x) : (i64) -> i64
    return %w1 : !idr.world
  }
}
