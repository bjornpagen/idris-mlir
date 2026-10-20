// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/\[127 : i32/[126 : i32/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=folded=@folded,returns=@folds:"hi"/"ab",folds-balanced' -o /dev/null
// A string built from a constant list folds to the constant string: pack
// of the characters, concat of the strings; the folders release what the
// runtime gave them.
//
// The runtime's pack and concat at run time, and the length of what they
// build, are the oracle for every row of the table: each row folds in its
// own region (@folded), and is computed at run time from the row the byte
// read chose (@at_run_time, which the sed makes the program's). On the
// byte of each row, and on the empty input for the last, the two print the
// same: the row's operands, then its results; each operand is printed as
// well as used, so that no op on it is its one consumer, which case-of-
// case would move into the rows, where the run form would fold too. The
// rows: the empty list, a list of the empty string, the characters 0, 127,
// 128, U+10FFFF and ones of two, three and four bytes, strings of each,
// and empty strings among others. A wrong fold is found on its row: the
// sed makes row 3's first character 126, where the run packs 127.
//
// The last line asks that the folders leave no cell live; it comes after
// the differential, so that the differential holds whatever it finds.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0003'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN:
!Chars = !idr.data<"Chars">
!Strs = !idr.data<"Strs">
#types = #idr.types<
  "Chars" = list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons],
  "Strs" = list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]
>
idr.program @strings root(@Prog.main) stage(first) types #types {
  idr.func @folds() -> (!idr.str, !idr.str) {
    %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [105 : i32, #idr.con<!Chars, @Nil, []>]>]>
    %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Nil, []>]>]>
    %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %t = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
    return %s, %t : !idr.str, !idr.str
  }
  // The operands of each row, the last the default one: the row the byte
  // chose, known only at run time.
  idr.func @rows(%row: i64) -> (!idr.box<!Chars>, !idr.box<!Strs>) {
    %r:2 = idr.match_lit %row : i64 -> (!idr.box<!Chars>, !idr.box<!Strs>) {
    case 0 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [105 : i32, #idr.con<!Chars, @Nil, []>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Nil, []>]>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 1 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Nil, []>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Nil, []>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 2 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [0 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Nil, []>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 3 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [127 : i32, #idr.con<!Chars, @Cons, [128 : i32, #idr.con<!Chars, @Nil, []>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["x", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Nil, []>]>]>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 4 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [233 : i32, #idr.con<!Chars, @Cons, [8364 : i32, #idr.con<!Chars, @Cons, [128512 : i32, #idr.con<!Chars, @Nil, []>]>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["\C3\A9", #idr.con<!Strs, @Cons, ["\F0\9F\98\80", #idr.con<!Strs, @Nil, []>]>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 5 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [1114111 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["abc", #idr.con<!Strs, @Nil, []>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    case 6 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [65 : i32, #idr.con<!Chars, @Cons, [0 : i32, #idr.con<!Chars, @Cons, [66 : i32, #idr.con<!Chars, @Nil, []>]>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["c", #idr.con<!Strs, @Nil, []>]>]>]>]>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    default(%other: i64) {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [120 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["xy", #idr.con<!Strs, @Nil, []>]>
      idr.yield %cs, %ss : !idr.box<!Chars>, !idr.box<!Strs>
    }
    }
    return %r#0, %r#1 : !idr.box<!Chars>, !idr.box<!Strs>
  }
  // Each row's results, computed at run time from the row @rows chose.
  idr.func @at_run_time(%row: i64) -> (!idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64) {
    %cs, %ss = idr.call @rows(%row) : (i64) -> (!idr.box<!Chars>, !idr.box<!Strs>)
    %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %np = idr.str.length %p
    %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
    %nc = idr.str.length %c
    return %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
  }
  // Each row's results on its constants, which the folders compute.
  idr.func @folded(%row: i64) -> (!idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64) {
    %r:6 = idr.match_lit %row : i64 -> (!idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64) {
    case 0 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [105 : i32, #idr.con<!Chars, @Nil, []>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Nil, []>]>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 1 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Nil, []>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Nil, []>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 2 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [0 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Nil, []>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 3 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [127 : i32, #idr.con<!Chars, @Cons, [128 : i32, #idr.con<!Chars, @Nil, []>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["x", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Nil, []>]>]>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 4 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [233 : i32, #idr.con<!Chars, @Cons, [8364 : i32, #idr.con<!Chars, @Cons, [128512 : i32, #idr.con<!Chars, @Nil, []>]>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["\C3\A9", #idr.con<!Strs, @Cons, ["\F0\9F\98\80", #idr.con<!Strs, @Nil, []>]>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 5 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [1114111 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["abc", #idr.con<!Strs, @Nil, []>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    case 6 {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [65 : i32, #idr.con<!Chars, @Cons, [0 : i32, #idr.con<!Chars, @Cons, [66 : i32, #idr.con<!Chars, @Nil, []>]>]>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["a", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["b", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["c", #idr.con<!Strs, @Nil, []>]>]>]>]>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    default(%other: i64) {
      %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [120 : i32, #idr.con<!Chars, @Nil, []>]>
      %ss = idr.constant !idr.box<!Strs> #idr.con<!Strs, @Cons, ["xy", #idr.con<!Strs, @Nil, []>]>
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      %np = idr.str.length %p
      %c = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
      %nc = idr.str.length %c
      idr.yield %cs, %ss, %p, %np, %c, %nc : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
    }
    }
    return %r#0, %r#1, %r#2, %r#3, %r#4, %r#5 : !idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64
  }
  // The program: the results of the row the byte read chooses, folded,
  // or, in the run form, computed at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %cs, %ss, %p, %np, %c, %nc = idr.call @folded(%row) : (i64) -> (!idr.box<!Chars>, !idr.box<!Strs>, !idr.str, i64, !idr.str, i64)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w2 = idr.io.put_list %cs, %w1 : !idr.box<!Chars>
    %w3 = idr.io.put_char %space, %w2
    %w4 = idr.io.put_list %ss, %w3 : !idr.box<!Strs>
    %w5 = idr.io.put_char %space, %w4
    %w6 = idr.io.put_str %p, %w5
    %w7 = idr.io.put_char %space, %w6
    %w8 = idr.io.put_sint %np, %w7 : i64
    %w9 = idr.io.put_char %space, %w8
    %w10 = idr.io.put_str %c, %w9
    %w11 = idr.io.put_char %space, %w10
    %w12 = idr.io.put_sint %nc, %w11 : i64
    %w13 = idr.io.put_char %newline, %w12
    return %w13 : !idr.world
  }
}
