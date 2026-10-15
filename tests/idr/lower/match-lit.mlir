// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@byte:[],call-order=@word:[@idris_rt_str_cmp,@idris_rt_str_cmp],call-order=@nat:[@idris_rt_big_cmp,@idris_rt_big_sub]' -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded (R04), so the checks are of the counted program; confirm them against it.
// An integer literal match is a switch on the key's zero-extended bits, so
// the byte -1 is the case 255, and asks the runtime for nothing; a string
// or big match compares with each key in turn, in the else branch of the
// comparison before, then takes the default: one comparison by the
// runtime for each key.
// CHECK-LABEL: func.func private @byte(
// CHECK: scf.index_switch
// CHECK: case 1 {
// CHECK: case 255 {
// CHECK: default {
idr.program @"match-lit" root(@Prog.main) stage(first) {
  idr.func @byte(%b: i8) -> i64 {
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
  idr.func @word(%s: !idr.str) -> i64 {
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
  idr.func @nat(%n: !idr.big) -> !idr.big {
    %r = idr.match_lit %n : !idr.big -> (!idr.big) {
    case #idr.big<0> {
      idr.yield %n : !idr.big
    }
    default {
      %one = idr.constant #idr.big<1> : !idr.big
      %p = idr.big.sub %n, %one
      idr.yield %p : !idr.big
    }
    }
    return %r : !idr.big
  }
  idr.func @Prog.main() -> i64 {
    %b = arith.constant 1 : i8
    %r = idr.call @byte(%b) : (i8) -> i64
    %s = idr.constant "two" : !idr.str
    %t = idr.call @word(%s) : (!idr.str) -> i64
    %n = idr.constant #idr.big<3> : !idr.big
    %p = idr.call @nat(%n) : (!idr.big) -> !idr.big
    %sum = arith.addi %r, %t : i64
    return %sum : i64
  }
}
