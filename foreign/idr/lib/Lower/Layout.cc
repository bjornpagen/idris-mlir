// Runtime layouts of idr values (LOW-DATA-1, LOW-BOX-1, LOW-CLOS-1).

#include "Lower/Layout.h"

using namespace mlir;

namespace idr::lower {

namespace {

// The size and alignment of a component: a scalar or a pointer.
unsigned sizeOf(Type type) {
  if (auto integer = dyn_cast<IntegerType>(type))
    return llvm::PowerOf2Ceil((integer.getWidth() + 7) / 8);
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
  for (const auto &field : fields)
    for (const Slot &slot : field)
      all.push_back(slot.type);
  return all;
}

Layouts::Layouts(ModuleOp m) : module(m) {
  auto note = [&](FlatSymbolRefAttr callee, unsigned captures) {
    auto key = std::make_pair(Attribute(callee), captures);
    if (labelIds.try_emplace(key, static_cast<unsigned>(labels.size())).second)
      labels.push_back(
          {callee, captures,
           module.lookupSymbol<func::FuncOp>(callee.getAttr()).getFunctionType()});
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
    return it->second;
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
      SmallVector<unsigned> slots;
      for (Type component : components(cast<TypeAttr>(field).getValue())) {
        auto chosen = static_cast<unsigned>(layout.slots.size());
        for (unsigned i = 0; i < layout.slots.size(); ++i)
          if (!used[i] && layout.slots[i] == component) {
            chosen = i;
            break;
          }
        if (chosen == layout.slots.size()) {
          layout.slots.push_back(component);
          used.push_back(false);
        }
        used[chosen] = true;
        slots.push_back(chosen);
      }
      perField.push_back(std::move(slots));
    }
    layout.fields[ctor.getSymName()] = std::move(perField);
  }
  return sums.try_emplace(name, std::move(layout)).first->second;
}

SmallVector<Type> Layouts::components(Type type) {
  MLIRContext *ctx = module.getContext();
  if (isa<ErasedType, WorldType>(type))
    return {};
  if (isa<StrType, BoxType, FnType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  if (isa<BigType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type))
    return sum(data.getName().getAttr()).types();
  return {type};
}

Cell Layouts::cellOf(ArrayRef<Type> fieldTypes, unsigned start) {
  Cell cell;
  unsigned at = start;
  for (Type field : fieldTypes) {
    SmallVector<Slot> slots;
    for (Type component : components(field)) {
      unsigned size = sizeOf(component);
      at = llvm::alignTo(at, size);
      slots.push_back({component, at});
      at += size;
    }
    cell.fields.push_back(std::move(slots));
  }
  cell.size = static_cast<unsigned>(llvm::alignTo(at, 8));
  return cell;
}

const Cell &Layouts::box(CtorOp ctor) {
  auto it = boxes.find(ctor);
  if (it != boxes.end())
    return it->second;
  SmallVector<Type> fields;
  for (Attribute field : ctor.getFieldTypes())
    fields.push_back(cast<TypeAttr>(field).getValue());
  return boxes.try_emplace(ctor, cellOf(fields, 8)).first->second;
}

const Cell &Layouts::closure(const Label &label) {
  unsigned id = labelId(label);
  auto it = closures.find(id);
  if (it != closures.end())
    return it->second;
  SmallVector<Type> fields{LLVM::LLVMPointerType::get(module.getContext())};
  llvm::append_range(fields, label.captureTypes());
  return closures.try_emplace(id, cellOf(fields, 8)).first->second;
}

} // namespace idr::lower
