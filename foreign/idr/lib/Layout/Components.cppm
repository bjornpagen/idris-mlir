// idr.layout:components: the runtime components of the value types of a
// module, and which of them a cell's header counts. They are the same on
// every target: what a component takes in bytes is Layouts', and what is
// counted is not a matter of bytes.
export module idr.layout:components;

import idr.mlir;
import idr.dialect;

import :sums;

export namespace idr::layout {

class Components {
public:
  // The components of the values of `m`, by its declarations as they are
  // now: a declaration that changes after this is not seen.
  explicit Components(mlir::ModuleOp m);

  // The declaration named `name`, or null.
  DataOp declaration(mlir::StringAttr name) const;

  // The runtime components of a value type: none for !idr.erased and
  // !idr.world, the slots of an unboxed sum, one pointer for strings, boxes
  // (memo cells included) and reuse tokens, one i64 for bigs, the type
  // itself for scalars. A !idr.fn that idr-defunctionalize leaves is a
  // value the program never reaches, and it is still lowered, as one
  // pointer.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);
  // For each of those components, whether it is counted: a pointer to a
  // cell, a big's word, or a counted slot of a sum.
  llvm::SmallVector<bool> counted(mlir::Type type);

  // The number of counted components of a value of `type`, and of values
  // of `types` side by side: the object slots they take in a cell.
  unsigned objects(mlir::Type type);
  unsigned objects(llvm::ArrayRef<mlir::Type> types);

  // The layout of the unboxed sum named `name`, computed once.
  const SumLayout &sum(mlir::StringAttr name);

  mlir::ModuleOp getModule() const;

protected:
  mlir::ModuleOp module;

private:
  // Resolved once, so that measuring a module is linear in what it
  // measures: a lookup in the module scans its body.
  llvm::DenseMap<mlir::StringAttr, DataOp> decls;
  // Each layout has its own allocation, so that a reference to one stays
  // valid while others are computed.
  llvm::DenseMap<mlir::StringAttr, std::unique_ptr<SumLayout>> sums;
};

} // namespace idr::layout

using namespace mlir;

namespace idr::layout {

Components::Components(ModuleOp m) : module(m) {
  for (DataOp data : m.getOps<DataOp>())
    decls[data.getSymNameAttr()] = data;
}

DataOp Components::declaration(StringAttr name) const { return decls.lookup(name); }

const SumLayout &Components::sum(StringAttr name) {
  auto it = sums.find(name);
  if (it != sums.end())
    return *it->second;
  DataOp data = declaration(name);
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

SmallVector<Type> Components::components(Type type) {
  MLIRContext *ctx = module.getContext();
  // Linearity is a fact for the passes; at runtime the value is itself.
  if (isErased(type) || isWorld(type))
    return {};
  type = unrestricted(type);
  // A destination is the address of a field's word.
  if (isa<StrType, BoxType, FnType, TokenType, DestType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  // An array is its cell and its size in each dimension, the memref's: an
  // array of rank 1 its length, an IORef's nothing more. A bounds check
  // compares two registers, so the one a program's own test made redundant
  // folds away, where a load of the length from the cell, which the stores
  // into the cell may alias, would stay in every loop.
  if (isArray(type)) {
    SmallVector<Type> out{LLVM::LLVMPointerType::get(ctx)};
    out.append(static_cast<size_t>(cast<MemRefType>(type).getRank()), IntegerType::get(ctx, 64));
    return out;
  }
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type))
    return sum(data.getName().getAttr()).types();
  return {type};
}

SmallVector<bool> Components::counted(Type type) {
  if (isErased(type) || isWorld(type))
    return {};
  type = unrestricted(type);
  if (isa<StrType, BoxType, FnType, TokenType, BigType, NatType>(type))
    return {true};
  if (isArray(type)) {
    SmallVector<bool> out{true};
    out.append(static_cast<size_t>(cast<MemRefType>(type).getRank()), false);
    return out;
  }
  if (isa<DestType>(type))
    return {false};
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

unsigned Components::objects(Type type) {
  return static_cast<unsigned>(llvm::count(counted(type), true));
}

unsigned Components::objects(ArrayRef<Type> types) {
  unsigned all = 0;
  for (Type type : types)
    all += objects(type);
  return all;
}

ModuleOp Components::getModule() const { return module; }

} // namespace idr::layout
