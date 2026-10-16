// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@values:[],signature=@values:()->(!llvm.ptr,!llvm.ptr,i64,i64,!llvm.ptr,i8,i64,f64)' -o /dev/null
// NEEDS-ACCEPTANCE: the lowered type of @values, Num as its tag and one slot for each constructor's field, as data-layout.mlir lays a sum out.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Every constant of a string, a big outside the small range or a box is a
// private constant global with count 0, shared when equal. A string's
// header holds the ASCII flag, the byte length and the scalar count (the
// runtime counts them); a small big is its tagged word; a large one a
// static bignum, its limbs in the same global. An unboxed constant is its
// components, and a slot its constructor does not use is zero. A constant
// costs nothing at run time: no runtime call makes one. The globals' types
// and words are the runtime's layout of static data.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!Num = !idr.data<"Num", plain [@I(i64), @D(f64)]>
idr.program @constants root(@Prog.main) stage(owned) {
  idr.func @values() -> (!idr.str, !idr.str, !idr.big, !idr.big, !idr.box<!List>,
                                  !Num) {
    %s1 = idr.constant "h\C3\A9!" : !idr.str
    %s2 = idr.constant "h\C3\A9!" : !idr.str
    %small = idr.constant #idr.big<-43> : !idr.big
    %large = idr.constant #idr.big<-36893488147419103231> : !idr.big
    %l = idr.constant #idr.con<!List, @Cons, [7, #idr.con<!List, @Nil, []>]> : !idr.box<!List>
    %n = idr.constant #idr.con<!Num, @D, [2.5 : f64]> : !Num
    return %s1, %s2, %small, %large, %l, %n
        : !idr.str, !idr.str, !idr.big, !idr.big, !idr.box<!List>, !Num
  }
  idr.func @Prog.main() -> i64 {
    %v:6 = idr.call @values() : () -> (!idr.str, !idr.str, !idr.big, !idr.big, !idr.box<!List>,
                                        !Num)
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
