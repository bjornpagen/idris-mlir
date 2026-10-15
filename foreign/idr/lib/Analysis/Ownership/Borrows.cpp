// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: a parameter the function never needs a reference of
// its own for is borrowed, and its callers keep the reference, which saves
// an idr.dup and an idr.drop per call.
//
// Every parameter starts borrowed and becomes owned, until nothing changes
// in the module, when it or a field read from it
//   - is taken apart (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor;
//   - is returned, or yielded by a match, whose results are owned;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call. A self call
// whose result a tail position puts in a constructor counts as one:
// idr-trmc makes it a tail call that writes the field, unless a drop sits
// between the call and the constructor.
// The public root keeps its parameters owned: its caller is not a call
// this analysis sees. A parameter of quantity 1 is owned too: Idris proved
// the function uses it once, so it moves to that use and is never counted.
//
// The takes of reset/reuse are its decisions, not ops yet: each one owns
// its box where the take will go, in the order a walk would meet it.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/References.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;
using idr::ownership::Counted;
using idr::ownership::readFrom;

namespace idr {

namespace {

// What one function contributes before the fixpoint, found on its own: the
// functions it calls.
struct Local {
  SmallVector<FuncOp> callees;
};

class Inference {
public:
  Inference(ModuleOp module, SymbolTable &symbols, const Reuses &reuses)
      : module(module), symbols(symbols), reuses(reuses) {}

  void run(DenseMap<Operation *, SmallVector<Borrows::Param>> &paramsOf,
           DenseMap<Operation *, SmallVector<bool>> &resultsOf, unsigned &borrowed) {
    SmallVector<FuncOp> all(module.getOps<FuncOp>());
    SmallVector<Local> locals(all.size());
    parallelForEach(module.getContext(), llvm::seq<size_t>(0, all.size()),
                    [&](size_t index) { locals[index] = local(all[index]); });
    for (auto [fn, found] : llvm::zip_equal(all, locals)) {
      functions.push_back(fn);
      for (FuncOp g : found.callees)
        callers[g].insert(fn);
    }
    for (FuncOp fn : functions) {
      bool fixed = fn.isPublic();
      SmallVector<bool> params;
      for (Type type : fn.getArgumentTypes())
        params.push_back(fixed || !counted(type) || quantityOf(type) == Quantity::One);
      owned[fn] = std::move(params);
    }
    findCycles(all, locals);
    // A parameter only ever becomes owned, so a function is walked again
    // only when its own parameter or a callee's did. Walking every function
    // whenever any parameter changed walks the module once per parameter.
    llvm::SetVector<FuncOp> work;
    for (FuncOp fn : llvm::reverse(functions))
      work.insert(fn);
    while (!work.empty()) {
      collect(work.pop_back_val());
      for (FuncOp fn : dirtied) {
        work.insert(fn);
        if (auto callersOf = callers.find(fn); callersOf != callers.end())
          for (FuncOp caller : callersOf->second)
            work.insert(caller);
      }
      dirtied.clear();
    }
    for (FuncOp fn : functions) {
      SmallVector<Borrows::Param> &params = paramsOf[fn];
      for (auto [type, holds] : llvm::zip_equal(fn.getArgumentTypes(), owned[fn])) {
        if (!counted(type)) {
          params.push_back(Borrows::Param::Untracked);
          continue;
        }
        params.push_back(holds ? Borrows::Param::Owned : Borrows::Param::Borrowed);
        borrowed += holds ? 0 : 1;
      }
      SmallVector<bool> &results = resultsOf[fn];
      for (Type result : fn.getResultTypes())
        results.push_back(counted(result));
    }
  }

private:
  // The part of the start state one function decides alone; it reads the
  // table, which no one writes while the workers run.
  Local local(FuncOp fn) {
    Local found;
    fn->walk([&](CallOp call) {
      if (auto g = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr()))
        found.callees.push_back(g);
    });
    return found;
  }

  // The cycles of calls, for the tail calls to keep.
  void findCycles(ArrayRef<FuncOp> all, ArrayRef<Local> locals) {
    DenseMap<FuncOp, ArrayRef<FuncOp>> calls;
    for (auto [fn, found] : llvm::zip_equal(all, locals))
      calls[fn] = found.callees;
    auto components = stronglyConnected<FuncOp>(
        functions, [&](FuncOp fn) { return SmallVector<FuncOp>(calls.lookup(fn)); });
    for (auto [index, component] : llvm::enumerate(components))
      for (FuncOp fn : component)
        cycleOf[fn] = static_cast<unsigned>(index);
  }

