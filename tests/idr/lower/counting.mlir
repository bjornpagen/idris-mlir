// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// The counting ops call the runtime on each counted component: a string's
// pointer, a big's word (as a pointer), each counted slot of a sum. A take
// of a box yields its cell when it is exclusive, and otherwise gives each
// field a reference and drops the box's; a token that is dropped has its
// memory freed; a reuse builds in the token, or in a new cell when it is
// null.
// CHECK-LABEL: func.func private @counts(
// CHECK-SAME: %[[S:[^:]*]]: !llvm.ptr {{.*}}, %{{[^:]*}}: i8 {{.*}}, %[[D:[^:]*]]: !llvm.ptr, %{{[^:]*}}: i64, %[[N:[^:]*]]: i64)
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
// A reference to static data (a constant box, a constant string) runs
// nothing: static data holds no count.
// CHECK-LABEL: func.func private @static(
// CHECK-NOT: llvm.call @idris_rt_inc
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
  func.func private @counts(%s: !idr.str, %d: !idr.own<!idr.data<@S>>, %b: !idr.own<!idr.big>) -> !idr.own<!idr.str> {
    %o = idr.dup %s : !idr.str
    idr.drop %d : !idr.own<!idr.data<@S>>
    idr.drop %b : !idr.own<!idr.big>
    return %o : !idr.own<!idr.str>
  }
  func.func private @unused(%x: i64) -> !idr.own<!idr.data<@S>> {
    %d = idr.con @S::@B(%x) : (i64) -> !idr.own<!idr.data<@S>>
    return %d : !idr.own<!idr.data<@S>>
  }
  func.func private @drop(%l: !idr.own<!idr.box<@L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<@L>>
    %r = idr.match %v : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
      idr.drop %w#2 : !idr.own<!idr.box<@L>>
      idr.drop %w#0 : !idr.own<!idr.token>
      idr.yield %h : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<@L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func private @static(%x: i64) -> (!idr.own<!idr.box<@L>>, !idr.own<!idr.str>) {
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %s = idr.constant "static" : !idr.str
    %r = idr.match_lit %x : i64 -> (!idr.own<!idr.box<@L>>) {
    case 0 {
      %o = idr.dup %n : !idr.box<@L>
      idr.yield %o : !idr.own<!idr.box<@L>>
    }
    default {
      %o = idr.dup %n : !idr.box<@L>
      %c = idr.con @L::@C(%x, %o) : (i64, !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>>
      idr.yield %c : !idr.own<!idr.box<@L>>
    }
    }
    %t = idr.dup %s : !idr.str
    return %r, %t : !idr.own<!idr.box<@L>>, !idr.own<!idr.str>
  }
  func.func private @rebuild(%l: !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<@L>>
    %r = idr.match %v : !idr.box<@L> -> (!idr.own<!idr.box<@L>>) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
      %c = idr.reuse %w#0 @L::@C(%w#1, %w#2) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>>
      idr.yield %c : !idr.own<!idr.box<@L>>
    }
    default {
      idr.yield %l : !idr.own<!idr.box<@L>>
    }
    }
    return %r : !idr.own<!idr.box<@L>>
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
