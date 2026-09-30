// Runtime layouts of idr values.

#include "Lower/Layout.h"

using namespace mlir;

namespace idr::lower {

namespace {

// The size and alignment of a component: a scalar or a pointer.
unsigned sizeOf(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return static_cast<unsigned>(llvm::PowerOf2Ceil((integer.getWidth() + 7) / 8));
  return 8;
}

} // namespace

SmallVector<Type> SumLayout::types() const {
  SmallVector<Type> all;
  if (tag)
    all.push_back(tag);
  all.append(slots.begin(), slots.end());
  return all;
}

SmallVector<Type> Cell::members(MLIRContext *ctx) const {
  auto i32 = IntegerType::get(ctx, 32);
  SmallVector<Type> all{i32, i32};
  for (auto [field, component] : order)
    all.push_back(fields[field][component].type);
  return all;
}

Layouts::Layouts(ModuleOp m) : module(m) {
  auto note = [&](FlatSymbolRefAttr callee, unsigned captures) {
    auto key = std::make_pair(Attribute(callee), captures);
    auto fn = module.lookupSymbol<func::FuncOp>(callee.getAttr());
    if (fn && labelIds.try_emplace(key, static_cast<unsigned>(labels.size())).second)
      labels.push_back({callee, captures, fn.getFunctionType()});
  };
  module.walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto closure = dyn_cast<ClosureOp>(op))
      note(closure.getCalleeAttr(), static_cast<unsigned>(closure.getCaptures().size()));
    op->getAttrDictionary().walk([&](ClosureAttr closure) {
      note(closure.getCallee(), static_cast<unsigned>(closure.getCaptures().size()));
    });
  });
}

unsigned Layouts::labelId(FlatSymbolRefAttr callee, unsigned captures) const {
  return labelIds.lookup(std::make_pair(Attribute(callee), captures));
}

const SumLayout &Layouts::sum(StringAttr name) {
  auto it = sums.find(name);
  if (it != sums.end())
    return *it->second;
  auto data = module.lookupSymbol<DataOp>(name);
  SumLayout layout;
  auto ctors = data.getCtors();
  Builder b(module.getContext());
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = b.getIntegerType(width);
  }
  for (CtorOp ctor : ctors) {
    SmallVector<bool> used(layout.slots.size(), false);
    SmallVector<SmallVector<unsigned>> perField;
    for (Attribute field : ctor.getFieldTypes()) {
      Type fieldType = cast<TypeAttr>(field).getValue();
      SmallVector<unsigned> slots;
      for (auto [component, isCounted] :
           llvm::zip_equal(components(fieldType), counted(fieldType))) {
        auto chosen = static_cast<unsigned>(layout.slots.size());
        for (unsigned i = 0; i < layout.slots.size(); ++i)
          if (!used[i] && layout.slots[i] == component && layout.counted[i] == isCounted) {
            chosen = i;
            break;
          }
        if (chosen == layout.slots.size()) {
          layout.slots.push_back(component);
          layout.counted.push_back(isCounted);
          used.push_back(false);
        }
        used[chosen] = true;
        slots.push_back(chosen);
      }
      perField.push_back(std::move(slots));
    }
    layout.fields[ctor.getSymName()] = std::move(perField);
  }
  auto &slot = sums[name];
  slot = std::make_unique<SumLayout>(std::move(layout));
  return *slot;
}

SmallVector<Type> Layouts::components(Type type) {
  MLIRContext *ctx = module.getContext();
  // Linearity is a fact for the passes; at runtime the value is itself.
  type = unrestricted(type);
  if (isa<ErasedType, WorldType>(type))
    return {};
  if (isa<StrType, BoxType, FnType, TokenType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type))
    return sum(data.getName().getAttr()).types();
  return {type};
}

SmallVector<bool> Layouts::counted(Type type) {
  type = unrestricted(type);
  if (isa<ErasedType, WorldType>(type))
    return {};
  if (isa<StrType, BoxType, FnType, TokenType, BigType, NatType>(type))
    return {true};
  if (auto data = dyn_cast<DataType>(type)) {
    const SumLayout &layout = sum(data.getName().getAttr());
    SmallVector<bool> all;
    if (layout.tag)
      all.push_back(false);
    all.append(layout.counted.begin(), layout.counted.end());
    return all;
  }
  return {false};
}

Cell Layouts::cellOf(ArrayRef<Type> fieldTypes, unsigned leading) {
  Cell cell;
  SmallVector<SmallVector<bool>> countedness;
  for (Type field : fieldTypes) {
    SmallVector<Slot> slots;
    for (Type component : components(field))
      slots.push_back({component, 0});
    cell.fields.push_back(std::move(slots));
    countedness.push_back(counted(field));
  }
  unsigned at = 8;
  auto place = [&](unsigned field, unsigned component) {
    Slot &slot = cell.fields[field][component];
    unsigned size = sizeOf(slot.type);
    at = static_cast<unsigned>(llvm::alignTo(at, size));
    slot.offset = at;
    at += size;
    cell.order.push_back({field, component});
  };
  auto fields = static_cast<unsigned>(fieldTypes.size());
  for (unsigned f = 0; f < std::min(leading, fields); ++f)
    for (unsigned c = 0; c < cell.fields[f].size(); ++c)
      place(f, c);
  // The object slots, each 8 bytes, so contiguous.
  for (unsigned f = leading; f < fields; ++f)
    for (unsigned c = 0; c < cell.fields[f].size(); ++c)
      if (countedness[f][c]) {
        place(f, c);
        ++cell.objs;
      }
  for (unsigned f = leading; f < fields; ++f)
    for (unsigned c = 0; c < cell.fields[f].size(); ++c)
      if (!countedness[f][c])
        place(f, c);
  cell.size = static_cast<unsigned>(llvm::alignTo(at, 8));
  return cell;
}

const Cell &Layouts::box(CtorOp ctor) {
  auto it = boxes.find(ctor);
  if (it != boxes.end())
    return *it->second;
  SmallVector<Type> fields;
  for (Attribute field : ctor.getFieldTypes())
    fields.push_back(cast<TypeAttr>(field).getValue());
  auto cell = std::make_unique<Cell>(cellOf(fields, 0));
  return *(boxes[ctor] = std::move(cell));
}

const Cell &Layouts::closure(const Label &label) {
  unsigned id = labelId(label);
  auto it = closures.find(id);
  if (it != closures.end())
    return *it->second;
  SmallVector<Type> fields{LLVM::LLVMPointerType::get(module.getContext())};
  llvm::append_range(fields, label.captureTypes());
  auto cell = std::make_unique<Cell>(cellOf(fields, 1));
  return *(closures[id] = std::move(cell));
}

} // namespace idr::lower
