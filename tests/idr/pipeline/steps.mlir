// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir -c %s -o %t.o --dump-dir=%t.dir
// RUN: ls %t.dir > %t.dumps
// RUN: awk '!/^[0-9][0-9]-[a-z][a-z0-9-]*[.]mlir$/ { exit 1 } $0 + 0 != NR { exit 1 } END { if (NR < 2) exit 1 }' %t.dumps
// RUN: head -n 1 %t.dumps | grep -qx 01-idr-target.mlir
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
// RUN: %status 2 idris-mlir -c %s -o %t.bad.o --without=idr-redirect
// RUN: %status 2 idris-mlir -c %s -o %t.bad.o --without=idr-rc-place
// idris-mlir dumps the module after each pass its manager runs, one file
// per pass, `<NN>-<pass>.mlir` numbered in order from 01, the first
// idr-target, which sets the build's target (a nested group is named by
// the first pass it ran); and idris-mlir-opt's
// idr-pipeline is that same pipeline, on the module idr-target has given
// the build's target, as idris-mlir gives it: the module it ends with is
// the one idris-mlir dumped last. Which steps there are, and their order, are
// the pipeline's own business. --without leaves named steps out (and turns
// idr-rc's mechanisms off), for measuring what each is worth; a name that
// is no step, or idr-lower, is a usage error, and so is a pass of the
// simplify round or one a step runs nested inside itself.
module attributes {idr.program} {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
