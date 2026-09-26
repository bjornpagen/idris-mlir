// The idr dialect: types, verifiers, folders and effects
// (docs/architecture/08-idr-dialect.md).

#include "idr/Idr.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

#include "idr/IdrDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IdrTypes.cpp.inc"

#define GET_OP_CLASSES
#include "idr/IdrOps.cpp.inc"

namespace {

// IDR-IF-1: every idr op may be inlined anywhere.
struct IdrInliner : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;
  bool isLegalToInline(Operation *, Region *, bool, IRMapping &) const final {
    return true;
  }
  bool isLegalToInline(Region *, Region *, bool, IRMapping &) const final {
    return true;
  }
};

} // namespace

void IdrDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IdrTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "idr/IdrOps.cpp.inc"
      >();
  addInterfaces<IdrInliner>();
}

Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                           Type type, Location loc) {
  if (isa<ErasedType>(type) && isa<UnitAttr>(value))
    return ErasedOp::create(builder, loc, type);
  if (isa<StrType>(type))
    if (auto str = dyn_cast<StringAttr>(value))
      return StrLitOp::create(builder, loc, type, str);
  if (auto integer = dyn_cast<IntegerAttr>(value))
    return arith::ConstantOp::create(builder, loc, type, integer);
  return nullptr;
}

//===----------------------------------------------------------------------===//
// Lookup helpers
//===----------------------------------------------------------------------===//

DataOp idr::lookupData(Operation *from, DataType type) {
  return SymbolTable::lookupNearestSymbolFrom<DataOp>(from, type.getName());
}

CtorOp idr::lookupCtor(DataOp data, StringRef ctor) {
  if (!data)
    return nullptr;
  return dyn_cast_or_null<CtorOp>(SymbolTable::lookupSymbolIn(data, ctor));
}

SmallVector<CtorOp> DataOp::getCtors() {
  SmallVector<CtorOp> ctors;
  for (auto ctor : getBody().front().getOps<CtorOp>())
    ctors.push_back(ctor);
  return ctors;
}

//===----------------------------------------------------------------------===//
// Data declarations
//===----------------------------------------------------------------------===//

static bool isFieldType(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() &&
           llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  return isa<DataType, ErasedType, StrType, WorldType>(type);
}

// IDR-DATA-1, IDR-DATA-2
LogicalResult DataOp::verify() {
  uint64_t expected = 0;
  for (Operation &op : getBody().front()) {
    auto ctor = dyn_cast<CtorOp>(op);
    if (!ctor)
      return op.emitOpError("is not allowed inside idr.data");
    if (ctor.getTag() != expected)
      return ctor.emitOpError("has tag ")
             << ctor.getTag() << "; tags must be 0..n-1 in order";
    ++expected;
  }
  return success();
}

