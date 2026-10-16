// NEEDS-ACCEPTANCE: that this owned module verifies as written, and that reuses-every-cell fails once, at the drop of the token @drop's take yields.
// RUN: idris-mlir-opt %s --idr-expect=holds=reuses-every-cell=@rebuild -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=reuses-every-cell=@drop -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// The cell a take yields for a constructor with fields is built in again
// (@rebuild), or freed: @drop drops its token, and the cell goes.
// CHECK-DAG: error: expected reuses-every-cell: the cell of {{.*}} is freed, not reused, in @drop
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"reuses-every-cell" root(@Prog.main) stage(owned) {
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
  idr.func @drop(%l: !idr.own<!idr.box<!L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      idr.drop %w#2 : !idr.own<!idr.box<!L>>
      idr.drop %w#0 : !idr.own<!idr.token>
      idr.yield %h : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<!L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
