// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-guards=@proving,crash-sites=@failing:1,crash-sites=@again:1 -o /dev/null
// The guard of a string's head or tail folds to the string where the
// string shows it has a character: a constant other than "", or one built
// with a character or a number in it. The head of a string built with a
// character is then that character. On "" the guard stays, to crash where
// it runs. A guard of what an identical guard already checked folds too.
idr.program @"fold-nonempty" root(@root) stage(first) {
  idr.func @proving(%c: i32, %s: !idr.str, %x: i64) -> (i32, !idr.str, !idr.str, !idr.str) {
    %t = idr.str.cons %c, %s
    %g = idr.check.nonempty %t, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    %abc = idr.constant !idr.str "abc"
    %g1 = idr.check.nonempty %abc, "tail of an empty string" : !idr.str
    %bc = idr.str.tail %g1
    %shown = idr.str.show_sint %x : i64
    %g2 = idr.check.nonempty %shown, "tail of an empty string" : !idr.str
    %rest = idr.str.tail %g2
    %both = idr.str.append %s, %abc
    %g3 = idr.check.nonempty %both, "tail of an empty string" : !idr.str
    %more = idr.str.tail %g3
    return %h, %bc, %rest, %more : i32, !idr.str, !idr.str, !idr.str
  }

  idr.func @failing() -> i32 {
    %empty = idr.constant !idr.str ""
    %g = idr.check.nonempty %empty, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    return %h : i32
  }

  idr.func @again(%s: !idr.str) -> (i32, !idr.str) {
    %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    %g1 = idr.check.nonempty %g, "tail of an empty string" : !idr.str
    %t = idr.str.tail %g1
    return %h, %t : i32, !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
