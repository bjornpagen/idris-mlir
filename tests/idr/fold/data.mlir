// NEEDS-ACCEPTANCE: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before.
// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@constant_con:(#idr.con<!idr.data<"S", plain [@A(), @B(i64, !idr.str)]>, @B, [1, "x"]>)/(#idr.con<!idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>, @Cons, [2, #idr.con<!idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>, @Nil, []>]>),returns=@known:1/_/"y",returns=@of_constant:7/1/(#idr.con<!idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>, @Nil, []>),returns=@unknown:_/_/0,returns=@cse:#idr.big<12345678901234567890>/#idr.big<12345678901234567890>' -o /dev/null
// NEEDS-ACCEPTANCE: how the printer writes a constructor constant (#idr.con), which the property reads back alone, its data type written with its body
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Constructors of constants fold to constants; fields and tags of known
// constructors fold.


!S = !idr.data<"S", plain [@A(), @B(i64, !idr.str)]>
!One = !idr.data<"One", plain [@Only(i64)]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @data root(@root) stage(first) {
  idr.func @constant_con() -> (!S, !idr.box<!L>) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %x = idr.constant !idr.str "x"
    %s = idr.con !S @B(%one : i64, %x : !idr.str)
    %nil = idr.con !idr.box<!L> @Nil()
    %l = idr.con !idr.box<!L> @Cons(%two : i64, %nil : !idr.box<!L>)
    return %s, %l : !S, !idr.box<!L>
  }

  // A constructor with a runtime field stays; its fields and tag fold.
  idr.func @known(%x: i64) -> (i64, i64, !idr.str) {
    %y = idr.constant !idr.str "y"
    %s = idr.con !S @B(%x : i64, %y : !idr.str)
    %t = idr.tag %s : !S
    %f = idr.field %s : !S @B[0] -> i64
    %g = idr.field %s : !S @B[1] -> !idr.str
    return %t, %f, %g : i64, i64, !idr.str
  }

  // Fields and tags of a constant fold, nested ones included.
  idr.func @of_constant() -> (i64, i64, !idr.box<!L>) {
    %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [7 : i64, #idr.con<!L, @Nil, []>]>
    %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
    %t = idr.tag %l : !idr.box<!L>
    %n = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
    return %h, %t, %n : i64, i64, !idr.box<!L>
  }

  // A field of another constructor is unspecified and does not fold; the tag
  // of a type of one constructor is 0.
  idr.func @unknown(%v: !S, %o: !One) -> (i64, i64, i64) {
    %a = idr.con !S @A()
    %f = idr.field %a : !S @B[0] -> i64
    %t = idr.tag %v : !S
    %u = idr.tag %o : !One
    return %f, %t, %u : i64, i64, i64
  }

  // Equal constants are one value.
  idr.func @cse() -> (!idr.big, !idr.big) {
    %a = idr.constant !idr.big #idr.big<12345678901234567890>
    %b = idr.constant !idr.big #idr.big<12345678901234567890>
    return %a, %b : !idr.big, !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
