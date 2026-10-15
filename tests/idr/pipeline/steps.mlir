// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: idris-mlir -c %s -o %t.o -mlir-print-ir-after-all -mlir-print-ir-tree-dir=%t.dir
// RUN: ls %t.dir/builtin_module_no-symbol-name | grep '[.]mlir$' | sort -n > %t.dumps
// RUN: awk '!/^[0-9]+_[a-z][a-z0-9-]*[.]mlir$/ { exit 1 } $0 + 0 != NR - 1 { exit 1 } END { if (NR < 2) exit 1 }' %t.dumps
// RUN: head -n 1 %t.dumps | grep -qx 0_idr-target.mlir
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.pipeline.mlir
// RUN: sh -c 'idris-mlir-opt "%t.dir/builtin_module_no-symbol-name/$(tail -n 1 %t.dumps)" -o %t.last.mlir'
// RUN: idris-mlir-opt %t.pipeline.mlir -o %t.again.mlir
// RUN: cmp %t.last.mlir %t.again.mlir
// NEEDS-ACCEPTANCE: the tree printer's directory for the module (builtin_module_no-symbol-name) and its file names (<n>_<pass>.mlir), as the pinned MLIR writes them.
// idris-mlir prints the module after each pass its manager runs through
// upstream's IR printer, into a tree of files: the module's own passes as
// `<n>_<pass>.mlir`, numbered in order from 0, the first idr-target, which
// sets the build's target; a pass run on every function prints into each
// function's directory below. idris-mlir-opt's idr-pipeline is that same
// pipeline, on the module idr-target has given the build's target, as
// idris-mlir gives it: the module it ends with is the one idris-mlir
// printed last. Which steps there are, and their order, are the
// pipeline's own business; no option of the compiler leaves one out.
module {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
