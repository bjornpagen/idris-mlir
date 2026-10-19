// RUN: idris-mlir-opt %s --idr-expect=holds=stage=higher -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=stage=first -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-expect=holds=stage=lowered,lowered -o /dev/null
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-entry --idr-expect=holds=entry -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-demand -o /dev/null 2> %t.demand.err
// RUN: FileCheck %s --check-prefix=DEMAND < %t.demand.err
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-rc -o /dev/null 2> %t.twice.err
// RUN: FileCheck %s --check-prefix=TWICE < %t.twice.err
// The stage is the program's, said once: idr-defunctionalize brings it
// from higher to first, idr-rc from first to owned, idr-lower from owned
// to lowered, its functions upstream's in place, and idr-entry takes the
// program apart into the module, its root the entry @main. Each pass
// states the stage it runs at in its record, and refuses another: the
// in-place promise idr-demand checks is in the grades idr-rc writes.
// DEMAND: error: internal error: idr-demand runs on a program at owned, not first
// TWICE: error: internal error: idr-rc-cells runs on a program at first, not owned
idr.program @stages root(@Prog.main) stage(higher) {
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