// IDR-DATA-2, IDR-DATA-3
LogicalResult CtorOp::verify() {
  auto types = getFieldTypes();
  auto quantities = getQuantities();
  if (types.size() != quantities.size())
    return emitOpError("needs one quantity per field");
  for (auto [typeAttr, quantityAttr] : llvm::zip(types, quantities)) {
    Type type = cast<TypeAttr>(typeAttr).getValue();
    StringRef quantity = cast<StringAttr>(quantityAttr).getValue();
    if (!isFieldType(type))
      return emitOpError("has a field of unsupported type ") << type;
    if (!llvm::is_contained({"0", "1", "w"}, quantity))
      return emitOpError("has quantity '") << quantity << "'";
    if ((quantity == "0") != isa<ErasedType>(type))
      return emitOpError("must use quantity 0 exactly for !idr.erased fields");
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Values
//===----------------------------------------------------------------------===//

OpFoldResult ErasedOp::fold(FoldAdaptor) { return UnitAttr::get(getContext()); }

OpFoldResult StrLitOp::fold(FoldAdaptor) { return getValueAttr(); }

// IDR-CON-1
LogicalResult ConOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto ref = getCtor();
  if (ref.getNestedReferences().size() != 1)
    return emitOpError("expects a constructor reference @T::@C");
  auto type = cast<DataType>(getResult().getType());
  if (ref.getRootReference() != type.getName().getAttr())
    return emitOpError("builds ") << ref << " but has type " << type;
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(*this, type.getName());
  CtorOp ctor = lookupCtor(data, ref.getLeafReference());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << ref;
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  for (auto [expected, value] : llvm::zip(types, getFields()))
    if (cast<TypeAttr>(expected).getValue() != value.getType())
      return emitOpError("field has type ")
             << value.getType() << ", expected " << expected;
  return success();
}

// IDR-FIELD-1
LogicalResult FieldOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto type = cast<DataType>(getValue().getType());
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(*this, type.getName());
  CtorOp ctor = lookupCtor(data, getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor @") << getCtor();
  auto types = ctor.getFieldTypes();
  if (getIndex() >= types.size())
    return emitOpError("field index out of range");
  if (cast<TypeAttr>(types[static_cast<unsigned>(getIndex())]).getValue() !=
      getResult().getType())
    return emitOpError("result type does not match the field type");
  return success();
}

// Folds to the tag of a known constructor, or 0 for a single-constructor type.
OpFoldResult TagOp::fold(FoldAdaptor) {
  auto index = [&](uint64_t tag) {
    return IntegerAttr::get(IndexType::get(getContext()), static_cast<int64_t>(tag));
  };
  if (auto con = getValue().getDefiningOp<ConOp>()) {
    auto type = cast<DataType>(con.getResult().getType());
    if (CtorOp ctor = lookupCtor(lookupData(*this, type),
                                 con.getCtor().getLeafReference()))
      return index(ctor.getTag());
  }
  if (DataOp data = lookupData(*this, cast<DataType>(getValue().getType())))
    if (data.getCtors().size() == 1)
      return index(0);
  return {};
}

OpFoldResult FieldOp::fold(FoldAdaptor) {
  auto con = getValue().getDefiningOp<ConOp>();
  if (!con || con.getCtor().getLeafReference() != getCtorAttr().getAttr())
    return {};
  return con.getFields()[static_cast<unsigned>(getIndex())];
}

//===----------------------------------------------------------------------===//
// Division (IDR-DIV-*, IDR-EFF-1)
//===----------------------------------------------------------------------===//

// Euclidean quotient and remainder (SEM-INT-3) on the mathematical values of
// `a` and `b` in `width` bits; the quotient wraps.
static std::pair<APInt, APInt> idrisDivMod(const APInt &a, const APInt &b,
                                           bool isSigned) {
  if (!isSigned)
    return {a.udiv(b), a.urem(b)};
  if (a.isMinSignedValue() && b.isAllOnes())
    return {a, APInt::getZero(a.getBitWidth())};
  APInt q = a.sdiv(b), r = a.srem(b);
  if (r.isNegative()) {
    if (b.isStrictlyPositive()) {
      q -= 1;
      r += b;
    } else {
      q += 1;
      r -= b;
    }
  }
  return {q, r};
}

template <typename OpT>
static OpFoldResult foldDivision(OpT op, Attribute lhsAttr, Attribute rhsAttr,
                                 bool quotient) {
  auto rhs = dyn_cast_or_null<IntegerAttr>(rhsAttr);
  if (!rhs || rhs.getValue().isZero())
    return {};
  if (rhs.getValue().isOne())
    return quotient ? OpFoldResult(op.getLhs())
                    : OpFoldResult(IntegerAttr::get(op.getType(), 0));
  auto lhs = dyn_cast_or_null<IntegerAttr>(lhsAttr);
  if (!lhs)
    return {};
  auto [q, r] = idrisDivMod(lhs.getValue(), rhs.getValue(), op.getIsSigned());
  return IntegerAttr::get(op.getType(), quotient ? q : r);
}

OpFoldResult DivOp::fold(FoldAdaptor adaptor) {
  return foldDivision(*this, adaptor.getLhs(), adaptor.getRhs(), true);
}

OpFoldResult ModOp::fold(FoldAdaptor adaptor) {
  return foldDivision(*this, adaptor.getLhs(), adaptor.getRhs(), false);
}

static bool divisorKnownNonZero(Value divisor) {
  APInt value;
  return matchPattern(divisor, m_ConstantInt(&value)) && !value.isZero();
}

template <typename OpT>
static void divisionEffects(
    OpT op,
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (!divisorKnownNonZero(op.getRhs()))
    effects.emplace_back(MemoryEffects::Write::get(), CrashResource::get());
}

void DivOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  divisionEffects(*this, effects);
}

void ModOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  divisionEffects(*this, effects);
}

Speculation::Speculatability DivOp::getSpeculatability() {
  return divisorKnownNonZero(getRhs()) ? Speculation::Speculatable
                                       : Speculation::NotSpeculatable;
}

Speculation::Speculatability ModOp::getSpeculatability() {
  return divisorKnownNonZero(getRhs()) ? Speculation::Speculatable
                                       : Speculation::NotSpeculatable;
}

//===----------------------------------------------------------------------===//
// Characters (IDR-CHAR-1)
//===----------------------------------------------------------------------===//

OpFoldResult ToCharOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!value)
    return {};
  const APInt &bits = value.getValue();
  bool negative = getIsSigned() && bits.isNegative();
  uint64_t code = negative || bits.getActiveBits() > 32 ? UINT64_MAX
                                                        : bits.getZExtValue();
  bool scalar = code <= 0xD7FF || (code >= 0xE000 && code <= 0x10FFFF);
  return IntegerAttr::get(getType(), scalar ? static_cast<int64_t>(code) : 0);
}
