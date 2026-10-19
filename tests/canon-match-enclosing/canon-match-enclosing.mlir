// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=matches-once=@lit_in_case,returns-on-paths=@lit_in_case:1+3,\
// RUN: matches-once=@lit_in_default,returns-on-paths=@lit_in_default:0+1+20,\
// RUN: returns-on-paths=@lit_in_default_unknown:0+10+20,returns-on-paths=@lit_other_value:1+2+3,\
// RUN: matches-once=@data_in_case,reads-no-fields=@data_in_case,matches-once=@data_in_default,\
// RUN: reads-no-fields=@field_in_case,reads-fields=@field_of_linear_match -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=matches-once=@lit_in_case,returns-on-paths=@lit_in_case:1+3,matches-once=@lit_in_default,returns-on-paths=@lit_in_default:0+1+20,matches-once=@data_in_case,matches-once=@data_in_default,reads-no-fields=@field_in_case' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns-on-paths=@lit_in_default_unknown:0+20' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns-on-paths=@lit_other_value:1+3' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=reads-no-fields=@field_of_linear_match' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=reads-fields=@field_in_case' -o /dev/null
// BEFORE-DAG: expected matches-once: {{.*}}@lit_in_case
// BEFORE-DAG: expected returns-on-paths: {{.*}}@lit_in_case
// BEFORE-DAG: expected matches-once: {{.*}}@lit_in_default
// BEFORE-DAG: expected returns-on-paths: {{.*}}@lit_in_default
// BEFORE-DAG: expected matches-once: {{.*}}@data_in_case
// BEFORE-DAG: expected matches-once: {{.*}}@data_in_default
// BEFORE-DAG: expected reads-no-fields: {{.*}}@field_in_case
// A match nested in a region of a match on the same value knows its region:
// in a case of the enclosing match the value has that case, and in its
// default it has none of the enclosing cases. The known region replaces the
// match, and a field it reads of the value is the enclosing region's own
// argument. What each function may return, path by path, is what it
// returned before: a case the enclosing match rules out is gone, and one
// it does not rule out stays.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it. The paths it keeps are kept:
// @lit_in_default_unknown may still return 10 and @lit_other_value 2,
// @field_of_linear_match still reads its field, and @field_in_case reads
// none.

