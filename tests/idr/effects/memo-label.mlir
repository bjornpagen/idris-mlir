// RUN: idris-mlir-opt %s --idr-effects | FileCheck %s
// A memo sum stands to a suspension as a sum of closures stands to a
// closure: making a cell of one of its labels names that label's
// function, so what the label may do flows to the maker as it does from
// an idr.suspend. Making a cell of a state names no function: `forced`
// holds a value already made, and the maker does no more than its own
// body does.

idr.data @lazy$0 box memo labels [@divides] {
  idr.ctor @divides (i64)
  idr.ctor @running ()
  idr.ctor @forced (i64)
}

// CHECK-LABEL: idr.func private @divides(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @divides(%x: i64) -> i64 attributes {total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}

// CHECK-LABEL: idr.func private @makes(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @makes(%x: i64) -> !idr.box<@lazy$0> attributes {total} {
  %t = idr.con @lazy$0::@divides(%x) : (i64) -> !idr.box<@lazy$0>
  return %t : !idr.box<@lazy$0>
}

// CHECK-LABEL: idr.func private @done(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @done(%x: i64) -> !idr.box<@lazy$0> attributes {total} {
  %t = idr.con @lazy$0::@forced(%x) : (i64) -> !idr.box<@lazy$0>
  return %t : !idr.box<@lazy$0>
}
