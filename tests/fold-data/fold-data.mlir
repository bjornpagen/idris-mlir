// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@constant_con:(#idr.con<!idr.data<"S">,@B,[1,"x"]>)/(#idr.con<!idr.data<"L">,@Cons,[2,#idr.con<!idr.data<"L">,@Nil,[]>]>),returns=@known:1/_/"y",returns=@of_constant:7/1/(#idr.con<!idr.data<"L">,@Nil,[]>),returns=@unknown:_/_/0,returns=@cse:#idr.big<12345678901234567890>/#idr.big<12345678901234567890>,folded=@folded' -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/\[-1 : i64, "y"\]/[-2 : i64, "y"]/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// Constructors of constants fold to constants; fields and tags of known
// constructors fold. A pass option ends at a space, so the constants are
// written without one.
//
// The values as the lowering lays them out, read at run time, are the
// oracle for every row of the table: each row folds in its own region
// (@folded), and is computed at run time from the row the byte read chose
// (@at_run_time, which the sed makes the program's). On the byte of each
// row, and on the empty input for the last, the two print the same: the
// row's operands, then its results; each operand is printed as well as
// used, so that no op on it is its one consumer, which case-of-case would
// move into the rows, where the run form would fold too. The rows: the
// tags of both constructors of a sum and the word a match takes from one
// (-5 for @A), the fields of a record of a word and a string (0, 1, -1,
// the most negative and the most positive Int, the empty string and one of
// a character of two bytes), and the head, tag and tail's tag of lists of
// one, two and three elements; a constructor value is no output, so the
// row's values are printed only as what is read of them. A wrong fold is
// found on its row: the sed makes row 4's word -2, in the sum and the
// record, where the run reads -1.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0004'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN:
!S = !idr.data<"S">
!One = !idr.data<"One">
!L = !idr.data<"L">
!P = !idr.data<"P">
#types = #idr.types<
  "L" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons],
  "One" = plain [@Only(i64)],
  "P" = plain [@MkP(i64, !idr.str)],
  "S" = plain [@A(), @B(i64, !idr.str)]
