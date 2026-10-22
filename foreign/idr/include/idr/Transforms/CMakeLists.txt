# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The passes' declarations, registration and bases, generated into
# include/idr/Transforms/Passes.h.inc, which each area header includes with
# the GEN_PASS_DECL_ of its own passes (IdrPassesIncGen), from the records
# the specification's generator writes (IR/Generated/IdrPasses.td).
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/../IR/Generated/IdrPasses.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Idr)
# The steps only idr-optimize's inner pipeline runs: their bases, options
# and statistics, with no registration, so no tool can run one alone.
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/../IR/Generated/IdrInnerPasses.td)
mlir_tablegen(InnerPasses.h.inc -gen-pass-decls -name IdrInner)
add_public_tablegen_target(IdrPassesIncGen)
