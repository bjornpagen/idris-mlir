// RUN: idris-mlir-opt %s --idr-expect=holds=may-diverge=@spin -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=may-diverge=@count,may-diverge=@divides,may-diverge=@wind -verify-diagnostics -o /dev/null
// A function may never end where its row holds divergence, whichever op
// put it there; each row here is the one its body derives. @spin, which
// Idris proved, has taken in a loop Idris did not prove, marked at its
// join region's entry, so its row holds divergence. @count's loop is the
// same loop, proved: its row holds nothing. @divides may crash, and
// always ends: a crash is no divergence. @wind's row holds divergence
// and its copy's, which has lost the mark, does not: a property of @wind
// is one of every copy of it, and the copy is reported at its location, a
// name alone, which points nowhere in this file.
idr.program @rows root(@main) stage(first) {
  idr.func <{row = []}> @main() {
    idr.return
  }
  idr.func <{row = ["divergence"]}> @spin(%n: i64) -> i64 attributes {terminates = #idr.terminates} {
    %r = idr.loop tokens(%k) -> (i64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%n : i64)
    } join tokens(%again)(%m: i64) {
      idr.may_loop
      %s = idr.lit.match %m : i64 -> (i64) {
        case 1(%key0: i64) {
          idr.yield %m : i64
        } default(%d: i64) {
          %two = arith.constant 2 : i64
          %next = arith.subi %d, %two : i64
          idr.jump %again(%next : i64)
        }
      }
      idr.yield %s : i64
    }
    return %r : i64
  }
  // expected-error @below {{expected may-diverge: }}
  idr.func <{row = []}> @count(%n: i64) -> i64 attributes {terminates = #idr.terminates} {
    %r = idr.loop tokens(%k) -> (i64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%n : i64)
    } join tokens(%again)(%m: i64) {
      %s = idr.lit.match %m : i64 -> (i64) {
        case 1(%key1: i64) {
          idr.yield %m : i64
        } default(%d: i64) {
          %two = arith.constant 2 : i64
          %next = arith.subi %d, %two : i64
          idr.jump %again(%next : i64)
        }
      }
      idr.yield %s : i64
    }
    return %r : i64
  }
  // expected-error @below {{expected may-diverge: }}
  idr.func <{row = ["crash"]}> @divides(%x: i64, %d: i64) -> i64 attributes {terminates = #idr.terminates} {
    %checked = idr.check.nonzero %d, division_by_zero at #idr.site<"Main.idr", 3, 5, "Main.divides"> : (i64) -> i64
    %y = arith.divui %x, %checked : i64
    return %y : i64
  }
  idr.func <{row = ["divergence"]}> @wind(%n: i64) -> i64 attributes {terminates = #idr.terminates} {
    %r = idr.loop tokens(%k) -> (i64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%n : i64)
    } join tokens(%again)(%m: i64) {
      idr.may_loop
      %s = idr.lit.match %m : i64 -> (i64) {
        case 1(%key2: i64) {
          idr.yield %m : i64
        } default(%d: i64) {
          %two = arith.constant 2 : i64
          %next = arith.subi %d, %two : i64
          idr.jump %again(%next : i64)
        }
      }
      idr.yield %s : i64
    }
    return %r : i64
  }
  // expected-error @unknown {{expected may-diverge: }}
  idr.func <{row = []}> @wind_1(%n: i64) -> i64 attributes {terminates = #idr.terminates} {
    %r = idr.loop tokens(%k) -> (i64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%n : i64)
    } join tokens(%again)(%m: i64) {
      %s = idr.lit.match %m : i64 -> (i64) {
        case 1(%key3: i64) {
          idr.yield %m : i64
        } default(%d: i64) {
          %two = arith.constant 2 : i64
          %next = arith.subi %d, %two : i64
          idr.jump %again(%next : i64)
        }
      }
      idr.yield %s : i64
    }
    return %r : i64
  } loc("wind")
}