>
idr.program @data root(@Prog.main) stage(first) types #types {
  idr.func @constant_con() -> (!S, !idr.box<!L>) {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %x = idr.constant !idr.str "x"
    %s = idr.con !S @B(%one : i64, %x : !idr.str)
    %nil = idr.con !idr.box<!L> @Nil()
    %l = idr.con !idr.box<!L> @Cons(%two : i64, %nil : !idr.box<!L>)
    return %s, %l : !S, !idr.box<!L>
  }

  // A constructor with a runtime field stays; its fields and tag fold.
  idr.func @known(%x: i64) -> (i64, i64, !idr.str) {
    %y = idr.constant !idr.str "y"
    %s = idr.con !S @B(%x : i64, %y : !idr.str)
    %t = idr.tag %s : !S
    %f = idr.field %s : !S @B[0] -> i64
    %g = idr.field %s : !S @B[1] -> !idr.str
    return %t, %f, %g : i64, i64, !idr.str
  }

  // Fields and tags of a constant fold, nested ones included.
  idr.func @of_constant() -> (i64, i64, !idr.box<!L>) {
    %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [7 : i64, #idr.con<!L, @Nil, []>]>
    %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
    %t = idr.tag %l : !idr.box<!L>
    %n = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
    return %h, %t, %n : i64, i64, !idr.box<!L>
  }

  // A field of another constructor is unspecified and does not fold; the tag
  // of a type of one constructor is 0.
  idr.func @unknown(%v: !S, %o: !One) -> (i64, i64, i64) {
    %a = idr.con !S @A()
    %f = idr.field %a : !S @B[0] -> i64
    %t = idr.tag %v : !S
    %u = idr.tag %o : !One
    return %f, %t, %u : i64, i64, i64
  }

  // Equal constants are one value.
  idr.func @cse() -> (!idr.big, !idr.big) {
    %a = idr.constant !idr.big #idr.big<12345678901234567890>
    %b = idr.constant !idr.big #idr.big<12345678901234567890>
    return %a, %b : !idr.big, !idr.big
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!S, !P, !idr.box<!L>) {
    %r:3 = idr.match_lit %row : i64 -> (!S, !P, !idr.box<!L>) {
    case 0 {
      %s = idr.constant !S #idr.con<!S, @A, []>
      %p = idr.constant !P #idr.con<!P, @MkP, [0 : i64, ""]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [1 : i64, #idr.con<!L, @Nil, []>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    case 1 {
      %s = idr.constant !S #idr.con<!S, @B, [1 : i64, "x"]>
      %p = idr.constant !P #idr.con<!P, @MkP, [1 : i64, "x"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [2 : i64, #idr.con<!L, @Cons, [3 : i64, #idr.con<!L, @Nil, []>]>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    case 2 {
      %s = idr.constant !S #idr.con<!S, @B, [-9223372036854775808 : i64, ""]>
      %p = idr.constant !P #idr.con<!P, @MkP, [-9223372036854775808 : i64, "\C3\A9"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [-9223372036854775808 : i64, #idr.con<!L, @Nil, []>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    case 3 {
      %s = idr.constant !S #idr.con<!S, @A, []>
      %p = idr.constant !P #idr.con<!P, @MkP, [9223372036854775807 : i64, "abc"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [9223372036854775807 : i64, #idr.con<!L, @Cons, [-9223372036854775808 : i64, #idr.con<!L, @Cons, [0 : i64, #idr.con<!L, @Nil, []>]>]>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    case 4 {
      %s = idr.constant !S #idr.con<!S, @B, [-1 : i64, "y"]>
      %p = idr.constant !P #idr.con<!P, @MkP, [-1 : i64, "y"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [-1 : i64, #idr.con<!L, @Cons, [-1 : i64, #idr.con<!L, @Nil, []>]>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    default(%other: i64) {
      %s = idr.constant !S #idr.con<!S, @B, [0 : i64, ""]>
      %p = idr.constant !P #idr.con<!P, @MkP, [7 : i64, "z"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [0 : i64, #idr.con<!L, @Nil, []>]>
      idr.yield %s, %p, %l : !S, !P, !idr.box<!L>
    }
    }
    return %r#0, %r#1, %r#2 : !S, !P, !idr.box<!L>
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (i64, i64, i64, !idr.str, i64, i64, i64) {
    %s, %p, %l = idr.call @rows(%row) : (i64) -> (!S, !P, !idr.box<!L>)
    %t = idr.tag %s : !S
    %sx = idr.match %s : !S -> (i64) {
    case @B(%bx: i64, %bs: !idr.str) {
      idr.yield %bx : i64
    }
    default(%sa: !S) {
      %none = arith.constant -5 : i64
      idr.yield %none : i64
    }
    }
    %f0 = idr.field %p : !P @MkP[0] -> i64
    %f1 = idr.field %p : !P @MkP[1] -> !idr.str
    %tl = idr.tag %l : !idr.box<!L>
    %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
    %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
    %tt = idr.tag %rest : !idr.box<!L>
    return %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (i64, i64, i64, !idr.str, i64, i64, i64) {
    %r:7 = idr.match_lit %row : i64 -> (i64, i64, i64, !idr.str, i64, i64, i64) {
    case 0 {
      %s = idr.constant !S #idr.con<!S, @A, []>
      %p = idr.constant !P #idr.con<!P, @MkP, [0 : i64, ""]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [1 : i64, #idr.con<!L, @Nil, []>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    case 1 {
      %s = idr.constant !S #idr.con<!S, @B, [1 : i64, "x"]>
      %p = idr.constant !P #idr.con<!P, @MkP, [1 : i64, "x"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [2 : i64, #idr.con<!L, @Cons, [3 : i64, #idr.con<!L, @Nil, []>]>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    case 2 {
      %s = idr.constant !S #idr.con<!S, @B, [-9223372036854775808 : i64, ""]>
      %p = idr.constant !P #idr.con<!P, @MkP, [-9223372036854775808 : i64, "\C3\A9"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [-9223372036854775808 : i64, #idr.con<!L, @Nil, []>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    case 3 {
      %s = idr.constant !S #idr.con<!S, @A, []>
      %p = idr.constant !P #idr.con<!P, @MkP, [9223372036854775807 : i64, "abc"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [9223372036854775807 : i64, #idr.con<!L, @Cons, [-9223372036854775808 : i64, #idr.con<!L, @Cons, [0 : i64, #idr.con<!L, @Nil, []>]>]>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    case 4 {
      %s = idr.constant !S #idr.con<!S, @B, [-1 : i64, "y"]>
      %p = idr.constant !P #idr.con<!P, @MkP, [-1 : i64, "y"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [-1 : i64, #idr.con<!L, @Cons, [-1 : i64, #idr.con<!L, @Nil, []>]>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    default(%other: i64) {
      %s = idr.constant !S #idr.con<!S, @B, [0 : i64, ""]>
      %p = idr.constant !P #idr.con<!P, @MkP, [7 : i64, "z"]>
      %l = idr.constant !idr.box<!L> #idr.con<!L, @Cons, [0 : i64, #idr.con<!L, @Nil, []>]>
      %t = idr.tag %s : !S
      %sx = idr.match %s : !S -> (i64) {
      case @B(%bx: i64, %bs: !idr.str) {
        idr.yield %bx : i64
      }
      default(%sa: !S) {
        %none = arith.constant -5 : i64
        idr.yield %none : i64
      }
      }
      %f0 = idr.field %p : !P @MkP[0] -> i64
      %f1 = idr.field %p : !P @MkP[1] -> !idr.str
      %tl = idr.tag %l : !idr.box<!L>
      %h = idr.field %l : !idr.box<!L> @Cons[0] -> i64
      %rest = idr.field %l : !idr.box<!L> @Cons[1] -> !idr.box<!L>
      %tt = idr.tag %rest : !idr.box<!L>
      idr.yield %t, %sx, %f0, %f1, %tl, %h, %tt : i64, i64, i64, !idr.str, i64, i64, i64
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6 : i64, i64, i64, !idr.str, i64, i64, i64
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %t, %sx, %f0, %f1, %tl, %h, %tt = idr.call @folded(%row) : (i64) -> (i64, i64, i64, !idr.str, i64, i64, i64)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_sint %t, %w1 : i64
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_sint %sx, %w3 : i64
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_sint %f0, %w5 : i64
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_str %f1, %w7
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_sint %tl, %w9 : i64
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_sint %h, %w11 : i64
    %w13 = idr.io.put_char %space, %w12
    %w14 = idr.io.put_sint %tt, %w13 : i64
    %w15 = idr.io.put_char %newline, %w14
    return %w15 : !idr.world
  }
}
