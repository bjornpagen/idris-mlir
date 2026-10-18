// NEEDS-ACCEPTANCE: that test-idr-facts reports each op's answers at the op, none of the four for an output and all four for a call idr-effects proved pure; and that the second run fails only because canonicalize erases that unused call before the report, so its expected remark is never produced ("expected remark ... was not produced").
// RUN: idris-mlir-opt %s --idr-effects --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-effects --canonicalize --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// What the dialect answers about an op is reported at the op, as a remark,
// and stated where the test expects it, not as a mark the IR under test
// carries: an output may be neither dropped, moved, delayed nor merged; a
// call of a function that only computes, which idr-effects writes on the
// call, may be all four. An expectation of an op a pass erases before the
// report is never met, so the run that erases the unused call fails.
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
