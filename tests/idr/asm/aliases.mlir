// RUN: idris-mlir-opt %s | FileCheck %s --implicit-check-not='!idr.data<@' --implicit-check-not='!idr.box<@'
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s --implicit-check-not='!idr.data<@' --implicit-check-not='!idr.box<@'
// A data type is written by a short name, defined once at the top of the
// text: its symbol is as long as the instance it names. The name is the
// symbol's pieces between brackets, commas and spaces, each after its last
// dot, joined with `_`; two that shorten alike are numbered apart. It is
// the same for an unboxed sum and a box, and wherever the type occurs: a
// signature, a grade, a field, an op's type. A constant with more than 256
// constructors and closures in its tree is written once, by name, too:
// spelled out wherever it occurs, a constant whose parts are shared is as
// large as its tree.
// CHECK-DAG: !List_Nat = !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">
// CHECK-DAG: !Maybe_Nat = !idr.data<@"Prelude.Types.Maybe[Prelude.Types.Nat]">
// CHECK-DAG: !Shape = !idr.box<@Main.Shape>
// CHECK-DAG: ![[A:Pair1?]] = !idr.data<@A.Pair>
// CHECK-DAG: ![[B:Pair1?]] = !idr.data<@B.Pair>
// CHECK-DAG: !Tree = !idr.box<@Tree>
// CHECK-DAG: #idr_value = #idr.con<@Tree::@Node, [#idr.con<@Tree::@Node,
// CHECK-LABEL: idr.data @"Prelude.Types.List[Prelude.Types.Nat]" box {
// CHECK: idr.ctor @Cons (!idr.nat, !List_Nat)
// CHECK-LABEL: idr.func private @owned(!idr.own<!List_Nat>) -> !List_Nat
// CHECK-LABEL: idr.func private @len(
// CHECK-SAME: %{{.*}}: !List_Nat, %{{.*}}: !Maybe_Nat, %{{.*}}: !Shape) -> !List_Nat
// CHECK: constant #idr.con<@"Prelude.Types.List[Prelude.Types.Nat]"::@Nil, []> : !List_Nat
// CHECK: field %{{.*}}[@Circle, 0] : !Shape -> f64
// CHECK-LABEL: idr.func private @pairs(
// CHECK-SAME: %{{.*}}: ![[A]], %{{.*}}: ![[B]])
// CHECK-LABEL: idr.func private @trees(
// CHECK: constant #idr_value : !Tree
// CHECK: constant #idr.con<@Tree::@Node, [#idr.con<@Tree::@Leaf, []>, #idr.con<@Tree::@Leaf, []>]> : !Tree

#t0 = #idr.con<@Tree::@Leaf, []>
#t1 = #idr.con<@Tree::@Node, [#t0, #t0]>
#t2 = #idr.con<@Tree::@Node, [#t1, #t1]>
#t3 = #idr.con<@Tree::@Node, [#t2, #t2]>
#t4 = #idr.con<@Tree::@Node, [#t3, #t3]>
#t5 = #idr.con<@Tree::@Node, [#t4, #t4]>
#t6 = #idr.con<@Tree::@Node, [#t5, #t5]>
#t7 = #idr.con<@Tree::@Node, [#t6, #t6]>
#t8 = #idr.con<@Tree::@Node, [#t7, #t7]>

idr.data @"Prelude.Types.List[Prelude.Types.Nat]" box {
  idr.ctor @Nil ()
  idr.ctor @Cons (!idr.nat, !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">)
}
idr.data @"Prelude.Types.Maybe[Prelude.Types.Nat]" {
  idr.ctor @Nothing ()
  idr.ctor @Just (!idr.nat)
}
idr.data @Main.Shape box {
  idr.ctor @Circle (f64)
  idr.ctor @Rect (f64, f64)
}
idr.data @A.Pair {
  idr.ctor @MkPair (i64, i64)
}
idr.data @B.Pair {
  idr.ctor @MkPair (f64, f64)
}
idr.data @Tree box {
  idr.ctor @Leaf ()
  idr.ctor @Node (!idr.box<@Tree>, !idr.box<@Tree>)
}

idr.func private @owned(!idr.own<!idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">>)
    -> !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">
idr.func private @len(%l: !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">,
                      %m: !idr.data<@"Prelude.Types.Maybe[Prelude.Types.Nat]">,
                      %s: !idr.box<@Main.Shape>)
    -> !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]"> {
  %n = idr.constant #idr.con<@"Prelude.Types.List[Prelude.Types.Nat]"::@Nil, []>
     : !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">
  %r = idr.field %s[@Circle, 0] : !idr.box<@Main.Shape> -> f64
  return %n : !idr.box<@"Prelude.Types.List[Prelude.Types.Nat]">
}
idr.func private @pairs(%a: !idr.data<@A.Pair>, %b: !idr.data<@B.Pair>) {
  return
}
idr.func private @trees() -> (!idr.box<@Tree>, !idr.box<@Tree>) {
  %big = idr.constant #t8 : !idr.box<@Tree>
  %small = idr.constant #t1 : !idr.box<@Tree>
  return %big, %small : !idr.box<@Tree>, !idr.box<@Tree>
}
