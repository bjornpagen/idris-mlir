// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// The guard of a string's head or tail folds to the string where the
// string shows it has a character: a constant other than "", or one built
// with a character or a number in it. The head of a string built with a
// character is then that character. On "" the guard stays, to crash where
// it runs. A guard of what an identical guard already checked folds too.
// CHECK-LABEL: func.func @proving(
// CHECK-SAME: %[[C:[^:]*]]: i32, %[[S:[^:]*]]: !idr.str, %[[X:[^:]*]]: i64)
// CHECK-NOT: idr.check.nonempty
// CHECK-NOT: idr.str.head
// CHECK: idr.str.tail
// CHECK-NOT: idr.check.nonempty
// CHECK: return %[[C]],
func.func @proving(%c: i32, %s: !idr.str, %x: i64) -> (i32, !idr.str, !idr.str, !idr.str) {
  %t = idr.str.cons %c, %s
  %g = idr.check.nonempty %t, "head of an empty string" : !idr.str
  %h = idr.str.head %g
  %abc = idr.constant "abc" : !idr.str
  %g1 = idr.check.nonempty %abc, "tail of an empty string" : !idr.str
  %bc = idr.str.tail %g1
  %shown = idr.str.show signed %x : i64
  %g2 = idr.check.nonempty %shown, "tail of an empty string" : !idr.str
  %rest = idr.str.tail %g2
  %both = idr.str.append %s, %abc
  %g3 = idr.check.nonempty %both, "tail of an empty string" : !idr.str
  %more = idr.str.tail %g3
  return %h, %bc, %rest, %more : i32, !idr.str, !idr.str, !idr.str
}

// CHECK-LABEL: func.func @failing(
// CHECK: idr.check.nonempty %{{.*}}, "head of an empty string" : !idr.str
// CHECK: return
func.func @failing() -> i32 {
  %empty = idr.constant "" : !idr.str
  %g = idr.check.nonempty %empty, "head of an empty string" : !idr.str
  %h = idr.str.head %g
  return %h : i32
}

// CHECK-LABEL: func.func @again(
// CHECK-SAME: %[[S:[^:]*]]: !idr.str)
// CHECK: %[[G:.*]] = idr.check.nonempty %[[S]], "head of an empty string" : !idr.str
// CHECK-NOT: idr.check.nonempty
// CHECK: idr.str.head %[[G]]
// CHECK-NOT: idr.check.nonempty
// CHECK: idr.str.tail %[[G]]
// CHECK-NOT: idr.check.nonempty
// CHECK: return
func.func @again(%s: !idr.str) -> (i32, !idr.str) {
  %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
  %h = idr.str.head %g
  %g1 = idr.check.nonempty %g, "tail of an empty string" : !idr.str
  %t = idr.str.tail %g1
  return %h, %t : i32, !idr.str
}
