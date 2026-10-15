// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A take of an exclusive value moves its fields out with no count test:
// the cell is the token. A reuse of an exclusive token builds in it with
// no null test and no allocation. A take of an owned value tests, and a
// reuse of its token tests for null.
// CHECK-LABEL: func.func private @exclusive(
// CHECK-NOT: idris_rt_inc
// CHECK-NOT: idris_rt_dec
// CHECK-NOT: idris_rt_cell
// CHECK-NOT: scf.if
// CHECK: llvm.store
// CHECK-LABEL: func.func private @owned(
// CHECK: scf.if
// CHECK: idris_rt_inc
// CHECK: idris_rt_cell
!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l @C : !idr.excl<!idr.box<!L>> -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %c = idr.reuse %w#0 @C(%x, %w#2) : (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %c : !idr.excl<!idr.box<!L>>
  }
  idr.func private @owned(%l: !idr.own<!idr.box<!L>>, %x: i64) -> !idr.own<!idr.box<!L>> {
    %w:3 = idr.take %l @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
    %c = idr.reuse %w#0 @C(%x, %w#2) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
