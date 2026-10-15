// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's run may do, from what its body does itself and what
// it runs. The bodies separate: each is walked on a worker into its own
// slot, and nothing else of the module is read there but the symbol table
// and what the label solve answers.
//
// The bits flow from a function to every function that runs it. Over the
// components of that graph, callees first, the least fixpoint is one pass:
// a component's summary is the or of its members' own parts and of what
// each run out of it carries, each target's summary final already, and
// every member gets it. A run to a member of the same component carries
// nothing new: that member's own part is in the or.
#include "idr/Analysis/Effects.h"

#include "idr/Analysis/Holds.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <cassert>

using namespace mlir;

namespace {

// What one walk of a body finds: what the body does itself, and the
// functions it runs, those a call or an apply runs apart from those a
// force may run, since a force carries the observable bit only from a
// label that runs at every force.
struct Body {
  idr::EffectSummary own;
  SmallVector<idr::FuncOp> called;
  SmallVector<idr::FuncOp> forced;
};

// Where the labels of an apply or a force come from: the label solve before
// the conversion, the memo sum's type after it.
using LabelSource = llvm::function_ref<void(Operation *, SmallVectorImpl<idr::FuncOp> &)>;

void add(idr::EffectSummary &into, const idr::EffectSummary &from) {
  into.effect = into.effect | from.effect;
  into.observable = into.observable || from.observable;
}

// What `fn` does before its body runs a single op: it may not return unless
// Idris proved it total, and it performs IO when a world reaches it, which
// only a parameter can bring.
idr::EffectSummary entry(idr::FuncOp fn, const idr::Holds &holds) {
  idr::EffectSummary own;
  if (!fn.getTotal())
    own.effect = own.effect | idr::Effect::diverge;
  if (llvm::any_of(fn.getArgumentTypes(), [&](Type type) { return holds.mayHoldWorld(type); }))
    own.effect = own.effect | idr::Effect::io;
  return own;
}

idr::FuncOp calleeOf(idr::CallOp call, const SymbolTable &symbols) {
  auto callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
  assert(callee && "the closed world makes every callee an idr.func of the module");
  return callee;
}

// What `op` does itself, into `body.own`, and what it runs, into
// `body.called` and `body.forced`. A world forged here is IO no parameter
// announces.
void visit(Operation *op, Body &body, const SymbolTable &symbols, LabelSource labels) {
  if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op); mayCrash && mayCrash.getCrashCause())
    body.own.effect = body.own.effect | idr::Effect::crash;
  if (isa<idr::WorldNewOp>(op))
    body.own.effect = body.own.effect | idr::Effect::io;
  if (op->hasTrait<idr::ObservableIO>())
    body.own.observable = true;
  if (auto call = dyn_cast<idr::CallOp>(op))
    body.called.push_back(calleeOf(call, symbols));
  else if (isa<idr::ApplyOp>(op))
    labels(op, body.called);
  else if (isa<idr::ForceOp>(op))
    labels(op, body.forced);
}

// What a call or a function may do: its `effects`, or everything when it
// has none.
idr::Effect mayDo(idr::EffectAttr effects) { return effects ? effects.getValue() : idr::anyEffect; }

// Gives `op` the fact `effect`, the full set as no attribute; an equal fact
// is left as it is.
template <typename OpT>
void give(OpT op, idr::Effect effect) {
  if (effect == idr::anyEffect) {
    if (op.getEffectsAttr())
      op.removeEffectsAttr();
    return;
  }
  auto want = idr::EffectAttr::get(op.getContext(), effect);
  if (op.getEffectsAttr() != want)
    op.setEffectsAttr(want);
}

} // namespace

