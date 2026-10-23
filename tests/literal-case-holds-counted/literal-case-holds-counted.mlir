// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A literal match moves its scrutinee into the binding of each of its
// regions, a case's binding equal to its key, so a scrutinee whose count
// frees it is held in every region by that region's binding, which gives
// it up there, and no path leaves a reference that nothing gives up. @main
// reads a line, a string its count frees, and matches it: the case of "a"
// reads nothing of its binding, the case of "bb" reads its binding's
// length, and the default reads its binding's length too. The slice from
// the graded stage to the owned stage is verified after every pass, and
// once the program is counted the linearity rule holds each binding to one
// giving up on every path that goes on, so it verifies, with nothing
// expected, only where every region gives its binding up.
idr.program @lines root(@main) stage(graded) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %n = idr.lit.match %line : !idr.str -> (i64) {
    case "a"(%a: !idr.str) {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    case "bb"(%b: !idr.str) {
      %length = idr.str.length %b : (!idr.str) -> i64
      idr.yield %length : i64
    }
    default(%d: !idr.str) {
      %length = idr.str.length %d : (!idr.str) -> i64
      idr.yield %length : i64
    }
    }
    %text = idr.str.show_sint %n : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
