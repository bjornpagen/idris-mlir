// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=matches-nothing=@of_con,builds-nothing=@of_con,\
// RUN: returns=@of_constant:4.0,returns=@to_default:0.0,matches-nothing=@single,reads-fields=@single,\
// RUN: matches=@crashes,returns=@literals:2/3/4 -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=matches-nothing=@of_con,builds-nothing=@of_con,returns=@of_constant:4.0,returns=@to_default:0.0,matches-nothing=@single,reads-fields=@single,returns=@literals:2/3/4' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches=@of_con' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches-nothing=@crashes' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns=@of_constant:2.0' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns=@literals:2/3/1' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=builds=@of_con' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=reads-no-fields=@single' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected matches-nothing: {{.*}}@of_con
// BEFORE-DAG: expected builds-nothing: {{.*}}@of_con
// BEFORE-DAG: expected returns: {{.*}}@of_constant
// BEFORE-DAG: expected returns: {{.*}}@to_default
// BEFORE-DAG: expected matches-nothing: {{.*}}@single
// BEFORE-DAG: expected reads-fields: {{.*}}@single
// BEFORE-DAG: expected returns: {{.*}}@literals
// A match whose taken region is known is replaced by that region: the
// scrutinee is a constant or built by idr.con, or one region is left. The
// region's arguments become the constructor's fields.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and each property fails after it where
// the pass did its work or kept the match (@crashes); a constant other than
// the one returned fails too.

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
  // The program's root runs every function above: @crashes when the
  // byte's low bit is set, after the others, on a side made from the rest
  // of it.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %bit = arith.andi %byte, %c1 : i64
    %half = arith.shrui %byte, %c1 : i64
    %f = arith.sitofp %half : i64 to f64
    %q = arith.constant 0.25 : f64
    %g = arith.addf %f, %q : f64
    %r0 = idr.call @of_con(%f, %g) : (f64, f64) -> f64
    %w1 = idr.io.put_double %r0, %w0
    %r1 = idr.call @of_constant() : () -> f64
    %w2 = idr.io.put_double %r1, %w1
    %r2 = idr.call @to_default(%f) : (f64) -> f64
    %w3 = idr.io.put_double %r2, %w2
    %circle = idr.con !Shape @Circle(%g : f64)
    %r3 = idr.call @single(%circle) : (!Shape) -> f64
    %w4 = idr.io.put_double %r3, %w3
    %a, %b, %c = idr.call @literals() : () -> (i64, i64, i64)
    %w5 = idr.io.put_sint %a, %w4 : i64
    %w6 = idr.io.put_sint %b, %w5 : i64
    %w7 = idr.io.put_sint %c, %w6 : i64
    %w8 = idr.match_lit %bit : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w7 : !idr.world
    }
    default(%d: i64) {
      %r4 = idr.call @crashes(%f) : (f64) -> f64
      %v = idr.io.put_double %r4, %w7
      idr.yield %v : !idr.world
    }
    }
    return %w8 : !idr.world
  }
}
