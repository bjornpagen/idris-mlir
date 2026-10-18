// NEEDS-ACCEPTANCE: the constants written type first, as idr.constant now reads them; the crashes and guards as before.
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=computes-nothing=@may_crash,crash-sites=@may_crash:8,computes-nothing=@cannot_crash,no-guards=@cannot_crash,crash-sites=@past_end:1,crash-sites=@crash:1 -o /dev/null
// A primitive that may crash is its guard and the op it guards, as Emit
// writes it. When its result is unused the op goes, since it only
// computes, and the guard keeps its crash; the guard goes exactly when its
// operands rule the crash out. A crash also writes the IO resource, so it
// stays ordered with output, and two guards are not merged: each of
// @may_crash's eight places that may crash is kept.

idr.program @crash root(@root) stage(first) {
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
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
