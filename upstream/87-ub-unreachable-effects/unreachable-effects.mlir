// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//
// mlir-opt unreachable-effects.mlir -canonicalize
//
// At the pin the execute_region stays: ub.unreachable declares no memory
// effects, which a reader of effects takes for every effect, so the region
// op is not trivially dead. With the patch it goes, and the function is a
// bare return. no_inline keeps the region from being inlined instead.
func.func @dead_region_ending_in_unreachable() {
  scf.execute_region no_inline {
    ub.unreachable
  }
  return
}
