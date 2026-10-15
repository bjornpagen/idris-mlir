# The dialect's declarations and definitions, generated from the ODS into
# include/idr/IR, which IdrDialect.h includes: enums, attributes, the
# dialect, the op interfaces, types and ops (IdrOpsIncGen). IdrOps.td
# includes every other part of the ODS. The interface generator writes only
# the interfaces of the file it is given, so it reads IdrInterfaces.td, which
# defines every op interface of the dialect but one. The flow interface is
# held by every op as an external model; idr/IR/Flow.h includes what IdrFlow.td
# generates, and IdrDialect.h includes none of it.
set(LLVM_TARGET_DEFINITIONS IdrInterfaces.td)
mlir_tablegen(IdrInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(IdrInterfaces.cpp.inc -gen-op-interface-defs)
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
