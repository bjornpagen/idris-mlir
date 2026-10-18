// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=matches-nothing=@of_con,builds-nothing=@of_con,\
// RUN: returns=@of_constant:4.0,returns=@to_default:0.0,matches-nothing=@single,reads-fields=@single,\
// RUN: matches=@crashes,returns=@literals:2/3/4 -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A match whose taken region is known is replaced by that region: the
// scrutinee is a constant or built by idr.con, or one region is left. The
// region's arguments become the constructor's fields.

!Shape = !idr.data<"Shape", plain [@Circle(f64), @Rect(f64, f64)]>
idr.program @"match-known" root(@root) stage(first) {
  idr.func @of_con(%w: f64, %h: f64) -> f64 {
    %s = idr.con !Shape @Rect(%w : f64, %h : f64)
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      %a = arith.mulf %x, %x : f64
      idr.yield %a : f64
    }
    case @Rect(%x: f64, %y: f64) {
      %a = arith.mulf %x, %y : f64
      idr.yield %a : f64
    }
    }
    return %r : f64
  }

  idr.func @of_constant() -> f64 {
    %s = idr.constant !Shape #idr.con<!Shape, @Circle, [2.0 : f64]>
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      %a = arith.mulf %x, %x : f64
      idr.yield %a : f64
    }
    case @Rect(%x: f64, %y: f64) {
      %a = arith.mulf %x, %y : f64
      idr.yield %a : f64
    }
    }
    return %r : f64
  }

  // A constructor without a case takes the default.
  idr.func @to_default(%w: f64) -> f64 {
    %s = idr.con !Shape @Rect(%w : f64, %w : f64)
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      idr.yield %x : f64
    }
    default(%d: !Shape) {
      %z = arith.constant 0.0 : f64
      idr.yield %z : f64
    }
    }
    return %r : f64
  }

  // One region left: the others are impossible, so it runs, and its fields
  // are read from the scrutinee.
  idr.func @single(%s: !Shape) -> f64 {
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      %a = arith.mulf %x, %x : f64
      idr.yield %a : f64
    }
    }
    return %r : f64
  }

  // A region that crashes is never inlined into the middle of a block: the
  // match stays.
  idr.func @crashes(%w: f64) -> f64 {
    %s = idr.con !Shape @Rect(%w : f64, %w : f64)
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      idr.yield %x : f64
    }
    case @Rect(%x: f64, %y: f64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    return %r : f64
  }

  // Literals: integers, strings and bigs.
  idr.func @literals() -> (i64, i64, i64) {
    %n = arith.constant 7 : i64
    %s = idr.constant !idr.str "b"
    %g = idr.constant !idr.big #idr.big<99999999999999999999>
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %three = arith.constant 3 : i64
    %four = arith.constant 4 : i64
    %a = idr.match_lit %n : i64 -> (i64) {
    case 7 {
      idr.yield %two : i64
    }
    default(%d: i64) {
      idr.yield %one : i64
    }
    }
    %b = idr.match_lit %s : !idr.str -> (i64) {
    case "a" {
      idr.yield %one : i64
    }
    case "b" {
      idr.yield %three : i64
    }
    default(%d1: !idr.str) {
      idr.yield %one : i64
    }
    }
    %c = idr.match_lit %g : !idr.big -> (i64) {
    case #idr.big<0> {
      idr.yield %one : i64
    }
    default(%d2: !idr.big) {
      idr.yield %four : i64
    }
    }
    return %a, %b, %c : i64, i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
