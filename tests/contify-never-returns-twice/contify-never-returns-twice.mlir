// RUN: idris-mlir-opt %s --idr-contify -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=contified,not-called=@fail_a,not-called=@fail_b,never-returns=@loop -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=contified,not-called=@fail_a,not-called=@fail_b,never-returns=@loop -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// BEFORE-DAG: expected contified: @fail_a {{.*}}
// BEFORE-DAG: expected contified: @fail_b {{.*}}
// BEFORE-DAG: expected not-called: @fail_a {{.*}}
// BEFORE-DAG: expected not-called: @fail_b {{.*}}
// BEFORE-DAG: expected never-returns: @loop {{.*}}
// @fail_a and @fail_b are each called once, by @loop, and call @loop back
// before they crash, so the three are one cycle of calls and each of the
// two is a continuation of @loop. Neither returns: its one block ends in
// ub.unreachable. Moving @fail_a into its call leaves the rest of @loop
// unreachable, a second block, which holds the call of @fail_b; the sweep
// moves @fail_b into that call, and erases the unreachable block of @loop
// once every function was swept. None of this held before the pass. The
// program never ends, so no run of it can say what it means.
idr.program @"never-returns-twice" root(@root) stage(first) {
  idr.func @loop(%n: i64) -> i64 {
    %a = idr.call @fail_a(%n) : (i64) -> i64
    %b = idr.call @fail_b(%a) : (i64) -> i64
    return %b : i64
  }
  idr.func @fail_a(%n: i64) -> i64 {
    %r = idr.call @loop(%n) : (i64) -> i64
    idr.crash "a"
    ub.unreachable
  }
  idr.func @fail_b(%n: i64) -> i64 {
    %r = idr.call @loop(%n) : (i64) -> i64
    idr.crash "b"
    ub.unreachable
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r = idr.call @loop(%n) : (i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
