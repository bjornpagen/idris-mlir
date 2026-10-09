// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n "x" | %status 1 %t > %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=OUT < %t.out
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// A list packed or concatenated only to be written is written as it is
// walked, and its bytes are those of the string built from it where the
// string is kept: UTF-8 for a character from 128 up, in order with the
// program's other output, all of it written before a crash's message.
// The first character is read, so that neither list is a constant.
// OUT: [xé€😀] [xé€😀] 4
// OUT-NEXT: [ab-x] [ab-x] 4
// ERR: idris-mlir: done
module attributes {idr.program} {
  idr.data @Chars box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i32, !idr.box<@Chars>)
  }
  idr.data @Strs box {
    idr.ctor @Nil ()
    idr.ctor @Cons (!idr.str, !idr.box<@Strs>)
  }
  func.func private @pick(%c: i32) -> !idr.str {
    %r = idr.match_lit %c : i32 -> (!idr.str) {
    case 121 {
      %s = idr.constant "y" : !idr.str
      idr.yield %s : !idr.str
    }
    default {
      idr.crash "done"
      ub.unreachable
    }
    }
    return %r : !idr.str
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %open = arith.constant 91 : i32
    %close = arith.constant 93 : i32
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %x, %w1 = idr.io.get_byte %w
    %cnil = idr.con @Chars::@Nil() : () -> !idr.box<@Chars>
    %grin = arith.constant 128512 : i32
    %euro = arith.constant 8364 : i32
    %e = arith.constant 233 : i32
    %c3 = idr.con @Chars::@Cons(%grin, %cnil) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
    %c2 = idr.con @Chars::@Cons(%euro, %c3) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
    %c1 = idr.con @Chars::@Cons(%e, %c2) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
    %cs = idr.con @Chars::@Cons(%x, %c1) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
    // Written as it is walked.
    %w2 = idr.io.put_char %open, %w1
    %walked = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
    %w3 = idr.io.put_str %walked, %w2
    %w4 = idr.io.put_char %close, %w3
    %w5 = idr.io.put_char %space, %w4
    // Built, since its length is taken too.
    %w6 = idr.io.put_char %open, %w5
    %built = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
    %w7 = idr.io.put_str %built, %w6
    %w8 = idr.io.put_char %close, %w7
    %w9 = idr.io.put_char %space, %w8
    %n = idr.str.length %built
    %w10 = idr.io.put_int signed %n, %w9 : i64
    %w11 = idr.io.put_char %newline, %w10
    %snil = idr.con @Strs::@Nil() : () -> !idr.box<@Strs>
    %ab = idr.constant "ab" : !idr.str
    %dash = idr.constant "-" : !idr.str
    %xs = idr.str.from_char %x
    %s3 = idr.con @Strs::@Cons(%xs, %snil) : (!idr.str, !idr.box<@Strs>) -> !idr.box<@Strs>
    %s2 = idr.con @Strs::@Cons(%dash, %s3) : (!idr.str, !idr.box<@Strs>) -> !idr.box<@Strs>
    %ss = idr.con @Strs::@Cons(%ab, %s2) : (!idr.str, !idr.box<@Strs>) -> !idr.box<@Strs>
    %w12 = idr.io.put_char %open, %w11
    %joined = idr.str.concat %ss : !idr.box<@Strs> -> !idr.str
    %w13 = idr.io.put_str %joined, %w12
    %w14 = idr.io.put_char %close, %w13
    %w15 = idr.io.put_char %space, %w14
    %w16 = idr.io.put_char %open, %w15
    %kept = idr.str.concat %ss : !idr.box<@Strs> -> !idr.str
    %w17 = idr.io.put_str %kept, %w16
    %w18 = idr.io.put_char %close, %w17
    %w19 = idr.io.put_char %space, %w18
    %m = idr.str.length %kept
    %w20 = idr.io.put_int signed %m, %w19 : i64
    %w21 = idr.io.put_char %newline, %w20
    %p = func.call @pick(%x) : (i32) -> !idr.str
    %w22 = idr.io.put_str %p, %w21
    return %w22 : !idr.world
  }
}