  // The parameter `value` is of the function being collected, if it is one.
  std::optional<unsigned> paramIndex(Value value) {
    auto arg = dyn_cast<BlockArgument>(value);
    if (!arg || arg.getOwner()->getParentOp() != current.getOperation())
      return std::nullopt;
    return arg.getArgNumber();
  }

  void ownParam(FuncOp fn, unsigned index) {
    SmallVector<bool> &params = owned[fn];
    if (index < params.size() && !params[index]) {
      params[index] = true;
      dirtied.insert(fn);
    }
  }

  // `value` needs a reference of its own.
  void own(Value value) {
    if (!counted.tracked(value))
      return;
    if (std::optional<unsigned> index = paramIndex(value)) {
      ownParam(current, *index);
      return;
    }
    if (Value from = readFrom(value)) {
      if (ownedFields.insert(value).second)
        own(from);
    }
  }

  void ownIfParam(Value value) {
    if (paramIndex(value) && counted.tracked(value))
      own(value);
  }

  // Whether `value` holds a reference of its own in the function.
  bool isOwned(Value value) {
    if (!counted.tracked(value))
      return false;
    if (std::optional<unsigned> index = paramIndex(value))
      return owned[current][*index];
    if (Value from = readFrom(value))
      return ownedFields.contains(value) || isOwned(from);
    return true;
  }

  void collect(FuncOp fn) {
    current = fn;
    ownedFields.clear();
    takenAfter.clear();
    takenAtStart.clear();
    // A box a take of another site's field takes apart is that take's,
    // which owns it already.
    for (const Reuses::Site &site : reuses.sites(fn))
      if (site.box)
        (site.after ? takenAfter[site.after] : takenAtStart[site.block]).push_back(site.box);
    for (Block &block : fn.getBody())
      visit(block);
  }

  // The ops of `block` as a post-order walk meets them, with each take
  // where it will go.
  void visit(Block &block) {
    for (Value box : takenAtStart.lookup(&block))
      own(box);
    for (Operation &op : block) {
      for (Region &region : op.getRegions())
        for (Block &inner : region)
          visit(inner);
      collectOp(&op);
      for (Value box : takenAfter.lookup(&op))
        own(box);
    }
  }

  void collectOp(Operation *op) {
    if (auto call = dyn_cast<CallOp>(op)) {
      auto g = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
      auto it = g ? owned.find(g) : owned.end();
      for (auto [index, arg] : llvm::enumerate(call.getArgOperands()))
        if (it == owned.end() || index >= it->second.size() || it->second[index])
          own(arg);
      if (it != owned.end() && cycleOf.lookup(g) == cycleOf.lookup(current) &&
          (tail::inTailPosition(call) || tail::inTailPositionModuloConstructor(call)))
        for (auto [index, arg] : llvm::enumerate(call.getArgOperands()))
          if (isOwned(arg))
            ownParam(g, static_cast<unsigned>(index));
    } else if (isa<ConOp>(op)) {
      for (Value operand : op->getOperands())
        ownIfParam(operand);
    } else if (isa<ReturnOp, YieldOp>(op)) {
      // Borrowed, a returned parameter would need a reference of its own
      // to leave the call with, and the caller's value would be shared
      // from then on.
      for (Value operand : op->getOperands())
        own(operand);
    }
  }

  ModuleOp module;
  SymbolTable &symbols;
  Counted counted;
  const Reuses &reuses;
  SmallVector<FuncOp> functions;
  DenseMap<FuncOp, SmallVector<bool>> owned;
  DenseMap<FuncOp, unsigned> cycleOf;
  DenseMap<FuncOp, llvm::SetVector<FuncOp>> callers;
  FuncOp current;
  DenseSet<Value> ownedFields;
  DenseMap<Operation *, SmallVector<Value>> takenAfter;
  DenseMap<Block *, SmallVector<Value>> takenAtStart;
  llvm::SetVector<FuncOp> dirtied;
};

} // namespace

Borrows::Borrows(Operation *module, AnalysisManager &am) {
  const Reuses &reuses = am.getAnalysis<Reuses>();
  Inference(cast<ModuleOp>(module), am.getAnalysis<SymbolTable>(), reuses)
      .run(paramsOf, resultsOf, numBorrowed);
}

bool Borrows::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Borrows>() || !pa.isPreserved<Reuses>() || !pa.isPreserved<SymbolTable>();
}

ArrayRef<Borrows::Param> Borrows::params(FuncOp fn) const {
  auto it = paramsOf.find(fn);
  return it == paramsOf.end() ? ArrayRef<Param>() : ArrayRef<Param>(it->second);
}

ArrayRef<bool> Borrows::countedResults(FuncOp fn) const {
  auto it = resultsOf.find(fn);
  return it == resultsOf.end() ? ArrayRef<bool>() : ArrayRef<bool>(it->second);
}

} // namespace idr
