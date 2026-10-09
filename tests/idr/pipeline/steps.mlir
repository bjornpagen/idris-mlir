// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir -c %s -o %t.o --dump-dir=%t.dir
// RUN: ls %t.dir > %t.dumps
// RUN: awk '!/^[0-9][0-9]-[a-z][a-z0-9-]*[.]mlir$/ { exit 1 } $0 + 0 != NR { exit 1 } END { if (NR < 2) exit 1 }' %t.dumps
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.pipeline.mlir
// RUN: sh -c 'for dump in %t.dir/*; do last=$dump; done; idris-mlir-opt "$last" -o %t.last.mlir'
// RUN: idris-mlir-opt %t.pipeline.mlir -o %t.again.mlir
// RUN: cmp %t.last.mlir %t.again.mlir
// RUN: rm -rf %t.without && mkdir -p %t.without
// RUN: idris-mlir -c %s -o %t.without.o --without=idr-returned-arguments,idr-stack,sink,reuse --dump-dir=%t.without
// RUN: ls %t.without | not grep -q 'idr-returned-arguments\|idr-stack'
// RUN: ls %t.without | grep -q 'idr-rc'
// RUN: %status 2 idris-mlir -c %s -o %t.bad.o --without=idr-lower
// RUN: %status 2 idris-mlir -c %s -o %t.bad.o --without=idr-sinking
// idris-mlir dumps the module after each step of its pipeline, one file
// per step, `<NN>-<step>.mlir` numbered in order from 01; and idris-mlir-opt's
// idr-pipeline is that same pipeline, on the module idr-target has given
// the build's target, as idris-mlir gives it: the module it ends with is
// the one idris-mlir dumped last. Which steps there are, and their order, are
// the pipeline's own business. --without leaves named steps out (and turns
// idr-rc's mechanisms off), for measuring what each is worth; a name that
// is no step, or idr-lower, is a usage error.
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
