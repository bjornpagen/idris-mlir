// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir-cc %s -o %t.o --dump-after=all --dump-dir=%t.dir
// RUN: ls %t.dir > %t.dumps
// RUN: awk '!/^[0-9][0-9]-[a-z][a-z0-9-]*[.]mlir$/ { exit 1 } $0 + 0 != NR { exit 1 } END { if (NR < 2) exit 1 }' %t.dumps
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.pipeline.mlir
// RUN: sh -c 'for dump in %t.dir/*; do last=$dump; done; idris-mlir-opt "$last" -o %t.last.mlir'
// RUN: idris-mlir-opt %t.pipeline.mlir -o %t.again.mlir
// RUN: cmp %t.last.mlir %t.again.mlir
// idris-mlir-cc dumps the module after each step of its pipeline, one file
// per step, `<NN>-<step>.mlir` numbered in order from 01; and idris-mlir-opt's
// idr-pipeline is that same pipeline, on the module idr-target has given
// the build's target, as idris-mlir-cc gives it: the module it ends with is
// the one idris-mlir-cc dumped last. Which steps there are, and their order, are
// the pipeline's own business.
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
