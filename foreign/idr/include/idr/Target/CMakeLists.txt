# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The schedule library's transform op, generated into
# include/idr/Target/ScheduleOps.{h,cpp}.inc, which Schedules.cpp alone
# includes (IdrScheduleOpsIncGen), from the record the specification's
# generator writes beside the dialect's own ops: it is an op of upstream's
# transform dialect, so it is read apart from them (IR/Generated).
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/../IR/Generated/IdrTransformOps.td)
mlir_tablegen(ScheduleOps.h.inc -gen-op-decls)
mlir_tablegen(ScheduleOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(IdrScheduleOpsIncGen)
