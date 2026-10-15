// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's generated definition: its attributes and enums as
// TableGen defines them, its constants as folding materializes them,
// upstream's patterns it adds to every op's, and what it registers when it
// is initialized. The types are lib/IR/Types.cpp's, where a data type's
// storage is complete, which registering one needs.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/Transforms/Transforms.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace idr;

#include "idr/IR/IdrDialect.cpp.inc"
#include "idr/IR/IdrEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.cpp.inc"

// idr.constant for the dialect's values and strings, and
// arith.constant for scalars.
Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                           Type type, Location loc) {
  if (ConstantOp::isBuildableWith(value, type))
    return ConstantOp::create(builder, loc, type, value);
  if (arith::ConstantOp::isBuildableWith(value, type))
    return arith::ConstantOp::create(builder, loc, type, cast<TypedAttr>(value));
  return nullptr;
}

// The dimension of an array, `memref.dim` of an `idr.array.new`, is the
// size the array was made with: upstream's resolution of a dimension
// through ReifyRankedShapedTypeOpInterface, which idr.array.new
// implements, as a canonicalization.
void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  memref::populateResolveRankedShapedTypeResultDimsPatterns(results);
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
}
