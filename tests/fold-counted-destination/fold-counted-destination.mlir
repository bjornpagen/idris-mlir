// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned})' -o /dev/null
// A fold whose destination holds counted elements moves the destination
// into its result on tensors and, bufferized, writes it in place and gives
// nothing, the buffer staying with its holder; at each step its
// accumulator is taken out of the destination with the reference its place
// held, which the step moves on or gives up. @main reads a line, so the
// string is no constant, holds it in an array of no axis, and folds three
// steps over it, each appending the step's index to the accumulator, which
// it only reads: the accumulator is given up in its step and the appended
// string moves back in. The module starts on tensors and is verified after
// every pass to the owned stage, on its tensors and then on their buffers,
// so it verifies, with nothing expected, only where the fold's moves can
// be asked on buffers, where its tensor result is gone, and where counting
// and the linearity rule read the accumulator alike, as a value holding its
// own reference, given up once on every run of the step.
idr.program @folds root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %steps = arith.constant 3 : index
    %none = tensor.empty() : tensor<!idr.str>
    %init = idr.array.tabulate outs(%none : tensor<!idr.str>) {
      idr.array.yield %line : !idr.str
    } -> tensor<!idr.str>
    %folded = idr.array.fold_last [%steps] outs(%init : tensor<!idr.str>) {
    ^bb0(%i: index, %acc: !idr.str):
      %w = arith.index_cast %i : index to i64
      %digit = idr.str.show_sint %w : (i64) -> !idr.str
      %next = idr.str.append %acc, %digit : (!idr.str, !idr.str) -> !idr.str
      idr.array.yield %next : !idr.str
    } -> tensor<!idr.str>
    %text = tensor.extract %folded[] : tensor<!idr.str>
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
