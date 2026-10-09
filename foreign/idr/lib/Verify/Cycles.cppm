// idr.verify:cycles: no array can hold a reference to itself. Idris is
// strict and its data immutable, so a new object only points at objects
// that exist before it, and the heap is acyclic: what lets counting free
// everything, with a release walk that marks nothing and a count of one
// that means nobody else. An array, of any rank (an IORef is one of rank
// 0), is the one cell written after it exists, so a knot needs an array
// whose element type can reach the array again, and whether one can is a
// question of types, answered once for the module.
export module idr.verify:cycles;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;
using namespace idr;

namespace {

// What a value of each type can hold a reference to. A node is a
// declaration, by its value type, or an array; an edge goes from a
// declaration to what its constructors' fields name and from an array to
// what its element names, through grades. An unboxed sum is a node like a
// box: its fields are stored where it is, so what they name is reached
// through it. A memo sum is a declaration like any other: its cell is
// written once, with a value computed from captures older than the cell,
// so only an array's edge closes a knot. A static memo can reach itself
// (a constant stream whose forced tail is the constant), but only through
// static cells, which are never counted. Before idr-defunctionalize a
// closure's captures are not types yet, and a closure names nothing.
class TypeGraph {
public:
  explicit TypeGraph(ModuleOp module) {
    for (auto data : module.getOps<DataOp>()) {
      unsigned at = node(data.getValueType());
      declarations[at] = data;
    }
    // A field adds the nodes it names, so the list grows as it is read.
    for (unsigned at = 0; at < types.size(); ++at) {
      if (auto array = dyn_cast<MemRefType>(types[at])) {
        edge(at, array.getElementType());
        continue;
      }
      if (!declarations[at])
        continue;
      for (auto ctor : declarations[at].getBody().getOps<CtorOp>()) {
        ArrayAttr fields = ctor.getFieldTypesAttr();
        for (Attribute field : fields ? fields.getValue() : ArrayRef<Attribute>())
          if (auto held = dyn_cast<TypeAttr>(field))
            edge(at, held.getValue());
      }
    }
  }

  Type type(unsigned at) const { return types[at]; }
  bool isArray(unsigned at) const { return isa<MemRefType>(types[at]); }

  // The sets of types that reach one another through an array. An array
  // cannot hold itself, so a strongly connected component with an array in
  // it is a cycle through that array's edge, and a component without one
  // is immutable data, which cannot knot.
  SmallVector<SmallVector<unsigned>> knots() const {
    SmallVector<SmallVector<unsigned>> out;
    if (llvm::none_of(types, [](Type node) { return isa<MemRefType>(node); }))
      return out;
    for (SmallVector<unsigned> &component : idr::graph::components(successors))
      if (component.size() > 1 && llvm::any_of(component, [&](unsigned at) { return isArray(at); }))
        out.push_back(std::move(component));
    return out;
  }

  // The cycle of `component` through its array `array`, by a shortest
  // path: from what the array holds back to the array, and to what it holds
  // again.
  SmallVector<unsigned> cycle(unsigned array, ArrayRef<unsigned> component) const {
    unsigned element = successors[array].front();
    // A walk breadth first from the element: `unseen` is what of the
    // component it has not reached yet, `previous` the step that reached
    // each of the rest.
    llvm::BitVector unseen(static_cast<unsigned>(types.size()));
    for (unsigned at : component)
      unseen.set(at);
    unseen.reset(element);
    SmallVector<unsigned> previous(types.size());
    SmallVector<unsigned> queue{element};
    for (size_t at = 0; at < queue.size() && unseen.test(array); ++at)
      for (unsigned next : successors[queue[at]])
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

private:
  // The node of `type`, added if it is new.
  unsigned node(Type type) {
    auto [it, fresh] = index.try_emplace(type, static_cast<unsigned>(types.size()));
    if (fresh) {
      types.push_back(type);
      declarations.emplace_back();
      successors.emplace_back();
    }
    return it->second;
  }

  // An edge from `from` to what a field or an element of type `type`
  // names, seen through its grade: a declaration or an array, if any.
  void edge(unsigned from, Type type) {
    type = unrestricted(type);
    if (!isa<DataType, BoxType>(type) && !idr::isArray(type))
      return;
    unsigned to = node(type);
    successors[from].push_back(to);
  }

  SmallVector<Type> types;
  SmallVector<DataOp> declarations;
  SmallVector<SmallVector<unsigned>> successors;
  llvm::DenseMap<Type, unsigned> index;
};

// A type as the message names it: a declaration by its symbol, an array by
// what it holds, an array of rank 0 as the IORef it is.
void describe(InFlightDiagnostic &out, Type type) {
  if (auto array = dyn_cast<MemRefType>(type)) {
    out << (array.getRank() == 0 ? "IORef of " : "array of ");
    describe(out, array.getElementType());
  } else if (auto data = dyn_cast<DataType>(type)) {
    out << data.getName().getValue();
  } else if (auto box = dyn_cast<BoxType>(type)) {
    out << box.getName().getValue();
  } else {
    out << type;
  }
}

} // namespace

export namespace idr::verify {

// No array can hold a reference to itself: no cycle of types passes
// through an array. Each cycle is reported once, with the types on it, at
// the first idr.array.new that makes one of its arrays, or else at the
// module.
LogicalResult cycles(ModuleOp module) {
  TypeGraph graph(module);
  SmallVector<SmallVector<unsigned>> knots = graph.knots();
  if (knots.empty())
    return success();

  // The array each message names: the one the first idr.array.new of the
  // knot makes, else the knot's first. This runs before the ops are
  // verified, so an array.new is read by the type of its result alone.
  llvm::DenseMap<Type, std::pair<unsigned, unsigned>> knotOf;
  SmallVector<unsigned> named;
  SmallVector<Operation *> made(knots.size(), nullptr);
  for (auto [knot, members] : llvm::enumerate(knots)) {
    for (unsigned at : members)
      if (graph.isArray(at))
        knotOf[graph.type(at)] = {static_cast<unsigned>(knot), at};
    named.push_back(*llvm::find_if(members, [&](unsigned at) { return graph.isArray(at); }));
  }
  module.walk([&](Operation *op) {
    if (!isa<ArrayNewOp>(op) || op->getNumResults() == 0)
      return;
    auto found = knotOf.find(unrestricted(op->getResult(0).getType()));
    if (found == knotOf.end() || made[found->second.first])
      return;
    made[found->second.first] = op;
    named[found->second.first] = found->second.second;
  });

  for (auto [members, op, array] : llvm::zip_equal(knots, made, named)) {
    SmallVector<unsigned> cycle = graph.cycle(array, members);
    InFlightDiagnostic error = op ? op->emitError() : module.emitError();
    // The lead names the array itself, by its rank: the path after it runs
    // from what the array holds, through any types between, to the array
    // and back.
    error << "unsupported (cycle): an ";
    describe(error, graph.type(array));
    error << " can hold a reference to itself through ";
    for (auto [step, at] : llvm::enumerate(cycle)) {
      if (step != 0)
        error << " -> ";
      describe(error, graph.type(at));
    }
  }
  return failure();
}

} // namespace idr::verify
