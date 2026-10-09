// idr.specialize:bindingtimes: which parameters of a function a call may
// specialize on.
//
// A function is recursive when it is on a cycle of references (the
// functions it calls, and those its closures and closure constants name):
// recursion through a closure counts. A parameter of a recursive function
// is
//   - fixed when every reference to the function from its cycles passes it
//     unchanged in the same position: one clone serves the whole recursion,
//     whose calls then have its key;
//   - decreasing when every such reference passes a proper part of it: a
//     field of it, an argument of a region of a match on it, or its
//     predecessor as a Nat (`idr.big.pred`, defined on non-zero values
//     only); the keys shrink along the chain of clones;
//   - bounded when every such reference passes it or a proper part of it:
//     the keys are parts of the first one;
//   - other otherwise: an accumulator, a counter, a closure rebuilt on every
//     iteration. A call never specializes on it.
//
// The classes are found as Lean's fixed parameters are: each function is
// interpreted over abstract values (a parameter, a proper part of one, or
// anything), and so is every function of its cycles that it reaches, once
// for each assignment of abstract values to its parameters, so the analysis
// ends. They are computed from the module as the pass finds it, before it
// changes anything: a clone the pass makes has none until its next run.
//
// A raised clone recurses where its callee does, though on no cycle of
// references until raising closes it: it runs its callee's body with the
// consumer at its tails, and a call of the callee there whose result is
// consumed alike becomes a call of the clone once inlining shows the
// consumer. Its parameters are its callee's, then the apply's arguments,
// and that recursion passes the callee's as the callee does and the
// apply's arguments as anything. So each parameter of a raised clone of a
// recursive callee has its callee's binding time as well as its own, and
// an apply's argument is other. A callee that is gone, or that takes other
// parameters now, makes no call that raising would turn into the clone.
export module idr.specialize:bindingtimes;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :bindingtime;
import :clones;
import :interpreter;

using namespace mlir;

export namespace idr::specialize {

class BindingTimes {
public:
  BindingTimes(mlir::ModuleOp module, CloneTable &clones);

  // The binding time of parameter `index` of `fn`, or none for a function
  // the analysis did not see: one made after it ran.
  std::optional<BindingTime> of(mlir::func::FuncOp fn, unsigned index) const;

private:
  // Every parameter of every function the analysis saw; Free throughout for
  // one on no cycle.
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<BindingTime>> times;
};

} // namespace idr::specialize

namespace idr::specialize {

namespace {

// The binding time of a parameter that two recursions pass, one as `a` and
// the other as `b` says: free where one does not recur.
BindingTime join(BindingTime a, BindingTime b) {
  if (a == BindingTime::Free || a == b)
    return b;
  if (b == BindingTime::Free)
    return a;
  if (a == BindingTime::Other || b == BindingTime::Other)
    return BindingTime::Other;
  // Fixed, decreasing or bounded on each side: the parameter or a part of it.
  return BindingTime::Bounded;
}

// The callee of a raised clone's key and the arity the key counts, or none
// for another key.
std::optional<std::pair<StringAttr, unsigned>> raisedFrom(Attribute key) {
  if (auto apply = dyn_cast<KeyApplyAttr>(key))
    return std::make_pair(apply.getCallee(), apply.getArity());
  if (auto field = dyn_cast<KeyApplyFieldAttr>(key))
    return std::make_pair(field.getCallee(), field.getArity());
  return std::nullopt;
}

} // namespace

BindingTimes::BindingTimes(ModuleOp module, CloneTable &clones) {
  SymbolTable &symbols = clones.symbols();
  idr::graph::References references(module, symbols);
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>()) {
    times[fn.getOperation()].assign(fn.getNumArguments(), BindingTime::Free);
    if (!fn.isExternal())
      functions.push_back(fn);
  }
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> edges;
  for (func::FuncOp fn : functions) {
    SmallVector<func::FuncOp> &out = edges[fn];
    for (const idr::graph::References::Site &site : references.of(fn))
      if (!llvm::is_contained(out, site.target))
        out.push_back(site.target);
  }
  for (const SmallVector<func::FuncOp> &component : idr::graph::stronglyConnected<func::FuncOp>(
           functions, [&](func::FuncOp fn) { return edges.lookup(fn); })) {
    func::FuncOp first = component.front();
    if (component.size() == 1 && !llvm::is_contained(edges.lookup(first), first))
      continue;
    llvm::DenseSet<Operation *> cycle;
    for (func::FuncOp fn : component)
      cycle.insert(fn.getOperation());
    for (func::FuncOp fn : component)
      times[fn.getOperation()] = Interpreter(fn, cycle, references).run();
  }

  // Raised clones, each after a raised clone it was raised from.
  llvm::DenseSet<Operation *> inherited;
  auto inherit = [&](auto &self, func::FuncOp fn) -> void {
    if (!inherited.insert(fn.getOperation()).second)
      return;
    const Clone *clone = clones.find(fn);
    std::optional<std::pair<StringAttr, unsigned>> from =
        clone ? raisedFrom(clone->key) : std::nullopt;
    if (!from)
      return;
    auto [name, arity] = *from;
    auto callee = symbols.lookup<func::FuncOp>(name);
    if (!callee || callee.isExternal() || callee.getNumArguments() != arity)
      return;
    self(self, callee);
    SmallVector<BindingTime> theirs = times.lookup(callee.getOperation());
    if (llvm::all_of(theirs, [](BindingTime t) { return t == BindingTime::Free; }))
      return;
    SmallVector<BindingTime> &ours = times[fn.getOperation()];
    for (auto [p, hole] : llvm::enumerate(clone->holes))
      ours[p] = join(ours[p], hole < arity ? theirs[hole] : BindingTime::Other);
  };
  for (func::FuncOp fn : functions)
    inherit(inherit, fn);
}

std::optional<BindingTime> BindingTimes::of(func::FuncOp fn, unsigned index) const {
  auto it = times.find(fn.getOperation());
  if (it == times.end())
    return std::nullopt;
  return it->second[index];
}

} // namespace idr::specialize
