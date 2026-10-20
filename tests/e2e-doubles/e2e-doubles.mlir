// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s --match-full-lines --implicit-check-not={{.}}
// Doubles printed by the runtime: the shortest digits that read back, an
// exact tie to the even last digit; positional from 1e-3 up to below 1e10,
// with a fraction always (1.0), and in exponent form outside, with no
// fraction when one digit is enough (1e10), an exponent of no sign but
// its minus and no leading zero; a subnormal as any other; -0.0 with its
// sign; the special values as IEEE 754 spells them, NaN without a sign.
// Each value is its own line, at both ends of each form, and nothing else
// is printed. Then the cast to an integer truncates and wraps (2^64 is 0).
// CHECK: 1.1258999068426242e15
// CHECK-NEXT: 5e-324
// CHECK-NEXT: 2.225073858507201e-308
// CHECK-NEXT: 2.2250738585072014e-308
// CHECK-NEXT: 9.999999999999998e-4
// CHECK-NEXT: 0.001
// CHECK-NEXT: 0.00123
// CHECK-NEXT: 0.1
// CHECK-NEXT: 0.30000000000000004
// CHECK-NEXT: 0.0
// CHECK-NEXT: -0.0
// CHECK-NEXT: 1.0
// CHECK-NEXT: -1.5
// CHECK-NEXT: 4.35
// CHECK-NEXT: 100.0
// CHECK-NEXT: 123456.789
// CHECK-NEXT: 9999999999.0
// CHECK-NEXT: 9999999999.999998
// CHECK-NEXT: 1e10
// CHECK-NEXT: 9.007199254740992e15
// CHECK-NEXT: 1e16
// CHECK-NEXT: 1e21
// CHECK-NEXT: 1e23
// CHECK-NEXT: 1.7976931348623157e308
// CHECK-NEXT: 1e-5
// CHECK-NEXT: -1e-300
// CHECK-NEXT: nan
// CHECK-NEXT: nan
// CHECK-NEXT: inf
// CHECK-NEXT: -inf
// CHECK-NEXT: -2 0 7
idr.program @doubles root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @line(%x: f64, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.put_double %x, %w
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
  idr.func @pass(%x: f64) -> f64 {
    return %x : f64
  }
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    // an exact tie, to the even last digit
    %d0 = arith.constant 1125899906842624.25 : f64
    %w1 = idr.call @line(%d0, %w0) : (f64, !idr.world) -> !idr.world
    // the smallest subnormal
    %d1 = arith.constant 4.9406564584124654e-324 : f64
    %w2 = idr.call @line(%d1, %w1) : (f64, !idr.world) -> !idr.world
    // the largest subnormal, shortest in 16 digits
    %d2 = arith.constant 2.2250738585072009e-308 : f64
    %w3 = idr.call @line(%d2, %w2) : (f64, !idr.world) -> !idr.world
    // the smallest normal
    %d3 = arith.constant 2.2250738585072014e-308 : f64
    %w4 = idr.call @line(%d3, %w3) : (f64, !idr.world) -> !idr.world
    // the largest Double below 1e-3
    %d4 = arith.constant 9.999999999999998e-4 : f64
    %w5 = idr.call @line(%d4, %w4) : (f64, !idr.world) -> !idr.world
    // 1e-3, the first positional
    %d5 = arith.constant 1.0e-3 : f64
    %w6 = idr.call @line(%d5, %w5) : (f64, !idr.world) -> !idr.world
    %d6 = arith.constant 0.00123 : f64
    %w7 = idr.call @line(%d6, %w6) : (f64, !idr.world) -> !idr.world
    %d7 = arith.constant 0.1 : f64
    %w8 = idr.call @line(%d7, %w7) : (f64, !idr.world) -> !idr.world
    // 0.1 + 0.2
    %d8 = arith.constant 0.30000000000000004 : f64
    %w9 = idr.call @line(%d8, %w8) : (f64, !idr.world) -> !idr.world
    %d9 = arith.constant 0.0 : f64
    %w10 = idr.call @line(%d9, %w9) : (f64, !idr.world) -> !idr.world
    %d10 = arith.constant -0.0 : f64
    %w11 = idr.call @line(%d10, %w10) : (f64, !idr.world) -> !idr.world
    %d11 = arith.constant 1.0 : f64
    %w12 = idr.call @line(%d11, %w11) : (f64, !idr.world) -> !idr.world
    %d12 = arith.constant -1.5 : f64
    %w13 = idr.call @line(%d12, %w12) : (f64, !idr.world) -> !idr.world
    %d13 = arith.constant 4.35 : f64
    %w14 = idr.call @line(%d13, %w13) : (f64, !idr.world) -> !idr.world
    %d14 = arith.constant 100.0 : f64
    %w15 = idr.call @line(%d14, %w14) : (f64, !idr.world) -> !idr.world
    %d15 = arith.constant 123456.789 : f64
    %w16 = idr.call @line(%d15, %w15) : (f64, !idr.world) -> !idr.world
    %d16 = arith.constant 9999999999.0 : f64
    %w17 = idr.call @line(%d16, %w16) : (f64, !idr.world) -> !idr.world
    // the largest Double below 1e10, the last positional
    %d17 = arith.constant 9999999999.999998 : f64
    %w18 = idr.call @line(%d17, %w17) : (f64, !idr.world) -> !idr.world
    // 1e10, the first in exponent form
    %d18 = arith.constant 1.0e10 : f64
    %w19 = idr.call @line(%d18, %w18) : (f64, !idr.world) -> !idr.world
    // 2^53 + 1, which is 2^53
    %d19 = arith.constant 9007199254740993.0 : f64
    %w20 = idr.call @line(%d19, %w19) : (f64, !idr.world) -> !idr.world
    %d20 = arith.constant 1.0e16 : f64
    %w21 = idr.call @line(%d20, %w20) : (f64, !idr.world) -> !idr.world
    %d21 = arith.constant 1.0e21 : f64
    %w22 = idr.call @line(%d21, %w21) : (f64, !idr.world) -> !idr.world
    // whose nearest Double prints as 1e23
    %d22 = arith.constant 1.0e23 : f64
    %w23 = idr.call @line(%d22, %w22) : (f64, !idr.world) -> !idr.world
    // the largest Double
    %d23 = arith.constant 1.7976931348623157e308 : f64
    %w24 = idr.call @line(%d23, %w23) : (f64, !idr.world) -> !idr.world
    %d24 = arith.constant 1.0e-5 : f64
    %w25 = idr.call @line(%d24, %w24) : (f64, !idr.world) -> !idr.world
    %d25 = arith.constant -1.0e-300 : f64
    %w26 = idr.call @line(%d25, %w25) : (f64, !idr.world) -> !idr.world
    // NaN
    %d26 = arith.constant 0x7FF8000000000000 : f64
    %w27 = idr.call @line(%d26, %w26) : (f64, !idr.world) -> !idr.world
    // NaN with its sign set
    %d27 = arith.constant 0xFFF8000000000000 : f64
    %w28 = idr.call @line(%d27, %w27) : (f64, !idr.world) -> !idr.world
    // infinity
    %d28 = arith.constant 0x7FF0000000000000 : f64
    %w29 = idr.call @line(%d28, %w28) : (f64, !idr.world) -> !idr.world
    // -infinity
    %d29 = arith.constant 0xFFF0000000000000 : f64
    %w30 = idr.call @line(%d29, %w29) : (f64, !idr.world) -> !idr.world
    %x = arith.constant -2.75 : f64
    %xr = idr.call @pass(%x) : (f64) -> f64
    %i = idr.to_int %xr : i64
    %v1 = idr.io.put_sint %i, %w30 : i64
    %sp = arith.constant 32 : i32
    %v2 = idr.io.put_char %sp, %v1
    %big = arith.constant 1.8446744073709552e19 : f64
    %br = idr.call @pass(%big) : (f64) -> f64
    %j = idr.to_int %br : i8
    %v3 = idr.io.put_sint %j, %v2 : i8
    %v4 = idr.io.put_char %sp, %v3
    %seven = arith.constant 7.9 : f64
    %sr = idr.call @pass(%seven) : (f64) -> f64
    %k = idr.to_int %sr : i16
    %v5 = idr.io.put_sint %k, %v4 : i16
    %nl = arith.constant 10 : i32
    %v6 = idr.io.put_char %nl, %v5
    return %v6 : !idr.world
  }
}
