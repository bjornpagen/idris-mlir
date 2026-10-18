// NEEDS-ACCEPTANCE: that the module parses in this wave's printed forms (constants written type first, a default binding the scrutinee), and that the -verify-diagnostics run after idr-rc passes: the idr.cell.init idr-rc's cells step makes of @build's cons, which takes the con's place and location, builds in a fresh cell; @build and @both build in no recycled cell; and the one idr.dup in @both, placed at the con that takes %a twice, is the only count left there (its parameter %b read alone, borrowed, is never dropped).
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@map,counts-nothing=@sum -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-in-place=@build,counts-nothing=@both,reuses-in-place=@both -verify-diagnostics -o /dev/null
// NEEDS-ACCEPTANCE: how the error names the constructor, by its flat name within its type.
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// What reference counting leaves in a function, as properties. A map over
// a list builds each cell in the one it took apart, and a sum that only
// reads its list counts nothing. A function that builds a list takes
// nothing apart, so its cells are fresh; a function that keeps a string
// twice counts, and reuses nothing.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
!Two = !idr.data<"Two", plain [@Two(!idr.str, !idr.str)]>
idr.program @counting root(@root) stage(first) {
  idr.func @map(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = idr.call @map(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  // expected-error @below {{expected reuses-in-place: nothing is built in a reused cell in @build}}
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      // expected-error @below {{expected reuses-in-place: a box of @C gets a fresh cell in @build}}
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
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
  // expected-error @below {{expected reuses-in-place: nothing is built in a reused cell in @both}}
  idr.func @both(%a: !idr.str, %b: !idr.str) -> (!Two, i64) {
    // expected-error @below {{expected counts-nothing: idr.dup in @both}}
    %p = idr.con !Two @Two(%a : !idr.str, %a : !idr.str)
    %n = idr.str.length %b
    return %p, %n : !Two, i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c = idr.constant !idr.str "x"
    %p:2 = idr.call @both(%c, %c) : (!idr.str, !idr.str) -> (!Two, i64)
    %c3 = arith.constant 3 : i64
    %l = idr.call @build(%c3) : (i64) -> !idr.box<!L>
    %m = idr.call @map(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %z = arith.constant 0 : i64
    %s = idr.call @sum(%m, %z) : (!idr.box<!L>, i64) -> i64
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
