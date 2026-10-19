// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=builds-nothing=@raised_past_call,no-heap-allocation=@lowered_with_call,no-heap-allocation=@across_computing,crashes-before-output=@across_computing,no-heap-allocation=@lowered_past_crash,crashes-before-output=@lowered_past_crash -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=builds-nothing=@raised_past_call,no-heap-allocation=@lowered_with_call,no-heap-allocation=@across_computing -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize='test-convergence=true region-simplify=disabled top-down=true' -o /dev/null
// Case-of-case moves a consumer into a match, or a match down to its
// consumer, across what only computes; a call only computes when its own
// effects say so, which idr-optimize writes on it from its callee's once
// the callee is final. A field read is raised into a match past a call
// of a pure callee (@raised_past_call), where it folds against each
// constructor; the match itself cannot move down, since a region crashes.
// A match whose region calls a pure callee only computes, so it moves down
// past output to the output of its string, and each region writes its own
// (@lowered_with_call). Output moves into a match across a call that only
// computes, where each region writes its own (@across_computing); the
// match itself may crash, so it cannot move down instead. A call of a
// callee that may crash is a barrier: the match moves down to the output
// after the call, where each region writes its own and no string is built
// (@lowered_past_crash), and no output moves up above the call. A call at
// its default effects may do anything, so canonicalize alone moves nothing
// across one that the move must order against (the third RUN line, where
// each value still built is reported). A match that only computes orders
// against no call, so moving it down past one to its consumer is right at
// any effects, and @lowered_past_crash is asked nothing there.
// Every function is never inlined, and @maybe_of builds the
// value @lowered_with_call takes behind a call, so no site is given a
// known constructor and redirected to a specialization.
// No move changes what the program prints before it crashes: on every
// one-byte input x (0 crashes in @raised_past_call after @lowered_with_call
// printed `Anone`; 1 takes every region that does not crash; the rest crash
// in @across_computing after @lowered_past_crash printed), the optimized
// program prints and exits as the program as written does
// (%differential, which compares stdout and the exit status).
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
idr.program @"case-of-case-calls" root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total, no_inline} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @divides(%n: i64) -> i64 attributes {total, no_inline} {
    %m = idr.check.nonzero %n, "division by zero" : i64
    %r = idr.divs %n, %m : i64
    return %r : i64
  }
  idr.func @raised_past_call(%b: i64, %c: i64) -> i64 attributes {no_inline} {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      idr.crash "zero"
      ub.unreachable
    }
    case 1 {
      // expected-error @below {{idr.con builds a value in @raised_past_call}}
      %x = idr.con !P @MkP(%c : i64, %b : i64)
      idr.yield %x : !P
    }
    default(%d: i64) {
      // expected-error @below {{idr.con builds a value in @raised_past_call}}
      %y = idr.con !P @MkP(%b : i64, %c : i64)
      idr.yield %y : !P
    }
    }
    %k = idr.call @square(%c) : (i64) -> i64
    %f = idr.field %q : !P @MkP[0] -> i64
    %s = arith.addi %f, %k : i64
    return %s : i64
  }
  idr.func @lowered_with_call(%m: !Maybe, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %s = idr.match %m : !Maybe -> (!idr.str) {
    case @Nothing() {
      %c = idr.constant !idr.str "none"
      idr.yield %c : !idr.str
    }
    case @Just(%x: i64) {
      %y = idr.call @square(%x) : (i64) -> i64
      // expected-error @below {{allocates in @lowered_with_call}}
      %t = idr.str.show_sint %y : i64
      idr.yield %t : !idr.str
    }
    }
    %ch = arith.constant 65 : i32
    %w1 = idr.io.put_char %ch, %w
    %w2 = idr.io.put_str %s, %w1
    return %w2 : !idr.world
  }
  idr.func @lowered_past_crash(%n: i64, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %c = idr.constant !idr.str "zero"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
      %t = idr.str.show_sint %n : i64
      idr.yield %t : !idr.str
    }
    }
    %k = idr.call @divides(%n) : (i64) -> i64
    %w1 = idr.io.put_str %s, %w
    %w2 = idr.io.put_sint %k, %w1 : i64
    return %w2 : !idr.world
  }
  idr.func @across_computing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) attributes {no_inline} {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      // expected-error @below {{allocates in @across_computing}}
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant !idr.str "one"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    %q = idr.call @square(%x) : (i64) -> i64
    %w1 = idr.io.put_str %s, %w
    return %w1, %q : !idr.world, i64
  }
  idr.func @maybe_of(%x: i64) -> !Maybe attributes {total, no_inline} {
    %m = idr.match_lit %x : i64 -> (!Maybe) {
    case 0 {
      %no = idr.con !Maybe @Nothing()
      idr.yield %no : !Maybe
    }
    default(%d: i64) {
      %j = idr.con !Maybe @Just(%x : i64)
      idr.yield %j : !Maybe
    }
    }
    return %m : !Maybe
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %m = idr.call @maybe_of(%x) : (i64) -> !Maybe
    %w1 = idr.call @lowered_with_call(%m, %w0) : (!Maybe, !idr.world) -> !idr.world
    %r = idr.call @raised_past_call(%x, %x) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    %w3 = idr.call @lowered_past_crash(%x, %w2) : (i64, !idr.world) -> !idr.world
    %w4, %q = idr.call @across_computing(%x, %x, %w3) : (i64, i64, !idr.world) -> (!idr.world, i64)
    %w5 = idr.io.put_sint %q, %w4 : i64
    return %w5 : !idr.world
  }
}
