// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=calls=@Main.main:@digits -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls=@Main.main:@digitsTotal -o /dev/null
// Raising takes the output of a string into a copy of the callee that
// builds it, where the output runs at each level of the recursion, before
// the levels around it end. @digits writes a number's digits, and on 7 it
// loops for ever: Idris has no proof that it ends, so its effects say it
// may not. Raised, a call of it would write the leading digits of a number
// whose last level never ends, where the program as written writes
// nothing; so its call stays, and builds the string the output takes.
// @digitsTotal is the same function with that proof, and its call is
// raised: no call of it by its own name is left.
// Both programs write the same on every input they are run on: the bytes
// below, none of them a number whose digits reach 7 (%differential runs
// no program that does not end).
// STDIN: \0000
// STDIN: \0011
// STDIN: \0144
// STDIN: \0377
idr.program @"may-not-end" root(@Main.main) stage(higher) {
  idr.func @digits(%n: i64) -> !idr.str {
    %ten = arith.constant 10 : i64
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 7 {
      %again = idr.call @digits(%n) : (i64) -> !idr.str
      idr.yield %again : !idr.str
    }
    default(%m: i64) {
      %small = arith.cmpi slt, %m, %ten : i64
      %b = arith.extui %small : i1 to i64
      %t = idr.match_lit %b : i64 -> (!idr.str) {
      case 1 {
        %d = idr.str.show_sint %m : i64
        idr.yield %d : !idr.str
      }
      default(%z: i64) {
        %q = arith.divsi %m, %ten : i64
        %r = arith.remsi %m, %ten : i64
        %rest = idr.call @digits(%q) : (i64) -> !idr.str
        %last = idr.str.show_sint %r : i64
        %both = idr.str.append %rest, %last
        idr.yield %both : !idr.str
      }
      }
      idr.yield %t : !idr.str
    }
    }
    return %s : !idr.str
  }
  idr.func @digitsTotal(%n: i64) -> !idr.str attributes {total} {
    %ten = arith.constant 10 : i64
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    default(%m: i64) {
      %small = arith.cmpi slt, %m, %ten : i64
      %b = arith.extui %small : i1 to i64
      %t = idr.match_lit %b : i64 -> (!idr.str) {
      case 1 {
        %d = idr.str.show_sint %m : i64
        idr.yield %d : !idr.str
      }
      default(%z: i64) {
        %q = arith.divsi %m, %ten : i64
        %r = arith.remsi %m, %ten : i64
        %rest = idr.call @digitsTotal(%q) : (i64) -> !idr.str
        %last = idr.str.show_sint %r : i64
        %both = idr.str.append %rest, %last
        idr.yield %both : !idr.str
      }
      }
      idr.yield %t : !idr.str
    }
    }
    return %s : !idr.str
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %s = idr.call @digits(%n) : (i64) -> !idr.str
    %w2 = idr.io.put_str %s, %w1
    %nl = arith.constant 10 : i32
    %w3 = idr.io.put_char %nl, %w2
    %t = idr.call @digitsTotal(%n) : (i64) -> !idr.str
    %w4 = idr.io.put_str %t, %w3
    %w5 = idr.io.put_char %nl, %w4
    return %w5 : !idr.world
  }
}
