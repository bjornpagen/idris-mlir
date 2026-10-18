// NEEDS-ACCEPTANCE: that calls with equal raise keys share one node, the key holding its consumer's form by digest in the run's table (S22), with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@f,not-called=@g,not-called=@pair -o /dev/null
// A copy made by raising is keyed by its callee and what consumes the
// result: a dispatch of it, or of one field of it. Calls with equal keys
// share a copy, whatever their arguments. A call with a constant argument
// shares it too: the raising is decided before any specialization of the
// call. @f, @g and @pair loop, so none is inlined; none is called after
// the optimizer.
!Pair = !idr.data<"Pair", plain [@MkPair(!idr.fn<(i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)]>
idr.program @"shared-key" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @sub(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  idr.func @f(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @f(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @g(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @g(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @pair(%a: i64, %k: i64) -> !Pair {
    %r = idr.match_lit %k : i64 -> (!Pair) {
    case 0 {
      %p = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      %q = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      %v = idr.con !Pair @MkPair(%p : !idr.fn<(i64) -> (i64)>, %q : !idr.fn<(i64) -> (i64)>)
      idr.yield %v : !Pair
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @pair(%a, %m) : (i64, i64) -> !Pair
      idr.yield %v : !Pair
    }
    }
    return %r : !Pair
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %x = arith.addi %n, %n : i64
    %c3 = arith.constant 3 : i64
    %g1 = idr.call @g(%n, %x) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.apply %g1(%x) : !idr.fn<(i64) -> (i64)>
    %f1 = idr.call @f(%n, %x) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r2 = idr.apply %f1(%x) : !idr.fn<(i64) -> (i64)>
    %f2 = idr.call @f(%x, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r3 = idr.apply %f2(%n) : !idr.fn<(i64) -> (i64)>
    %p = idr.call @pair(%n, %x) : (i64, i64) -> !Pair
    %p0 = idr.field %p : !Pair @MkPair[0] -> !idr.fn<(i64) -> (i64)>
    %r4 = idr.apply %p0(%x) : !idr.fn<(i64) -> (i64)>
    %q = idr.call @pair(%x, %n) : (i64, i64) -> !Pair
    %q1 = idr.field %q : !Pair @MkPair[1] -> !idr.fn<(i64) -> (i64)>
    %r5 = idr.apply %q1(%n) : !idr.fn<(i64) -> (i64)>
    %f3 = idr.call @f(%c3, %x) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r6 = idr.apply %f3(%x) : !idr.fn<(i64) -> (i64)>
    %s1 = arith.addi %r1, %r2 : i64
    %s2 = arith.addi %s1, %r3 : i64
    %s3 = arith.addi %s2, %r4 : i64
    %s4 = arith.addi %s3, %r5 : i64
    %s5 = arith.addi %s4, %r6 : i64
    %w2 = idr.io.put_int signed %s5, %w1 : i64
    return %w2 : !idr.world
  }
}
