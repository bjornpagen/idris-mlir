// RUN: idris-mlir-opt %s | FileCheck %s --implicit-check-not='!idr.data<@' --implicit-check-not='!idr.box<@'
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s --implicit-check-not='!idr.data<@' --implicit-check-not='!idr.box<@'
// NEEDS-ACCEPTANCE: the aliases the printer gives data types, and where it prints them.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A data type is written by a short name, defined once at the top of the
// text with its body: its name is as long as the instance it names. The
// short name is the name's pieces between brackets, commas and spaces,
// each after its last dot, joined with `_`; two that shorten alike are
// numbered apart. A box has no alias of its own: it is the box of its
// data type's, wherever the type occurs: a signature, a grade, a field, an
// op's type. Inside its own body a recursive type is its name alone. A
// constant with more than 256 constructors and closures in its tree is
// written once, by name, too: spelled out wherever it occurs, a constant
// whose parts are shared is as large as its tree.
// CHECK-DAG: !List_Nat = !idr.data<"Prelude.Types.List[Prelude.Types.Nat]", list [@Nil() nil, @Cons(!idr.nat, !idr.box<!idr.data<"Prelude.Types.List[Prelude.Types.Nat]">>) cons]>
// CHECK-DAG: !Maybe_Nat = !idr.data<"Prelude.Types.Maybe[Prelude.Types.Nat]", plain [@Nothing(), @Just(!idr.nat)]>
// CHECK-DAG: !Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64)]>
// CHECK-DAG: ![[A:Pair1?]] = !idr.data<"A.Pair", plain [@MkPair(i64, i64)]>
// CHECK-DAG: ![[B:Pair1?]] = !idr.data<"B.Pair", plain [@MkPair(f64, f64)]>
// CHECK-DAG: !Tree = !idr.data<"Tree", plain [@Leaf(), @Node(!idr.box<!idr.data<"Tree">>, !idr.box<!idr.data<"Tree">>)]>
// CHECK-DAG: #idr_value = #idr.con<!Tree, @Node, [#idr.con<!Tree, @Node,
// CHECK-LABEL: idr.func @owned(
// CHECK-SAME: : !idr.own<!idr.box<!List_Nat>>) -> !idr.box<!List_Nat>
// CHECK-LABEL: idr.func @len(
// CHECK-SAME: %{{.*}}: !idr.box<!List_Nat>, %{{.*}}: !Maybe_Nat, %{{.*}}: !idr.box<!Shape>) -> !idr.box<!List_Nat>
// CHECK: constant #idr.con<!List_Nat, @Nil, []> : !idr.box<!List_Nat>
// CHECK: field %{{.*}} : !idr.box<!Shape> @Circle[0] -> f64
// CHECK-LABEL: idr.func @pairs(
// CHECK-SAME: %{{.*}}: ![[A]], %{{.*}}: ![[B]])
// CHECK-LABEL: idr.func @trees(
// CHECK: constant #idr_value : !idr.box<!Tree>
// CHECK: constant #idr.con<!Tree, @Node, [#idr.con<!Tree, @Leaf, []>, #idr.con<!Tree, @Leaf, []>]> : !idr.box<!Tree>

!Prelude.Types.List_Prelude.Types.Nat_ = !idr.data<"Prelude.Types.List[Prelude.Types.Nat]", list [@Nil() nil, @Cons(!idr.nat, !idr.box<!idr.data<"Prelude.Types.List[Prelude.Types.Nat]">>) cons]>
!Prelude.Types.Maybe_Prelude.Types.Nat_ = !idr.data<"Prelude.Types.Maybe[Prelude.Types.Nat]", plain [@Nothing(), @Just(!idr.nat)]>
!Main.Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64)]>
!A.Pair = !idr.data<"A.Pair", plain [@MkPair(i64, i64)]>
!B.Pair = !idr.data<"B.Pair", plain [@MkPair(f64, f64)]>
!Tree = !idr.data<"Tree", plain [@Leaf(), @Node(!idr.box<!idr.data<"Tree">>, !idr.box<!idr.data<"Tree">>)]>
#t0 = #idr.con<!Tree, @Leaf, []>
#t1 = #idr.con<!Tree, @Node, [#t0, #t0]>
#t2 = #idr.con<!Tree, @Node, [#t1, #t1]>
#t3 = #idr.con<!Tree, @Node, [#t2, #t2]>
#t4 = #idr.con<!Tree, @Node, [#t3, #t3]>
#t5 = #idr.con<!Tree, @Node, [#t4, #t4]>
#t6 = #idr.con<!Tree, @Node, [#t5, #t5]>
#t7 = #idr.con<!Tree, @Node, [#t6, #t6]>
#t8 = #idr.con<!Tree, @Node, [#t7, #t7]>


idr.program @aliases root(@root) stage(owned) {
  idr.func @owned(%a0: !idr.own<!idr.box<!Prelude.Types.List_Prelude.Types.Nat_>>)
      -> !idr.q<many, borrow, !idr.box<!Prelude.Types.List_Prelude.Types.Nat_>> {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @len(%l: !idr.q<many, borrow, !idr.box<!Prelude.Types.List_Prelude.Types.Nat_>>,
                        %m: !idr.q<many, borrow, !Prelude.Types.Maybe_Prelude.Types.Nat_>,
                        %s: !idr.q<many, borrow, !idr.box<!Main.Shape>>)
      -> !idr.q<many, borrow, !idr.box<!Prelude.Types.List_Prelude.Types.Nat_>> {
    %n = idr.constant #idr.con<!Prelude.Types.List_Prelude.Types.Nat_, @Nil, []>
       : !idr.q<many, borrow, !idr.box<!Prelude.Types.List_Prelude.Types.Nat_>>
    %r = idr.field %s : !idr.q<many, borrow, !idr.box<!Main.Shape>> @Circle[0] -> f64
    return %n : !idr.q<many, borrow, !idr.box<!Prelude.Types.List_Prelude.Types.Nat_>>
  }
  idr.func @pairs(%a: !A.Pair, %b: !B.Pair) {
    return
  }
  idr.func @trees() -> (!idr.q<many, borrow, !idr.box<!Tree>>, !idr.q<many, borrow, !idr.box<!Tree>>) {
    %big = idr.constant #t8 : !idr.box<!Tree>
    %small = idr.constant #t1 : !idr.box<!Tree>
    return %big, %small : !idr.q<many, borrow, !idr.box<!Tree>>, !idr.q<many, borrow, !idr.box<!Tree>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
