# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What the ODS says beside its ops for the rest of the tree, written by
# idris-mlir-tblgen: the runtime's C functions the ops and the lowering call,
# as C declares them (idris_rt_ops.h, which runtime/idris_rt.h includes) and
# as the lowering and the folders read them (IdrRuntimeAbi.inc), from the
# ops' marks and the records beside them (IdrRuntime.td); the word op of
# each big op (IdrBigToWord.inc); the rules a refusal names, with their
# categories, for the tests (IdrRules.txt) and for refusalHead
# (IdrRuleCategories.inc); each guarded op's guards (IdrGuards.inc); the
# codes of a field of the bytecode's table of data types (IdrTable.h.inc);
# the role and the stage of each pass, for the tests (IdrPassRoles.txt,
# IdrPassStages.txt). They come first, so that the ops' headers' target,
# made after them, depends on them, and everything that waits on the ops'
# headers waits on these too.
set(TABLEGEN_OUTPUT "")
set(IDR_TABLEGEN_EXE idris-mlir-tblgen)
set(IDR_TABLEGEN_TARGET idris-mlir-tblgen)
set(LLVM_TARGET_DEFINITIONS IdrRuntime.td)
tablegen(IDR idris_rt_ops.h -gen-runtime-abi-decls)
tablegen(IDR IdrRuntimeAbi.inc -gen-runtime-abi-defs)
set(LLVM_TARGET_DEFINITIONS IdrOps.td)
tablegen(IDR IdrBigToWord.inc -gen-big-to-word)
tablegen(IDR IdrRules.txt -gen-rule-list)
tablegen(IDR IdrRuleCategories.inc -gen-rule-categories)
tablegen(IDR IdrGuards.inc -gen-guards)
set(LLVM_TARGET_DEFINITIONS IdrBytecode.td)
tablegen(IDR IdrTable.h.inc -gen-idr-table-codes)
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/../Transforms/Passes.td)
tablegen(IDR IdrPassRoles.txt -gen-pass-roles)
tablegen(IDR IdrPassStages.txt -gen-pass-stages)
add_public_tablegen_target(IdrRuntimeAbiIncGen)
set(TABLEGEN_OUTPUT "")

# The dialect's declarations and definitions, generated from the ODS into
# include/idr/IR, which IdrDialect.h includes: enums, attributes, the
# dialect, the op interfaces, types and ops (IdrOpsIncGen). IdrOps.td
# includes every other part of the ODS. The interface generator writes only
# the interfaces of the file it is given, so it reads IdrInterfaces.td, which
# defines every op and type interface of the dialect but one: the flow
# interface, which our ops declare in their ODS and whose edge vocabulary
# idr/IR/FlowEdges.h holds, generated from IdrFlow.td and included there.
set(LLVM_TARGET_DEFINITIONS IdrInterfaces.td)
mlir_tablegen(IdrInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(IdrInterfaces.cpp.inc -gen-op-interface-defs)
mlir_tablegen(IdrTypeInterfaces.h.inc -gen-type-interface-decls)
mlir_tablegen(IdrTypeInterfaces.cpp.inc -gen-type-interface-defs)
set(LLVM_TARGET_DEFINITIONS IdrFlow.td)
mlir_tablegen(IdrFlow.h.inc -gen-op-interface-decls)
mlir_tablegen(IdrFlow.cpp.inc -gen-op-interface-defs)
# The dialect's bytecode: each record of IdrBytecode.td read by upstream's
# generated reader (lib/IR/Bytecode.cpp holds what the records cannot say:
# the module's one table of data types).
set(LLVM_TARGET_DEFINITIONS IdrBytecode.td)
mlir_tablegen(IdrBytecode.cpp.inc -gen-bytecode -bytecode-dialect="Idr")
set(LLVM_TARGET_DEFINITIONS IdrOps.td)
mlir_tablegen(IdrEnums.h.inc -gen-enum-decls)
mlir_tablegen(IdrEnums.cpp.inc -gen-enum-defs)
mlir_tablegen(IdrAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=idr)
mlir_tablegen(IdrAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=idr)
mlir_tablegen(IdrDialect.h.inc -gen-dialect-decls -dialect=idr)
mlir_tablegen(IdrDialect.cpp.inc -gen-dialect-defs -dialect=idr)
mlir_tablegen(IdrTypes.h.inc -gen-typedef-decls -typedefs-dialect=idr)
mlir_tablegen(IdrTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=idr)
mlir_tablegen(IdrOps.h.inc -gen-op-decls)
mlir_tablegen(IdrOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(IdrOpsIncGen)
