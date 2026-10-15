// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's run may do, from what its body does itself and what
// it calls. Over the components of the call graph, callees first, the least
// fixpoint is one pass: a component's effects are the or of its members'
// own parts and of the effects of each callee outside it, final already,
// and every member gets them.
#include "idr/Analysis/Effects.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <cassert>

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

// What `fn` does before its body runs a single op (it may not return
// unless Idris proved it total, and it performs IO when a world reaches
// it, which only a parameter can bring), then what each op of its body
// does itself. A world forged here is IO no parameter announces.
Body bodyOf(idr::FuncOp fn, const SymbolTable &symbols) {
  Body body;
  if (!fn.getTotal())
    body.own = body.own | idr::Effect::diverge;
  if (llvm::any_of(fn.getArgumentTypes(), idr::holdsWorld))
    body.own = body.own | idr::Effect::io;
  fn.getBody().walk([&](Operation *op) {
    if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op); mayCrash && mayCrash.getCrashCause())
      body.own = body.own | idr::Effect::crash;
    if (isa<idr::WorldNewOp>(op))
      body.own = body.own | idr::Effect::io;
    if (auto call = dyn_cast<idr::CallOp>(op))
      body.callees.push_back(calleeOf(call, symbols));
  });
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
        sum = sum | idr::entryOf(callee);
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

SmallVector<SmallVector<idr::FuncOp>> idr::callGraphComponents(const CallGraph &graph) {
  SmallVector<SmallVector<FuncOp>> out;
  // The walk starts at the external node, which reaches every function;
  // it and the unknown callee are no function and are left out.
  for (auto it = llvm::scc_begin(&graph); !it.isAtEnd(); ++it) {
    SmallVector<FuncOp> members;
    for (CallGraphNode *node : *it)
      if (!node->isExternal())
        if (auto fn = dyn_cast<FuncOp>(node->getCallableRegion()->getParentOp()))
          members.push_back(fn);
    if (!members.empty())
      out.push_back(std::move(members));
  }
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
  // function joins once, so the work ends with the set.
  SmallVector<SmallVector<unsigned>> runners(fns.size());
  for (auto [at, slot] : llvm::enumerate(runs))
    for (FuncOp target : slot.targets)
      runners[positions.lookup(target.getOperation())].push_back(static_cast<unsigned>(at));
  llvm::DenseSet<FuncOp> observed;
  SmallVector<unsigned> work;
  for (auto [at, slot] : llvm::enumerate(runs))
    if (slot.observes && observed.insert(fns[at]).second)
      work.push_back(static_cast<unsigned>(at));
  while (!work.empty()) {
    unsigned at = work.pop_back_val();
    for (unsigned runner : runners[at])
      if (observed.insert(fns[runner]).second)
        work.push_back(runner);
  }
  return observed;
}
