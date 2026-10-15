// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=exclusive-copy=@keep,exclusive-copy=@sum -o /dev/null
// NEEDS-ACCEPTANCE: that idr-rc follows the exclusive call of @keep to the call its result feeds, so @sum gets its exclusive copy in the same run.
// A value given twice to one callee: the first call takes a shared
// reference (a dup, since the value is used again), the second the only
// one, so it goes to the callee's exclusive copy. That copy gives back an
// exclusive value, which feeds a third function: that call goes to its
// exclusive copy too, found in the same run as the first, however many
// copies lead to it. @sum is called exclusively nowhere else, so its
// exclusive copy is there only if the second call was followed.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"second-redirect" root(@root) stage(first) {
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
      idr.yield %e : !idr.box<!L>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @keep(%l: !idr.box<!L>) -> !idr.box<!L> {
    return %l : !idr.box<!L>
  }
  idr.func @sum(%l: !idr.box<!L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.box<!L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c3 = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %q = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    // Used again below: a shared reference.
    %a = idr.call @keep(%q) : (!idr.box<!L>) -> !idr.box<!L>
    %s1 = idr.call @sum(%a, %z) : (!idr.box<!L>, i64) -> i64
    // The last use: the only reference.
    %b = idr.call @keep(%q) : (!idr.box<!L>) -> !idr.box<!L>
    %s2 = idr.call @sum(%b, %z) : (!idr.box<!L>, i64) -> i64
    %w1 = idr.io.put_int signed %s1, %w : i64
    %w2 = idr.io.put_int signed %s2, %w1 : i64
    return %w2 : !idr.world
  }
}
