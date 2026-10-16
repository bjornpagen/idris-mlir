# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What the ODS says beside its ops for the rest of the tree, written by
# idris-mlir-tblgen: the runtime's C functions the ops call, as C declares
# them (idris_rt_ops.h, which runtime/idris_rt.h includes) and as the
# lowering and the folders read them (IdrRuntimeAbi.inc); the word op of
# each big op (IdrBigToWord.inc); the rules a refusal names, with their
# categories, for the tests (IdrRules.txt); the role of each pass (IdrPassRoles.txt). They come first, so that the
# ops' headers' target, made after them, depends on them, and everything
# that waits on the ops' headers waits on these too.
set(TABLEGEN_OUTPUT "")
set(IDR_TABLEGEN_EXE idris-mlir-tblgen)
set(IDR_TABLEGEN_TARGET idris-mlir-tblgen)
set(LLVM_TARGET_DEFINITIONS IdrOps.td)
tablegen(IDR idris_rt_ops.h -gen-runtime-abi-decls)
tablegen(IDR IdrRuntimeAbi.inc -gen-runtime-abi-defs)
tablegen(IDR IdrBigToWord.inc -gen-big-to-word)
tablegen(IDR IdrRules.txt -gen-rule-list)
# The role of each pass, read from the passes' declarations, beside the
# rules for the tests (IdrPassRoles.txt).
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/../Transforms/Passes.td)
tablegen(IDR IdrPassRoles.txt -gen-pass-roles)
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
