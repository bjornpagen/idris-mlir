// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: a parameter the function never needs a reference of
// its own for is borrowed, and its callers keep the reference, which saves
// an idr.dup and an idr.drop per call.
//
// Every parameter starts borrowed and becomes owned when it or a field read
// from it
//   - is taken apart (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor;
//   - is returned, or forwarded on (a match's yield, the value a loop
//     carries round), which owns what it holds;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call. A self call
// whose result a tail position puts in a constructor counts as one:
// idr-trmc makes it a tail call that writes the field, unless a drop sits
// between the call and the constructor. An element read from a buffer
// takes a reference of its own where it is read: it is owned, and owning
// it asks nothing of the buffer.
// The program's root keeps its parameters owned: its caller is not a call
// this analysis sees. A parameter of quantity 1 is owned too: Idris proved
// the function uses it once, so it moves to that use and is never counted.
// A memo cell is never owned: a force writes it while its caller still
// reads it, so the dispatch that forces it reads a view.
//
// What a function's parameters need depends on its own body, on its
// callees' parameters, and through a tail call on what the functions of
// its cycle pass it. So the cycles of the call graph are solved callees
// first, each once every function it calls outside it is final.
//
// The takes of reset/reuse are its decisions, not ops yet: each one owns
// its box where the take will go, in the order a walk would meet it.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/Analysis/CallGraph.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;
using idr::ownership::readFrom;
using idr::ownership::tracked;

namespace idr {

namespace {

class Inference {
public:
  Inference(ProgramOp program, SymbolTable &symbols, const Reuses &reuses)
      : program(program), symbols(symbols), reuses(reuses) {}

  void run(DenseMap<Operation *, SmallVector<Borrows::Param>> &paramsOf,
           DenseMap<Operation *, SmallVector<bool>> &resultsOf, unsigned &borrowed) {
    FuncOp root = program.lookupRoot();
    SmallVector<FuncOp> functions(program.getOps<FuncOp>());
    for (FuncOp fn : functions) {
      bool fixed = fn == root;
      SmallVector<bool> params, views;
      for (Type type : fn.getArgumentTypes()) {
        bool view = !fixed && ownership::isMemoCell(type);
        views.push_back(view);
        params.push_back(!view && (fixed || !ownership::counted(type) ||
                                   quantityOf(type) == Quantity::One));
      }
      owned[fn] = std::move(params);
      viewsOf[fn] = std::move(views);
    }
    const CallGraph graph(program);
    for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc)
      solve(*scc);
    for (FuncOp fn : functions) {
      SmallVector<Borrows::Param> &params = paramsOf[fn];
      for (auto [type, holds] : llvm::zip_equal(fn.getArgumentTypes(), owned[fn])) {
        if (!ownership::counted(type)) {
          params.push_back(Borrows::Param::Untracked);
          continue;
        }
        params.push_back(holds ? Borrows::Param::Owned : Borrows::Param::Borrowed);
        borrowed += holds ? 0 : 1;
      }
      SmallVector<bool> &results = resultsOf[fn];
      for (Type result : fn.getResultTypes())
        results.push_back(ownership::counted(result));
    }
  }

private:
  static FuncOp functionOf(const CallGraphNode *node) {
    return cast<FuncOp>(node->getCallableRegion()->getParentOp());
  }

  // One cycle of calls, every function it calls outside it final. A
  // function is walked again only when its own parameter or that of a
  // function it calls on the cycle became owned; a parameter becomes owned
  // once, so the walks end, and walking every function of the cycle
  // whenever any parameter changed would walk it once per parameter.
  void solve(ArrayRef<CallGraphNode *> nodes) {
    cycle.clear();
    for (const CallGraphNode *node : nodes)
      if (!node->isExternal())
        cycle.insert(functionOf(node));
    if (cycle.empty())
      return;
    DenseMap<FuncOp, llvm::SetVector<FuncOp>> callers;
    for (const CallGraphNode *node : nodes)
      if (!node->isExternal())
        for (const CallGraphNode::Edge &edge : *node)
          if (edge.isCall() && !edge.getTarget()->isExternal())
            if (FuncOp callee = functionOf(edge.getTarget()); cycle.contains(callee))
              callers[callee].insert(functionOf(node));
    llvm::SetVector<FuncOp> work;
    for (FuncOp fn : llvm::reverse(cycle))
      work.insert(fn);
    while (!work.empty()) {
      collect(work.pop_back_val());
      for (FuncOp fn : dirtied) {
        work.insert(fn);
        if (auto of = callers.find(fn); of != callers.end())
          for (FuncOp caller : of->second)
            work.insert(caller);
      }
      dirtied.clear();
    }
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
    if (index < params.size() && !params[index] && !viewsOf[fn][index]) {
      params[index] = true;
      dirtied.insert(fn);
    }
  }

  // `value` needs a reference of its own. An element has one already.
  void own(Value value) {
    if (!tracked(value) || ownership::isCountedElement(value))
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
    if (paramIndex(value) && tracked(value))
      own(value);
  }

  // Whether `value` holds a reference of its own in the function.
  bool isOwned(Value value) {
    if (!tracked(value))
      return false;
    if (std::optional<unsigned> index = paramIndex(value))
      return owned[current][*index];
    if (ownership::isCountedElement(value))
      return true;
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
      if (it != owned.end() && cycle.contains(g) &&
          (tail::inTailPosition(call) || tail::inTailPositionModuloConstructor(call)))
        for (auto [index, arg] : llvm::enumerate(call.getArgOperands()))
          if (isOwned(arg))
            ownParam(g, static_cast<unsigned>(index));
      return;
    }
    if (isa<ConOp>(op)) {
      for (Value operand : op->getOperands())
        ownIfParam(operand);
      return;
    }
    // Borrowed, a returned or forwarded parameter would need a reference
    // of its own to move on with, and the caller's value would be shared
    // from then on.
    if (isa<ReturnOp>(op))
      for (Value operand : op->getOperands())
        own(operand);
    forwardedValues(op, [&](OpOperand &operand, Value) { own(operand.get()); });
  }

  ProgramOp program;
  SymbolTable &symbols;
  const Reuses &reuses;
  DenseMap<FuncOp, SmallVector<bool>> owned;
  // The parameters that are views whatever the function does with them.
  DenseMap<FuncOp, SmallVector<bool>> viewsOf;
  // The functions of the cycle being solved.
  llvm::SetVector<FuncOp> cycle;
  FuncOp current;
  DenseSet<Value> ownedFields;
  DenseMap<Operation *, SmallVector<Value>> takenAfter;
  DenseMap<Block *, SmallVector<Value>> takenAtStart;
  llvm::SetVector<FuncOp> dirtied;
};

} // namespace

Borrows::Borrows(Operation *program, AnalysisManager &am) {
  const Reuses &reuses = am.getAnalysis<Reuses>();
  Inference(cast<ProgramOp>(program), am.getAnalysis<SymbolTable>(), reuses)
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
