// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of the value types of a module, which of them a
// cell's header counts, and the layouts of the sums held in place they are
// made of.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;

namespace idr::layout {

namespace {

using Sums = llvm::DenseMap<DataType, std::unique_ptr<SumLayout>>;

// The layout of the sum `type`, every sum its fields hold in place already
// in `sums`.
SumLayout sumLayout(DataType type, const Sums &sums) {
  SumLayout layout;
  ArrayRef<Ctor> ctors = type.getCtors();
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = IntegerType::get(type.getContext(), width);
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
           llvm::zip_equal(componentsOf(fieldType, sums), countedOf(fieldType, sums))) {
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
  return layout;
}

// The data types the fields of `type` hold in place.
SmallVector<DataType> heldInPlace(DataType type) {
  SmallVector<DataType> held;
  for (const Ctor &ctor : type.getCtors())
    for (Type field : ctor.fields)
      forEachNamed(
          field,
          [&](DataType data, bool inPlace) {
            if (inPlace)
              held.push_back(data);
          },
          [](MemRefType) {}, [](Type) {});
  return held;
}

const SumLayout &sumIn(const Sums &sums, DataType type) {
  if (auto it = sums.find(type); it != sums.end())
    return *it->second;
  llvm::reportFatalInternalError("no layout of the sum \"" + type.getName() +
                                 "\", which no value of the module held when its layouts were "
                                 "computed, or which holds itself in place");
}

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

// Callees first along "holds in place", so each sum reads only sums made
// before it: containment in place is acyclic once layout::fit has made the
// boxes, so every component is one type that does not hold itself.
Sums sumsOf(ArrayRef<DataType> types) {
  Sums sums;
  for (const SmallVector<DataType> &component :
       idr::stronglyConnected<DataType>(types, heldInPlace))
    for (DataType type : component)
      sums.try_emplace(type, std::make_unique<SumLayout>(sumLayout(type, sums)));
  return sums;
}

// An array is its cell and what of its descriptor its type leaves to the
// value. A bounds check compares two registers, so the one a program's own
// test made redundant folds away, where a load of the length from the cell,
// which the stores into the cell may alias, would stay in every loop.
SmallVector<Type> componentsOf(Type type, const Sums &sums) {
  MLIRContext *ctx = type.getContext();
  // Linearity is a fact for the passes; at runtime the value is itself. A
  // world is no value at all.
  if (isWorld(type))
    return {};
  type = unrestricted(type);
  if (auto data = dyn_cast<DataType>(type))
    return sumIn(sums, data).types();
  if (isa<RankedTensorType, MemRefType>(type)) {
    SmallVector<Type> out{LLVM::LLVMPointerType::get(ctx)};
    out.append(descriptorWords(cast<ShapedType>(type)), IntegerType::get(ctx, 64));
    return out;
  }
  // A big's word is a small integer or a cell's address. Every other value
  // that holds a reference is the address of its cell, and a destination
  // the address of the word it fills.
  if (isa<BigType, NatType>(type))
    return {IntegerType::get(ctx, 64)};
  if (holdsReferences(type) || isa<DestType>(type))
    return {LLVM::LLVMPointerType::get(ctx)};
  return {type};
}

// A component is counted where the value it is holds a reference itself: a
// cell's address, a big's word, an array's cell. A sum's slots are counted
// as its layout says.
SmallVector<bool> countedOf(Type type, const Sums &sums) {
  if (isWorld(type))
    return {};
  type = unrestricted(type);
  if (auto data = dyn_cast<DataType>(type)) {
    const SumLayout &layout = sumIn(sums, data);
    SmallVector<bool> all;
    if (layout.tag)
      all.push_back(false);
    all.append(layout.counted.begin(), layout.counted.end());
    return all;
  }
  if (isa<RankedTensorType, MemRefType>(type)) {
    SmallVector<bool> out{true};
    out.append(descriptorWords(cast<ShapedType>(type)), false);
    return out;
  }
  return {holdsReferences(type)};
}

} // namespace idr::layout
