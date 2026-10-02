// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A match nested in a region of a match on the same value knows its region:
// in a case of the enclosing match the value has that case, and in its
// default it has none of the enclosing cases. The known region replaces the
// match, and a field it reads of the value is the enclosing region's own
// argument.

idr.data @Shape {
  idr.ctor @Circle (f64)
  idr.ctor @Rect (f64, f64)
  idr.ctor @Point ()
}

// The inner match on the same literal takes the enclosing case: one test
// of %n is left, and nothing else is tested.
// CHECK-LABEL: func.func @lit_in_case(
// CHECK-SAME: %[[N:.*]]: i64)
// CHECK: idr.match_lit %[[N]]
// CHECK-NOT: idr.match_lit
// CHECK: return
func.func @lit_in_case(%n: i64) -> i64 {
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %s = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    }
    idr.yield %s : i64
  }
  default {
    %three = arith.constant 3 : i64
    idr.yield %three : i64
  }
  }
  return %r : i64
}

// In the enclosing default the value is none of its cases, so an inner
// match with only those cases takes its own default: the inner cases are
// gone, and only the outer two tests remain.
// CHECK-LABEL: func.func @lit_in_default(
// CHECK: idr.match_lit
// CHECK-NOT: idr.match_lit
// CHECK: return
func.func @lit_in_default(%n: i64) -> i64 {
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %zero = arith.constant 0 : i64
    idr.yield %zero : i64
  }
  case 1 {
    %one = arith.constant 1 : i64
    idr.yield %one : i64
  }
  default {
    %s = idr.match_lit %n : i64 -> (i64) {
    case 1 {
      %ten = arith.constant 10 : i64
      idr.yield %ten : i64
    }
    default {
      %twenty = arith.constant 20 : i64
      idr.yield %twenty : i64
    }
    }
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// The enclosing default rules out 0 only: an inner match with a case of
// its own stays, since %n may still be 7.
// CHECK-LABEL: func.func @lit_in_default_unknown(
// CHECK: idr.match_lit
// CHECK: idr.match_lit
// CHECK: case 7
func.func @lit_in_default_unknown(%n: i64) -> i64 {
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %zero = arith.constant 0 : i64
    idr.yield %zero : i64
  }
  default {
    %s = idr.match_lit %n : i64 -> (i64) {
    case 7 {
      %ten = arith.constant 10 : i64
      idr.yield %ten : i64
    }
    default {
      %twenty = arith.constant 20 : i64
      idr.yield %twenty : i64
    }
    }
    idr.yield %s : i64
  }
  }
  return %r : i64
}

// Another value tells nothing: both matches stay.
// CHECK-LABEL: func.func @lit_other_value(
// CHECK: idr.match_lit
// CHECK: idr.match_lit
func.func @lit_other_value(%n: i64, %m: i64) -> i64 {
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %s = idr.match_lit %m : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    }
    idr.yield %s : i64
  }
  default {
    %three = arith.constant 3 : i64
    idr.yield %three : i64
  }
  }
  return %r : i64
}

// An inner match on the same data value takes the enclosing case, and its
// fields are the enclosing region's arguments: no second match, no read of
// a field.
// CHECK-LABEL: func.func @data_in_case(
// CHECK-SAME: %[[S:.*]]: !idr.data<@Shape>)
// CHECK: idr.match %[[S]]
// CHECK: case @Rect(%[[W:.*]]: f64, %[[H:.*]]: f64) {
// CHECK-NOT: idr.match
// CHECK-NOT: idr.field
// CHECK: %[[A:.*]] = arith.mulf %[[W]], %[[H]] : f64
// CHECK: idr.yield %[[A]]
func.func @data_in_case(%s: !idr.data<@Shape>) -> f64 {
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Rect(%w: f64, %h: f64) {
    %a = idr.match %s : !idr.data<@Shape> -> (f64) {
    case @Circle(%x: f64) {
      %c = arith.mulf %x, %x : f64
      idr.yield %c : f64
    }
    case @Rect(%x: f64, %y: f64) {
      %c = arith.mulf %x, %y : f64
      idr.yield %c : f64
    }
    default {
      %z = arith.constant 0.0 : f64
      idr.yield %z : f64
    }
    }
    idr.yield %a : f64
  }
  default {
    %z = arith.constant 0.0 : f64
    idr.yield %z : f64
  }
  }
  return %r : f64
}

// In the enclosing default the value is neither a circle nor a rectangle:
// an inner match of those two cases and a default takes the default.
// CHECK-LABEL: func.func @data_in_default(
// CHECK: idr.match
// CHECK-NOT: idr.match
// CHECK: return
func.func @data_in_default(%s: !idr.data<@Shape>) -> f64 {
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Circle(%x: f64) {
    idr.yield %x : f64
  }
  case @Rect(%w: f64, %h: f64) {
    idr.yield %w : f64
  }
  default {
    %a = idr.match %s : !idr.data<@Shape> -> (f64) {
    case @Circle(%x: f64) {
      %c = arith.mulf %x, %x : f64
      idr.yield %c : f64
    }
    case @Rect(%x: f64, %y: f64) {
      %c = arith.mulf %x, %y : f64
      idr.yield %c : f64
    }
    default {
      %one = arith.constant 1.0 : f64
      idr.yield %one : f64
    }
    }
    idr.yield %a : f64
  }
  }
  return %r : f64
}

// A field read in the case of a match on the value is the region's
// argument, wherever in the region it is.
// CHECK-LABEL: func.func @field_in_case(
// CHECK-SAME: %[[S:.*]]: !idr.data<@Shape>, %[[B:.*]]: i64)
// CHECK: case @Rect(%[[W:.*]]: f64, %[[H:.*]]: f64) {
// CHECK-NOT: idr.field
// CHECK: arith.addf %[[W]], %[[H]] : f64
func.func @field_in_case(%s: !idr.data<@Shape>, %b: i64) -> f64 {
  %r = idr.match %s : !idr.data<@Shape> -> (f64) {
  case @Rect(%w: f64, %h: f64) {
    %a = idr.match_lit %b : i64 -> (f64) {
    case 0 {
      %x = idr.field %s[@Rect, 0] : !idr.data<@Shape> -> f64
      %y = idr.field %s[@Rect, 1] : !idr.data<@Shape> -> f64
      %c = arith.addf %x, %y : f64
      idr.yield %c : f64
    }
    default {
      idr.yield %w : f64
    }
    }
    idr.yield %a : f64
  }
  default {
    %z = arith.constant 0.0 : f64
    idr.yield %z : f64
  }
  }
  return %r : f64
}

// A match on a linear value takes it apart, and a field of the value it
// was entered from is a second read, which the region's argument cannot
// stand in for: the read stays as it is.
// CHECK-LABEL: func.func @field_of_linear_match(
// CHECK: idr.field
func.func @field_of_linear_match(%s: !idr.data<@Shape>) -> f64 {
  %l = idr.lin.enter %s : !idr.lin<!idr.data<@Shape>>
  %r = idr.match %l : !idr.lin<!idr.data<@Shape>> -> (f64) {
  case @Rect(%w: f64, %h: f64) {
    %x = idr.field %s[@Rect, 0] : !idr.data<@Shape> -> f64
    %c = arith.addf %x, %h : f64
    idr.yield %c : f64
  }
  default {
    %z = arith.constant 0.0 : f64
    idr.yield %z : f64
  }
  }
  return %r : f64
}
