// RUN: idris-mlir-opt %s --idr-expect=holds=reuses-in-place=@map,counts-nothing=@sum -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=reuses-in-place=@build,counts-nothing=@both,reuses-in-place=@both -verify-diagnostics -o /dev/null
// What reference counting leaves in a function, as properties. A map over
// a list builds each cell in the one it took apart, and a sum that only
// reads its list counts nothing. A function that builds a list takes
// nothing apart, so its cells are fresh; a function that keeps a string
// twice counts, and reuses nothing. The program is written at the owned
// stage, as counting leaves one, so that what the oracle judges is this
// module and not what idr-rc happens to make of one.
!L = !idr.data<"L">
!Two = !idr.data<"Two">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons],
  "Two" = plain [@Two(!idr.str, !idr.str)]
>
idr.program @counting root(@root) stage(owned) types #types {
  idr.func @map(%l: !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>> {
    %n = idr.constant !idr.q<many, borrow, !idr.box<!L>> #idr.con<!L, @N, []>
    %v = idr.borrow %l : !idr.excl<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.excl<!idr.box<!L>>) {
    case @N() {
      idr.unpack %l : !idr.excl<!idr.box<!L>> @N -> ()
      %e = idr.dup %n : !idr.q<many, borrow, !idr.box<!L>> -> !idr.excl<!idr.box<!L>>
      idr.yield %e : !idr.excl<!idr.box<!L>>
    }
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %token, %fields:2 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
      %h2 = arith.muli %fields#0, %fields#0 : i64
      %t2 = idr.call @map(%fields#1) : (!idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
      %cell = idr.cell.recycle %token : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %c = idr.cell.init %cell : !idr.cell<!idr.box<!L>, @C> (%h2 : i64, %t2 : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
      idr.yield %c : !idr.excl<!idr.box<!L>>
    }
    }
    return %r : !idr.excl<!idr.box<!L>>
  }
  // expected-error @below {{expected reuses-in-place: }}
  idr.func @build(%n: i64) -> !idr.excl<!idr.box<!L>> {
    %r = idr.match_lit %n : i64 -> (!idr.excl<!idr.box<!L>>) {
    case 0 {
      %e = idr.constant !idr.q<many, borrow, !idr.box<!L>> #idr.con<!L, @N, []>
      %d = idr.dup %e : !idr.q<many, borrow, !idr.box<!L>> -> !idr.excl<!idr.box<!L>>
      idr.yield %d : !idr.excl<!idr.box<!L>>
    }
    default(%k: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.excl<!idr.box<!L>>
      %cell = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
      // expected-error @below {{expected reuses-in-place: }}
      %c = idr.cell.init %cell : !idr.cell<!idr.box<!L>, @C> (%n : i64, %t : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
      idr.yield %c : !idr.excl<!idr.box<!L>>
    }
    }
    return %r : !idr.excl<!idr.box<!L>>
  }
  idr.func @sum(%l: !idr.q<many, borrow, !idr.box<!L>>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.q<many, borrow, !idr.box<!L>>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // expected-error @below {{expected reuses-in-place: }}
  idr.func @both(%a: !idr.own<!idr.str>, %b: !idr.q<many, borrow, !idr.str>) -> (!idr.excl<!Two>, i64) {
    %v = idr.borrow %a : !idr.own<!idr.str>
    // expected-error @below {{expected counts-nothing: }}
    %a2 = idr.dup %v : !idr.q<many, borrow, !idr.str>
    %p = idr.con !idr.excl<!Two> @Two(%a2 : !idr.own<!idr.str>, %a : !idr.own<!idr.str>)
    %n = idr.str.length borrow %b
    return %p, %n : !idr.excl<!Two>, i64
  }
  idr.func @root() -> i64 {
    %c3 = arith.constant 3 : i64
    %l = idr.call @build(%c3) : (i64) -> !idr.excl<!idr.box<!L>>
    %m = idr.call @map(%l) : (!idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    %v = idr.borrow %m : !idr.excl<!idr.box<!L>>
    %z = arith.constant 0 : i64
    %s = idr.call @sum(%v, %z) : (!idr.q<many, borrow, !idr.box<!L>>, i64) -> i64
    idr.drop %m : !idr.excl<!idr.box<!L>>
    return %s : i64
  }
}
