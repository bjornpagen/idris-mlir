// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s --match-full-lines --implicit-check-not={{.}}
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize --canonicalize '--idr-expect=holds=calls=@Prog.main:@fact,calls=@Prog.main:@dashes' -o /dev/null
// A closed call of a pure, total function stays in the module, through the
// optimizer, as a call of it or of a copy (each named by its function's
// location, as Emit names it), and runs at run time, to its value: at each
// recursion's base (fact 0, dashes of 0), one step past it, 20!, the
// largest factorial an Int holds, and 21!, which wraps; and the dashes
// between copies of a string, the empty one too.
// CHECK: 3628800 x-x-x
// CHECK-NEXT: 1 1 2432902008176640000 -4249290049419214848
// CHECK-NEXT: x ---
idr.program @eval root(@Prog.main) stage(higher) {
  idr.func @fact(%n: i64) -> i64 attributes {total, no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = idr.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  } loc("fact")
  idr.func @dashes(%s: !idr.str, %n: i64) -> !idr.str attributes {total, no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      idr.yield %s : !idr.str
    }
    default(%k: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = idr.call @dashes(%s, %m) : (!idr.str, i64) -> !idr.str
      %dash = arith.constant 45 : i32
      %d = idr.str.cons %dash, %rest
      %x = idr.str.append %s, %d
      idr.yield %x : !idr.str
    }
    }
    return %r : !idr.str
  } loc("dashes")
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %sp = arith.constant 32 : i32
    %nl = arith.constant 10 : i32
    %ten = arith.constant 10 : i64
    %f = idr.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_sint %f, %w : i64
    %w2 = idr.io.put_char %sp, %w1
    %x = idr.constant !idr.str "x"
    %two = arith.constant 2 : i64
    %s = idr.call @dashes(%x, %two) : (!idr.str, i64) -> !idr.str
    %w3 = idr.io.put_str %s, %w2
    %w4 = idr.io.put_char %nl, %w3
    %zero = arith.constant 0 : i64
    %f0 = idr.call @fact(%zero) : (i64) -> i64
    %w5 = idr.io.put_sint %f0, %w4 : i64
    %w6 = idr.io.put_char %sp, %w5
    %one = arith.constant 1 : i64
    %f1 = idr.call @fact(%one) : (i64) -> i64
    %w7 = idr.io.put_sint %f1, %w6 : i64
    %w8 = idr.io.put_char %sp, %w7
    %twenty = arith.constant 20 : i64
    %f20 = idr.call @fact(%twenty) : (i64) -> i64
    %w9 = idr.io.put_sint %f20, %w8 : i64
    %w10 = idr.io.put_char %sp, %w9
    %twentyone = arith.constant 21 : i64
    %f21 = idr.call @fact(%twentyone) : (i64) -> i64
    %w11 = idr.io.put_sint %f21, %w10 : i64
    %w12 = idr.io.put_char %nl, %w11
    %s0 = idr.call @dashes(%x, %zero) : (!idr.str, i64) -> !idr.str
    %w13 = idr.io.put_str %s0, %w12
    %w14 = idr.io.put_char %sp, %w13
    %e = idr.constant !idr.str ""
    %three = arith.constant 3 : i64
    %s3 = idr.call @dashes(%e, %three) : (!idr.str, i64) -> !idr.str
    %w15 = idr.io.put_str %s3, %w14
    %w16 = idr.io.put_char %nl, %w15
    return %w16 : !idr.world
  }
}
