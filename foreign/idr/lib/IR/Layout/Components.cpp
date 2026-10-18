// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of the value types of a module, each with whether
// it is counted, the plan of a memref's descriptor, and the layouts of the
// sums held in place they are made of.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

using namespace mlir;

namespace idr::layout {

namespace {

using Sums = llvm::DenseMap<DataType, std::unique_ptr<SumLayout>>;

// The layout of the sum `type`, every sum its fields hold in place already
// in `sums`: the tag, when the sum has one, then the words its fields take.
// A constructor's fields take the words before them that no field of the
// same constructor took, of the same type and countedness, so two
// constructors share their words.
SumLayout sumLayout(DataType type, const Sums &sums) {
  SumLayout layout;
  ArrayRef<Ctor> ctors = type.getCtors();
  if (ctors.size() >= 2) {
    unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
    layout.tag = IntegerType::get(type.getContext(), width);
    layout.words.push_back(Component{*layout.tag, false});
  }
  // The words fields take are those from here on: the tag is no field's.
  auto firstField = static_cast<unsigned>(layout.words.size());
  for (const Ctor &ctor : ctors) {
    // The free words of each component, counted and not, in word order.
    // Built once per constructor: searching the words again for every field
    // is quadratic in a wide sum.
    struct Free {
      DenseMap<Type, SmallVector<unsigned>> words;
      DenseMap<Type, unsigned> cursor;
    };
    Free free[2];
    for (unsigned i = firstField, n = static_cast<unsigned>(layout.words.size()); i < n; ++i)
      free[layout.words[i].counted].words[layout.words[i].type].push_back(i);
    SmallVector<SmallVector<unsigned>> perField;
    for (Type fieldType : ctor.fields) {
      SmallVector<unsigned> taken;
      for (const Component &component : components(fieldType, sums)) {
        Free &index = free[component.counted];
        SmallVector<unsigned> &bucket = index.words[component.type];
        unsigned &at = index.cursor[component.type];
        unsigned chosen;
        if (at < bucket.size())
          chosen = bucket[at++];
        else {
          chosen = static_cast<unsigned>(layout.words.size());
          layout.words.push_back(component);
        }
        taken.push_back(chosen);
      }
      perField.push_back(std::move(taken));
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

// Whether a value of `type` holds no component, `met` the data types the
// walk is inside of.
bool holdsNone(Type type, llvm::DenseSet<DataType> &met) {
  if (isWorld(type))
    return true;
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || data.getCtors().size() > 1 || !met.insert(data).second)
    return false;
  bool none = llvm::all_of(data.getCtors(), [&](const Ctor &ctor) {
    return llvm::all_of(ctor.fields, [&](Type field) { return holdsNone(field, met); });
  });
  met.erase(data);
  return none;
}

DescriptorField fieldOf(int64_t value) {
  if (ShapedType::isDynamic(value))
    return Carried{};
  return Fixed{value};
}

unsigned carriedIn(ArrayRef<DescriptorField> fields) {
  return static_cast<unsigned>(llvm::count_if(fields, [](const DescriptorField &field) {
    return std::holds_alternative<Carried>(field);
  }));
}

} // namespace

bool holdsNoComponent(Type type) {
  llvm::DenseSet<DataType> met;
  return holdsNone(type, met);
}

unsigned DescriptorFields::carried() const {
  return carriedIn(offset) + carriedIn(sizes) + (strides ? carriedIn(*strides) : 0u);
}

DescriptorFields DescriptorFields::of(ShapedType type) {
  DescriptorFields fields{Fixed{0}, llvm::map_to_vector(type.getShape(), fieldOf), std::nullopt};
  auto memref = dyn_cast<MemRefType>(type);
  // A tensor and an identity layout carry no stride: the sizes say them.
  if (!memref || memref.getLayout().isIdentity())
    return fields;
  SmallVector<int64_t> steps;
  int64_t start;
  if (failed(memref.getStridesAndOffset(steps, start))) {
    std::string text;
    llvm::raw_string_ostream(text) << memref;
    llvm::reportFatalInternalError(llvm::Twine("the layout of ") + text +
                                   " has no strides, and the program's verifier refuses a memref "
                                   "value whose layout is not strided");
  }
  fields.offset = fieldOf(start);
  fields.strides = llvm::map_to_vector(steps, fieldOf);
  return fields;
}

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

// A component is counted where the value it is holds a reference itself: a
// cell's address, a big's word, an array's cell; a sum's words are counted
// as its layout says. An array is its cell and what of its descriptor its
// type leaves to the value. A bounds check compares two registers, so the
// one a program's own test made redundant folds away, where a load of the
// length from the cell, which the stores into the cell may alias, would
// stay in every loop.
SmallVector<Component> components(Type type, const Sums &sums) {
  if (holdsNoComponent(type))
    return {};
  MLIRContext *ctx = type.getContext();
  // A grade is a fact for the passes; at runtime the value is itself.
  type = unrestricted(type);
  if (auto data = dyn_cast<DataType>(type))
    return sumIn(sums, data).words;
  if (isa<RankedTensorType, MemRefType>(type)) {
    SmallVector<Component> out{{LLVM::LLVMPointerType::get(ctx), true}};
    out.append(DescriptorFields::of(cast<ShapedType>(type)).carried(),
               Component{IntegerType::get(ctx, 64), false});
    return out;
  }
  // A big's word is a small integer or a cell's address. Every other value
  // that holds a reference is the address of its cell, a destination the
  // address of the word it fills, and a cell the address of its memory.
  if (isa<BigType, NatType>(type))
    return {{IntegerType::get(ctx, 64), holdsReferences(type)}};
  if (holdsReferences(type) || isa<DestType, CellType>(type))
    return {{LLVM::LLVMPointerType::get(ctx), holdsReferences(type)}};
  return {{type, holdsReferences(type)}};
}

} // namespace idr::layout
