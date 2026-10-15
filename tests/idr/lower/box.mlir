// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@push:(i64,!llvm.ptr)->!llvm.ptr,signature=@first:(!llvm.ptr)->i64,calls-only=@push:[@idris_rt_cell],calls-only=@first:[],writes-nothing=@first,aligned-access' -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// A boxed constructor is a new cell: the runtime allocates it with its
// header (count 1, the info word: tag 1, one object slot, kind box), and its
// fields are stored at their offsets, the counted ones first: the header
// and the offsets are the runtime's layout, so they are checked as the
// words written. A match on a box reads the tag from the low bits of the
// info word, and each case its fields from the cell, writing nothing.
// CHECK-LABEL: func.func private @push(
// CHECK-SAME: %[[X:[^:]*]]: i64
// CHECK-SAME: %[[L:[^:]*]]: !llvm.ptr
// CHECK-DAG: %[[SIZE:.*]] = llvm.mlir.constant(24 : i64) : i64
// CHECK-DAG: %[[INFO:.*]] = llvm.mlir.constant(65537 : i32) : i32
// CHECK: %[[CELL:.*]] = llvm.call @idris_rt_cell(%[[SIZE]], %[[INFO]]) {{.*}}: (i64, i32) -> !llvm.ptr
// CHECK: %[[HEAD:.*]] = llvm.getelementptr %[[CELL]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %[[X]], %[[HEAD]] {{.*}}: i64, !llvm.ptr
// CHECK: %[[TAIL:.*]] = llvm.getelementptr %[[CELL]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %[[L]], %[[TAIL]] {{.*}}: !llvm.ptr, !llvm.ptr
// CHECK-LABEL: func.func private @first(
// CHECK-SAME: %[[F:[^:]*]]: !llvm.ptr
// CHECK: %[[TAGP:.*]] = llvm.getelementptr %[[F]][4] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[WORD:.*]] = llvm.load %[[TAGP]] {{.*}}: !llvm.ptr -> i32
// CHECK: %[[TAG:.*]] = llvm.and %[[WORD]], %{{.*}} : i32
// CHECK: arith.extui %[[TAG]] : i32 to i64
// CHECK: scf.index_switch
// CHECK: llvm.getelementptr %[[F]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.load %{{.*}} {{.*}}: !llvm.ptr -> i64
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @box root(@Prog.main) stage(first) {
  idr.func @push(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %l : !idr.box<!List>)
    return %c : !idr.box<!List>
  }
  idr.func @first(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %n = idr.con !idr.box<!List> @Nil()
    %one = arith.constant 1 : i64
    %l = idr.call @push(%one, %n) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %h = idr.call @first(%l) : (!idr.box<!List>) -> i64
    return %h : i64
  }
}
