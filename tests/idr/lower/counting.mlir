// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// The counting ops call the runtime on each counted component: a string's
// pointer, a big's word (as a pointer), each counted slot of a sum. A take
// of a box yields its cell when it is exclusive, and otherwise gives each
// field a reference and drops the box's; a token that is dropped has its
// memory freed; a reuse builds in the token, or in a new cell when it is
// null.
// CHECK-LABEL: func.func private @counts(
// CHECK-SAME: %[[S:[^:]*]]: !llvm.ptr{{( \{[^}]*\})?}}, %{{[^:]*}}: i8{{( \{[^}]*\})?}}, %[[D:[^:]*]]: !llvm.ptr{{( \{[^}]*\})?}}, %{{[^:]*}}: i64, %[[N:[^:]*]]: i64)
// CHECK: llvm.call @idris_rt_inc(%[[S]]) {{.*}}: (!llvm.ptr) -> ()
// CHECK: llvm.call @idris_rt_dec(%[[D]]) {{.*}}: (!llvm.ptr) -> ()
// CHECK: %[[B:.*]] = llvm.inttoptr %[[N]] : i64 to !llvm.ptr
// CHECK: llvm.call @idris_rt_dec(%[[B]]) {{.*}}: (!llvm.ptr) -> ()
// CHECK-LABEL: func.func private @unused(
// An unused counted slot is empty.
// CHECK: llvm.mlir.zero : !llvm.ptr
// CHECK-LABEL: func.func private @drop(
// CHECK: %[[T:.*]] = scf.if %{{.*}} -> (!llvm.ptr) {
// CHECK-NEXT: scf.yield %arg0 : !llvm.ptr
// CHECK-NEXT: } else {
// CHECK: llvm.call @idris_rt_inc(
// CHECK: llvm.call @idris_rt_dec(%arg0) {{.*}}: (!llvm.ptr) -> ()
// CHECK: llvm.call @idris_rt_free_cell(%[[T]]) {{.*}}: (!llvm.ptr) -> ()
// CHECK-LABEL: func.func private @rebuild(
// CHECK: %[[W:.*]] = scf.if %{{.*}} -> (!llvm.ptr) {
// CHECK: %[[NULL:.*]] = llvm.icmp "eq" %[[W]], %{{.*}} : !llvm.ptr
// CHECK: scf.if %[[NULL]] -> (!llvm.ptr) {
// CHECK: llvm.call @idris_rt_cell(
// CHECK: } else {
// CHECK: llvm.store %{{.*}}, %[[W]]{{.*}} {{.*}}: i32, !llvm.ptr
module attributes {idr.program, idr.stage = "owned"} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.data @S {
    idr.ctor @A (!idr.str)
    idr.ctor @B (i64)
  }
  func.func private @counts(%s: !idr.str, %d: !idr.data<@S>, %b: !idr.big) -> (!idr.str, !idr.str) {
    idr.inc %s : !idr.str
    idr.dec %d : !idr.data<@S>
    idr.dec %b : !idr.big
    return %s, %s : !idr.str, !idr.str
  }
  func.func private @unused(%x: i64) -> !idr.data<@S> {
    %d = idr.con @S::@B(%x) : (i64) -> !idr.data<@S>
    return %d : !idr.data<@S>
  }
  func.func private @drop(%l: !idr.box<@L>) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.box<@L> -> (!idr.token, i64, !idr.box<@L>)
      idr.dec %w#2 : !idr.box<@L>
      idr.dec %w#0 : !idr.token
      idr.yield %h : i64
    }
    default {
      idr.dec %l : !idr.box<@L>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func private @rebuild(%l: !idr.box<@L>) -> !idr.box<@L> {
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.box<@L> -> (!idr.token, i64, !idr.box<@L>)
      %c = idr.reuse %w#0 @L::@C(%w#1, %w#2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    default {
      idr.yield %l : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
