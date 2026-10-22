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
#include <optional>
#include <string_view>
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

std::optional<APInt> idr::integerAt(Type type, std::int64_t value) {
  Type plain = unrestricted(type);
  if (isa<BigType>(plain) || (isa<NatType>(plain) && value >= 0))
    return APInt(64, static_cast<std::uint64_t>(value), /*isSigned=*/true);
  if (!plain.isIntOrIndex())
    return std::nullopt;
  unsigned width =
      plain.isIndex() ? IndexType::kInternalStorageBitWidth : plain.getIntOrFloatBitWidth();
  if (!llvm::isIntN(width, value))
    return std::nullopt;
  return APInt(width, static_cast<std::uint64_t>(value), /*isSigned=*/true);
}

namespace {

// The integer `value` as a constant of `type`, made from its integer there:
// a big's literal at a big or a natural, an integer attribute of the plain
// type at a word. None where it is no value of the type.
std::optional<Attribute> literalAt(Type type, std::int64_t value) {
  std::optional<APInt> integer = integerAt(type, value);
  if (!integer)
    return std::nullopt;
  Type plain = unrestricted(type);
  if (isa<BigType>(plain) || isa<NatType>(plain))
    return BigAttr::get(type.getContext(), *integer);
  return IntegerAttr::get(plain, *integer);
}

// The string `value` as a constant of `type`: a string's literal at a
// string. None at any other type.
std::optional<Attribute> literalAt(Type type, std::string_view value) {
  if (!isa<StrType>(unrestricted(type)))
    return std::nullopt;
  return StringAttr::get(type.getContext(), llvm::StringRef(value.data(), value.size()));
}

} // namespace

// One dispatch on the op's registered class, which only the open op set
// leaves to run time: a fold over the generated units, each a class and its
// identity, an integer or a string, made the constant of its kind.
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
