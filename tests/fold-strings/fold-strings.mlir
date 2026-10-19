// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=folds-balanced,returns=@folds:"hi"/"ab"' -o /dev/null
// A string built from a constant list folds to the constant string: pack
// of the characters, concat of the strings; the folders release what the
// runtime gave them.
!Chars = !idr.data<"Chars", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons]>
!Strs = !idr.data<"Strs", list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]>
idr.program @strings root(@root) stage(first) {
  idr.func @folds() -> (!idr.str, !idr.str) {
    %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [105 : i32, #idr.con<!Chars, @Nil, []>]>]>
    %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Nil, []>]>]>
    %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %t = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
    return %s, %t : !idr.str, !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
