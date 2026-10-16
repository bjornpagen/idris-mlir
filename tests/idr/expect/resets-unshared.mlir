// NEEDS-ACCEPTANCE: that this owned module verifies as written, and that resets-unshared fails once, at the take of @shared, whose box a dup of its view gave a second reference.
// RUN: idris-mlir-opt %s --idr-expect=holds=resets-unshared=@rebuild -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=resets-unshared=@shared -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A take that may reuse its cell tests one its function never gives a
// second reference (@rebuild); a function that dups a view of the box it
// then takes tests a cell it shares itself (@shared).
// CHECK-DAG: error: expected resets-unshared: {{.*}} in @shared tests a cell that its function gives a second reference
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"resets-unshared" root(@Prog.main) stage(owned) {
  idr.func @rebuild(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %c = idr.reuse %w#0 !idr.own<!idr.box<!L>> @C(%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %c : !idr.own<!idr.box<!L>>
    }
    default {
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
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %c = idr.reuse %w#0 !idr.own<!idr.box<!L>> @C(%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %c : !idr.own<!idr.box<!L>>
    }
    default {
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
