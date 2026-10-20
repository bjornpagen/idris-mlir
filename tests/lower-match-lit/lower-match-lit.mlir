// RUN: sed 's/stage(first)/stage(higher)/' %s > %t.higher.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.higher.mlir
// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@byte:[],call-order=@word:[@idris_rt_str_cmp,@idris_rt_str_cmp],call-order=@nat:[@idris_rt_big_cmp],calls-only=@empty:[],straight-line=@empty' -o /dev/null
// An integer literal match is a switch on the key's zero-extended bits, so
// the byte -1 is the case 255, and asks the runtime for nothing; a string
// or big match compares with each key in turn, in the else branch of the
// comparison before, then takes the default: one comparison by the
// runtime for each key. What a region then computes is its own (@nat's
// default subtracts, however the lowering spells that). A string match
// with no case is its default alone: no comparison and no switch.
// Each key is matched as its type's value: the root reads a byte and a
// line and gives @byte the byte as an Int8 (1, 255 that is -1, others),
// @word and @empty the line ("one", "two", others), and @nat the Integer
// the line reads as (0, others, past the small range and below 0). The
// program prints what the reference at the end (REF) computes with
// comparisons alone, no match on a literal, compiled whole by idris-mlir
// (stage higher, which a program with no closure may say) and lowered by
// the steps above, as the program as written does (%differential, on the
// inputs below).
// STDIN: \0001one\n
// STDIN: \0377two\n
// STDIN: \0002three\n
// STDIN: \0000one\n
// STDIN: \00010\n
// STDIN: \03774611686018427387904\n
// STDIN: \0177-4611686018427387904\n
// STDIN: \0200\n
// STDIN:
idr.program @"match-lit" root(@Prog.main) stage(first) types #idr.types<> {
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
    default(%d: i8) {
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
    default(%d: !idr.str) {
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
    default(%d: !idr.big) {
      %one = idr.constant !idr.big #idr.big<1>
      %p = idr.big.sub %n, %one
      idr.yield %p : !idr.big
    }
    }
    return %r : !idr.big
  }
  idr.func @empty(%s: !idr.str) -> i64 {
    %r = idr.match_lit %s : !idr.str -> (i64) {
    default(%d: !idr.str) {
      %x = arith.constant 7 : i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.trunci %c : i32 to i8
    %r = idr.call @byte(%b) : (i8) -> i64
    %s, %w2 = idr.io.get_line %w1
    %t = idr.call @word(%s) : (!idr.str) -> i64
    %n = idr.big.from_str %s
    %p = idr.call @nat(%n) : (!idr.big) -> !idr.big
    %e = idr.call @empty(%s) : (!idr.str) -> i64
    %nl = arith.constant 10 : i32
    %w3 = idr.io.put_sint %r, %w2 : i64
    %w4 = idr.io.put_char %nl, %w3
    %w5 = idr.io.put_sint %t, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %ps = idr.big.show %p
    %w7 = idr.io.put_str %ps, %w6
    %w8 = idr.io.put_char %nl, %w7
    %w9 = idr.io.put_sint %e, %w8 : i64
    %w10 = idr.io.put_char %nl, %w9
    return %w10 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %k1 = arith.constant 1 : i32
// REF:     %k255 = arith.constant 255 : i32
// REF:     %is1 = arith.cmpi eq, %c, %k1 : i32
// REF:     %is255 = arith.cmpi eq, %c, %k255 : i32
// REF:     %ten = arith.constant 10 : i64
// REF:     %twenty = arith.constant 20 : i64
// REF:     %thirty = arith.constant 30 : i64
// REF:     %r2 = arith.select %is255, %twenty, %thirty : i64
// REF:     %r = arith.select %is1, %ten, %r2 : i64
// REF:     %s, %w2 = idr.io.get_line %w1
// REF:     %one = idr.constant !idr.str "one"
// REF:     %two = idr.constant !idr.str "two"
// REF:     %isone = idr.str.cmp eq %s, %one
// REF:     %istwo = idr.str.cmp eq %s, %two
// REF:     %i1 = arith.constant 1 : i64
// REF:     %i2 = arith.constant 2 : i64
// REF:     %i0 = arith.constant 0 : i64
// REF:     %t2 = arith.select %istwo, %i2, %i0 : i64
// REF:     %t = arith.select %isone, %i1, %t2 : i64
// REF:     %n = idr.big.from_str %s
// REF:     %zero = idr.constant !idr.big #idr.big<0>
// REF:     %bone = idr.constant !idr.big #idr.big<1>
// REF:     %iszero = idr.big.cmp eq %n, %zero
// REF:     %less = idr.big.sub %n, %bone
// REF:     %p = arith.select %iszero, %n, %less : !idr.big
// REF:     %seven = arith.constant 7 : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w3 = idr.io.put_sint %r, %w2 : i64
// REF:     %w4 = idr.io.put_char %nl, %w3
// REF:     %w5 = idr.io.put_sint %t, %w4 : i64
// REF:     %w6 = idr.io.put_char %nl, %w5
// REF:     %ps = idr.big.show %p
// REF:     %w7 = idr.io.put_str %ps, %w6
// REF:     %w8 = idr.io.put_char %nl, %w7
// REF:     %w9 = idr.io.put_sint %seven, %w8 : i64
// REF:     %w10 = idr.io.put_char %nl, %w9
// REF:     return %w10 : !idr.world
// REF:   }
// REF: }
