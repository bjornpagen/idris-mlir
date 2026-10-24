// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=may-diverge=@main})' -o /dev/null
// Eager evaluation runs a computation whose value goes unused, so a loop
// Idris did not prove to end still runs, and may run forever, wherever its
// code is moved: a caller Idris proved to end that takes such a loop in may
// itself not end. @main is proved; the loop it takes in counts down by two
// to one, which an even start passes by and never reaches, and nothing
// reads what it gives. Its row holds divergence once the loop is in it.
//
// In the first program the loop is the frontend's, in @collatz, which
// @main calls twice, so @collatz is no continuation of @main's and is
// inlined as a leaf. In the second the loop is a pass's, made of
// @countdown's self tail call where @countdown, called once, becomes a join
// point of @main.
idr.program @inlined root(@main) stage(first) {
  idr.func @collatz(%n: i64) -> i64 {
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
  idr.func @main() attributes {terminates = #idr.terminates} {
    %even = arith.constant 98 : i64
    %odd = arith.constant 27 : i64
    %a = idr.call @collatz(%even) : (i64) -> i64
    %b = idr.call @collatz(%odd) : (i64) -> i64
    return
  }
}

// -----

idr.program @contified root(@main) stage(first) {
  idr.func @countdown(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 1(%key1: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %two = arith.constant 2 : i64
        %next = arith.subi %d, %two : i64
        %t = idr.tail_call @countdown(%next) : (i64) -> i64
        idr.yield %t : i64
      }
    }
    return %r : i64
  }
  idr.func @main() attributes {terminates = #idr.terminates} {
    %even = arith.constant 98 : i64
    %a = idr.call @countdown(%even) : (i64) -> i64
    return
  }
}
