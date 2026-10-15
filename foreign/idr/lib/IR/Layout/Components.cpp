// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of the value types of a module, and which of them
// a cell's header counts.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::layout {

Components::Components(ModuleOp m, ArrayRef<DataType> boxed)
    : module(m), asBoxes(boxed.begin(), boxed.end()) {}

const SumLayout *Components::computed(DataType type) const {
  auto it = sums.find(type);
  return it == sums.end() ? nullptr : it->second.get();
}

const SumLayout &Components::sum(DataType type) {
  if (const SumLayout *known = computed(type))
    return *known;
  SumLayout layout;
  ArrayRef<Ctor> ctors = type.getCtors();
  Builder b(module.getContext());
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = b.getIntegerType(width);
  }
  for (const Ctor &ctor : ctors) {
    // The free slots of each component, counted and not, in slot order.
    // Built once per constructor: searching the slots again for every field
    // is quadratic in a wide sum.
    struct Free {
      DenseMap<Type, SmallVector<unsigned>> slots;
      DenseMap<Type, unsigned> cursor;
    };
    Free free[2];
    for (unsigned i = 0, n = static_cast<unsigned>(layout.slots.size()); i < n; ++i)
      free[layout.counted[i]].slots[layout.slots[i]].push_back(i);
    SmallVector<SmallVector<unsigned>> perField;
    for (Type fieldType : ctor.fields) {
      SmallVector<unsigned> slots;
      for (auto [component, isCounted] :
           llvm::zip_equal(components(fieldType), counted(fieldType))) {
        Free &index = free[isCounted];
        SmallVector<unsigned> &bucket = index.slots[component];
        unsigned &at = index.cursor[component];
        unsigned chosen;
        if (at < bucket.size())
          chosen = bucket[at++];
        else {
          chosen = static_cast<unsigned>(layout.slots.size());
          layout.slots.push_back(component);
          layout.counted.push_back(isCounted);
        }
        slots.push_back(chosen);
      }
      perField.push_back(std::move(slots));
    }
    layout.fields.push_back(std::move(perField));
  }
  auto &slot = sums[type];
  slot = std::make_unique<SumLayout>(std::move(layout));
  return *slot;
}

namespace {

// The fields of an array's descriptor that its type does not fix, after
// the cell: the offset of a strided layout, when it is dynamic; each
// dynamic size; and each dynamic stride of a strided layout. An identity
// layout's offset is 0 and its strides are those of its sizes, computed
// where they are needed.
unsigned descriptorWords(ShapedType array) {
  unsigned words = static_cast<unsigned>(llvm::count_if(array.getShape(), ShapedType::isDynamic));
  auto memref = dyn_cast<MemRefType>(array);
  if (auto strided = memref ? dyn_cast<StridedLayoutAttr>(memref.getLayout()) : nullptr) {
    words += ShapedType::isDynamic(strided.getOffset()) ? 1 : 0;
    words += static_cast<unsigned>(llvm::count_if(strided.getStrides(), ShapedType::isDynamic));
  }
  return words;
}

} // namespace

SmallVector<Type> Components::componentsWith(Type type, SumOf sumOf) const {
  MLIRContext *ctx = module->getContext();
  // Linearity is a fact for the passes; at runtime the value is itself. A
  // world is no value at all.
  if (isWorld(type))
    return {};
  type = unrestricted(type);
  // A destination is the address of a field's word.
  if (isa<StrType, BoxType, FnType, TokenType, DestType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  // An array is its cell and what of its descriptor its type leaves to the
  // value. A bounds check compares two registers, so the one a program's
  // own test made redundant folds away, where a load of the length from the
  // cell, which the stores into the cell may alias, would stay in every
  // loop.
  if (auto array = dyn_cast<ShapedType>(type)) {
    SmallVector<Type> out{LLVM::LLVMPointerType::get(ctx)};
    out.append(descriptorWords(array), IntegerType::get(ctx, 64));
    return out;
  }
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (auto data = dyn_cast<DataType>(type)) {
    if (asBoxes.contains(data))
      return {LLVM::LLVMPointerType::get(ctx)};
    return sumOf(data).types();
  }
  return {type};
}

SmallVector<bool> Components::countedWith(Type type, SumOf sumOf) const {
  if (isWorld(type))
    return {};
  type = unrestricted(type);
  if (isa<StrType, BoxType, FnType, TokenType, BigType, NatType>(type))
    return {true};
  if (auto array = dyn_cast<ShapedType>(type)) {
    SmallVector<bool> out{true};
    out.append(descriptorWords(array), false);
    return out;
  }
  if (isa<DestType>(type))
    return {false};
  if (auto data = dyn_cast<DataType>(type)) {
    if (asBoxes.contains(data))
      return {true};
    const SumLayout &layout = sumOf(data);
    SmallVector<bool> all;
    if (layout.tag)
      all.push_back(false);
    all.append(layout.counted.begin(), layout.counted.end());
    return all;
  }
  return {false};
}

SmallVector<Type> Components::components(Type type) {
  return componentsWith(type, [&](DataType data) -> const SumLayout & { return sum(data); });
}

SmallVector<bool> Components::counted(Type type) {
  return countedWith(type, [&](DataType data) -> const SumLayout & { return sum(data); });
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
