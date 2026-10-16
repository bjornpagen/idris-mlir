// NEEDS-ACCEPTANCE: that this owned module verifies as written; that tests-nothing fails once at each of @owned's take and reuse and once of @Prog.main, which takes nothing apart; and that exclusive-copy fails once for @owned.
// RUN: idris-mlir-opt %s --idr-expect=holds=tests-nothing=@exclusive,exclusive-copy=@exclusive -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=tests-nothing=@owned,tests-nothing=@Prog.main,exclusive-copy=@owned -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 4
// A take of an exclusive value and a reuse of an exclusive token test
// nothing (@exclusive, which takes its one reference parameter exclusive);
// an owned one tests the count and the null (@owned), and a function that
// takes nothing apart has nothing to test.
// CHECK-DAG: error: expected tests-nothing: {{.*}} in @owned tests a value of {{.*}}, which is not exclusive
// CHECK-DAG: error: expected tests-nothing: {{.*}} in @owned tests a value of {{.*}}, which is not exclusive
// CHECK-DAG: error: expected tests-nothing: nothing is taken apart in @Prog.main
// CHECK-DAG: error: expected exclusive-copy: no copy of @owned takes its references exclusive
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"tests-nothing" root(@Prog.main) stage(owned) {
  idr.func @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %c = idr.reuse %w#0 !idr.excl<!idr.box<!L>> @C(%x : i64, %w#2 : !idr.excl<!idr.box<!L>>)
    return %c : !idr.excl<!idr.box<!L>>
  }
  idr.func @owned(%l: !idr.own<!idr.box<!L>>, %x: i64) -> !idr.own<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
    %c = idr.reuse %w#0 !idr.own<!idr.box<!L>> @C(%x : i64, %w#2 : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
