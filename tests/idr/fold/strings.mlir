// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=folds-balanced > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A string built from a constant list folds to the constant string: pack
// of the characters, concat of the strings; the folders release what the
// runtime gave them.
// CHECK-LABEL: idr.func private @folds(
// CHECK-DAG: constant "hi" : !idr.str
// CHECK-DAG: constant "ab" : !idr.str
// CHECK-NOT: idr.str.pack
// CHECK-NOT: idr.str.concat
!Chars = !idr.data<"Chars", list [@Nil(), @Cons(i32, !idr.box<!idr.data<"Chars">>)]>
!Strs = !idr.data<"Strs", list [@Nil(), @Cons(!idr.str, !idr.box<!idr.data<"Strs">>)]>
idr.func private @folds() -> (!idr.str, !idr.str) {
  %cs = idr.constant #idr.con<@Cons, [104 : i32, #idr.con<@Cons, [105 : i32, #idr.con<@Nil, []>]>]> : !idr.box<!Chars>
  %ss = idr.constant #idr.con<@Cons, ["a", #idr.con<@Cons, ["b", #idr.con<@Nil, []>]>]> : !idr.box<!Strs>
  %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
  %t = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
  return %s, %t : !idr.str, !idr.str
}
