// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.lowered.mlir
// RUN: idris-mlir -c %t.lowered.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '\007' | %t | FileCheck %s --match-full-lines
// RUN: %differential %s %t.lowered.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.lowered.mlir
// What a module holds decides where idris-mlir sends it, never an option:
// the pipeline's output, a module of the LLVM dialect alone, goes to LLVM
// as it is, so a module idris-mlir-opt lowered is linked and run by the
// real backend. The program it makes is the program: of the byte b it
// reads, it prints the area of a circle of b (3b^2) for an even b and of
// a b by b + 1 rectangle for an odd one, 56 for 7, on every one-byte input
// as the module as written compiled by idris-mlir does and as the
// reference at the end (REF), with no shape, does (%differential).
// CHECK: 56
!Shape = !idr.data<"Shape", plain [@Circle(i64), @Rect(i64, i64)]>
idr.program @"lowered-input" root(@Prog.main) stage(higher) {
  idr.func @area(%s: !Shape) -> i64 {
    %r = idr.match %s : !Shape -> (i64) {
    case @Circle(%x: i64) {
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      idr.yield %a : i64
    }
    case @Rect(%w: i64, %h: i64) {
      %b = arith.muli %w, %h : i64
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %two = arith.constant 2 : i64
    %parity = arith.remui %b, %two : i64
    %s = idr.match_lit %parity : i64 -> (!Shape) {
    case 0 {
      %circle = idr.con !Shape @Circle(%b : i64)
      idr.yield %circle : !Shape
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %h = arith.addi %b, %one : i64
      %rect = idr.con !Shape @Rect(%b : i64, %h : i64)
      idr.yield %rect : !Shape
    }
    }
    %a = idr.call @area(%s) : (!Shape) -> i64
    %w2 = idr.io.put_sint %a, %w1 : i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %b = arith.extui %c : i32 to i64
// REF:     %one = arith.constant 1 : i64
// REF:     %three = arith.constant 3 : i64
// REF:     %odd = arith.trunci %c : i32 to i1
// REF:     %h = arith.addi %b, %one : i64
// REF:     %bb = arith.muli %b, %b : i64
// REF:     %circle = arith.muli %three, %bb : i64
// REF:     %rect = arith.muli %b, %h : i64
// REF:     %a = arith.select %odd, %rect, %circle : i64
// REF:     %w2 = idr.io.put_sint %a, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
