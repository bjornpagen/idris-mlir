// The containment among the module's types. Idris is strict and never
// writes data once made, so a new object only points at objects that exist
// before it, and the heap is acyclic: what lets counting free everything,
// with a release walk that marks nothing and a count of one that means
// nobody else. An array, of any rank (an IORef is one of rank 0), is the
// one cell written after it exists, so a knot needs an array whose element
// type can reach the array again, and whether one can is a question of
// types, answered once for the module.
//
// An unboxed sum is a node like a box: its fields are stored where it is,
// so what they name is reached through it. A memo sum is a declaration like
// any other: its cell is written once, with a value computed from captures
// older than the cell, so only an array's edge closes a knot. A static memo
// can reach itself (a constant stream whose forced tail is the constant),
// but only through static cells, which are never counted. Before
// idr-defunctionalize a closure's captures are not types yet, and a closure
// names nothing, so the graph is partial until then.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

idr::TypeGraph::TypeGraph(Operation *module) {
  for (auto data : cast<ModuleOp>(module).getOps<DataOp>()) {
    unsigned at = insert(data.getValueType());
    declarations[at] = data;
  }
  // A field adds the nodes it names, so the list grows as it is read.
  for (unsigned at = 0; at < types.size(); ++at) {
    if (auto array = dyn_cast<MemRefType>(types[at])) {
      edge(at, array.getElementType());
      continue;
    }
    DataOp data = declarations[at];
    if (!data)
      continue;
    for (auto ctor : data.getBody().getOps<CtorOp>())
      for (Type held : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
        edge(at, held);
  }
  parts = idr::components(edges);
}

unsigned idr::TypeGraph::insert(Type type) {
  auto [it, fresh] = index.try_emplace(type, static_cast<unsigned>(types.size()));
  if (fresh) {
    types.push_back(type);
    declarations.emplace_back();
    edges.emplace_back();
  }
  return it->second;
}

// An edge from `from` to what a field or an element of type `type` names,
// seen through its grade: a declaration or an array, if any. A field
// `!idr.lin<!idr.data<@X>>` stores @X where the bare field would.
void idr::TypeGraph::edge(unsigned from, Type type) {
  type = unrestricted(type);
  if (!isa<DataType, BoxType>(type) && !idr::isArray(type))
    return;
  unsigned to = insert(type);
  edges[from].push_back(to);
}

std::optional<unsigned> idr::TypeGraph::node(Type type) const {
  auto found = index.find(unrestricted(type));
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

// Containment through unboxed sums must be acyclic: an unboxed value is
// stored where it is held, so one that holds itself, inline or through a
// grade, is infinite. The subgraph is the unboxed declarations and the
// edges between them; a declaration is on a cycle when its component has
// two or more or it holds itself directly.
SmallVector<idr::DataOp> idr::TypeGraph::containsItself() const {
  constexpr unsigned absent = ~0u;
  SmallVector<unsigned> local(types.size(), absent);
  SmallVector<unsigned> nodes;
  for (unsigned at = 0, n = size(); at < n; ++at) {
    DataOp data = declarations[at];
    if (data && !data.getBox()) {
      local[at] = static_cast<unsigned>(nodes.size());
      nodes.push_back(at);
    }
  }
  SmallVector<SmallVector<unsigned>> inner(nodes.size());
  for (auto [from, at] : llvm::enumerate(nodes))
    for (unsigned to : edges[at])
      if (local[to] != absent)
        inner[from].push_back(local[to]);
  SmallVector<unsigned> onCycle;
  for (const SmallVector<unsigned> &component : idr::components(inner))
    for (unsigned vertex : component)
      if (component.size() > 1 || llvm::is_contained(inner[vertex], vertex))
        onCycle.push_back(nodes[vertex]);
  llvm::sort(onCycle);
  SmallVector<DataOp> out;
  for (unsigned at : onCycle)
    out.push_back(declarations[at]);
  return out;
}
