# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect's declarations and definitions, which IdrDialect.h includes,
# read from the ODS the specification's generator writes into Generated/
# (committed, never edited, held to the specification by make check):
# enums, attributes, the dialect, the op, type and attribute interfaces,
# types and ops, and the bytecode (IdrOpsIncGen). IdrOps.td includes the
# dialect's base, interfaces and types. The interface generator writes only
# the interfaces of the file it is given, so it reads IdrInterfaces.td,
# which defines every interface of the dialect. Every other header the
# specification decides it writes itself into Generated/.
#
# The one generator of ours that runs here reads upstream's records: each
# upstream op the dialect admits is named in C++ by the alias the
# specification gives it, and idris-mlir-tblgen reads upstream's record of
# each op one admitted record file names, a run per file, since a record's
# name is unique only within its dialect's ODS
# (IdrAdmitted<Dialect>Classes.h.inc, which Generated/AdmittedClasses.h.inc
# includes). The files are the specification's outputs, so the list is
# theirs; the base file holds the records' classes and admits nothing.
file(GLOB IDR_ADMITTED_RECORDS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Generated/IdrAdmitted*.td")
list(REMOVE_ITEM IDR_ADMITTED_RECORDS "${CMAKE_CURRENT_SOURCE_DIR}/Generated/IdrAdmittedBase.td")
set(IDR_TABLEGEN_EXE idris-mlir-tblgen)
set(IDR_TABLEGEN_TARGET idris-mlir-tblgen)
foreach(records IN LISTS IDR_ADMITTED_RECORDS)
	get_filename_component(admitted "${records}" NAME_WE)
	set(LLVM_TARGET_DEFINITIONS "${records}")
	tablegen(IDR ${admitted}Classes.h.inc -gen-admitted-classes)
endforeach()

set(LLVM_TARGET_DEFINITIONS Generated/IdrInterfaces.td)
mlir_tablegen(IdrInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(IdrInterfaces.cpp.inc -gen-op-interface-defs)
mlir_tablegen(IdrTypeInterfaces.h.inc -gen-type-interface-decls)
mlir_tablegen(IdrTypeInterfaces.cpp.inc -gen-type-interface-defs)
mlir_tablegen(IdrAttrInterfaces.h.inc -gen-attr-interface-decls)
mlir_tablegen(IdrAttrInterfaces.cpp.inc -gen-attr-interface-defs)
# The dialect's bytecode: each record of IdrBytecode.td read by upstream's
# generated reader.
set(LLVM_TARGET_DEFINITIONS Generated/IdrBytecode.td)
mlir_tablegen(IdrBytecode.cpp.inc -gen-bytecode -bytecode-dialect="Idr")
set(LLVM_TARGET_DEFINITIONS Generated/IdrOps.td)
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
