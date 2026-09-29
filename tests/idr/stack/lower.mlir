// RUN: idris-mlir-opt %s --idr-stack --idr-lower > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %s --idr-stack --idr-lower=jit=true | FileCheck %s --check-prefix=JIT
// A cell idr-stack marks lives in a slot of its function's entry block and
// never comes from the allocator; its header, written where the con runs,
// has count 1 and the stack mark, bit 31 of the info word (so the word is
// negative as an i32). In a loop the slot is allocated once, before the
// loop. A cell that escapes comes from idris_rt_cell. In JIT mode every
// cell comes from the evaluation arena, marked or not.

// CHECK-LABEL: func.func private @local(
// CHECK-NEXT: llvm.mlir.constant(1 : i64)
// CHECK-NEXT: %[[SLOT:.*]] = llvm.alloca
// CHECK-NOT: idris_rt_cell
// CHECK-DAG: %[[INFO:.*]] = llvm.getelementptr %[[SLOT]][4]
// CHECK-DAG: %[[MARK:.*]] = llvm.mlir.constant(-{{[0-9]+}} : i32)
// CHECK: llvm.store %[[MARK]], %[[INFO]]
// CHECK-NOT: idris_rt_cell
// CHECK: return

// CHECK-LABEL: func.func private @loop(
// CHECK-NEXT: llvm.mlir.constant(1 : i64)
// CHECK-NEXT: llvm.alloca
// CHECK-NOT: idris_rt_cell
// CHECK: scf.while
// CHECK-NOT: llvm.alloca
// CHECK-NOT: idris_rt_cell
// CHECK: return

// CHECK-LABEL: func.func private @returned(
// CHECK-NOT: llvm.alloca
// CHECK: idris_rt_cell
// CHECK: return

// JIT-LABEL: func.func private @local(
// JIT-NOT: llvm.alloca
// JIT: idris_rt_arena_alloc
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil tag 0 ()
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>)
  }
  func.func private @head(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @local(%x: i64, %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = func.call @head(%c) : (!idr.box<@List>) -> i64
    return %r : i64
  }
  func.func private @loop(%n: i64, %t: !idr.box<@List>) -> i64 {
    %zero = arith.constant 0 : i64
    %r:2 = scf.while (%i = %n, %acc = %zero) : (i64, i64) -> (i64, i64) {
      %more = arith.cmpi ne, %i, %zero : i64
      scf.condition(%more) %i, %acc : i64, i64
    } do {
    ^bb0(%j: i64, %a: i64):
      %c = idr.con @List::@Cons(%j, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
      %h = func.call @head(%c) : (!idr.box<@List>) -> i64
      %b = arith.addi %a, %h : i64
      %one = arith.constant 1 : i64
      %m = arith.subi %j, %one : i64
      scf.yield %m, %b : i64, i64
    }
    return %r#1 : i64
  }
  func.func private @returned(%x: i64, %t: !idr.box<@List>) -> !idr.box<@List> {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %c : !idr.box<@List>
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
