// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned})' -o /dev/null
// A scan reads its counted input and keeps it with its holder, and moves
// its destination into its result on tensors and, bufferized, writes it in
// place and gives nothing; each accumulator is a copy of what the input or
// the step before wrote, with a reference of its own, which the step moves
// on or gives up. @main reads a line, so the string is no constant, holds
// it in an array of no axis as the scan's input, and scans three steps
// into an array of three, each appending the step's index to the
// accumulator, which it only reads; it writes the last. The module starts
// on tensors and is verified after every pass to the owned stage, on its
// tensors and then on their buffers, so it verifies, with nothing
// expected, only where the scan's moves can be asked on buffers, where its
// tensor result is gone, and where counting and the linearity rule read the
// accumulator alike, as a value holding its own reference, given up once on
// every run of the step, and the input as only read.
idr.program @scans root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %steps = arith.constant 3 : index
    %last = arith.constant 2 : index
    %none = tensor.empty() : tensor<!idr.str>
    %init = idr.array.tabulate outs(%none : tensor<!idr.str>) {
      idr.array.yield %line : !idr.str
    } -> tensor<!idr.str>
    %dest = tensor.empty() : tensor<3x!idr.str>
    %scanned = idr.array.scan_last [%steps] ins(%init : tensor<!idr.str>) outs(%dest : tensor<3x!idr.str>) {
    ^bb0(%i: index, %acc: !idr.str):
      %w = arith.index_cast %i : index to i64
      %digit = idr.str.show_sint %w : (i64) -> !idr.str
      %next = idr.str.append %acc, %digit : (!idr.str, !idr.str) -> !idr.str
      idr.array.yield %next : !idr.str
    } -> tensor<3x!idr.str>
    %text = tensor.extract %scanned[%last] : tensor<3x!idr.str>
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
