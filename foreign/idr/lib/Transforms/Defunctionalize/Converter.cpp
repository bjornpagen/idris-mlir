// The types of the conversion and the one materialization between them.
//
// A value's type is its slot's: the value conversion answers it from the
// key decision, so a match case's argument has its field's type, a fold's
// element its array's, a force's result its cell's `forced` slot, and every
// other value the type the labels the analysis found for it decided. The
// type conversion keeps a grade around its carrier and retypes an array by
// its elements' slot; a bare closure or suspension type has no slot
// without a value, so it has no conversion of its own.
//
// Where a value moves between slots of two keys (call operand to argument,
// return to result, yield to match result, field, element, capture, and
// through a rewritten apply to and from its labels), the patterns ask for
// the target materialization: a match that rebuilds each constructor of the
// one sum in the other, the labels' with their captures and a cell's states
// with its value. No source materialization exists: a value the conversion
// left in its old type is a closure or a suspension nothing lowers, so a
// conversion that needs one fails.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::defunctionalize {

SlotTypeConverter::SlotTypeConverter(Slots &slots) : keys(slots) {
  // The most recently added conversion is tried first, and only those
  // added after the last one that reads a value are cached. The type alone
  // answers, once per type, every type that names no closure or suspension
  // carrier, which is every value the key decision holds no key for; it
  // declines a carrier, and the value's slot answers.
  addConversion([this](Value value, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
    out.push_back(keys.typeOf(value));
    return success();
  });
  addConversion([this](Type type) -> std::optional<Type> {
    if (isa<FnType, LazyType>(unrestricted(type)))
      return std::nullopt;
    return keys.arrayed(type);
  });
  addTargetMaterialization([this](OpBuilder &b, Type to, ValueRange inputs, Location loc) -> Value {
    if (inputs.size() != 1)
      return nullptr;
    return rebuild(b, to, inputs.front(), loc);
  });
}

bool SlotTypeConverter::legal(Operation *op) const {
  // Only a use of the module as it was has a slot to move into; a use the
  // conversion made was made with its value already moved.
  for (OpOperand &use : op->getOpOperands()) {
    if (!legal(use.get()))
      return false;
    Key to = keys.sinkKey(use);
    if (to.first && keys.needsCoercion(keys.keyOf(use.get()), to))
      return false;
  }
  if (!llvm::all_of(op->getResults(), [&](Value result) { return legal(result); }))
    return false;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (!llvm::all_of(block.getArguments(), [&](Value arg) { return legal(arg); }))
        return false;
  return true;
}

// A linear value is used once, rebuilt, and enters the other linear slot.
Value SlotTypeConverter::coerce(OpBuilder &b, Location loc, Value value, const Key &from,
                                const Key &to, Type sink) const {
  if (!keys.needsCoercion(from, to))
    return value;
  if (isLinear(value.getType())) {
    Value used = LinUseOp::create(b, loc, unrestricted(value.getType()), value);
    Value moved = coerce(b, loc, used, from, to, unrestricted(sink));
    if (!moved)
      return nullptr;
    return LinEnterOp::create(b, loc, linear(moved.getType()), moved);
  }
  // A value no slot of the program ever holds, or one moving into a slot no
  // label reaches, a move that never runs, is the program's poison, as any
  // poison is.
  if (keys.unreached(from) || Slots::isEmpty(to))
    return ub::PoisonOp::create(b, loc, sink);
  return materializeTargetConversion(b, loc, sink, value);
}

Value SlotTypeConverter::coerceOperand(OpBuilder &b, OpOperand &use, Value remapped) const {
  Value original = use.get();
  if (!isKeyed(original.getType()))
    return remapped;
  Key to = keys.sinkKey(use);
  if (!to.first)
    return remapped;
  return coerce(b, use.getOwner()->getLoc(), remapped, keys.keyOf(original), to,
                keys.typeOf(original.getType(), to));
}

