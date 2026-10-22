// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's generated definition: its enums and attributes as
// mlir-tblgen defines them from the specification's printed ODS, its
// constants as folding materializes them, and what it registers when it is
// initialized. The types are registered where their storage is complete
// (registerTypes).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace idr;

#include "idr/IR/IdrDialect.cpp.inc"
#include "idr/IR/IdrEnums.cpp.inc"
#include "idr/IR/IdrAttrInterfaces.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.cpp.inc"

// idr.constant for the dialect's values and strings, and arith.constant
// for scalars: the two kinds of constant there are.
Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value, Type type,
                                           Location loc) {
  if (ConstantOp::isBuildableWith(value, type))
    return ConstantOp::create(builder, loc, type, value);
  if (arith::ConstantOp::isBuildableWith(value, type))
    return arith::ConstantOp::create(builder, loc, type, cast<TypedAttr>(value));
  return nullptr;
}

void IdrDialect::initialize() {
  registerTypes();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "idr/IR/IdrAttrs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >();
  addInlinerInterface(*this);
  detail::addAsmInterface(*this);
  detail::addBytecodeInterface(*this);
}
