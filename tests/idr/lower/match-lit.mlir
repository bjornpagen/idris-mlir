// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// An integer literal match is a switch on the key's zero-extended bits; a
// string or big match compares with each key in turn, in the else branch of
// the comparison before, then takes the default.
// CHECK-LABEL: func.func private @byte(
// CHECK: %[[W:.*]] = arith.extui %{{.*}} : i8 to i64
// CHECK: %[[I:.*]] = arith.index_castui %[[W]] : i64 to index
// CHECK: scf.index_switch %[[I]] -> i64
// CHECK: case 1 {
// CHECK: case 255 {
// CHECK: default {
// CHECK-LABEL: func.func private @word(
// CHECK: %[[A:.*]] = llvm.mlir.addressof @__idr_str_{{[0-9]+}} : !llvm.ptr
// CHECK: %[[C:.*]] = llvm.call @idris_rt_str_cmp(%{{.*}}, %[[A]]) : (!llvm.ptr, !llvm.ptr) -> i32
// CHECK: %[[E:.*]] = arith.cmpi eq, %[[C]], %{{.*}} : i32
// CHECK: scf.if %[[E]] -> (i64) {
// CHECK: } else {
// CHECK: llvm.call @idris_rt_str_cmp
// CHECK: scf.if
// CHECK-LABEL: func.func private @nat(
// CHECK: %[[Z:.*]] = llvm.mlir.constant(1 : i64) : i64
// CHECK: llvm.call @idris_rt_big_cmp(%{{.*}}, %[[Z]]) : (i64, i64) -> i32
// CHECK: scf.if
// CHECK: llvm.call @idris_rt_big_sub
module attributes {idr.program} {
  func.func private @byte(%b: i8) -> i64 {
    %r = idr.match_lit %b : i8 -> (i64) {
    case 1 {
      %x = arith.constant 10 : i64
      idr.yield %x : i64
    }
    case -1 {
      %x = arith.constant 20 : i64
      idr.yield %x : i64
    }
    default {
      %x = arith.constant 30 : i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @word(%s: !idr.str) -> i64 {
    %r = idr.match_lit %s : !idr.str -> (i64) {
    case "one" {
      %x = arith.constant 1 : i64
      idr.yield %x : i64
    }
    case "two" {
      %x = arith.constant 2 : i64
      idr.yield %x : i64
    }
    default {
      %x = arith.constant 0 : i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @nat(%n: !idr.big) -> !idr.big {
    %r = idr.match_lit %n : !idr.big -> (!idr.big) {
    case #idr.big<"0"> {
      idr.yield %n : !idr.big
    }
    default {
      %one = idr.constant #idr.big<"1"> : !idr.big
      %p = idr.big.sub %n, %one
      idr.yield %p : !idr.big
    }
    }
    return %r : !idr.big
  }
  func.func @Prog.main() -> i64 {
    %b = arith.constant 1 : i8
    %r = func.call @byte(%b) : (i8) -> i64
    %s = idr.constant "two" : !idr.str
    %t = func.call @word(%s) : (!idr.str) -> i64
    %n = idr.constant #idr.big<"3"> : !idr.big
    %p = func.call @nat(%n) : (!idr.big) -> !idr.big
    %sum = arith.addi %r, %t : i64
    return %sum : i64
  }
}
