// NEEDS-ACCEPTANCE: that this module parses with each match's default binding its scrutinee, that each of Placement.cpp's properties holds of the functions that place their work on the paths that need it, and that the -verify-diagnostics run passes: each fails at the op its comment names, in each function that does not.
// RUN: idris-mlir-opt %s --idr-expect=holds=builds-where-used=@built_where,calls-where-used=@called_where:@g,\
// RUN: matches-once=@tests_other,crashes-before-output=@checks_first,parameters-used=@built_where,\
// RUN: results-used=@tests_other,regions-distinct=@tests_other,checks-every-path=@checks_first -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=builds-where-used=@built_early,\
// RUN: calls-where-used=@called_early:@g,matches-once=@tests_twice,crashes-before-output=@writes_first,\
// RUN: parameters-used=@ignores,results-used=@half_used,regions-distinct=@same_twice,\
// RUN: checks-every-path=@checks_some,checks-every-path=@ignores -verify-diagnostics -o /dev/null
// Where a function's work happens on the paths through its matches: a
// value built, or a call made, where it is used, not before a match one
// region of which uses it; a value tested once on a path; a write after
// what may crash; every parameter and result read; regions that differ;
// and a check on every path.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"List">>) cons]>
!B = !idr.data<"B", plain [@F(), @T()]>
idr.program @placement root(@root) stage(first) {
  idr.func @g(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @built_where(%v: i32, %t: !idr.box<!List>) -> !idr.box<!List> {
    %l = idr.con !idr.box<!List> @Cons(%v : i32, %t : !idr.box<!List>)
    return %l : !idr.box<!List>
  }
  idr.func @built_early(%a: i64, %v: i32, %t: !idr.box<!List>) -> !idr.box<!List> {
    // expected-error @below {{expected builds-where-used: idr.con in @built_early builds a value only the regions of a later op use}}
    %l = idr.con !idr.box<!List> @Cons(%v : i32, %t : !idr.box<!List>)
    %r = idr.match_lit %a : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %l : !idr.box<!List>
    }
    default(%d: i64) {
      idr.yield %t : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @called_where(%x: i64) -> i64 {
    %y = idr.call @g(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @called_early(%a: i64, %x: i64) -> i64 {
    // expected-error @below {{expected calls-where-used: a call of @g in @called_early runs where only the regions of a later op use it}}
    %y = idr.call @g(%x) : (i64) -> i64
    %r = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      idr.yield %y : i64
    }
    default(%d: i64) {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // A match on another value inside a case tells it nothing.
  idr.func @tests_other(%n: i64, %m: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = idr.match_lit %m : i64 -> (i64) {
      case 0 {
        %one = arith.constant 1 : i64
        idr.yield %one : i64
      }
      default(%e: i64) {
        %two = arith.constant 2 : i64
        idr.yield %two : i64
      }
      }
      idr.yield %s : i64
    }
    default(%d: i64) {
      %three = arith.constant 3 : i64
      idr.yield %three : i64
    }
    }
    return %r : i64
  }
  // In the case of %n that is 0, %n is tested again.
  idr.func @tests_twice(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      // expected-error @below {{expected matches-once: idr.match_lit in @tests_twice tests a value a match around it already decided}}
      %s = idr.match_lit %n : i64 -> (i64) {
      case 0 {
        %one = arith.constant 1 : i64
        idr.yield %one : i64
      }
      default(%e: i64) {
        %two = arith.constant 2 : i64
        idr.yield %two : i64
      }
      }
      idr.yield %s : i64
    }
    default(%d: i64) {
      %three = arith.constant 3 : i64
      idr.yield %three : i64
    }
    }
    return %r : i64
  }
  idr.func @checks_first(%x: i64, %y: i64, %w: !idr.world) -> (i64, !idr.world) {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %g : i64
    %s = idr.constant !idr.str "divided"
    %w1 = idr.io.put_str %s, %w
    return %q, %w1 : i64, !idr.world
  }
  idr.func @writes_first(%x: i64, %y: i64, %w: !idr.world) -> (i64, !idr.world) {
    %s = idr.constant !idr.str "dividing"
    // expected-error @below {{expected crashes-before-output: idr.io.put_str in @writes_first may write before idr.check.nonzero, which may crash}}
    %w1 = idr.io.put_str %s, %w
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %g : i64
    return %q, %w1 : i64, !idr.world
  }
  // expected-error @below {{expected parameters-used: parameter 1 of @ignores is not read}}
  // expected-error @below {{expected checks-every-path: no check in @ignores}}
  idr.func @ignores(%x: i64, %unused: i64) -> i64 {
    return %x : i64
  }
  idr.func @half_used(%b: !B, %x: i64, %y: i64) -> i64 {
    // expected-error @below {{expected results-used: result 1 of idr.match in @half_used is not used}}
    %r:2 = idr.match %b : !B -> (i64, i64) {
    case @F() {
      idr.yield %x, %y : i64, i64
    }
    case @T() {
      idr.yield %y, %x : i64, i64
    }
    }
    return %r#0 : i64
  }
  idr.func @same_twice(%n: i64, %x: i64) -> i64 {
    // expected-error @below {{expected regions-distinct: idr.match_lit in @same_twice has case 0 and case 1 that do the same}}
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = arith.addi %x, %x : i64
      idr.yield %s : i64
    }
    case 1 {
      %s = arith.addi %x, %x : i64
      idr.yield %s : i64
    }
    default(%d: i64) {
      idr.yield %d : i64
    }
    }
    return %r : i64
  }
  idr.func @checks_some(%n: i64, %x: i64, %y: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      // expected-error @below {{expected checks-every-path: idr.check.nonzero in @checks_some runs on some paths only}}
      %g = idr.check.nonzero %y, "division by zero" : i64
      %q = idr.div signed %x, %g : i64
      idr.yield %q : i64
    }
    default(%d: i64) {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
