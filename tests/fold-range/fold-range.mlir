// RUN: idris-mlir-opt %s --int-range-optimizations --idr-expect=holds=returns=@ranges:true/true/true/true/true/true/_/_,returns=@linear:true,returns=@field:_ -o /dev/null
// RUN: idris-mlir-opt %s --int-range-optimizations -o %t.ranged.mlir
// RUN: %differential %s %t.ranged.mlir
// Tags, characters and lengths have known ranges, which
// upstream's integer range optimizations use. A bound one inside the
// range decides nothing: a tag of three constructors may be 2, and a
// character U+10FFFF.
//
// The decisions are right on every input: the program, which prints
// every comparison, means the same before the optimizations and after,
// which idris-mlir's own pipeline does not run, on the empty input and
// every byte, read as a signed byte so that values of each sign reach
// every function.


!T = !idr.data<"T", plain [@A(), @B(), @C()]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(!idr.lin<i64>, !idr.lin<!idr.box<!idr.data<"L">>>) cons]>
idr.program @range root(@root) stage(first) {
  idr.func @ranges(%t: !T, %x: i64, %u: i8, %d: f64, %s: !idr.str)
      -> (i1, i1, i1, i1, i1, i1, i1, i1) {
    %three = arith.constant 3 : i64
    %tag = idr.tag %t : !T
    %a = arith.cmpi ult, %tag, %three : i64
    %max = arith.constant 1114111 : i32
    %ch = idr.to_char_s %x : i64
    %b = arith.cmpi ule, %ch, %max : i32
    %zero = arith.constant 48 : i32
    %minus = arith.constant 45 : i32
    %ih = idr.int_head_s %x : i64
    %c = arith.cmpi sge, %ih, %minus : i32
    %uh = idr.int_head_u %u : i8
    %e = arith.cmpi sge, %uh, %zero : i32
    %dh = idr.double_head %d
    %f = arith.cmpi sge, %dh, %minus : i32
    %len = idr.str.length %s
    %z = arith.constant 0 : i64
    %g = arith.cmpi sge, %len, %z : i64
    %two = arith.constant 2 : i64
    %h = arith.cmpi ult, %tag, %two : i64
    %near = arith.constant 1114110 : i32
    %k = arith.cmpi ule, %ch, %near : i32
    return %a, %b, %c, %e, %f, %g, %h, %k : i1, i1, i1, i1, i1, i1, i1, i1
  }

  // A grade is no barrier to the analysis: a linear tag entered and used has
  // the tag's range.
  idr.func @linear(%t: !T) -> i1 {
    %three = arith.constant 3 : i64
    %tag = idr.tag %t : !T
    %l = idr.lin.enter %tag : !idr.lin<i64>
    %u = idr.lin.use %l : !idr.lin<i64>
    %a = arith.cmpi ult, %u, %three : i64
    return %a : i1
  }

  // A linear field a match binds is a value the analysis never saw computed:
  // it may be any i64, and arithmetic on it keeps its own width.

  idr.func @field(%acc: i64, %l: !idr.lin<!idr.box<!L>>) -> i64 {
    %r = idr.match %l : !idr.lin<!idr.box<!L>> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%h: !idr.lin<i64>, %t: !idr.lin<!idr.box<!L>>) {
      %x = idr.lin.use %h : !idr.lin<i64>
      %s = arith.addi %acc, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // The root calls each function on values read at run time, so that
  // upstream's dataflow, which analyses only what it finds live, reaches
  // their bodies and knows nothing of their arguments, and prints what
  // each gives.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %u = arith.trunci %c : i32 to i8
    %x = arith.extsi %u : i8 to i64
    %d = arith.sitofp %x : i64 to f64
    %s = idr.str.show_sint %x : i64
    %t = idr.match_lit %x : i64 -> (!T) {
    case 0 {
      %a = idr.con !T @A()
      idr.yield %a : !T
    }
    case 1 {
      %b = idr.con !T @B()
      idr.yield %b : !T
    }
    default(%k: i64) {
      %e = idr.con !T @C()
      idr.yield %e : !T
    }
    }
    %r:8 = idr.call @ranges(%t, %x, %u, %d, %s) : (!T, i64, i8, f64, !idr.str) -> (i1, i1, i1, i1, i1, i1, i1, i1)
    %lr = idr.call @linear(%t) : (!T) -> i1
    %nil = idr.con !idr.box<!L> @Nil()
    %l = idr.lin.enter %nil : !idr.lin<!idr.box<!L>>
    %f = idr.call @field(%x, %l) : (i64, !idr.lin<!idr.box<!L>>) -> i64
    %w2 = idr.io.put_sint %f, %w1 : i64
    %r0 = arith.extui %r#0 : i1 to i64
    %r1 = arith.extui %r#1 : i1 to i64
    %r2 = arith.extui %r#2 : i1 to i64
    %r3 = arith.extui %r#3 : i1 to i64
    %r4 = arith.extui %r#4 : i1 to i64
    %r5 = arith.extui %r#5 : i1 to i64
    %r6 = arith.extui %r#6 : i1 to i64
    %r7 = arith.extui %r#7 : i1 to i64
    %r8 = arith.extui %lr : i1 to i64
    %w3 = idr.io.put_sint %r0, %w2 : i64
    %w4 = idr.io.put_sint %r1, %w3 : i64
    %w5 = idr.io.put_sint %r2, %w4 : i64
    %w6 = idr.io.put_sint %r3, %w5 : i64
    %w7 = idr.io.put_sint %r4, %w6 : i64
    %w8 = idr.io.put_sint %r5, %w7 : i64
    %w9 = idr.io.put_sint %r6, %w8 : i64
    %w10 = idr.io.put_sint %r7, %w9 : i64
    %w11 = idr.io.put_sint %r8, %w10 : i64
    return %w11 : !idr.world
  }
}
