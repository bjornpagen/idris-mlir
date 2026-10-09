// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// Every constant of a string, a big outside the small range or a box is a
// private constant global with count 0, shared when equal. A string's
// header holds the ASCII flag, the byte length and the scalar count (the
// runtime counts them); a small big is its tagged word; a large one a
// static bignum, its limbs in the same global. An unboxed constant is its
// components, and a slot its constructor does not use is zero.
// CHECK-DAG: llvm.mlir.global private constant @[[S:__idr_str_[0-9]+]]() {{.*}} : !llvm.struct<(i32, i32, i64, i64, array<4 x i8>)>
// -(2^65 - 1): two limbs, size -2.
// CHECK-DAG: llvm.mlir.constant(dense<[-1, 1]> : tensor<2xi64>) : !llvm.array<2 x i64>
// CHECK-DAG: llvm.mlir.constant(-2 : i64) : i64
// CHECK-DAG: llvm.mlir.global private constant @[[B:__idr_big_[0-9]+]]() {{.*}} : !llvm.struct<(i32, i32, i64, array<2 x i64>)>
// A box's counted fields come first.
// CHECK-DAG: llvm.mlir.global private constant @[[BOX:__idr_box_[0-9]+]]() {{.*}} : !llvm.struct<packed (i32, i32, ptr, i64)>
// The string "hé!": not ASCII, 4 bytes, 3 scalars.
// CHECK-DAG: %{{.*}} = llvm.mlir.constant("h\C3\A9!") : !llvm.array<4 x i8>
// CHECK-LABEL: func.func private @values()
// CHECK: %[[S1:.*]] = llvm.mlir.addressof @[[S]] : !llvm.ptr
// CHECK: %[[S2:.*]] = llvm.mlir.addressof @[[S]] : !llvm.ptr
// CHECK: %[[SMALL:.*]] = llvm.mlir.constant(-85 : i64) : i64
// CHECK: %[[BA:.*]] = llvm.mlir.addressof @[[B]] : !llvm.ptr
// CHECK: %[[LARGE:.*]] = llvm.ptrtoint %[[BA]] : !llvm.ptr to i64
// CHECK: llvm.mlir.addressof @[[BOX]] : !llvm.ptr
// CHECK-DAG: llvm.mlir.constant(1 : i8) : i8
// CHECK-DAG: llvm.mlir.constant(2.500000e+00 : f64) : f64
// CHECK-DAG: llvm.mlir.zero : i64
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  idr.data @Num {
    idr.ctor @I (i64)
    idr.ctor @D (f64)
  }
  func.func private @values() -> (!idr.str, !idr.str, !idr.big, !idr.big, !idr.box<@List>,
                                  !idr.data<@Num>) {
    %s1 = idr.constant "h\C3\A9!" : !idr.str
    %s2 = idr.constant "h\C3\A9!" : !idr.str
    %small = idr.constant #idr.big<"-43"> : !idr.big
    %large = idr.constant #idr.big<"-36893488147419103231"> : !idr.big
    %l = idr.constant #idr.con<@List::@Cons, [7, #idr.con<@List::@Nil, []>]> : !idr.box<@List>
    %n = idr.constant #idr.con<@Num::@D, [2.5 : f64]> : !idr.data<@Num>
    return %s1, %s2, %small, %large, %l, %n
        : !idr.str, !idr.str, !idr.big, !idr.big, !idr.box<@List>, !idr.data<@Num>
  }
  func.func @Prog.main() -> i64 {
    %v:6 = func.call @values() : () -> (!idr.str, !idr.str, !idr.big, !idr.big, !idr.box<@List>,
                                        !idr.data<@Num>)
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
