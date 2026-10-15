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
// written only before it is shared, so it closes no knot and is no node.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>

using namespace mlir;

idr::TypeGraph::TypeGraph(Operation *module) {
  // Every data type a value, a field or an element is of, and how it is
  // held there: a type directly in a box is held boxed, anywhere else in
  // place. A constant constructor names its type as its identity, not as a
  // value it holds, and its op's result type says how the value is held.
  llvm::SetVector<DataType> found;
  llvm::DenseSet<DataType> boxedSet, inPlaceSet;
  AttrTypeWalker walker;
  walker.addWalk([](ConAttr) { return WalkResult::skip(); });
  walker.addWalk([&](BoxType box) {
    found.insert(box.getData());
    boxedSet.insert(box.getData());
    return WalkResult::skip();
  });
  walker.addWalk([&](DataType data) {
    found.insert(data);
    inPlaceSet.insert(data);
    return WalkResult::advance();
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
  // A field adds the types it names, so the list grows as it is read.
  for (size_t at = 0; at < found.size(); ++at)
    for (const Ctor &ctor : found[at].getCtors())
      for (Type field : ctor.fields)
        walk(field);

  SmallVector<DataType> named(found.begin(), found.end());
  llvm::sort(named, [](DataType a, DataType b) { return a.getName() < b.getName(); });
  for (DataType data : named) {
    unsigned at = insert(data);
    heldBoxed[at] = boxedSet.contains(data);
    heldInPlace[at] = inPlaceSet.contains(data);
  }
  for (unsigned at = 0; at < types.size(); ++at) {
    if (auto array = dyn_cast<MemRefType>(types[at])) {
      edge(at, array.getElementType());
      continue;
    }
    for (const Ctor &ctor : cast<DataType>(types[at]).getCtors())
      for (Type field : ctor.fields)
        edge(at, field);
  }
  parts = idr::components(edges);
}

unsigned idr::TypeGraph::insert(Type type) {
  auto [it, fresh] = index.try_emplace(type, static_cast<unsigned>(types.size()));
  if (fresh) {
    types.push_back(type);
    heldBoxed.push_back(false);
    heldInPlace.push_back(false);
    edges.emplace_back();
    inPlace.emplace_back();
  }
  return it->second;
}

// An edge from `from` to what a field or an element of type `type` names,
// seen through its grade: a data type, in place or in a box, or an array.
// A field `!idr.lin<T>` stores T where the bare field would.
void idr::TypeGraph::edge(unsigned from, Type type) {
  type = unrestricted(type);
  if (auto box = dyn_cast<BoxType>(type)) {
    edges[from].push_back(insert(box.getData()));
    return;
  }
  if (auto data = dyn_cast<DataType>(type)) {
    unsigned to = insert(data);
    edges[from].push_back(to);
    inPlace[from].push_back(to);
    return;
  }
  if (idr::isArray(type))
    edges[from].push_back(insert(type));
}

std::optional<unsigned> idr::TypeGraph::node(Type type) const {
  type = unrestricted(type);
  if (auto box = dyn_cast<BoxType>(type))
    type = box.getData();
  auto found = index.find(type);
  if (found == index.end())
    return std::nullopt;
  return found->second;
}

bool idr::TypeGraph::isArray(unsigned at) const { return isa<MemRefType>(types[at]); }

// An array cannot hold itself, so a strongly connected component with an
// array in it is a cycle through that array's edge, and a component
// without one is data never written once made, which cannot knot.
SmallVector<SmallVector<unsigned>> idr::TypeGraph::knots() const {
  SmallVector<SmallVector<unsigned>> out;
  if (llvm::none_of(types, [](Type node) { return isa<MemRefType>(node); }))
    return out;
  for (const SmallVector<unsigned> &component : parts)
    if (component.size() > 1 && llvm::any_of(component, [&](unsigned at) { return isArray(at); }))
      out.push_back(component);
  return out;
}

SmallVector<unsigned> idr::TypeGraph::cycle(unsigned array, ArrayRef<unsigned> component) const {
  unsigned element = edges[array].front();
  // A walk breadth first from the element: `unseen` is what of the
  // component it has not reached yet, `previous` the step that reached each
  // of the rest.
  llvm::BitVector unseen(static_cast<unsigned>(types.size()));
  for (unsigned at : component)
    unseen.set(at);
  unseen.reset(element);
  SmallVector<unsigned> previous(types.size());
  SmallVector<unsigned> queue{element};
  for (size_t at = 0; at < queue.size() && unseen.test(array); ++at)
    for (unsigned next : edges[queue[at]])
      if (unseen.test(next)) {
        unseen.reset(next);
        previous[next] = queue[at];
        queue.push_back(next);
      }
  SmallVector<unsigned> out{element, array};
  while (out.back() != element)
    out.push_back(previous[out.back()]);
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
    if (DataType data = declaration(at))
      out.push_back(data);
  return out;
}
