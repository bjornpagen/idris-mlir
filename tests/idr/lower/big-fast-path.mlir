// RUN: idris-mlir-opt %s --idr-lower=jit=true --canonicalize --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts \
// RUN:   | mlir-translate --mlir-to-llvmir | opt -O2 -S | FileCheck %s
// The small case of every big and natural op is inline, and the runtime is
// called only on the cold path. Stated through LLVM: where the operands are
// small by construction (integers narrower than the small range) and the
// result fits, the optimized function calls no big function at all; where
// they may be anything, the call is there, behind a branch weighted against
// it.
// CHECK-LABEL: define {{.*}} @sum(
// CHECK-NOT: @idris_rt_big
// CHECK-NOT: @idris_rt_nat
// CHECK: ret
// CHECK-LABEL: define {{.*}} @difference(
// CHECK-NOT: @idris_rt_big
// CHECK: ret
// CHECK-LABEL: define {{.*}} @product(
// CHECK-NOT: @idris_rt_big
// CHECK: ret
// CHECK-LABEL: define {{.*}} @compared(
// CHECK-NOT: @idris_rt_big
// CHECK: ret
// CHECK-LABEL: define {{.*}} @naturals(
// CHECK-NOT: @idris_rt_big
// CHECK-NOT: @idris_rt_nat
// CHECK: ret
// CHECK-LABEL: define {{.*}} @unknown(
// CHECK: br i1 {{.*}}, !prof
// CHECK: call {{.*}} @idris_rt_big_add(
// CHECK: ret
module {
  func.func @sum(%x: i32, %y: i32) -> i64 {
    %a = idr.big.from_int signed %x : i32
    %b = idr.big.from_int signed %y : i32
    %s = idr.big.add %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  func.func @difference(%x: i32, %y: i8) -> i64 {
    %a = idr.big.from_int signed %x : i32
    %b = idr.big.from_int %y : i8
    %s = idr.big.sub %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  func.func @product(%x: i32, %y: i16) -> i64 {
    %a = idr.big.from_int signed %x : i32
    %b = idr.big.from_int signed %y : i16
    %s = idr.big.mul %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  func.func @compared(%x: i32, %y: i32) -> i1 {
    %a = idr.big.from_int signed %x : i32
    %b = idr.big.from_int signed %y : i32
    %lt = idr.big.cmp lt %a, %b
    %eq = idr.big.cmp eq %a, %b
    %r = arith.xori %lt, %eq : i1
    return %r : i1
  }
  // The clamp of an Integer, one more, and its predecessor: all natural.
  func.func @naturals(%x: i32) -> i64 {
    %a = idr.big.from_int signed %x : i32
    %n = idr.nat.from_big %a
    %one = idr.constant #idr.big<"1"> : !idr.nat
    %s = idr.big.add %n, %one : !idr.nat
    %p = idr.big.pred %s
    %i = idr.nat.to_big %p
    %r = idr.big.to_int %i : i64
    return %r : i64
  }
  func.func @unknown(%a: !idr.big, %b: !idr.big) -> !idr.big {
    %s = idr.big.add %a, %b
    return %s : !idr.big
  }
}
