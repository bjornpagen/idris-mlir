// NEEDS-ACCEPTANCE: a nullary boxed constructor taken after idr-rc allocates nothing: idr-rc leaves the atom's idr.con a con, which lowers to the atom's static cell, and its take is an idr.unpack, which frees nothing (§7, ir-ops-6; S4). At the base @nil allocates a cell its take never frees.
// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@nil:()->!llvm.ptr,calls-only=@nil:[],calls-only=@isNil:[@idris_rt_inc,@idris_rt_dec],calls-only=@Prog.main:[@nil,@isNil,@idris_rt_inc,@idris_rt_dec]' -o /dev/null
// A constructor without fields of a boxed sum is its atom: one static cell,
// count 0, so no heap cell is made for it and none is freed, and the
// counting of it changes nothing. @nil returns it with no call; @isNil
// takes it apart with no call of its own.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @atom root(@Prog.main) stage(first) {
  idr.func @nil() -> !idr.box<!List> {
    %n = idr.con !idr.box<!List> @Nil()
    return %n : !idr.box<!List>
  }
  idr.func @isNil(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Nil() {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: !idr.box<!List>) {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %n = idr.call @nil() : () -> !idr.box<!List>
    %r = idr.call @isNil(%n) : (!idr.box<!List>) -> i64
    return %r : i64
  }
}
