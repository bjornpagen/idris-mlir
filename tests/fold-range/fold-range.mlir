// RUN: idris-mlir-opt %s --int-range-optimizations --idr-expect=holds=returns=@ranges:true/true/true/true/true/true,returns=@linear:true,returns=@field:_ -o /dev/null
// Tags, characters and lengths have known ranges, which
// upstream's integer range optimizations use.


!T = !idr.data<"T", plain [@A(), @B(), @C()]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(!idr.lin<i64>, !idr.lin<!idr.box<!idr.data<"L">>>) cons]>
idr.program @range root(@root) stage(first) {
  idr.func @ranges(%t: !T, %x: i64, %u: i8, %d: f64, %s: !idr.str)
      -> (i1, i1, i1, i1, i1, i1) {
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
    return %a, %b, %c, %e, %f, %g : i1, i1, i1, i1, i1, i1
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
  // their bodies and knows nothing of their arguments.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extsi %c : i32 to i64
    %u = arith.trunci %c : i32 to i8
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
    %r:6 = idr.call @ranges(%t, %x, %u, %d, %s) : (!T, i64, i8, f64, !idr.str) -> (i1, i1, i1, i1, i1, i1)
    %lr = idr.call @linear(%t) : (!T) -> i1
    %nil = idr.con !idr.box<!L> @Nil()
    %l = idr.lin.enter %nil : !idr.lin<!idr.box<!L>>
    %f = idr.call @field(%x, %l) : (i64, !idr.lin<!idr.box<!L>>) -> i64
    %w2 = idr.io.put_sint %f, %w1 : i64
    return %w2 : !idr.world
  }
}
