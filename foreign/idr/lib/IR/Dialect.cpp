// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect's generated definition: its enums and attributes as
// mlir-tblgen defines them from the specification's printed ODS, its
// constants as folding materializes them, the identities of the operations
// an accumulator may combine, and what it registers when it is initialized.
// The types are registered where their storage is complete (registerTypes).

#include "idr/IR/IdrDialect.h"

// The attributes whose storage is hand C++ (a family's keeps beside its key
// what is computed of it when it is made, a big's keys its integer at its
// fewest bits): complete here, where the generated attribute classes are
// defined.
#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/Ops/BigStorage.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/Support/MathExtras.h"

#include <cstdint>
#include <tuple>

#include "idr/IR/Generated/Laws.h.inc"

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

namespace {

// The integer `value` as a constant of `type`: a big's literal, a natural's
// where it is not negative, or an integer's of the type's width where it
// fits. None at any other type, which no identity of the specification's is
// a value of.
std::optional<Attribute> literalAt(Type type, std::int64_t value) {
  Type plain = unrestricted(type);
  if (isa<BigType>(plain) || (isa<NatType>(plain) && value >= 0))
    return BigAttr::get(type.getContext(),
                        APInt(64, static_cast<std::uint64_t>(value), /*isSigned=*/true));
  if (!plain.isIntOrIndex())
    return std::nullopt;
  unsigned width =
      plain.isIndex() ? IndexType::kInternalStorageBitWidth : plain.getIntOrFloatBitWidth();
  if (!llvm::isIntN(width, value))
    return std::nullopt;
  return IntegerAttr::get(plain, value);
}

} // namespace

// One dispatch on the op's registered class, which only the open op set
// leaves to run time: a fold over the generated units, each a class and its
// identity.
std::optional<Attribute> laws::identityOf(Operation *op) {
  if (op->getNumResults() != 1)
    return std::nullopt;
  std::optional<Attribute> identity;
  std::apply(
      [&]<class... Us>(Us...) {
        (void)((isa<typename Us::Op>(op)
                    ? (identity = literalAt(op->getResult(0).getType(), Us::identity), true)
                    : false) ||
               ...);
      },
      laws::Units{});
  return identity;
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
