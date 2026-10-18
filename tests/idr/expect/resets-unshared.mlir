// NEEDS-ACCEPTANCE: that this owned module, in this wave's printed forms (the take with its token, idr.cell.recycle and idr.cell.init, a default that binds the scrutinee), verifies as written, and that the -verify-diagnostics run passes.
// RUN: idris-mlir-opt %s --idr-expect=holds=resets-unshared=@rebuild -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=resets-unshared=@shared -verify-diagnostics -o /dev/null
// A take that may recycle its cell tests one its function never gives a
// second reference (@rebuild); a function that dups a view of the box it
// then takes tests a cell it shares itself (@shared).
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"resets-unshared" root(@Prog.main) stage(owned) {
  idr.func @rebuild(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %c = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %b : !idr.own<!idr.box<!L>>
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  idr.func @shared(%l: !idr.own<!idr.box<!L>>) -> (!idr.own<!idr.box<!L>>, !idr.own<!idr.box<!L>>) {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %d = idr.dup %v : !idr.q<many, borrow, !idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      // expected-error @below {{expected resets-unshared: idr.take in @shared tests a cell that its function gives a second reference}}
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %c = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %b : !idr.own<!idr.box<!L>>
    }
    default(%e: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r, %d : !idr.own<!idr.box<!L>>, !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
