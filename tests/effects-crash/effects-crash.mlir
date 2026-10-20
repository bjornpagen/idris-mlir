// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=computes-nothing=@may_crash,crash-sites=@may_crash:7,computes-nothing=@cannot_crash,no-guards=@cannot_crash,crash-sites=@past_end:1,crash-sites=@crash:1 -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: idris-mlir-opt %s --canonicalize --cse -o %t.folded.mlir
// RUN: %differential %t.folded.mlir %t.reference.mlir
// RUN: sed 's/case 300 {/case 3 {/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// A primitive that may crash is its guard and the op it guards, as Emit
// writes it. When its result is unused the op goes, since it only
// computes, and the guard keeps its crash; the guard goes exactly when its
// operands rule the crash out. A crash also writes the IO resource, so it
// stays ordered with output, and two guards are not merged: each of
// @may_crash's seven places that may crash is kept.
//
// So a guard whose result nothing reads still crashes where it runs: the
// program calls @may_crash on operands the byte read chooses, which satisfy
// every guard (the byte 0) or refuse one kind (an index at the length, the
// empty string, a zero divisor, NaN, an infinity, an index below 0), then
// @cannot_crash on the same operands, which never crashes, and writes ok.
// The REFERENCE lines crash on every byte but 0; the program means the
// same as written, and after the folds and CSE, on each choice and the
// empty input. A reference that does not crash on the zero divisor, as a
// program whose guard was dropped would not, is told apart on the byte 3
// (the sed makes its arm for 300, which no byte reaches, the arm for 3).
// CHECK: differential: effects-crash.mlir and {{.*}}wrong.mlir differ on '\0003'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN:

idr.program @crash root(@root) stage(first) types #idr.types<> {
  idr.func @may_crash(%s: !idr.str, %i: i64, %b: !idr.big, %d: f64) {
    %n = idr.str.length %s
    %i0 = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %0 = idr.str.index %s, %i0
    %s1 = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %1 = idr.str.head %s1
    %s2 = idr.check.nonempty %s, "tail of an empty string" : !idr.str
    %2 = idr.str.tail %s2
    %b3 = idr.check.nonzero %b, "division by zero" : !idr.big
    %3 = idr.big.div %b, %b3
    %b4 = idr.check.nonzero %b, "division by zero" : !idr.big
    %4 = idr.big.mod %b, %b4
    %d5 = idr.check.finite %d, "cast of a non-finite Double"
    %5 = idr.big.from_double %d5
    %d6 = idr.check.finite %d, "cast of a non-finite Double"
    %6 = idr.to_int %d6 : i64
    return
  }

  // The same primitives on operands that rule out the crash are dead code,
  // guards and all.
  idr.func @cannot_crash(%s: !idr.str, %c: i32, %x: i64, %b: !idr.big) {
    %lit = idr.constant !idr.str "h\C3\A9!"
    %two = arith.constant 2 : i64
    %n = idr.str.length %lit
    %i0 = idr.check.in_bounds %two, %lit, "string index out of range" : !idr.str
    %0 = idr.str.index %lit, %i0
    %cons = idr.str.cons %c, %s
    %s1 = idr.check.nonempty %cons, "head of an empty string" : !idr.str
    %1 = idr.str.head %s1
    %s2 = idr.check.nonempty %lit, "tail of an empty string" : !idr.str
    %2 = idr.str.tail %s2
    %shown = idr.str.show_sint %x : i64
    %s3 = idr.check.nonempty %shown, "tail of an empty string" : !idr.str
    %3 = idr.str.tail %s3
    %appended = idr.str.append %s, %lit
    %s4 = idr.check.nonempty %appended, "head of an empty string" : !idr.str
    %4 = idr.str.head %s4
    %seven = idr.constant !idr.big #idr.big<-7>
    %b5 = idr.check.nonzero %seven, "division by zero" : !idr.big
    %5 = idr.big.div %b, %b5
    %b6 = idr.check.nonzero %seven, "division by zero" : !idr.big
    %6 = idr.big.mod %b, %b6
    %half = arith.constant 0.5 : f64
    %d7 = idr.check.finite %half, "cast of a non-finite Double"
    %7 = idr.big.from_double %d7
    %d8 = idr.check.finite %half, "cast of a non-finite Double"
    %8 = idr.to_int %d8 : i64
    return
  }

  // An index past the last character (not the last byte) may crash.
  idr.func @past_end() {
    %lit = idr.constant !idr.str "h\C3\A9!"
    %three = arith.constant 3 : i64
    %n = idr.str.length %lit
    %i0 = idr.check.in_bounds %three, %lit, "string index out of range" : !idr.str
    %0 = idr.str.index %lit, %i0
    return
  }

  // A crash is kept, and two are not merged.
  idr.func @crash() {
    idr.crash "a"
    ub.unreachable
  }
  // The program: @may_crash and @cannot_crash on the operands the byte
  // chooses, then ok.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %s, %i, %b, %d = idr.match_lit %k : i64 -> (!idr.str, i64, !idr.big, f64) {
    case 0 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0.5 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    case 1 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 3 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0.5 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    case 2 {
      %s = idr.constant !idr.str ""
      %i = arith.constant 0 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0.5 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    case 3 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<0>
      %d = arith.constant 0.5 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    case 4 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0x7FF8000000000000 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    case 5 {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant 2 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0xFFF0000000000000 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    default(%other: i64) {
      %s = idr.constant !idr.str "abc"
      %i = arith.constant -1 : i64
      %b = idr.constant !idr.big #idr.big<7>
      %d = arith.constant 0.5 : f64
      idr.yield %s, %i, %b, %d : !idr.str, i64, !idr.big, f64
    }
    }
    idr.call @may_crash(%s, %i, %b, %d) : (!idr.str, i64, !idr.big, f64) -> ()
    %x = arith.constant 120 : i32
    idr.call @cannot_crash(%s, %x, %i, %b) : (!idr.str, i32, i64, !idr.big) -> ()
    %ok = idr.constant !idr.str "ok"
    %w2 = idr.io.put_str %ok, %w1
    return %w2 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@root) stage(first) types #idr.types<> {
// REFERENCE:   idr.func @root(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %w2 = idr.match_lit %c : i32 -> (!idr.world) {
// REFERENCE:     case 0 {
// REFERENCE:       %ok = idr.constant !idr.str "ok"
// REFERENCE:       %v = idr.io.put_str %ok, %w1
// REFERENCE:       idr.yield %v : !idr.world
// REFERENCE:     }
// REFERENCE:     case 300 {
// REFERENCE:       %ok = idr.constant !idr.str "ok"
// REFERENCE:       %v = idr.io.put_str %ok, %w1
// REFERENCE:       idr.yield %v : !idr.world
// REFERENCE:     }
// REFERENCE:     default(%d: i32) {
// REFERENCE:       idr.crash "refused"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %w2 : !idr.world
// REFERENCE:   }
// REFERENCE: }