// The inner match on the same literal takes the enclosing case: one test
// of %n is left, and nothing else is tested.
!Shape = !idr.data<"Shape", plain [@Circle(f64), @Rect(f64, f64), @Point()]>
idr.program @"match-enclosing" root(@root) stage(first) {
  idr.func @lit_in_case(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = idr.match_lit %n : i64 -> (i64) {
      case 0 {
        %one = arith.constant 1 : i64
        idr.yield %one : i64
      }
      default(%d: i64) {
        %two = arith.constant 2 : i64
        idr.yield %two : i64
      }
      }
      idr.yield %s : i64
    }
    default(%d1: i64) {
      %three = arith.constant 3 : i64
      idr.yield %three : i64
    }
    }
    return %r : i64
  }

  // In the enclosing default the value is none of its cases, so an inner
  // match with only those cases takes its own default: the inner cases are
  // gone, and only the outer two tests remain.
  idr.func @lit_in_default(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    case 1 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default(%d: i64) {
      %s = idr.match_lit %n : i64 -> (i64) {
      case 1 {
        %ten = arith.constant 10 : i64
        idr.yield %ten : i64
      }
      default(%d1: i64) {
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
  idr.func @lit_in_default_unknown(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    default(%d: i64) {
      %s = idr.match_lit %n : i64 -> (i64) {
      case 7 {
        %ten = arith.constant 10 : i64
        idr.yield %ten : i64
      }
      default(%d1: i64) {
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
  idr.func @lit_other_value(%n: i64, %m: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = idr.match_lit %m : i64 -> (i64) {
      case 0 {
        %one = arith.constant 1 : i64
        idr.yield %one : i64
      }
      default(%d: i64) {
        %two = arith.constant 2 : i64
        idr.yield %two : i64
      }
      }
      idr.yield %s : i64
    }
    default(%d1: i64) {
      %three = arith.constant 3 : i64
      idr.yield %three : i64
    }
    }
    return %r : i64
  }

  // An inner match on the same data value takes the enclosing case, and its
  // fields are the enclosing region's arguments: no second match, no read of
  // a field.
  idr.func @data_in_case(%s: !Shape) -> f64 {
    %r = idr.match %s : !Shape -> (f64) {
    case @Rect(%w: f64, %h: f64) {
      %a = idr.match %s : !Shape -> (f64) {
      case @Circle(%x: f64) {
        %c = arith.mulf %x, %x : f64
        idr.yield %c : f64
      }
      case @Rect(%x: f64, %y: f64) {
        %c = arith.mulf %x, %y : f64
        idr.yield %c : f64
      }
      default(%d: !Shape) {
        %z = arith.constant 0.0 : f64
        idr.yield %z : f64
      }
      }
      idr.yield %a : f64
    }
    default(%d1: !Shape) {
      %z = arith.constant 0.0 : f64
      idr.yield %z : f64
    }
    }
    return %r : f64
  }

  // In the enclosing default the value is neither a circle nor a rectangle:
  // an inner match of those two cases and a default takes the default.
  idr.func @data_in_default(%s: !Shape) -> f64 {
    %r = idr.match %s : !Shape -> (f64) {
    case @Circle(%x: f64) {
      idr.yield %x : f64
    }
    case @Rect(%w: f64, %h: f64) {
      idr.yield %w : f64
    }
    default(%d: !Shape) {
      %a = idr.match %s : !Shape -> (f64) {
      case @Circle(%x: f64) {
        %c = arith.mulf %x, %x : f64
        idr.yield %c : f64
      }
      case @Rect(%x: f64, %y: f64) {
        %c = arith.mulf %x, %y : f64
        idr.yield %c : f64
      }
      default(%d1: !Shape) {
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
  idr.func @field_in_case(%s: !Shape, %b: i64) -> f64 {
    %r = idr.match %s : !Shape -> (f64) {
    case @Rect(%w: f64, %h: f64) {
      %a = idr.match_lit %b : i64 -> (f64) {
      case 0 {
        %x = idr.field %s : !Shape @Rect[0] -> f64
        %y = idr.field %s : !Shape @Rect[1] -> f64
        %c = arith.addf %x, %y : f64
        idr.yield %c : f64
      }
      default(%d: i64) {
        idr.yield %w : f64
      }
      }
      idr.yield %a : f64
    }
    default(%d1: !Shape) {
      %z = arith.constant 0.0 : f64
      idr.yield %z : f64
    }
    }
    return %r : f64
  }

  // A match on a linear value takes it apart, and a field of the value it
  // was entered from is a second read, which the region's argument cannot
  // stand in for: the read stays as it is.
  idr.func @field_of_linear_match(%s: !Shape) -> f64 {
    %l = idr.lin.enter %s : !idr.lin<!Shape>
    %r = idr.match %l : !idr.lin<!Shape> -> (f64) {
    case @Rect(%w: f64, %h: f64) {
      %x = idr.field %s : !Shape @Rect[0] -> f64
      %c = arith.addf %x, %h : f64
      idr.yield %c : f64
    }
    default(%d: !idr.lin<!Shape>) {
      %z = arith.constant 0.0 : f64
      idr.yield %z : f64
    }
    }
    return %r : f64
  }
  // The program's root runs every function above on what it reads: a
  // literal from 0 to 8 and a second one from the rest of the byte, and a
  // shape of each kind with sides made from it.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c9 = arith.constant 9 : i64
    %n = arith.remui %x, %c9 : i64
    %m = arith.divui %x, %c9 : i64
    %mm = arith.remui %m, %c2 : i64
    %k = arith.remui %x, %c3 : i64
    %f = arith.sitofp %x : i64 to f64
    %half = arith.constant 0.5 : f64
    %g = arith.addf %f, %half : f64
    %s = idr.match_lit %k : i64 -> (!Shape) {
    case 0 {
      %c = idr.con !Shape @Circle(%f : f64)
      idr.yield %c : !Shape
    }
    case 1 {
      %r = idr.con !Shape @Rect(%f : f64, %g : f64)
      idr.yield %r : !Shape
    }
    default(%d: i64) {
      %p = idr.con !Shape @Point()
      idr.yield %p : !Shape
    }
    }
    %r0 = idr.call @lit_in_case(%n) : (i64) -> i64
    %w1 = idr.io.put_sint %r0, %w0 : i64
    %r1 = idr.call @lit_in_default(%n) : (i64) -> i64
    %w2 = idr.io.put_sint %r1, %w1 : i64
    %r2 = idr.call @lit_in_default_unknown(%n) : (i64) -> i64
    %w3 = idr.io.put_sint %r2, %w2 : i64
    %r3 = idr.call @lit_other_value(%n, %mm) : (i64, i64) -> i64
    %w4 = idr.io.put_sint %r3, %w3 : i64
    %r4 = idr.call @data_in_case(%s) : (!Shape) -> f64
    %w5 = idr.io.put_double %r4, %w4
    %r5 = idr.call @data_in_default(%s) : (!Shape) -> f64
    %w6 = idr.io.put_double %r5, %w5
    %r6 = idr.call @field_in_case(%s, %mm) : (!Shape, i64) -> f64
    %w7 = idr.io.put_double %r6, %w6
    %r7 = idr.call @field_of_linear_match(%s) : (!Shape) -> f64
    %w8 = idr.io.put_double %r7, %w7
    return %w8 : !idr.world
  }
}
