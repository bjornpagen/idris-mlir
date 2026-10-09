// RUN: idris-mlir-opt %s --idr-lower > %t.mlir
// RUN: FileCheck %s --implicit-check-not='llvm.mlir.global private @' < %t.mlir
// RUN: FileCheck %s --check-prefix=CELL < %t.mlir
// RUN: FileCheck %s --check-prefix=STREAM < %t.mlir
// A lazy constant is a memo cell in static data, which its first force
// writes, once: a global that is not constant, whose info word says the
// thunk kind (1 << 24) with its label's tag, here 0. Every other static
// cell stays constant, among them a constant stream whose tail is that
// cell: it holds the cell's address. @__idr_release_cafs releases what each
// such cell holds once forced, when the program ends.
// CHECK: llvm.mlir.global private @[[CAF:__idr_caf_[0-9]+]]()
// CHECK-LABEL: func.func private @__idr_release_cafs()
// CHECK-NEXT: %[[A:.*]] = llvm.mlir.addressof @[[CAF]] : !llvm.ptr
// CHECK-NEXT: llvm.call @idris_rt_caf_release(%[[A]]) : (!llvm.ptr) -> ()
// CHECK-NEXT: return
// CELL: llvm.mlir.global private @__idr_caf_{{[0-9]+}}()
// CELL-NOT: llvm.mlir.global
// CELL: llvm.mlir.constant(16777216 : i32) : i32
// STREAM: llvm.mlir.global private constant @__idr_box_{{[0-9]+}}()
// STREAM-NOT: llvm.mlir.global
// STREAM: llvm.mlir.addressof @__idr_caf_{{[0-9]+}} : !llvm.ptr
// STREAM-NOT: llvm.mlir.global
// STREAM: llvm.return
module attributes {idr.program} {
  idr.data @lazy$0 box memo labels [@ones] {
    idr.ctor @ones ()
    idr.ctor @running ()
    idr.ctor @forced (!idr.box<@Stream>)
  }
  idr.data @Stream box {
    idr.ctor @Cons (i64, !idr.box<@lazy$0>)
  }
  // ones = 1 :: ones: its tail is the thunk of the definition itself.
  func.func private @ones() -> !idr.box<@Stream> attributes {idr.total} {
    %s = idr.constant #idr.con<@Stream::@Cons, [1, #idr.con<@lazy$0::@ones, []>]> : !idr.box<@Stream>
    return %s : !idr.box<@Stream>
  }
  func.func @Prog.main() -> i64 {
    %s = func.call @ones() : () -> !idr.box<@Stream>
    %t = idr.field %s[@Cons, 1] : !idr.box<@Stream> -> !idr.box<@lazy$0>
    %u = idr.force %t : !idr.box<@lazy$0> -> !idr.box<@Stream>
    %h = idr.field %u[@Cons, 0] : !idr.box<@Stream> -> i64
    return %h : i64
  }
}
