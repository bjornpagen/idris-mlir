# The schedule library's transform op, generated into
# include/idr/Target/ScheduleOps.{h,cpp}.inc, which Schedules.cpp alone
# includes (IdrScheduleOpsIncGen).
set(LLVM_TARGET_DEFINITIONS ScheduleOps.td)
mlir_tablegen(ScheduleOps.h.inc -gen-op-decls)
mlir_tablegen(ScheduleOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(IdrScheduleOpsIncGen)
