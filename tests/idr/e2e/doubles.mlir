// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s
// Doubles printed by the runtime: the shortest digits that read back, an
// exact tie to the even last digit (1.1258999068426242e15, where Chez takes
// the larger), positional between 1e-3 and 1e10, a subnormal as any other,
// the special values as IEEE 754 spells them; and the cast to an integer
// truncates and wraps (2^64 is 0).
// CHECK: 1.1258999068426242e15
// CHECK-NEXT: 5e-324
// CHECK-NEXT: 2.2250738585072014e-308
// CHECK-NEXT: 0.001
// CHECK-NEXT: 9999999999.0
// CHECK-NEXT: 1e10
// CHECK-NEXT: -0.0
// CHECK-NEXT: nan
// CHECK-NEXT: -inf
// CHECK-NEXT: -2 0 7
module attributes {idr.program} {
  func.func private @line(%x: f64, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.put_double %x, %w
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
  func.func private @pass(%x: f64) -> f64 {
    return %x : f64
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %t = arith.constant 1125899906842624.25 : f64
    %w1 = func.call @line(%t, %w) : (f64, !idr.world) -> !idr.world
    %s = arith.constant 4.9406564584124654e-324 : f64
    %w2 = func.call @line(%s, %w1) : (f64, !idr.world) -> !idr.world
    %m = arith.constant 2.2250738585072014e-308 : f64
    %w3 = func.call @line(%m, %w2) : (f64, !idr.world) -> !idr.world
    %a = arith.constant 1.0e-3 : f64
    %w4 = func.call @line(%a, %w3) : (f64, !idr.world) -> !idr.world
    %b = arith.constant 9999999999.0 : f64
    %w5 = func.call @line(%b, %w4) : (f64, !idr.world) -> !idr.world
    %c = arith.constant 1.0e10 : f64
    %w6 = func.call @line(%c, %w5) : (f64, !idr.world) -> !idr.world
    %z = arith.constant -0.0 : f64
    %w7 = func.call @line(%z, %w6) : (f64, !idr.world) -> !idr.world
    %nan = arith.constant 0xFFF8000000000000 : f64
    %w8 = func.call @line(%nan, %w7) : (f64, !idr.world) -> !idr.world
    %inf = arith.constant 0xFFF0000000000000 : f64
    %w9 = func.call @line(%inf, %w8) : (f64, !idr.world) -> !idr.world
    %x = arith.constant -2.75 : f64
    %xr = func.call @pass(%x) : (f64) -> f64
    %i = idr.to_int %xr : i64
    %w10 = idr.io.put_int signed %i, %w9 : i64
    %sp = arith.constant 32 : i32
    %w11 = idr.io.put_char %sp, %w10
    %big = arith.constant 1.8446744073709552e19 : f64
    %br = func.call @pass(%big) : (f64) -> f64
    %j = idr.to_int %br : i8
    %w12 = idr.io.put_int signed %j, %w11 : i8
    %w13 = idr.io.put_char %sp, %w12
    %seven = arith.constant 7.9 : f64
    %sr = func.call @pass(%seven) : (f64) -> f64
    %k = idr.to_int %sr : i16
    %w14 = idr.io.put_int signed %k, %w13 : i16
    %nl = arith.constant 10 : i32
    %w15 = idr.io.put_char %nl, %w14
    return %w15 : !idr.world
  }
}
