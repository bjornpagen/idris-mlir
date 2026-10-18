// NEEDS-ACCEPTANCE: that idr-optimize's inline step takes both never-returning callees into @both, the second where the first left the rest of @both's block unreachable, and erases that rest once after its loop, so @both is one block the verifier after every pass accepts and its return is gone with the rest (S5, ir-verify-1).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@fail_a,not-called=@fail_b,never-returns=@both -o /dev/null
// A function body is one block. Inlining a callee that never returns (its
// one block ends in ub.unreachable, after a crash) keeps that terminator
// and leaves what followed the call in the caller unreachable, a second
// block. @both calls two such callees in sequence, each small and final,
// so its inline step takes in the first and then the second, whose call is
// in the block the first left unreachable; the step erases that block once
// it has taken every call it listed. @both is marked never to inline, so
// the root keeps calling it.
idr.program @"never-returns-twice" root(@root) stage(first) {
  idr.func @fail_a(%n: i64) -> i64 attributes {total} {
    idr.crash "a"
    ub.unreachable
  }
  idr.func @fail_b(%n: i64) -> i64 attributes {total} {
    idr.crash "b"
    ub.unreachable
  }
  idr.func @both(%n: i64) -> i64 attributes {no_inline} {
    %a = idr.call @fail_a(%n) : (i64) -> i64
    %b = idr.call @fail_b(%a) : (i64) -> i64
    return %b : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r = idr.call @both(%n) : (i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
