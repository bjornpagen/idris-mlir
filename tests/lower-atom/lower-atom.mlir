// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@nil:()->!llvm.ptr,calls-only=@nil:[],calls-only=@isNil:[@idris_rt_inc,@idris_rt_dec],calls-only=@Prog.main:[@nil,@isNil,@idris_rt_cell,@idris_rt_inc,@idris_rt_dec]' -o /dev/null
// A constructor without fields of a boxed sum is its atom: one static cell,
// count 0, so no heap cell is made for it and none is freed, and the
// counting of it changes nothing. @nil returns it with no call; @isNil
// takes it apart with no call of its own. The root asks @isNil of the atom
// and of a cell, so each case runs: the program, lowered and as written,
// exits with 2, the status the reference at the end (REF) computes with no
// list (%differential, on the one input, none, since it reads none).
// STDIN:
!List = !idr.data<"List">
#types = #idr.types<
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]
>
idr.program @atom root(@Prog.main) stage(first) types #types {
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
    %one = arith.constant 1 : i64
    %c = idr.con !idr.box<!List> @Cons(%one : i64, %n : !idr.box<!List>)
    %s = idr.call @isNil(%c) : (!idr.box<!List>) -> i64
    %twice = arith.addi %r, %r : i64
    %t = arith.addi %twice, %s : i64
    return %t : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %r = arith.constant 2 : i64
// REF:     return %r : i64
// REF:   }
// REF: }
