// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's run may do, from what its body does itself and what
// it calls. Over the components of the call graph, callees first, the least
// fixpoint is one pass: a component's effects are the or of its members'
// own parts and of the effects of each callee outside it, final already,
// and every member gets them.
#include "idr/Analysis/Effects.h"

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>
#include <optional>

using namespace mlir;

namespace {

// What one walk of a body finds: what the body does itself, and the
// callee of each of its calls, repeats kept.
struct Body {
  idr::Effect own = idr::Effect::none;
  SmallVector<idr::FuncOp> callees;
};

idr::FuncOp calleeOf(idr::CallOp call, const SymbolTable &symbols) {
  auto callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
  assert(callee && "the closed world makes every callee an idr.func of the program");
  return callee;
}

// What `fn`'s body does itself, idr::bodyEffect's one rule, which the
// program's verifier also reads; then the callee of each of its calls.
Body bodyOf(idr::FuncOp fn, const SymbolTable &symbols) {
  Body body{idr::bodyEffect(fn), {}};
  fn.getBody().walk([&](idr::CallOp call) { body.callees.push_back(calleeOf(call, symbols)); });
  return body;
}

// The or of the members' own parts and of the callees outside the
// component.
idr::Effect sumOf(ArrayRef<idr::FuncOp> component, ArrayRef<Body> bodies) {
  llvm::SmallPtrSet<Operation *, 8> members;
  for (idr::FuncOp member : component)
    members.insert(member.getOperation());
  idr::Effect sum = idr::Effect::none;
  for (const Body &body : bodies) {
    sum = sum | body.own;
    for (idr::FuncOp callee : body.callees)
      if (!members.contains(callee.getOperation()))
        sum = sum | callee.getEffects();
  }
  return sum;
}

} // namespace

void idr::setEntry(FuncOp fn, Effect effect) {
  if (effect == anyEffect) {
    if (fn.getEffectsAttr())
      fn.removeEffectsAttr();
    return;
  }
  auto want = EffectAttr::get(fn.getContext(), effect);
  if (fn.getEffectsAttr() != want)
    fn.setEffectsAttr(want);
}

// The graph's functions in its order, which is the program's, and the
// calls between them, each once, in the order each body makes them: the
// call graph's edges alone. Its external node is no part of it, so the
// components do not rest on that node reaching every function.
SmallVector<SmallVector<idr::FuncOp>> idr::callGraphComponents(const CallGraph &graph) {
  SmallVector<FuncOp> fns;
  llvm::DenseMap<const CallGraphNode *, unsigned> index;
  for (CallGraphNode *node : graph)
    if (auto fn = dyn_cast<FuncOp>(node->getCallableRegion()->getParentOp())) {
      index.try_emplace(node, static_cast<unsigned>(fns.size()));
      fns.push_back(fn);
    }
  SmallVector<SmallVector<unsigned>> calls(fns.size());
  for (CallGraphNode *node : graph) {
    auto from = index.find(node);
    if (from == index.end())
      continue;
    for (const CallGraphNode::Edge &edge : *node)
      if (edge.isCall())
        if (auto to = index.find(edge.getTarget()); to != index.end())
          calls[from->second].push_back(to->second);
  }
  SmallVector<SmallVector<FuncOp>> out;
  for (const SmallVector<unsigned> &component : components(calls))
    out.push_back(llvm::map_to_vector(component, [&](unsigned at) { return fns[at]; }));
  return out;
}

idr::Effect idr::componentEffects(ArrayRef<FuncOp> component, const SymbolTable &symbols) {
  SmallVector<Body> bodies;
  for (FuncOp member : component)
    bodies.push_back(bodyOf(member, symbols));
  return sumOf(component, bodies);
}

void idr::solveEffects(ProgramOp program) {
  SymbolTable symbols(program);
  CallGraph graph(program);
  SmallVector<SmallVector<FuncOp>> components = callGraphComponents(graph);

  // Each body is walked on a worker into its own slot; the solve then goes
  // through the components in order, each reading what the earlier ones
  // wrote.
  SmallVector<FuncOp> fns;
  for (const SmallVector<FuncOp> &component : components)
    llvm::append_range(fns, component);
  SmallVector<Body> bodies(fns.size());
  parallelFor(program.getContext(), 0, fns.size(),
              [&](size_t at) { bodies[at] = bodyOf(fns[at], symbols); });

  size_t at = 0;
  for (const SmallVector<FuncOp> &component : components) {
    Effect sum = sumOf(component, ArrayRef<Body>(bodies).slice(at, component.size()));
    at += component.size();
    for (FuncOp member : component)
      setEntry(member, sum);
  }
}

llvm::DenseSet<idr::FuncOp> idr::observableRuns(ProgramOp program, const SymbolTable &symbols,
                                                LabelsRun labelsRun) {
  SmallVector<FuncOp> fns(program.getOps<FuncOp>());
  llvm::DenseMap<Operation *, unsigned> positions;
  for (auto [at, fn] : llvm::enumerate(fns))
    positions.try_emplace(fn.getOperation(), static_cast<unsigned>(at));

  // Each body into its own slot: whether it observes something itself, and
  // what it runs.
  struct Runs {
    bool observes = false;
    SmallVector<FuncOp> targets;
  };
  SmallVector<Runs> runs(fns.size());
  parallelFor(program.getContext(), 0, fns.size(), [&](size_t at) {
    Runs &slot = runs[at];
    fns[at].getBody().walk([&](Operation *op) {
      if (op->hasTrait<ObservableIO>())
        slot.observes = true;
      if (auto call = dyn_cast<CallOp>(op))
        slot.targets.push_back(calleeOf(call, symbols));
      else if (isa<ApplyOp, ForceOp>(op))
        labelsRun(op, slot.targets);
    });
  });

  // The reach runs backwards, from what observes to what runs it. Each
  // target is a function of the program, so it has a position: a callee is
  // what the program's table resolves, and a label the function the table
  // gives for a label the solve read off the program.
  SmallVector<SmallVector<unsigned>> runners(fns.size());
  for (auto [at, slot] : llvm::enumerate(runs))
    for (FuncOp target : slot.targets)
      runners[positions.at(target.getOperation())].push_back(static_cast<unsigned>(at));
  // Each function enters the worklist once, when it is first found to
  // observe, and joins the set when it leaves it.
  OnceWorklist<unsigned> work;
  for (auto [at, slot] : llvm::enumerate(runs))
    if (slot.observes)
      work.push(static_cast<unsigned>(at));
  llvm::DenseSet<FuncOp> observed;
  while (std::optional<unsigned> at = work.pop()) {
    observed.insert(fns[*at]);
    for (unsigned runner : runners[*at])
      work.push(runner);
  }
  return observed;
}
