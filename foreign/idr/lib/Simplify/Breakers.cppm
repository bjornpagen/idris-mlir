// idr.simplify:breakers: every cycle of references among the functions that
// may be inlined keeps a loop breaker, at the start of every round
// of the simplify loop.
//
// The first round marks the breakers of the cycles Emit wrote; Emit marks
// none, so there is one rule for every cycle. The rounds then close
// new cycles: a call redirected to a clone that calls back, or, through
// sccp, a function that returns a closure constant of itself (an IO loop
// whose action is a constant: `echo = getChar >>= \c => ... echo`, where
// `echo` returns the action that `\c` closes over, so `\c` refers to
// itself). A cycle that a redirection closes only once inlining shows how
// a call is consumed (a call of a breaker in the breaker's clone, passed to
// a callee that applies it) is no cycle of references until then: the
// clone carries its callee's no_inline instead (idr-specialize). The
// inliner sees only calls. It refuses only self-recursion and a callee that
// calls its caller back (`Inliner::Impl::shouldInline`), and it blocks a
// recursive call edge, once inlining has unrolled it, only for the rest of
// that inliner run; each round's run starts afresh, so it would unroll
// such a cycle once per round, forever. A function refers to what it calls
// and to the functions its closures and closure constants name. In each
// cycle without a breaker (two or more functions, or one that refers to
// itself), the newest clone becomes `no_inline`, or else the first
// function in module order that does not break last (`idr.break_last`,
// which Emit writes from the registry's column), or else the first; then
// the rest of the cycle is cut the same way.
export module idr.simplify:breakers;

import idr.mlir;
import idr.facts;
import idr.graph;

using namespace mlir;

namespace {

// The breaker of a cycle: its newest clone, or else its first function in
// module order that does not break last, or else its first.
func::FuncOp choose(ArrayRef<func::FuncOp> cycle,
                    const llvm::DenseMap<func::FuncOp, unsigned> &order) {
  func::FuncOp newest, first, firstEarly;
  for (func::FuncOp fn : cycle) {
    unsigned at = order.lookup(fn);
    if (fn->hasAttr("idr.clone") && (!newest || order.lookup(newest) < at))
      newest = fn;
    if (!first || at < order.lookup(first))
      first = fn;
    if (!idr::facts::breaksLast(fn) && (!firstEarly || at < order.lookup(firstEarly)))
      firstEarly = fn;
  }
  return newest ? newest : firstEarly ? firstEarly : first;
}

} // namespace

namespace idr::simplify {

// Marks a loop breaker `no_inline` in every cycle of references of
// `module` that has none; returns how many it marked.
export unsigned markLoopBreakers(ModuleOp module) {
  SymbolTable symbols(module);
  llvm::DenseMap<func::FuncOp, unsigned> order;
  for (auto fn : module.getOps<func::FuncOp>())
    order.try_emplace(fn, order.size());

  // What each body names. Marking a breaker drops that function from the
  // graph and does not change a body's uses, so the uses are read once.
  // The edges between the functions that may be inlined are built from
  // those lists once; a later iteration deletes the edges that touch the
  // breaker instead of walking every callee list into a new adjacency.
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> named;
  SmallVector<func::FuncOp> nodes;
  llvm::DenseMap<func::FuncOp, unsigned> index;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    named.try_emplace(fn, idr::graph::refersTo(fn, symbols));
    if (fn.getNoInline())
      continue;
    index.try_emplace(fn, nodes.size());
    nodes.push_back(fn);
  }
  SmallVector<SmallVector<unsigned>> edges(nodes.size());
  SmallVector<SmallVector<unsigned>> incoming(nodes.size());
  for (unsigned at = 0; at < nodes.size(); ++at) {
    for (func::FuncOp next : named.find(nodes[at])->second) {
      auto to = index.find(next);
      if (to == index.end())
        continue;
      edges[at].push_back(to->second);
      incoming[to->second].push_back(at);
    }
  }
  // A dropped function keeps its index, so the others are not renumbered.
  // No edge is left in or out of it, and it is then a component of its own.
  SmallVector<bool> live(nodes.size(), true);
  auto drop = [&](unsigned at) {
    live[at] = false;
    for (unsigned from : incoming[at])
      llvm::erase(edges[from], at);
    edges[at].clear();
    incoming[at].clear();
  };

  unsigned marked = 0;
  for (bool again = true; again;) {
    again = false;
    for (const SmallVector<unsigned> &component : idr::graph::components(edges)) {
      if (!llvm::all_of(component, [&](unsigned vertex) { return live[vertex]; }))
        continue;
      SmallVector<func::FuncOp> cycle;
      for (unsigned vertex : component)
        cycle.push_back(nodes[vertex]);
      if (cycle.size() == 1 &&
          !llvm::is_contained(named.find(cycle.front())->second, cycle.front()))
        continue;
      func::FuncOp breaker = choose(cycle, order);
      breaker.setNoInline(true);
      drop(index.find(breaker)->second);
      ++marked;
      again = true;
    }
  }
  return marked;
}

} // namespace idr::simplify
