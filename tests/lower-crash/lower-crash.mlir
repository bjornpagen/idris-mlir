// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,crash-sites=@Main.name:1,crash-sites=@Main.never:1,never-returns=@Main.never,crash-sites=@Main.half:1,calls-only=@Main.half:[@idris_rt_crash]' -o /dev/null
// idr.crash calls the runtime's crash, which does not return, with its
// message and location; a function that never returns ends after it, with
// no return. The guard of a division by what may be zero is the same
// crash, at the division's location, when the divisor is zero, and then
// gives the divisor to the division, which tests nothing itself: the
// function may crash at that one place. What a crash prints is the
// program's output.
idr.program @crash root(@Main.main) stage(first) {
  idr.func @Main.name(%n: i64) -> !idr.str {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 1 {
      %s = idr.constant !idr.str "one"
      idr.yield %s : !idr.str
    }
    default(%d: i64) {
      idr.crash "unhandled input for Main.name" loc("Main.idr":3:1)
      ub.unreachable
    }
    }
    return %r : !idr.str
  }
  idr.func @Main.never(%n: i64) -> i64 {
    idr.crash "unhandled input for Main.never" loc("Main.idr":6:1)
    ub.unreachable
  }
  idr.func @Main.half(%a: i64, %b: i64) -> i64 {
    %c = idr.check.nonzero %b, "division by zero" : i64 loc("Main.idr":9:5)
    %q = idr.divs %a, %c : i64 loc("Main.idr":9:5)
    return %q : i64
  }
  idr.func @Main.main() -> i64 {
    %one = arith.constant 1 : i64
    %s = idr.call @Main.name(%one) : (i64) -> !idr.str
    %n = idr.call @Main.never(%one) : (i64) -> i64
    %h = idr.call @Main.half(%n, %one) : (i64, i64) -> i64
    return %h : i64
  }
}
