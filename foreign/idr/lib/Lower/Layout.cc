// Data layout for idr-lower (LOW-DATA-1).

#include "Lower/Layout.h"

using namespace mlir;

namespace idr::lower {

SmallVector<Type> Layout::types() const {
  SmallVector<Type> all;
  if (tag)
    all.push_back(tag);
  all.append(slots.begin(), slots.end());
  return all;
}

const Layout &Layouts::get(StringAttr name) {
  auto it = cache.find(name);
  if (it != cache.end())
    return it->second;
  auto data = module.lookupSymbol<idr::DataOp>(name);
  Layout layout;
  auto ctors = data.getCtors();
  Builder b(module.getContext());
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = b.getIntegerType(width);
  }
  for (idr::CtorOp ctor : ctors) {
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
  return cache.try_emplace(name, std::move(layout)).first->second;
}

SmallVector<Type> Layouts::components(Type type) {
  Builder b(module.getContext());
  if (isa<idr::ErasedType, idr::WorldType>(type))
    return {};
  if (isa<idr::StrType>(type))
    return {LLVM::LLVMPointerType::get(module.getContext()), b.getI64Type()};
  if (auto data = dyn_cast<idr::DataType>(type))
    return get(data.getName().getAttr()).types();
  return {type};
}

} // namespace idr::lower
