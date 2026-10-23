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
// A member of a family is a node however its values are held: in place,
// its fields are stored where it is, so what they name is reached through
// it. A memo sum is a member like any other: its cell is written once, with
// a value computed from captures older than the cell, so only an array's
// edge closes a knot. Before idr-defunctionalize a closure's captures are
// not types yet, and a closure names nothing, so the graph is partial until
// then. A value array (a tensor, or its buffer) is written only before it
// is shared, so it closes no knot and is no node; but what its elements
// name is reached through it.

#include "idr/Analysis/Solver/TypeGraph.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Match.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>
#include <optional>

using namespace mlir;
using namespace idr;

// Through its grade. An array is upstream's memref, which isArray tells
// from a value array's buffer.
std::optional<TypeGraph::Node> TypeGraph::nodeOf(Type type) {
  if (DataType data = dataTypeOf(type))
    return Node(Data{data});
  Type value = unrestricted(type);
  if (idr::isArray(value))
    return Node(Array{cast<MemRefType>(value)});
  return std::nullopt;
}

unsigned TypeGraph::insert(const Node &node) {
  Key key = match(
      node, [](const Data &member) { return Key(member.type.getGroup(), member.type.getMember()); },
      [](const Array &array) { return Key(TypeAttr::get(array.type), 0); });
  auto [it, fresh] = index.try_emplace(key, static_cast<unsigned>(nodes.size()));
  if (fresh)
    nodes.push_back(node);
  return it->second;
}

Type TypeGraph::type(unsigned at) const {
  return match(
      nodes[at], [](const Data &member) -> Type { return member.type; },
      [](const Array &array) -> Type { return array.type; });
}

bool TypeGraph::isArray(unsigned at) const {
  return match(
      nodes[at], [](const Data &) { return false; }, [](const Array &) { return true; });
}

// Through its grade, and through a value array to its elements.
void TypeGraph::named(Type type, SmallVectorImpl<unsigned> &out) {
  Type value = unrestricted(type);
  while (auto values = dyn_cast<ShapedType>(value)) {
    if (idr::isArray(value))
      break;
    value = unrestricted(values.getElementType());
  }
  if (std::optional<Node> node = nodeOf(value))
    out.push_back(insert(*node));
}

TypeGraph::TypeGraph(Operation *module) {
  // Every member and array a value is of: a constant constructor names its
  // type as its identity, not as a value it holds, and a declaration is
  // reached through the members that name it.
  AttrTypeWalker walker;
  walker.addWalk([](ConAttr) { return WalkResult::skip(); });
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](Type type) {
    std::optional<Node> node = nodeOf(type);
    if (!node)
      return WalkResult::advance();
    insert(*node);
    return WalkResult::skip();
  });
  module->walk([&](Operation *op) {
    walker.walk<WalkOrder::PreOrder>(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walker.walk<WalkOrder::PreOrder>(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk<WalkOrder::PreOrder>(type);
  });

  // A node adds the nodes it names, each once, so the list grows as it is
  // read and ends with the types the module's values reach. A member's
  // fields are its declaration's, over its binders: a field of its own
  // group names that member by position.
  footprint::Vector<std::pair<unsigned, unsigned>> edges;
  SmallVector<unsigned> to;
  for (unsigned at = 0; at < nodes.size(); ++at) {
    to.clear();
    // Copied out of the list, which grows as the node's fields insert.
    Node node = nodes[at];
    match(
        node, [&](const Array &array) { named(array.type.getElementType(), to); },
        [&](const Data &applied) {
          DataType data = applied.type;
          FamilyAttr group = data.getGroup();
          for (uint32_t tag = 0, n = data.declaredCount(); tag < n; ++tag)
            for (Type field : data.ctor(Tag{tag}).fields) {
              auto indexed = dyn_cast<IndexedTypeInterface>(unrestricted(field));
              if (std::optional<uint32_t> member =
                      indexed ? indexed.getPositionalMember() : std::nullopt) {
                MLIRContext *context = group.getContext();
                IndexArgsAttr any = families::opaqueArgs(
                    context, static_cast<uint32_t>(group.indices(*member).size()));
                to.push_back(insert(Data{DataType::get(context, group, *member, any.getTerms())}));
                continue;
              }
              named(field, to);
            }
        });
    for (unsigned target : to)
      edges.emplace_back(at, target);
  }

  CsrBuilder<TypeNode> builder(Count<NodeId>(static_cast<uint32_t>(nodes.size())));
  for (auto [from, target] : edges)
    builder.edge(NodeId(from), NodeId(target));
  graph = std::move(builder).finish();
  parts = components(*graph);
}

// An array cannot hold itself, so a component that is a cycle with an
// array in it is a cycle through that array's edge, and one without is
// data never written once made, which cannot knot.
SmallVector<SmallVector<unsigned>> TypeGraph::knots() const {
  SmallVector<SmallVector<unsigned>> out;
  for (auto component : parts->size().ids()) {
    if (!parts->cyclic(component))
      continue;
    SmallVector<unsigned> members;
    for (NodeId node : parts->members(component))
      members.push_back(node.index());
    if (llvm::any_of(members, [&](unsigned at) { return isArray(at); }))
      out.push_back(std::move(members));
  }
  return out;
}

SmallVector<unsigned> TypeGraph::cycle(unsigned array, ArrayRef<unsigned> component) const {
  llvm::DenseSet<unsigned> inComponent(component.begin(), component.end());
  // The element the array holds on the cycle: its one successor there.
  unsigned element = array;
  for (NodeId next : graph->successors(NodeId(array)))
    if (inComponent.contains(next.index())) {
      element = next.index();
      break;
    }
  // A walk breadth first from the element over the component, each node
  // reached once: `reached` in the order it reaches them, `previous` the
  // step that reached each but the element. The array holds the element,
  // and the component reaches the array from it, so the walk reaches it.
  llvm::SetVector<unsigned> reached;
  reached.insert(element);
  llvm::DenseMap<unsigned, unsigned> previous;
  for (size_t at = 0; at < reached.size() && !reached.contains(array); ++at)
    for (NodeId next : graph->successors(NodeId(reached[at])))
      if (inComponent.contains(next.index()) && reached.insert(next.index()))
        previous[next.index()] = reached[at];
  // Back from the array along the steps that reached it: each is to a node
  // reached before, so the path is at most the nodes reached.
  SmallVector<unsigned> out{element, array};
  for (size_t step = 0; step < reached.size() && out.back() != element; ++step)
    out.push_back(previous.lookup(out.back()));
  std::reverse(out.begin(), out.end());
  return out;
}
