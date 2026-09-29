// RUN: idris-mlir-opt %s --inline --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval --canonicalize | FileCheck %s
// The scalar folders against their lowerings, as fold-vs-jit.mlir does for
// strings and bigs: the first run inlines each call and folds the op in C++,
// the second evaluates the call through the JIT, running the op's lowering.
// Both must give the constants the CHECK lines hold (Euclidean division, MIN div -1, wrapping truncation of doubles, invalid scalars).
module {
  func.func private @div_s64(%a0: i64, %a1: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.div signed %a0, %a1 : i64
    return %r : i64
  }
  func.func private @mod_s64(%a0: i64, %a1: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.mod signed %a0, %a1 : i64
    return %r : i64
  }
  func.func private @div_u8(%a0: i8, %a1: i8) -> i8 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.div %a0, %a1 : i8
    return %r : i8
  }
  func.func private @mod_u8(%a0: i8, %a1: i8) -> i8 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.mod %a0, %a1 : i8
    return %r : i8
  }
  func.func private @to_char_s64(%a0: i64) -> i32 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.to_char signed %a0 : i64
    return %r : i32
  }
  func.func private @to_char_u8(%a0: i8) -> i32 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.to_char %a0 : i8
    return %r : i32
  }
  func.func private @to_int_i64(%a0: f64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.to_int %a0 : i64
    return %r : i64
  }
  func.func private @to_int_i8(%a0: f64) -> i8 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %r = idr.to_int %a0 : i8
    return %r : i8
  }
  // CHECK-LABEL: func.func @case0(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -4 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case0() -> i64 {
    %x0 = arith.constant -7 : i64
    %x1 = arith.constant 2 : i64
    %r = func.call @div_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case1(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -3 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case1() -> i64 {
    %x0 = arith.constant 7 : i64
    %x1 = arith.constant -2 : i64
    %r = func.call @div_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case2(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 4 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case2() -> i64 {
    %x0 = arith.constant -7 : i64
    %x1 = arith.constant -2 : i64
    %r = func.call @div_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case3(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -9223372036854775808 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case3() -> i64 {
    %x0 = arith.constant -9223372036854775808 : i64
    %x1 = arith.constant -1 : i64
    %r = func.call @div_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case4(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 1 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case4() -> i64 {
    %x0 = arith.constant -7 : i64
    %x1 = arith.constant 2 : i64
    %r = func.call @mod_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case5(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 1 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case5() -> i64 {
    %x0 = arith.constant -7 : i64
    %x1 = arith.constant -2 : i64
    %r = func.call @mod_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case6(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 1 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case6() -> i64 {
    %x0 = arith.constant 7 : i64
    %x1 = arith.constant -2 : i64
    %r = func.call @mod_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case7(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case7() -> i64 {
    %x0 = arith.constant -9223372036854775808 : i64
    %x1 = arith.constant -1 : i64
    %r = func.call @mod_s64(%x0, %x1) : (i64, i64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case8(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 35 : i8
  // CHECK-NEXT: return %[[V]]
  func.func @case8() -> i8 {
    %x0 = arith.constant -6 : i8
    %x1 = arith.constant 7 : i8
    %r = func.call @div_u8(%x0, %x1) : (i8, i8) -> i8
    return %r : i8
  }
  // CHECK-LABEL: func.func @case9(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 5 : i8
  // CHECK-NEXT: return %[[V]]
  func.func @case9() -> i8 {
    %x0 = arith.constant -6 : i8
    %x1 = arith.constant 7 : i8
    %r = func.call @mod_u8(%x0, %x1) : (i8, i8) -> i8
    return %r : i8
  }
  // CHECK-LABEL: func.func @case10(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 65 : i32
  // CHECK-NEXT: return %[[V]]
  func.func @case10() -> i32 {
    %x0 = arith.constant 65 : i64
    %r = func.call @to_char_s64(%x0) : (i64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case11(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0 : i32
  // CHECK-NEXT: return %[[V]]
  func.func @case11() -> i32 {
    %x0 = arith.constant 1114112 : i64
    %r = func.call @to_char_s64(%x0) : (i64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case12(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0 : i32
  // CHECK-NEXT: return %[[V]]
  func.func @case12() -> i32 {
    %x0 = arith.constant 55296 : i64
    %r = func.call @to_char_s64(%x0) : (i64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case13(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0 : i32
  // CHECK-NEXT: return %[[V]]
  func.func @case13() -> i32 {
    %x0 = arith.constant -1 : i64
    %r = func.call @to_char_s64(%x0) : (i64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case14(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 255 : i32
  // CHECK-NEXT: return %[[V]]
  func.func @case14() -> i32 {
    %x0 = arith.constant -1 : i8
    %r = func.call @to_char_u8(%x0) : (i8) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case15(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -2 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case15() -> i64 {
    %x0 = arith.constant -2.75 : f64
    %r = func.call @to_int_i64(%x0) : (f64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case16(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 7766279631452241920 : i64
  // CHECK-NEXT: return %[[V]]
  func.func @case16() -> i64 {
    %x0 = arith.constant 1.0e+20 : f64
    %r = func.call @to_int_i64(%x0) : (f64) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case17(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 44 : i8
  // CHECK-NEXT: return %[[V]]
  func.func @case17() -> i8 {
    %x0 = arith.constant 300.5 : f64
    %r = func.call @to_int_i8(%x0) : (f64) -> i8
    return %r : i8
  }
  // CHECK-LABEL: func.func @case18(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 127 : i8
  // CHECK-NEXT: return %[[V]]
  func.func @case18() -> i8 {
    %x0 = arith.constant -129.0 : f64
    %r = func.call @to_int_i8(%x0) : (f64) -> i8
    return %r : i8
  }
}
