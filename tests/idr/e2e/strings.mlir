// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n "b" | %t > %t.out
// RUN: FileCheck %s < %t.out
// rule: LOW-STR-2, LOW-CONST-1, LOW-MATCH-1
// Operations that allocate nothing, on strings that exist (static data;
// PROF-PRIM-4):
// the length and the characters of a string picked at runtime, and a match
// on it.
// CHECK: 3 98 é 2
module attributes {idr.program} {
  func.func private @word(%c: i32) -> !idr.str {
    %r = idr.match_lit %c : i32 -> (!idr.str) {
    case 97 {
      %s = idr.constant "apple" : !idr.str
      idr.yield %s : !idr.str
    }
    default {
      %s = idr.constant "b\C3\A9e" : !idr.str
      idr.yield %s : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func private @rank(%s: !idr.str) -> i64 {
    %r = idr.match_lit %s : !idr.str -> (i64) {
    case "apple" {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    case "b\C3\A9e" {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %s = func.call @word(%c) : (i32) -> !idr.str
    %n = idr.str.length %s
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %sp = arith.constant 32 : i32
    %w3 = idr.io.put_char %sp, %w2
    %h = idr.str.head %s
    %w4 = idr.io.put_int signed %h, %w3 : i32
    %w5 = idr.io.put_char %sp, %w4
    %one = arith.constant 1 : i64
    %e = idr.str.index %s, %one
    %w6 = idr.io.put_char %e, %w5
    %w7 = idr.io.put_char %sp, %w6
    %r = func.call @rank(%s) : (!idr.str) -> i64
    %w8 = idr.io.put_int signed %r, %w7 : i64
    %nl = arith.constant 10 : i32
    %w9 = idr.io.put_char %nl, %w8
    return %w9 : !idr.world
  }
}
