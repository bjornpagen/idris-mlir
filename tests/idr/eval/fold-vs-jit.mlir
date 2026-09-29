// RUN: idris-mlir-opt %s --inline --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval --canonicalize | FileCheck %s
// Every folder of a string or big op (and of double_head and int_head)
// against its lowering: each case calls a function of one op on constants.
// The first run inlines the call and folds the op, which calls the
// runtime's C in the compiler; the second evaluates the call, running the
// op's lowering through the JIT. Both must give the same constant, which the
// CHECK lines hold. The cases cover both signednesses, the widths that wrap,
// Doubles printed with ties and subnormals, the small and large bigs and
// their boundary, Euclidean division of negative bigs, correctly rounded
// casts, and non-ASCII strings.
module {
  func.func private @append(%a0: !idr.str, %a1: !idr.str) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.append %a0, %a1
    return %r : !idr.str
  }
  func.func private @cons(%a0: i32, %a1: !idr.str) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.cons %a0, %a1
    return %r : !idr.str
  }
  func.func private @from_char(%a0: i32) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.from_char %a0
    return %r : !idr.str
  }
  func.func private @show_s8(%a0: i8) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.show signed %a0 : i8
    return %r : !idr.str
  }
  func.func private @show_u8(%a0: i8) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.show %a0 : i8
    return %r : !idr.str
  }
  func.func private @show_s64(%a0: i64) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.show signed %a0 : i64
    return %r : !idr.str
  }
  func.func private @show_f64(%a0: f64) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.show %a0 : f64
    return %r : !idr.str
  }
  func.func private @substr(%a0: !idr.str, %a1: i64, %a2: i64) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.substr %a0, %a1, %a2
    return %r : !idr.str
  }
  func.func private @reverse(%a0: !idr.str) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.reverse %a0
    return %r : !idr.str
  }
  func.func private @tail(%a0: !idr.str) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.tail %a0
    return %r : !idr.str
  }
  func.func private @length(%a0: !idr.str) -> i64 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.length %a0
    return %r : i64
  }
  func.func private @index(%a0: !idr.str, %a1: i64) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.index %a0, %a1
    return %r : i32
  }
  func.func private @head(%a0: !idr.str) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.head %a0
    return %r : i32
  }
  func.func private @cmp_lt(%a0: !idr.str, %a1: !idr.str) -> i1 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.cmp lt %a0, %a1
    return %r : i1
  }
  func.func private @cmp_gte(%a0: !idr.str, %a1: !idr.str) -> i1 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.cmp gte %a0, %a1
    return %r : i1
  }
  func.func private @cmp_eq(%a0: !idr.str, %a1: !idr.str) -> i1 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.cmp eq %a0, %a1
    return %r : i1
  }
  func.func private @to_int16(%a0: !idr.str) -> i16 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.to_int signed %a0 : i16
    return %r : i16
  }
  func.func private @to_int64(%a0: !idr.str) -> i64 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.to_int signed %a0 : i64
    return %r : i64
  }
  func.func private @to_double(%a0: !idr.str) -> f64 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.to_double %a0
    return %r : f64
  }
  func.func private @big_add(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.add %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_sub(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.sub %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_mul(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.mul %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_div(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.div %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_mod(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.mod %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_and(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.and %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_or(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.or %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_xor(%a0: !idr.big, %a1: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.xor %a0, %a1
    return %r : !idr.big
  }
  func.func private @big_neg(%a0: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.neg %a0
    return %r : !idr.big
  }
  func.func private @big_cmp_gt(%a0: !idr.big, %a1: !idr.big) -> i1 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.cmp gt %a0, %a1
    return %r : i1
  }
  func.func private @big_cmp_lte(%a0: !idr.big, %a1: !idr.big) -> i1 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.cmp lte %a0, %a1
    return %r : i1
  }
  func.func private @big_from_u64(%a0: i64) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.from_int %a0 : i64
    return %r : !idr.big
  }
  func.func private @big_from_s8(%a0: i8) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.from_int signed %a0 : i8
    return %r : !idr.big
  }
  func.func private @big_to_i32(%a0: !idr.big) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.to_int %a0 : i32
    return %r : i32
  }
  func.func private @big_from_double(%a0: f64) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.from_double %a0
    return %r : !idr.big
  }
  func.func private @big_to_double(%a0: !idr.big) -> f64 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.to_double %a0
    return %r : f64
  }
  func.func private @big_show(%a0: !idr.big) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.show %a0
    return %r : !idr.str
  }
  func.func private @big_from_str(%a0: !idr.str) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.from_str %a0
    return %r : !idr.big
  }
  func.func private @double_head(%a0: f64) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.double_head %a0
    return %r : i32
  }
  func.func private @int_head_s32(%a0: i32) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.int_head signed %a0 : i32
    return %r : i32
  }
  func.func private @int_head_u8(%a0: i8) -> i32 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.int_head %a0 : i8
    return %r : i32
  }
  // CHECK-LABEL: func.func @case0(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "abc\C3\A9" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case0() -> !idr.str {
    %x0 = idr.constant "ab" : !idr.str
    %x1 = idr.constant "c\C3\A9" : !idr.str
    %r = func.call @append(%x0, %x1) : (!idr.str, !idr.str) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case1(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "x" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case1() -> !idr.str {
    %x0 = idr.constant "" : !idr.str
    %x1 = idr.constant "x" : !idr.str
    %r = func.call @append(%x0, %x1) : (!idr.str, !idr.str) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case2(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "\F0\9F\98\80x" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case2() -> !idr.str {
    %x0 = arith.constant 128512 : i32
    %x1 = idr.constant "x" : !idr.str
    %r = func.call @cons(%x0, %x1) : (i32, !idr.str) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case3(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "\C3\A9" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case3() -> !idr.str {
    %x0 = arith.constant 233 : i32
    %r = func.call @from_char(%x0) : (i32) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case4(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "-5" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case4() -> !idr.str {
    %x0 = arith.constant -5 : i8
    %r = func.call @show_s8(%x0) : (i8) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case5(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "251" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case5() -> !idr.str {
    %x0 = arith.constant -5 : i8
    %r = func.call @show_u8(%x0) : (i8) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case6(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "-9223372036854775808" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case6() -> !idr.str {
    %x0 = arith.constant -9223372036854775808 : i64
    %r = func.call @show_s64(%x0) : (i64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case7(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "1e22" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case7() -> !idr.str {
    %x0 = arith.constant 1.0e22 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case8(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "-0.0" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case8() -> !idr.str {
    %x0 = arith.constant -0.0 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case9(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "5e-324|1" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case9() -> !idr.str {
    %x0 = arith.constant 4.9406564584124654e-324 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case10(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "0.1" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case10() -> !idr.str {
    %x0 = arith.constant 0.1 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case11(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "0.001" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case11() -> !idr.str {
    %x0 = arith.constant 1.0e-3 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case12(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "123456789.125" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case12() -> !idr.str {
    %x0 = arith.constant 123456789.125 : f64
    %r = func.call @show_f64(%x0) : (f64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case13(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "\C3\A9ll" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case13() -> !idr.str {
    %x0 = idr.constant "h\C3\A9llo" : !idr.str
    %x1 = arith.constant 1 : i64
    %x2 = arith.constant 3 : i64
    %r = func.call @substr(%x0, %x1, %x2) : (!idr.str, i64, i64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case14(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "abc" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case14() -> !idr.str {
    %x0 = idr.constant "abc" : !idr.str
    %x1 = arith.constant -1 : i64
    %x2 = arith.constant 10 : i64
    %r = func.call @substr(%x0, %x1, %x2) : (!idr.str, i64, i64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case15(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case15() -> !idr.str {
    %x0 = idr.constant "abc" : !idr.str
    %x1 = arith.constant 5 : i64
    %x2 = arith.constant 1 : i64
    %r = func.call @substr(%x0, %x1, %x2) : (!idr.str, i64, i64) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case16(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "x\E8\AA\9E\E6\9C\AC\E6\97\A5" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case16() -> !idr.str {
    %x0 = idr.constant "\E6\97\A5\E6\9C\AC\E8\AA\9Ex" : !idr.str
    %r = func.call @reverse(%x0) : (!idr.str) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case17(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "\C3\A9llo" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case17() -> !idr.str {
    %x0 = idr.constant "h\C3\A9llo" : !idr.str
    %r = func.call @tail(%x0) : (!idr.str) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case18(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 3 : i64
  // CHECK-NEXT: return %[[V]] : i64
  func.func @case18() -> i64 {
    %x0 = idr.constant "\E6\97\A5\E6\9C\AC\E8\AA\9E" : !idr.str
    %r = func.call @length(%x0) : (!idr.str) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case19(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 233 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case19() -> i32 {
    %x0 = idr.constant "h\C3\A9llo" : !idr.str
    %x1 = arith.constant 1 : i64
    %r = func.call @index(%x0, %x1) : (!idr.str, i64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case20(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 233 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case20() -> i32 {
    %x0 = idr.constant "\C3\A9t\C3\A9" : !idr.str
    %r = func.call @head(%x0) : (!idr.str) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case21(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant true
  // CHECK-NEXT: return %[[V]] : i1
  func.func @case21() -> i1 {
    %x0 = idr.constant "a" : !idr.str
    %x1 = idr.constant "b" : !idr.str
    %r = func.call @cmp_lt(%x0, %x1) : (!idr.str, !idr.str) -> i1
    return %r : i1
  }
  // CHECK-LABEL: func.func @case22(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant true
  // CHECK-NEXT: return %[[V]] : i1
  func.func @case22() -> i1 {
    %x0 = idr.constant "b" : !idr.str
    %x1 = idr.constant "ab" : !idr.str
    %r = func.call @cmp_gte(%x0, %x1) : (!idr.str, !idr.str) -> i1
    return %r : i1
  }
  // CHECK-LABEL: func.func @case23(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant false
  // CHECK-NEXT: return %[[V]] : i1
  func.func @case23() -> i1 {
    %x0 = idr.constant "\C3\A9" : !idr.str
    %x1 = idr.constant "e" : !idr.str
    %r = func.call @cmp_eq(%x0, %x1) : (!idr.str, !idr.str) -> i1
    return %r : i1
  }
  // CHECK-LABEL: func.func @case24(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 4464 : i16
  // CHECK-NEXT: return %[[V]] : i16
  func.func @case24() -> i16 {
    %x0 = idr.constant "70000" : !idr.str
    %r = func.call @to_int16(%x0) : (!idr.str) -> i16
    return %r : i16
  }
  // CHECK-LABEL: func.func @case25(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -12 : i64
  // CHECK-NEXT: return %[[V]] : i64
  func.func @case25() -> i64 {
    %x0 = idr.constant "-12.7" : !idr.str
    %r = func.call @to_int64(%x0) : (!idr.str) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case26(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 1 : i64
  // CHECK-NEXT: return %[[V]] : i64
  func.func @case26() -> i64 {
    %x0 = idr.constant "18446744073709551617" : !idr.str
    %r = func.call @to_int64(%x0) : (!idr.str) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case27(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0 : i64
  // CHECK-NEXT: return %[[V]] : i64
  func.func @case27() -> i64 {
    %x0 = idr.constant " 1" : !idr.str
    %r = func.call @to_int64(%x0) : (!idr.str) -> i64
    return %r : i64
  }
  // CHECK-LABEL: func.func @case28(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0x7FF0000000000000 : f64
  // CHECK-NEXT: return %[[V]] : f64
  func.func @case28() -> f64 {
    %x0 = idr.constant "1e400" : !idr.str
    %r = func.call @to_double(%x0) : (!idr.str) -> f64
    return %r : f64
  }
  // CHECK-LABEL: func.func @case29(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -5.000000e-01 : f64
  // CHECK-NEXT: return %[[V]] : f64
  func.func @case29() -> f64 {
    %x0 = idr.constant "-0.5" : !idr.str
    %r = func.call @to_double(%x0) : (!idr.str) -> f64
    return %r : f64
  }
  // CHECK-LABEL: func.func @case30(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 5.000000e+00 : f64
  // CHECK-NEXT: return %[[V]] : f64
  func.func @case30() -> f64 {
    %x0 = idr.constant "+.5e1" : !idr.str
    %r = func.call @to_double(%x0) : (!idr.str) -> f64
    return %r : f64
  }
  // CHECK-LABEL: func.func @case31(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case31() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case32(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387912"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case32() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case33(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"5"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case33() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case34(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387903"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case34() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case35(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387906"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case35() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case36(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case36() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case37(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463463374607431768211454"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case37() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case38(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463467986293450195599362"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case38() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_add(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case39(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-10"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case39() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case40(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387898"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case40() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case41(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case41() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case42(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387907"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case42() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case43(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387900"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case43() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case44(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"9223372036854775808"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case44() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case45(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463463374607431768211460"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case45() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case46(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463458762921413340823552"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case46() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_sub(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case47(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-21"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case47() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case48(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"32281802128991715335"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case48() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case49(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"6"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case49() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case50(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-9223372036854775810"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case50() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case51(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"13835058055282163709"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case51() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case52(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-21267647932558653966460912964485513215"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case52() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case53(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-1020847100762815390390123822295304634371"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case53() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case54(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1569275433846670191299229722722855067493575154566204227585"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case54() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mul(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case55(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-3"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case55() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case56(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case56() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case57(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"0"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case57() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case58(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"0"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case58() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case59(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1537228672809129301"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case59() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case60(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"0"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case60() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case61(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-113427455640312821154458202477256070486"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case61() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case62(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"73786976294838206449"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case62() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_div(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case63(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case63() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case64(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387898"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case64() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case65(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case65() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case66(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case66() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case67(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"0"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case67() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case68(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387903"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case68() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case69(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case69() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case70(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387888"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case70() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_mod(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case71(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case71() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case72(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387911"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case72() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case73(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case73() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case74(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case74() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case75(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"3"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case75() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case76(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387903"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case76() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case77(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"3"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case77() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case78(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463467986293450195599361"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case78() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_and(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case79(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-5"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case79() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case80(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case80() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case81(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"3"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case81() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case82(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case82() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case83(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387903"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case83() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case84(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case84() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case85(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case85() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case86(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case86() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_or(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case87(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-6"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case87() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case88(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387910"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case88() -> !idr.big {
    %x0 = idr.constant #idr.big<"-7"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case89(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"1"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case89() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case90(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-4611686018427387907"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case90() -> !idr.big {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case91(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387900"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case91() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case92(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-9223372036854775808"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case92() -> !idr.big {
    %x0 = idr.constant #idr.big<"4611686018427387903"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case93(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-340282366920938463463374607431768211460"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case93() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"3"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case94(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"340282366920938463467986293450195599360"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case94() -> !idr.big {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %x1 = idr.constant #idr.big<"-4611686018427387905"> : !idr.big
    %r = func.call @big_xor(%x0, %x1) : (!idr.big, !idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case95(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"4611686018427387904"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case95() -> !idr.big {
    %x0 = idr.constant #idr.big<"-4611686018427387904"> : !idr.big
    %r = func.call @big_neg(%x0) : (!idr.big) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case96(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant true
  // CHECK-NEXT: return %[[V]] : i1
  func.func @case96() -> i1 {
    %x0 = idr.constant #idr.big<"2"> : !idr.big
    %x1 = idr.constant #idr.big<"-100000000000000000000"> : !idr.big
    %r = func.call @big_cmp_gt(%x0, %x1) : (!idr.big, !idr.big) -> i1
    return %r : i1
  }
  // CHECK-LABEL: func.func @case97(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant true
  // CHECK-NEXT: return %[[V]] : i1
  func.func @case97() -> i1 {
    %x0 = idr.constant #idr.big<"100000000000000000000"> : !idr.big
    %x1 = idr.constant #idr.big<"100000000000000000000"> : !idr.big
    %r = func.call @big_cmp_lte(%x0, %x1) : (!idr.big, !idr.big) -> i1
    return %r : i1
  }
  // CHECK-LABEL: func.func @case98(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"18446744073709551615"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case98() -> !idr.big {
    %x0 = arith.constant -1 : i64
    %r = func.call @big_from_u64(%x0) : (i64) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case99(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-128"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case99() -> !idr.big {
    %x0 = arith.constant -128 : i8
    %r = func.call @big_from_s8(%x0) : (i8) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case100(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 1 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case100() -> i32 {
    %x0 = idr.constant #idr.big<"4294967297"> : !idr.big
    %r = func.call @big_to_i32(%x0) : (!idr.big) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case101(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant -1 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case101() -> i32 {
    %x0 = idr.constant #idr.big<"-340282366920938463463374607431768211457"> : !idr.big
    %r = func.call @big_to_i32(%x0) : (!idr.big) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case102(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"100000000000000000000"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case102() -> !idr.big {
    %x0 = arith.constant 1.0e20 : f64
    %r = func.call @big_from_double(%x0) : (f64) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case103(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-2"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case103() -> !idr.big {
    %x0 = arith.constant -2.5 : f64
    %r = func.call @big_from_double(%x0) : (f64) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case104(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0x4340000000000000 : f64
  // CHECK-NEXT: return %[[V]] : f64
  func.func @case104() -> f64 {
    %x0 = idr.constant #idr.big<"9007199254740993"> : !idr.big
    %r = func.call @big_to_double(%x0) : (!idr.big) -> f64
    return %r : f64
  }
  // CHECK-LABEL: func.func @case105(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 0xFFF0000000000000 : f64
  // CHECK-NEXT: return %[[V]] : f64
  func.func @case105() -> f64 {
    %x0 = idr.constant #idr.big<"-179769313486231580793728971405303415079934132710037826936173778980444968292764750946649017977587207096330286416692887910946555547851940402630657488671505820681908902000708383676273854845817711531764475730270069855571366959622842914819860834936475292719074168444365510704342711559699508093042880177904174497792"> : !idr.big
    %r = func.call @big_to_double(%x0) : (!idr.big) -> f64
    return %r : f64
  }
  // CHECK-LABEL: func.func @case106(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant "-123456789012345678901234567890" : !idr.str
  // CHECK-NEXT: return %[[V]] : !idr.str
  func.func @case106() -> !idr.str {
    %x0 = idr.constant #idr.big<"-123456789012345678901234567890"> : !idr.big
    %r = func.call @big_show(%x0) : (!idr.big) -> !idr.str
    return %r : !idr.str
  }
  // CHECK-LABEL: func.func @case107(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"0"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case107() -> !idr.big {
    %x0 = idr.constant "  12" : !idr.str
    %r = func.call @big_from_str(%x0) : (!idr.str) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case108(
  // CHECK-NEXT: %[[V:[^ ]+]] = idr.constant #idr.big<"-123"> : !idr.big
  // CHECK-NEXT: return %[[V]] : !idr.big
  func.func @case108() -> !idr.big {
    %x0 = idr.constant "-000123" : !idr.str
    %r = func.call @big_from_str(%x0) : (!idr.str) -> !idr.big
    return %r : !idr.big
  }
  // CHECK-LABEL: func.func @case109(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 45 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case109() -> i32 {
    %x0 = arith.constant -1.5 : f64
    %r = func.call @double_head(%x0) : (f64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case110(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 43 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case110() -> i32 {
    %x0 = arith.constant 0x7FF8000000000000 : f64
    %r = func.call @double_head(%x0) : (f64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case111(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 48 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case111() -> i32 {
    %x0 = arith.constant 0.25 : f64
    %r = func.call @double_head(%x0) : (f64) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case112(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 45 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case112() -> i32 {
    %x0 = arith.constant -7 : i32
    %r = func.call @int_head_s32(%x0) : (i32) -> i32
    return %r : i32
  }
  // CHECK-LABEL: func.func @case113(
  // CHECK-NEXT: %[[V:[^ ]+]] = arith.constant 50 : i32
  // CHECK-NEXT: return %[[V]] : i32
  func.func @case113() -> i32 {
    %x0 = arith.constant -56 : i8
    %r = func.call @int_head_u8(%x0) : (i8) -> i32
    return %r : i32
  }
}

