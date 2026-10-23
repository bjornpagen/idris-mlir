// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A big an analysis proves fits a small becomes a word, and where a value
// that is no word's reader needs the big, the small of the word stands
// there: a word with no cell, typed as static data, which nothing frees
// and no count writes, so a small that is only read is given up nowhere.
// @main reads a line, takes its length's low byte, so the analysis bounds
// it, and makes an Integer of it and its sum with itself, which fits a
// small and becomes a word sum; the decimal text of the sum has no word
// form, so the small of the sum is read by it once, and nothing else uses
// it. The slice from the graded stage to the owned stage is verified after
// every pass, and once the program is counted the linearity rule holds
// every value its count frees to one giving up on every path that goes
// on, so it verifies, with nothing expected, only where the small read
// once holds no reference of its own.
idr.program @shown root(@main) stage(graded) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %length = idr.str.length %line : (!idr.str) -> i64
    %mask = arith.constant 255 : i64
    %byte = arith.andi %length, %mask : i64
    %a = idr.big.from_sint %byte : (i64) -> !idr.big
    %b = idr.big.add %a, %a : (!idr.big, !idr.big) -> !idr.big
    %text = idr.big.show %b : (!idr.big) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