LogicalResult SlotTypeConverter::coerceOperands(OpBuilder &b, Operation *op, ValueRange remapped,
                                                SmallVectorImpl<Value> &out) const {
  for (auto [use, value] : llvm::zip_equal(op->getOpOperands(), remapped)) {
    Value moved = coerceOperand(b, use, value);
    if (!moved)
      return failure();
    out.push_back(moved);
  }
  return success();
}

namespace {

// Each constructor of the sum `from` with the one of the same name in the
// sum `to`, whose fields hold the same values at their own grades; none
// when `to` lacks one, or when only one of them is a memo sum.
std::optional<SmallVector<std::pair<CtorOp, CtorOp>>> counterparts(SymbolTable &table, Type from,
                                                                    Type to) {
  DataOp source = getSumName(from) ? lookupData(table, from) : DataOp();
  DataOp into = getSumName(to) ? lookupData(table, to) : DataOp();
  if (!source || !into || isMemo(source) != isMemo(into))
    return std::nullopt;
  SmallVector<std::pair<CtorOp, CtorOp>> out;
  for (CtorOp ctor : source.getCtors()) {
    CtorOp same = lookupCtor(into, ctor.getSymName());
    if (!same || same.getFieldTypes().size() != ctor.getFieldTypes().size())
      return std::nullopt;
    for (auto [field, held] : llvm::zip(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                                        same.getFieldTypes().getAsValueRange<TypeAttr>()))
      if (unrestricted(field) != unrestricted(held))
        return std::nullopt;
    out.push_back({ctor, same});
  }
  return out;
}

// A match on `value` over its constructors, each case binding the fields at
// the scrutinee's grade and building the counterpart in `to` with them held
// as its fields.
Value rebuildIn(OpBuilder &b, Location loc, Type to, Value value,
                ArrayRef<std::pair<CtorOp, CtorOp>> pairs) {
  Type from = value.getType();
  StringAttr target = getSumName(to).getAttr();
  SmallVector<Attribute> cases;
  for (auto [ctor, same] : pairs)
    cases.push_back(FlatSymbolRefAttr::get(ctor.getSymNameAttr()));
  OpBuilder::InsertionGuard guard(b);
  auto made = MatchOp::create(b, loc, TypeRange{to}, value, b.getArrayAttr(cases),
                              static_cast<unsigned>(cases.size()));
  for (auto [pair, region] : llvm::zip(pairs, made.getRegions())) {
    auto [ctor, same] = pair;
    SmallVector<Type> bound;
    for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      bound.push_back(fieldType(from, field));
    Block *block = b.createBlock(&region, region.end(), bound,
                                 SmallVector<Location>(bound.size(), loc));
    SmallVector<Value> held;
    for (auto [arg, type] :
         llvm::zip(block->getArguments(), same.getFieldTypes().getAsValueRange<TypeAttr>()))
      held.push_back(heldAs(b, loc, arg, type));
    auto ref = SymbolRefAttr::get(target, {FlatSymbolRefAttr::get(same.getSymNameAttr())});
    Value rebuilt = ConOp::create(b, loc, to, ref, held);
    YieldOp::create(b, loc, rebuilt);
  }
  return made.getResult(0);
}

} // namespace

// `value`, of one sum, as a value of the sum `to`. A memo sum's `running`
// and `forced` are constructors like its labels, so a cell keeps its state.
// Null, with nothing built, when `to` cannot hold every constructor of
// `value`'s sum: a move the decision did not allow.
Value SlotTypeConverter::rebuild(OpBuilder &b, Type to, Value value, Location loc) const {
  Type from = value.getType();
  if (isLinear(from) != isLinear(to))
    return nullptr;
  auto pairs = counterparts(keys.symbols(), unrestricted(from), unrestricted(to));
  if (!pairs)
    return nullptr;
  if (!isLinear(from))
    return rebuildIn(b, loc, to, value, *pairs);
  Value used = LinUseOp::create(b, loc, unrestricted(from), value);
  Value moved = rebuildIn(b, loc, unrestricted(to), used, *pairs);
  return LinEnterOp::create(b, loc, to, moved);
}

} // namespace idr::defunctionalize
