// RUN: idris-mlir-opt %s --mlir-disable-threading --canonicalize --idr-expect=holds=folds-balanced > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A string built from a constant list folds to the constant string: pack
// of the characters, concat of the strings; the folders release what the
// runtime gave them.
// CHECK-LABEL: func.func @folds(
// CHECK-DAG: idr.constant "hi" : !idr.str
// CHECK-DAG: idr.constant "ab" : !idr.str
// CHECK-NOT: idr.str.pack
// CHECK-NOT: idr.str.concat
idr.data @Chars box {
  idr.ctor @Nil ()
  idr.ctor @Cons (i32, !idr.box<@Chars>)
}
idr.data @Strs box {
  idr.ctor @Nil ()
  idr.ctor @Cons (!idr.str, !idr.box<@Strs>)
}
func.func @folds() -> (!idr.str, !idr.str) {
  %cs = idr.constant #idr.con<@Chars::@Cons, [104 : i32, #idr.con<@Chars::@Cons, [105 : i32, #idr.con<@Chars::@Nil, []>]>]> : !idr.box<@Chars>
  %ss = idr.constant #idr.con<@Strs::@Cons, ["a", #idr.con<@Strs::@Cons, ["b", #idr.con<@Strs::@Nil, []>]>]> : !idr.box<@Strs>
  %s = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
  %t = idr.str.concat %ss : !idr.box<@Strs> -> !idr.str
  return %s, %t : !idr.str, !idr.str
}
