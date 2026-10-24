// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// A value that every path running into it passes one constant is that
// constant: an argument of a region, or a result of the op whose regions
// give it. After the first stage exp of each such value takes the
// constant, and exp, a C library function whose last digit is each
// library's, stays applied on a constant alone, which the property
// reports. In the first program @main's loop counts a byte of standard
// input down to zero, with a second parameter it is entered with as 2.0
// and that the jump back, out of the match it ends, passes on unchanged:
// so the parameter is 2.0 on every path. In the second a literal match on
// a constant runs one case, which yields 3.0; the default, which yields
// the byte read as a Double, does not run, so the match gives 3.0.
!Str = !idr.graded<many, static, !idr.str>
idr.program @invariant root(@main) stage(first) {
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %two = arith.constant 2.0 : f64
    %r = idr.loop tokens(%k) -> (f64) attributes {binders = [#idr.index_binders<[]>]} {
      idr.jump %k(%n, %two : i64, f64)
    } join tokens(%again)(%m: i64, %c: f64) {
      idr.may_loop
      %s = idr.lit.match %m : i64 -> (f64) {
        case 0(%key: i64) {
          // expected-error @below {{expected folded: }}
          %e = math.exp %c : f64
          idr.yield %e : f64
        } default(%d: i64) {
          %one = arith.constant 1 : i64
          %next = arith.subi %d, %one : i64
          idr.jump %again(%next, %c : i64, f64)
        }
      }
      idr.yield %s : f64
    }
    %text = idr.str.show_double %r : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
idr.program @live root(@main) stage(first) {
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %read = arith.uitofp %byte : i32 to f64
    %four = arith.constant 4 : i64
    %s = idr.lit.match %four : i64 -> (f64) {
      case 4(%key: i64) {
        %three = arith.constant 3.0 : f64
        idr.yield %three : f64
      } default(%d: i64) {
        idr.yield %read : f64
      }
    }
    // expected-error @below {{expected folded: }}
    %e = math.exp %s : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
