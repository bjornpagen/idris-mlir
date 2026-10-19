// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=exclusive-copy=@keep,exclusive-copy=@bump -o /dev/null
// A list built once and given once is the only reference to its cells,
// so the call of @keep on it goes to @keep's exclusive copy, while the call
// on a list used again below shares it and stays with @keep. The exclusive
// copy gives back an exclusive value, which feeds @bump, a function that
// takes its list apart: that call goes to @bump's exclusive copy too,
// found in the same run as the first, however many copies lead to it.
// @bump is given an exclusive value nowhere else, so its exclusive copy is
// there only if the call @keep's copy feeds was followed. Each function
// carries the location Emit gives it, its definition's name, by which a
// copy names what it was made from.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"second-redirect" root(@root) stage(first) {
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  } loc("build")
  idr.func @keep(%l: !idr.box<!L>) -> !idr.box<!L> {
    return %l : !idr.box<!L>
  } loc("keep")
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %one = arith.constant 1 : i64
      %h1 = arith.addi %h, %one : i64
      %t1 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h1 : i64, %t1 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  } loc("bump")
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
  } loc("sum")
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c3 = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %q = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    %a = idr.call @keep(%q) : (!idr.box<!L>) -> !idr.box<!L>
    %b = idr.call @bump(%a) : (!idr.box<!L>) -> !idr.box<!L>
    %s1 = idr.call @sum(%b, %z) : (!idr.box<!L>, i64) -> i64
    %p = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    %x = idr.call @keep(%p) : (!idr.box<!L>) -> !idr.box<!L>
    %y = idr.call @bump(%x) : (!idr.box<!L>) -> !idr.box<!L>
    %s2 = idr.call @sum(%y, %z) : (!idr.box<!L>, i64) -> i64
    %s3 = idr.call @sum(%p, %z) : (!idr.box<!L>, i64) -> i64
    %w1 = idr.io.put_sint %s1, %w : i64
    %w2 = idr.io.put_sint %s2, %w1 : i64
    %w3 = idr.io.put_sint %s3, %w2 : i64
    return %w3 : !idr.world
  } loc("root")
}
