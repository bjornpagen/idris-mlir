// RUN: idris-mlir-opt %s --idr-tail-calls | FileCheck %s
// What idr-tail-calls takes for a call in tail position on a cycle of calls,
// which it makes a guaranteed tail call, and what it leaves a call. @hub
// calls each function tested, and each callee calls @hub back: all of them
// are on one cycle. The caller and the callee of a tail call take tailcc;
// every other function keeps C's convention: @entry, whose address is
// taken, @main, which is public, and those with no tail call on a cycle.

// The return right after the call (@direct), the result taken apart and
// put back together (@repacked), carried to the return by a branch
// (@joined), and by the exit of a loop whose flag the path passes as a
// constant (@exits): each a tail call, with the return right after it.
// CHECK-LABEL: llvm.func tailcc @leaf(
// CHECK-LABEL: llvm.func tailcc @pair(
// CHECK-LABEL: llvm.func tailcc @step(
// CHECK-LABEL: llvm.func tailcc @direct(
// CHECK: llvm.call tailcc musttail @leaf(
// CHECK-NEXT: llvm.return
// CHECK-LABEL: llvm.func tailcc @repacked(
// CHECK: llvm.call tailcc musttail @pair(
// CHECK-NEXT: llvm.return
// CHECK-LABEL: llvm.func tailcc @joined(
// CHECK: llvm.call tailcc musttail @leaf(
// CHECK-NEXT: llvm.return
// CHECK-LABEL: llvm.func tailcc @exits(
// CHECK: llvm.call tailcc musttail @step(
// CHECK-NEXT: llvm.return
// A call whose result the path changes (@changed), or after which another
// call runs (@followed), is no tail call.
// CHECK-LABEL: llvm.func @changed(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @followed(
// CHECK-NOT: musttail
// CHECK: llvm.return
// A call that may reach its caller's frame stays a call: it takes a slot of
// the frame (@slot), or a pointer read from one (@read), or a pointer into
// the frame was written outside it (@leaked).
// CHECK-LABEL: llvm.func @load(
// CHECK-LABEL: llvm.func @slot(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @read(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @leaked(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @hub(
// A call in tail position from one cycle to another (@off, of @below,
// which never calls back) keeps the caller's frame once at most: it stays
// a call, and both keep C's convention.
// CHECK-LABEL: llvm.func @below(
// CHECK-LABEL: llvm.func @off(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @entry(
// CHECK-NOT: musttail
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @main(
module {
  llvm.func @leaf(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %h = llvm.call @hub(%y) : (i64) -> i64
    %s = llvm.add %h, %one : i64
    llvm.return %s : i64
  ^stop:
    llvm.return %x : i64
  }
  llvm.func @pair(%x: i64) -> !llvm.struct<(i64, i64)> attributes {sym_visibility = "private"} {
    %h = llvm.call @leaf(%x) : (i64) -> i64
    %u = llvm.mlir.poison : !llvm.struct<(i64, i64)>
    %a = llvm.insertvalue %h, %u[0] : !llvm.struct<(i64, i64)>
    %b = llvm.insertvalue %x, %a[1] : !llvm.struct<(i64, i64)>
    llvm.return %b : !llvm.struct<(i64, i64)>
  }
  llvm.func @step(%x: i64) attributes {sym_visibility = "private"} {
    %h = llvm.call @leaf(%x) : (i64) -> i64
    llvm.return
  }
  llvm.func @direct(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @leaf(%x) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @repacked(%x: i64) -> !llvm.struct<(i64, i64)> attributes {sym_visibility = "private"} {
    %r = llvm.call @pair(%x) : (i64) -> !llvm.struct<(i64, i64)>
    %a = llvm.extractvalue %r[0] : !llvm.struct<(i64, i64)>
    %b = llvm.extractvalue %r[1] : !llvm.struct<(i64, i64)>
    %u = llvm.mlir.poison : !llvm.struct<(i64, i64)>
    %c = llvm.insertvalue %a, %u[0] : !llvm.struct<(i64, i64)>
    %d = llvm.insertvalue %b, %c[1] : !llvm.struct<(i64, i64)>
    llvm.return %d : !llvm.struct<(i64, i64)>
  }
  llvm.func @joined(%x: i64, %c: i1) -> i64 attributes {sym_visibility = "private"} {
    llvm.cond_br %c, ^call, ^other
  ^call:
    %r = llvm.call @leaf(%x) : (i64) -> i64
    llvm.br ^join(%r : i64)
  ^other:
    llvm.br ^join(%x : i64)
  ^join(%v: i64):
    llvm.return %v : i64
  }
  llvm.func @exits(%x: i64) attributes {sym_visibility = "private"} {
    %true = llvm.mlir.constant(true) : i1
    %false = llvm.mlir.constant(false) : i1
    %zero = llvm.mlir.constant(0 : i64) : i64
    llvm.br ^head(%x : i64)
  ^head(%i: i64):
    %done = llvm.icmp "eq" %i, %zero : i64
    llvm.cond_br %done, ^exit, ^again
  ^again:
    %one = llvm.mlir.constant(1 : i64) : i64
    %j = llvm.sub %i, %one : i64
    llvm.br ^latch(%true, %j : i1, i64)
  ^exit:
    llvm.call @step(%i) : (i64) -> ()
    llvm.br ^latch(%false, %zero : i1, i64)
  ^latch(%go: i1, %k: i64):
    llvm.cond_br %go, ^head(%k : i64), ^out
  ^out:
    llvm.return
  }
  llvm.func @changed(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @leaf(%x) : (i64) -> i64
    %one = llvm.mlir.constant(1 : i64) : i64
    %s = llvm.add %r, %one : i64
    llvm.return %s : i64
  }
  llvm.func @followed(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @leaf(%x) : (i64) -> i64
    llvm.call @step(%x) : (i64) -> ()
    llvm.return %r : i64
  }
  llvm.func @load(%p: !llvm.ptr) -> i64 attributes {sym_visibility = "private"} {
    %v = llvm.load %p : !llvm.ptr -> i64
    %h = llvm.call @leaf(%v) : (i64) -> i64
    %s = llvm.add %h, %v : i64
    llvm.return %s : i64
  }
  llvm.func @slot(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %s = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    llvm.store %x, %s : i64, !llvm.ptr
    %r = llvm.call @load(%s) : (!llvm.ptr) -> i64
    llvm.return %r : i64
  }
  llvm.func @read(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %inner = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    %outer = llvm.alloca %one x !llvm.ptr : (i64) -> !llvm.ptr
    llvm.store %x, %inner : i64, !llvm.ptr
    llvm.store %inner, %outer : !llvm.ptr, !llvm.ptr
    %p = llvm.load %outer : !llvm.ptr -> !llvm.ptr
    %r = llvm.call @load(%p) : (!llvm.ptr) -> i64
    llvm.return %r : i64
  }
  llvm.func @leaked(%x: i64, %heap: !llvm.ptr) -> i64 attributes {sym_visibility = "private"} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %s = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    llvm.store %x, %s : i64, !llvm.ptr
    llvm.store %s, %heap : !llvm.ptr, !llvm.ptr
    %r = llvm.call @load(%heap) : (!llvm.ptr) -> i64
    llvm.return %r : i64
  }
  llvm.func @hub(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %true = llvm.mlir.constant(true) : i1
    %null = llvm.mlir.zero : !llvm.ptr
    %a = llvm.call @direct(%x) : (i64) -> i64
    %p = llvm.call @repacked(%a) : (i64) -> !llvm.struct<(i64, i64)>
    %b = llvm.extractvalue %p[0] : !llvm.struct<(i64, i64)>
    %c = llvm.call @joined(%b, %true) : (i64, i1) -> i64
    llvm.call @exits(%c) : (i64) -> ()
    %d = llvm.call @changed(%c) : (i64) -> i64
    %e = llvm.call @followed(%d) : (i64) -> i64
    %f = llvm.call @slot(%e) : (i64) -> i64
    %g = llvm.call @read(%f) : (i64) -> i64
    %h = llvm.call @leaked(%g, %null) : (i64, !llvm.ptr) -> i64
    %s = llvm.add %h, %x : i64
    llvm.return %s : i64
  }
  llvm.func @below(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %s = llvm.add %x, %one : i64
    llvm.return %s : i64
  }
  llvm.func @off(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @below(%x) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @entry(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @leaf(%x) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @main() -> i64 {
    %f = llvm.mlir.addressof @entry : !llvm.ptr
    %x = llvm.ptrtoint %f : !llvm.ptr to i64
    %a = llvm.call @hub(%x) : (i64) -> i64
    %b = llvm.call @off(%a) : (i64) -> i64
    llvm.return %b : i64
  }
}
