// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The containment among the module's types. Idris is strict and never
// writes data once made, so a new object only points at objects that exist
// before it, and the heap is acyclic: what lets counting free everything,
// with a release walk that marks nothing and a count of one that means
// nobody else. An array, of any rank (an IORef is one of rank 0), is the
// one cell written after it exists, so a knot needs an array whose element
// type can reach the array again, and whether one can is a question of
// types, answered once for the module.
//
// A data type is a node whether its values are held in place or in a box:
// held in place, its fields are stored where it is, so what they name is
// reached through it. A memo sum is a data type like any other: its cell is
// written once, with a value computed from captures older than the cell, so
// only an array's edge closes a knot. A static memo can reach itself (a
// constant stream whose forced tail is the constant), but only through
// static cells, which are never counted. Before idr-defunctionalize a
// closure's captures are not types yet, and a closure names nothing, so the
// graph is partial until then. A value array (a tensor, or its buffer) is
// written only before it is shared, so it closes no knot and is no node;
// but what its elements name is reached through it, so a knot that passes
// through one is still a knot, and its elements are held out of place.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>

using namespace mlir;

void idr::forEachNamed(Type type, function_ref<void(DataType, bool)> data,
                       function_ref<void(MemRefType)> array, function_ref<void(Type)> leaf) {
  type = unrestricted(type);
  if (auto box = dyn_cast<BoxType>(type))
    return data(box.getData(), /*inPlace=*/false);
  if (auto held = dyn_cast<DataType>(type))
    return data(held, /*inPlace=*/true);
  if (idr::isArray(type))
    return array(cast<MemRefType>(type));
  // A value array's elements are its buffer's, held out of place.
  if (auto values = dyn_cast<ShapedType>(type))
    return forEachNamed(
        values.getElementType(), [&](DataType element, bool) { data(element, false); }, array,
        leaf);
  leaf(type);
}

idr::TypeGraph::TypeGraph(Operation *module) {
  // Every data type a value, a field or an element is of, and how it is
  // held there: a type directly in a box is held boxed, anywhere else in
  // place. A constant constructor names its type as its identity, not as a
  // value it holds, and its op's result type says how the value is held.
  llvm::SetVector<DataType> found;
  AttrTypeWalker walker;
  walker.addWalk([](ConAttr) { return WalkResult::skip(); });
  walker.addWalk([&](BoxType box) {
    found.insert(box.getData());
    heldBoxed.insert(box.getData());
    return WalkResult::skip();
  });
  walker.addWalk([&](DataType data) {
    found.insert(data);
    heldInPlace.insert(data);
    return WalkResult::skip();
  });
  auto walk = [&](auto element) { walker.walk<WalkOrder::PreOrder>(element); };
  module->walk([&](Operation *op) {
    walk(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walk(type);
  });
  // A field adds the types it names, each once, so the set grows as it is
  // read and ends with the types the module's values reach.
  for (size_t at = 0; at < found.size(); ++at)
    for (const Ctor &ctor : found[at].getCtors())
      for (Type field : ctor.fields)
        walk(field);

  dataTypes.assign(found.begin(), found.end());
  llvm::sort(dataTypes, [](DataType a, DataType b) { return a.getName() < b.getName(); });
  for (DataType data : dataTypes)
    insert(data);
  // An array is inserted as it is met, once, so the list grows as it is
  // read, by the arrays the module's types name.
  for (unsigned at = 0; at < types.size(); ++at) {
    if (isArray(at)) {
      edges(at, cast<MemRefType>(types[at]).getElementType());
      continue;
    }
    for (const Ctor &ctor : dataTypes[at].getCtors())
      for (Type field : ctor.fields)
        edges(at, field);
  }
  parts = idr::components(successorsOf);
}

unsigned idr::TypeGraph::insert(Type type) {
  auto [it, fresh] = index.try_emplace(type, static_cast<unsigned>(types.size()));
  if (fresh) {
    types.push_back(type);
    successorsOf.emplace_back();
    inPlace.emplace_back();
  }
  return it->second;
}

// The edges from `from` to what a field or an element of type `type` names
// (forEachNamed). Each target is inserted before an edge to it is added, so
// no reference into a list is held while the lists grow.
void idr::TypeGraph::edges(unsigned from, Type type) {
  forEachNamed(
      type,
      [&](DataType data, bool held) {
        unsigned to = insert(data);
        successorsOf[from].push_back(to);
        if (held)
          inPlace[from].push_back(to);
      },
      [&](MemRefType array) {
        unsigned to = insert(array);
        successorsOf[from].push_back(to);
      },
      [](Type) {});
}

// An array cannot hold itself, so a strongly connected component with an
// array in it is a cycle through that array's edge, and a component
// without one is data never written once made, which cannot knot.
SmallVector<SmallVector<unsigned>> idr::TypeGraph::knots() const {
  SmallVector<SmallVector<unsigned>> out;
  if (types.size() == dataTypes.size())
    return out;
  for (const SmallVector<unsigned> &component : parts)
    if (component.size() > 1 && llvm::any_of(component, [&](unsigned at) { return isArray(at); }))
      out.push_back(component);
  return out;
}

SmallVector<unsigned> idr::TypeGraph::cycle(unsigned array, ArrayRef<unsigned> component) const {
  unsigned element = successorsOf[array].front();
  // A walk breadth first from the element over the component, each node
  // reached once: `reached` in the order it reaches them, `previous` the
  // step that reached each but the element. The array holds the element,
  // and the component reaches the array from it, so the walk reaches it.
  llvm::DenseSet<unsigned> inComponent(component.begin(), component.end());
  llvm::SetVector<unsigned> reached;
  reached.insert(element);
  llvm::DenseMap<unsigned, unsigned> previous;
  for (size_t at = 0; at < reached.size() && !reached.contains(array); ++at)
    for (unsigned next : successorsOf[reached[at]])
      if (inComponent.contains(next) && reached.insert(next))
        previous[next] = reached[at];
  // Back from the array along the steps that reached it: each is to a node
  // reached before, so the path is at most the nodes reached.
  SmallVector<unsigned> out{element, array};
  for (size_t step = 0; step < reached.size() && out.back() != element; ++step)
    out.push_back(previous.lookup(out.back()));
  assert(out.back() == element && "the component reaches its array from the element");
  std::reverse(out.begin(), out.end());
  return out;
}

// Containment in place must be acyclic: a value held in place is stored
// where it is held, so one that holds itself, in place or through a grade,
// is infinite. The subgraph is the edges in place; a data type is on a
// cycle when its component has two or more or it holds itself directly.
SmallVector<idr::DataType> idr::TypeGraph::containsItself() const {
  SmallVector<unsigned> onCycle;
  for (const SmallVector<unsigned> &component : idr::components(inPlace))
    for (unsigned vertex : component)
      if (component.size() > 1 || llvm::is_contained(inPlace[vertex], vertex))
        onCycle.push_back(vertex);
  llvm::sort(onCycle);
  SmallVector<DataType> out;
  for (unsigned at : onCycle)
    if (!isArray(at))
      out.push_back(dataTypes[at]);
  return out;
}
