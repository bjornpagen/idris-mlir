// RUN: idris-mlir-opt %s --idr-expect=holds=stage=higher -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=stage=first -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-expect=holds=stage=lowered,lowered -o %t.lowered.mlir
// RUN: %differential %s %t.lowered.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.lowered.mlir
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-entry --idr-expect=holds=entry -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-demand -o /dev/null 2> %t.demand.err
// RUN: FileCheck %s --check-prefix=DEMAND < %t.demand.err
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-rc -o /dev/null 2> %t.twice.err
// RUN: FileCheck %s --check-prefix=TWICE < %t.twice.err
// RUN: %status 1 idris-mlir-opt %s --idr-lower -o /dev/null 2> %t.early.err
// RUN: FileCheck %s --check-prefix=EARLY < %t.early.err
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-defunctionalize -o /dev/null 2> %t.back.err
// RUN: FileCheck %s --check-prefix=BACK < %t.back.err
// The stage is the program's, said once: idr-defunctionalize brings it
// from higher to first, idr-rc from first to owned, idr-lower from owned
// to lowered, its functions upstream's in place, and idr-entry takes the
// program apart into the module, its root the entry @main. Each pass
// states the stage it runs at in its record, and refuses another: the
// in-place promise idr-demand checks is in the grades idr-rc writes. No
// step is skipped (idr-lower on a program still at higher) and none goes
// back (idr-defunctionalize on a lowered one). The program, taken down the
// stages a step at a time, exits with the 42 its closure computes, as the
// program as written and the reference at the end (REF) do
// (%differential, on the one input, none, since it reads none).
// STDIN:
// DEMAND: error: internal error: idr-demand runs on a program at owned, not first
// TWICE: error: internal error: idr-rc-cells runs on a program at first, not owned
// EARLY: error: internal error: idr-lower runs on a program at owned, not higher
// BACK: error: internal error: idr-defunctionalize runs on a program at higher, not lowered
idr.program @stages root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 21 : i64
    %f = idr.closure @twice() : () -> !idr.fn<(i64) -> (i64)>
    %y = idr.apply %f(%c) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %c = arith.constant 42 : i64
// REF:     return %c : i64
// REF:   }
// REF: }
