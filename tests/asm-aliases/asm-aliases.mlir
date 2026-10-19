// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// RUN: idris-mlir-opt %s -o %t.once.mlir
// RUN: idris-mlir-opt %t.once.mlir -o %t.twice.mlir
// RUN: diff %t.once.mlir %t.twice.mlir
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
// Printed, the text reads back and prints as itself.
// CHECK-DAG: !List_Nat = !idr.data<"Prelude.Types.List[Prelude.Types.Nat]", list [@Nil() nil, @Cons(!idr.nat, !idr.box<!idr.data<"Prelude.Types.List[Prelude.Types.Nat]">>) cons]>
// CHECK-DAG: !Maybe_Nat = !idr.data<"Prelude.Types.Maybe[Prelude.Types.Nat]", plain [@Nothing(), @Just(!idr.nat)]>
// CHECK-DAG: !Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64)]>
// CHECK-DAG: ![[A:Pair1?]] = !idr.data<"A.Pair", plain [@MkPair(i64, i64)]>
// CHECK-DAG: ![[B:Pair1?]] = !idr.data<"B.Pair", plain [@MkPair(f64, f64)]>
// CHECK-DAG: !Tree = !idr.data<"Tree", plain [@Leaf(), @Node(!idr.box<!idr.data<"Tree">>, !idr.box<!idr.data<"Tree">>)]>
// CHECK-DAG: #idr_value = #idr.con<!Tree, @Node, [#idr.con<!Tree, @Node,
// CHECK-LABEL: idr.func @owned(
// CHECK-SAME: : !idr.own<!idr.box<!List_Nat>>) -> !idr.q<many, borrow, !idr.box<!List_Nat>>
// CHECK-LABEL: idr.func @len(
// CHECK-SAME: %{{[^:]*}}: !idr.q<many, borrow, !idr.box<!List_Nat>>, %{{[^:]*}}: !idr.q<many, borrow, !Maybe_Nat>, %{{[^:]*}}: !idr.q<many, borrow, !idr.box<!Shape>>) -> !idr.own<!idr.box<!List_Nat>>
// CHECK: constant !idr.q<many, borrow, !idr.box<!List_Nat>> #idr.con<!List_Nat, @Nil, []>
// CHECK: field %{{[^ ]*}} : !idr.q<many, borrow, !idr.box<!Shape>> @Circle[0] -> f64
// CHECK-LABEL: idr.func @pairs(
// CHECK-SAME: %{{.*}}: ![[A]], %{{.*}}: ![[B]])
// CHECK-LABEL: idr.func @trees(
// CHECK: constant !idr.q<many, borrow, !idr.box<!Tree>> #idr_value
// CHECK: constant !idr.q<many, borrow, !idr.box<!Tree>> #idr.con<!Tree, @Node, [#idr.con<!Tree, @Leaf, []>, #idr.con<!Tree, @Leaf, []>]>

!Prelude_Types_List_Prelude_Types_Nat_ = !idr.data<"Prelude.Types.List[Prelude.Types.Nat]", list [@Nil() nil, @Cons(!idr.nat, !idr.box<!idr.data<"Prelude.Types.List[Prelude.Types.Nat]">>) cons]>
!Prelude_Types_Maybe_Prelude_Types_Nat_ = !idr.data<"Prelude.Types.Maybe[Prelude.Types.Nat]", plain [@Nothing(), @Just(!idr.nat)]>
!Main_Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64)]>
!A_Pair = !idr.data<"A.Pair", plain [@MkPair(i64, i64)]>
!B_Pair = !idr.data<"B.Pair", plain [@MkPair(f64, f64)]>
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
  idr.func @owned(%a0: !idr.own<!idr.box<!Prelude_Types_List_Prelude_Types_Nat_>>)
      -> !idr.q<many, borrow, !idr.box<!Prelude_Types_List_Prelude_Types_Nat_>> {
    idr.crash "no body"
    ub.unreachable
  }
  idr.func @len(%l: !idr.q<many, borrow, !idr.box<!Prelude_Types_List_Prelude_Types_Nat_>>,
                        %m: !idr.q<many, borrow, !Prelude_Types_Maybe_Prelude_Types_Nat_>,
                        %s: !idr.q<many, borrow, !idr.box<!Main_Shape>>)
      -> !idr.own<!idr.box<!Prelude_Types_List_Prelude_Types_Nat_>> {
    %n = idr.constant !idr.q<many, borrow, !idr.box<!Prelude_Types_List_Prelude_Types_Nat_>>
       #idr.con<!Prelude_Types_List_Prelude_Types_Nat_, @Nil, []>
    %r = idr.field %s : !idr.q<many, borrow, !idr.box<!Main_Shape>> @Circle[0] -> f64
    %d = idr.dup %n : !idr.q<many, borrow, !idr.box<!Prelude_Types_List_Prelude_Types_Nat_>>
    return %d : !idr.own<!idr.box<!Prelude_Types_List_Prelude_Types_Nat_>>
  }
  idr.func @pairs(%a: !A_Pair, %b: !B_Pair) {
    return
  }
  idr.func @trees() -> (!idr.own<!idr.box<!Tree>>, !idr.own<!idr.box<!Tree>>) {
    %big = idr.constant !idr.q<many, borrow, !idr.box<!Tree>> #t8
    %small = idr.constant !idr.q<many, borrow, !idr.box<!Tree>> #t1
    %b = idr.dup %big : !idr.q<many, borrow, !idr.box<!Tree>>
    %s = idr.dup %small : !idr.q<many, borrow, !idr.box<!Tree>>
    return %b, %s : !idr.own<!idr.box<!Tree>>, !idr.own<!idr.box<!Tree>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
