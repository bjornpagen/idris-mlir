// RUN: idris-mlir-opt %s --idr-lower=jit=true | FileCheck %s
// A boxed constructor is a new cell: the runtime allocates it with its
// header (count 1, the info word: tag 1, one object slot, kind box), and its
// fields are stored at their offsets, the counted ones first. A match on a
// box reads the tag from the low bits of the info word, and each case its
// fields from the cell. A closure's cell holds its label, the address of its
// code and the captures; applying it calls the code with the closure first.
// The code loads the captures and calls the function with them before the
// arguments.
// Closures are lowered by idr-eval's lowering (jit) alone: the program's
// have all become sums.
// CHECK-LABEL: func.func private @push(
// CHECK-DAG: %[[SIZE:.*]] = llvm.mlir.constant(24 : i64) : i64
// CHECK-DAG: %[[INFO:.*]] = llvm.mlir.constant(65537 : i32) : i32
// CHECK: %[[CELL:.*]] = llvm.call @idris_rt_cell(%[[SIZE]], %[[INFO]]) : (i64, i32) -> !llvm.ptr
// CHECK: %[[HEAD:.*]] = llvm.getelementptr %[[CELL]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %arg0, %[[HEAD]] : i64, !llvm.ptr
// CHECK: %[[TAIL:.*]] = llvm.getelementptr %[[CELL]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %arg1, %[[TAIL]] : !llvm.ptr, !llvm.ptr
// CHECK-LABEL: func.func private @first(
// CHECK: %[[TAGP:.*]] = llvm.getelementptr %arg0[4] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[WORD:.*]] = llvm.load %[[TAGP]] : !llvm.ptr -> i32
// CHECK: %[[TAG:.*]] = llvm.and %[[WORD]], %{{.*}} : i32
// CHECK: arith.extui %[[TAG]] : i32 to i64
// CHECK: scf.index_switch
// CHECK: llvm.getelementptr %arg0[16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.load %{{.*}} : !llvm.ptr -> i64
// CHECK-LABEL: func.func private @adder(
// CHECK: %[[C:.*]] = llvm.call @idris_rt_cell(%{{.*}}, %{{.*}}) : (i64, i32) -> !llvm.ptr
// CHECK: %[[F:.*]] = constant @[[CODEFN:__idr_code_[0-9]+]] : (!llvm.ptr, i64) -> i64
// CHECK: %[[FP:.*]] = builtin.unrealized_conversion_cast %[[F]] : (!llvm.ptr, i64) -> i64 to !llvm.ptr
// CHECK: %[[CODE:.*]] = llvm.getelementptr %[[C]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %[[FP]], %[[CODE]] : !llvm.ptr, !llvm.ptr
// CHECK-LABEL: func.func private @run(
// CHECK: %[[CP:.*]] = llvm.getelementptr %arg0[8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[CODE2:.*]] = llvm.load %[[CP]] : !llvm.ptr -> !llvm.ptr
// CHECK: %[[FN:.*]] = builtin.unrealized_conversion_cast %[[CODE2]] : !llvm.ptr to (!llvm.ptr, i64) -> i64
// CHECK: call_indirect %[[FN]](%arg0, %arg1) : (!llvm.ptr, i64) -> i64
// CHECK: func.func private @[[CODEFN]](
// CHECK-SAME: %[[ENV:.*]]: !llvm.ptr, %[[X:.*]]: i64) -> i64
// CHECK: %[[K:.*]] = llvm.getelementptr %[[ENV]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[KV:.*]] = llvm.load %[[K]] : !llvm.ptr -> i64
// CHECK: call @add(%[[KV]], %[[X]]) : (i64, i64) -> i64
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil tag 0 ()
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>)
  }
  func.func private @push(%x: i64, %l: !idr.box<@List>) -> !idr.box<@List> {
    %c = idr.con @List::@Cons(%x, %l) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %c : !idr.box<@List>
  }
  func.func private @first(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func private @add(%k: i64, %x: i64) -> i64 {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @adder(%k: i64) -> !idr.fn<(i64) -> (i64)> {
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  func.func private @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %n = idr.con @List::@Nil() : () -> !idr.box<@List>
    %one = arith.constant 1 : i64
    %l = func.call @push(%one, %n) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %h = func.call @first(%l) : (!idr.box<@List>) -> i64
    %f = func.call @adder(%h) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = func.call @run(%f, %one) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}
