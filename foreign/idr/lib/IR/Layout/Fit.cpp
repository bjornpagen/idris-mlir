// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The boxes that make cells fit their headers. A cell's header counts its
// object slots in a few bits, and a sum held in place spreads its slots
// over every cell that holds it, so a record nested in a record can make a
// cell that no header counts. Holding the record in a box leaves one
// pointer in its place: the type of a value decides how it is flattened,
// so boxing a data type where it is held is the whole change, which every
// later pass and the lowering follow as they follow any box. A body is set
// once, so the types whose bodies held the record in place are remade.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::layout {

bool boxable(DataType data) {
  size_t ctors = data.getCtors().size();
  return ctors == 1 || (data.isClosures() && ctors <= IDRIS_RT_TAG_LIMIT);
}

Holders::Holders(ModuleOp m, ArrayRef<DataType> boxed) {
  TypeGraph graph(m.getOperation());
  llvm::DenseSet<DataType> asBoxes(boxed.begin(), boxed.end());
  for (unsigned at = 0, n = graph.size(); at < n; ++at)
    if (DataType data = graph.declaration(at); data && (graph.boxed(at) || asBoxes.contains(data)))
      boxes.push_back(data);
  llvm::SetVector<DataType> held;
  for (unsigned at = 0, n = graph.size(); at < n; ++at)
    if (graph.isArray(at))
      if (auto data = dyn_cast<DataType>(
              unrestricted(cast<MemRefType>(graph.type(at)).getElementType())))
        held.insert(data);
  elements = held.takeVector();
  llvm::sort(elements, [](DataType a, DataType b) { return a.getName() < b.getName(); });
}

void Holders::overflows(
    Components &parts,
    function_ref<void(DataType type, std::optional<unsigned> tag, ArrayRef<Type> held,
                      unsigned objects)>
        each) {
  for (DataType data : boxes)
    for (auto [tag, ctor] : llvm::enumerate(data.getCtors()))
      if (unsigned n = parts.objects(ctor.fields); n > mostObjects)
        each(data, static_cast<unsigned>(tag), ctor.fields, n);
  // An element of a box is one pointer.
  for (DataType data : elements)
    if (unsigned n = parts.objects(Type(data)); n > mostObjects)
      each(data, std::nullopt, Type(data), n);
}

namespace {

// The boxable data types of two or more object slots that a holder holds
// in place by `type`, looking through the sums held in place that are not
// boxable, whose slots it holds too. Boxing one of fewer slots shrinks no
// cell. A type already chosen is one pointer, and nothing to look through.
void candidates(Components &parts, Type type, const llvm::DenseSet<DataType> &chosen,
                llvm::MapVector<DataType, unsigned> &out, llvm::DenseSet<DataType> &seen) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || chosen.contains(data) || !seen.insert(data).second)
    return;
  if (boxable(data)) {
    if (unsigned n = parts.objects(Type(data)); n >= 2)
      out.insert({data, n});
    return;
  }
  for (const Ctor &ctor : data.getCtors())
    for (Type field : ctor.fields)
      candidates(parts, field, chosen, out, seen);
}

} // namespace

unsigned fit(ModuleOp module) {
  SmallVector<DataType> chosen;
  llvm::DenseSet<DataType> chosenSet;
  while (true) {
    // Measured afresh, as if the boxes chosen so far were made: the last
    // box changed the shapes.
    Components parts(module, chosen);
    Holders holders(module, chosen);
    llvm::MapVector<DataType, unsigned> wide;
    llvm::DenseSet<DataType> seen;
    holders.overflows(parts, [&](DataType, std::optional<unsigned>, ArrayRef<Type> held, unsigned) {
      for (Type type : held)
        candidates(parts, type, chosenSet, wide, seen);
    });
    // The widest takes the most object slots out of every cell that holds
    // it, so the fewest types become boxes; an outer record goes before
    // its parts, and a part only when the outer one's own cell then
    // overflows. Ties go to the smaller name, so the choice is the
    // module's alone.
    DataType widest;
    unsigned most = 0;
    for (auto [data, n] : wide)
      if (n > most || (n == most && data.getName() < widest.getName())) {
        widest = data;
        most = n;
      }
    if (!widest)
      break;
    chosen.push_back(widest);
    chosenSet.insert(widest);
  }
  if (chosen.empty())
    return 0;
  DataRemap remap(
      module, "box",
      [](Type, DataType, unsigned, unsigned) -> std::optional<Type> { return std::nullopt; },
      chosen);
  remap.retype(module.getOperation());
  return static_cast<unsigned>(chosen.size());
}

} // namespace idr::layout