idr::ModuleEffects::ModuleEffects(ModuleOp module, const Holds &holds, const SymbolTable &table,
                                  LabelsRun labelsRun)
    : symbols(table) {
  llvm::append_range(functions, module.getOps<FuncOp>());
  unsigned n = static_cast<unsigned>(functions.size());
  for (unsigned at = 0; at < n; ++at)
    positions.try_emplace(functions[at].getOperation(), at);

  // Each body into its own slot, with the labels its constants name as
  // suspensions: a closure constant that captures every parameter of its
  // function is a suspension, since a closure leaves at least one.
  SmallVector<Body> bodies(n);
  SmallVector<SmallVector<FuncOp>> named(n);
  parallelFor(module.getContext(), 0, n, [&](size_t at) {
    FuncOp fn = functions[at];
    Body &body = bodies[at];
    body.own = entry(fn, holds);
    fn.getBody().walk([&](Operation *op) {
      visit(op, body, symbols, labelsRun);
      if (auto constant = dyn_cast<ConstantOp>(op))
        constant.getValue().walk([&](ClosureAttr closure) {
          auto label = symbols.lookup<FuncOp>(closure.getCallee().getAttr());
          assert(label && "a closure constant names an idr.func of the module");
          if (closure.getCaptures().size() == label.getNumArguments())
            named[at].push_back(label);
        });
    });
  });
  for (const SmallVector<FuncOp> &labels : named)
    for (FuncOp label : labels)
      statics.insert(label.getOperation());

  SmallVector<SmallVector<unsigned>> successors(n);
  for (unsigned at = 0; at < n; ++at) {
    for (FuncOp target : bodies[at].called)
      successors[at].push_back(position(target));
    for (FuncOp target : bodies[at].forced)
      successors[at].push_back(position(target));
  }

  summaries.assign(n, EffectSummary());
  for (const SmallVector<unsigned> &component : idr::components(successors)) {
    EffectSummary sum;
    for (unsigned member : component) {
      const Body &body = bodies[member];
      add(sum, body.own);
      for (FuncOp target : body.called)
        add(sum, summaries[position(target)]);
      for (FuncOp target : body.forced) {
        unsigned to = position(target);
        sum.effect = sum.effect | summaries[to].effect;
        sum.observable = sum.observable || byNameAt(to);
      }
    }
    for (unsigned member : component)
      summaries[member] = sum;
  }
}

unsigned idr::ModuleEffects::position(FuncOp fn) const {
  auto found = positions.find(fn.getOperation());
  assert(found != positions.end() && "a function of the module the summary was solved on");
  return found->second;
}

bool idr::ModuleEffects::byNameAt(unsigned at) const {
  FuncOp fn = functions[at];
  return summaries[at].observable && !statics.contains(fn.getOperation());
}

bool idr::ModuleEffects::byName(FuncOp label) const { return byNameAt(position(label)); }

void idr::ModuleEffects::writeEntries() const {
  for (auto [fn, summary] : llvm::zip_equal(functions, summaries))
    give(fn, summary.effect);
  for (FuncOp fn : functions)
    fn.getBody().walk([&](CallOp call) {
      give(call, summaries[position(calleeOf(call, symbols))].effect);
    });
}

void idr::forcedLabels(ForceOp force, const SymbolTable &symbols,
                       SmallVectorImpl<FuncOp> &labels) {
  DataType data = dataTypeOf(force.getSuspension().getType());
  assert(data && data.isMemo() && "after the conversion a force reads a box of a memo sum");
  for (auto [tag, ctor] : llvm::enumerate(data.getCtors())) {
    if (!data.isLabel(static_cast<unsigned>(tag)))
      continue;
    auto label = symbols.lookup<FuncOp>(ctor.name);
    assert(label && "a label constructor names an idr.func of the module");
    labels.push_back(label);
  }
}

void idr::writeCallEffectsOnReady(ArrayRef<FuncOp> component, const SymbolTable &symbols) {
  llvm::SmallPtrSet<Operation *, 8> members;
  for (FuncOp member : component)
    members.insert(member.getOperation());
  for (FuncOp member : component)
    member.getBody().walk([&](CallOp call) {
      FuncOp callee = calleeOf(call, symbols);
      if (!members.contains(callee.getOperation()))
        give(call, mayDo(callee.getEffectsAttr()));
    });
}

void idr::writeEntriesOnFinal(ArrayRef<FuncOp> component, const Holds &holds,
                              const SymbolTable &symbols) {
  llvm::SmallPtrSet<Operation *, 8> members;
  for (FuncOp member : component)
    members.insert(member.getOperation());
  auto labels = [&](Operation *op, SmallVectorImpl<FuncOp> &out) {
    forcedLabels(cast<ForceOp>(op), symbols, out);
  };
  Effect sum = Effect::none;
  for (FuncOp member : component) {
    Body body;
    body.own = entry(member, holds);
    member.getBody().walk([&](Operation *op) { visit(op, body, symbols, labels); });
    sum = sum | body.own.effect;
    for (FuncOp target : llvm::concat<FuncOp>(body.called, body.forced))
      if (!members.contains(target.getOperation()))
        sum = sum | mayDo(target.getEffectsAttr());
  }
  for (FuncOp member : component)
    give(member, sum);
  for (FuncOp member : component)
    member.getBody().walk([&](CallOp call) {
      if (members.contains(calleeOf(call, symbols).getOperation()))
        give(call, sum);
    });
}
