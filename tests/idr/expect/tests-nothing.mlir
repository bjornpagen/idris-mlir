// NEEDS-ACCEPTANCE: that this owned module, in this wave's printed forms, verifies as written, the recycle of @exclusive's exclusive token included (the base could not parse it); and that the -verify-diagnostics run passes.
// RUN: idris-mlir-opt %s --idr-expect=holds=tests-nothing=@exclusive,exclusive-copy=@exclusive -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=tests-nothing=@owned,tests-nothing=@Prog.main,exclusive-copy=@owned -verify-diagnostics -o /dev/null
// expected-error @-4 {{expected exclusive-copy: no copy of @owned takes its references exclusive}}
// A take of an exclusive value and a recycle of an exclusive token test
// nothing (@exclusive, which takes its one reference parameter exclusive);
// an owned one tests the count and the null (@owned), and a function that
// takes nothing apart has nothing to test.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"tests-nothing" root(@Prog.main) stage(owned) {
  idr.func @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %c = idr.cell.recycle %w#0 : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %b : !idr.excl<!idr.box<!L>>
  }
  idr.func @owned(%l: !idr.own<!idr.box<!L>>, %x: i64) -> !idr.own<!idr.box<!L>> {
    // expected-error @below {{expected tests-nothing: idr.take in @owned tests a value of}}
    %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
    // expected-error @below {{expected tests-nothing: idr.cell.recycle in @owned tests a value of}}
    %c = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.own<!idr.box<!L>>)
    return %b : !idr.own<!idr.box<!L>>
  }
  // expected-error @below {{expected tests-nothing: nothing is taken apart in @Prog.main}}
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
