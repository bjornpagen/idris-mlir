// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Returned.cpp - Which results are always one of the arguments -------===//
//
// A value threaded through a function and given back (a linear array
// through every read and write of it, the state of a recursion or of a
// loop) is, once lowered, the argument itself on every path: through the
// join of an scf.if or scf.index_switch, through a loop whose every
// iteration yields it unchanged (what idr-tail-loops makes of a tail
// recursion, with poison where an exit value has none yet), and through
// the recursive calls, whose result is the argument they pass by the
// hypothesis the analysis refines to a fixpoint from the optimistic start.
// The result is then no information: the caller holds that value already,
// live across the call.
//
// Only a private function every use of which is a direct call changes its
// signature. A result that is an argument on some paths only stays, and so
// does one returned only by calls that never return (unconstrained at the
// fixpoint).
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::tail {
namespace {

using Known = Returned::Known;

// Which argument of a function a value is, under what is known of the
// eligible callees, by name, and under the hypotheses on the loop
// arguments being resolved: a loop argument is the function's argument
// when its initial value is and what the loop yields for it is too, by
// that hypothesis. A ub.poison is a value of the program, given where
// nothing reads it (on the path of a loop that does not take it, after a
// crash): it may be taken to be anything, so it agrees with anything.
class Solver {
public:
  Solver(const llvm::DenseMap<StringAttr, unsigned> &slots, ArrayRef<SmallVector<Known>> results)
      : slots(slots), results(results) {}

  Known argumentOf(func::FuncOp fn, Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value))
      return argumentOf(fn, arg);
    auto result = cast<OpResult>(value);
    Operation *op = result.getOwner();
    unsigned index = result.getResultNumber();
    if (isa<ub::PoisonOp>(op))
      return Known();
    if (isa<scf::IfOp, scf::IndexSwitchOp>(op)) {
      Known joined;
      for (Region &region : op->getRegions()) {
        if (region.empty())
          return Known::none();
        joined = joined.meet(argumentOf(fn, region.front().getTerminator()->getOperand(index)));
      }
      return joined;
    }
    if (auto select = dyn_cast<arith::SelectOp>(op))
      return argumentOf(fn, select.getTrueValue()).meet(argumentOf(fn, select.getFalseValue()));
    if (auto loop = dyn_cast<scf::WhileOp>(op))
      return argumentOf(fn, loop.getConditionOp().getArgs()[index]);
    if (auto loop = dyn_cast<scf::ForOp>(op))
      return argumentOf(fn, loop.getRegionIterArgs()[index]);
    if (auto call = dyn_cast<func::CallOp>(op)) {
      auto it = slots.find(call.getCalleeAttr().getAttr());
      if (it == slots.end())
        return Known::none();
      Known known = results[it->second][index];
      if (known.kind == Known::Argument)
        return argumentOf(fn, call.getOperand(known.argument));
      return known;
    }
    return Known::none();
  }

private:
  Known argumentOf(func::FuncOp fn, BlockArgument arg) {
    Block *block = arg.getOwner();
    if (block == &fn.getBody().front())
      return Known::arg(arg.getArgNumber());
    if (auto it = assumed.find(arg); it != assumed.end())
      return it->second;
    unsigned index = arg.getArgNumber();
    if (auto loop = dyn_cast<scf::WhileOp>(block->getParentOp())) {
      if (block == loop.getAfterBody())
        return argumentOf(fn, loop.getConditionOp().getArgs()[index]);
      return carried(fn, arg, loop.getInits()[index], loop.getYieldOp().getOperand(index));
    }
    if (auto loop = dyn_cast<scf::ForOp>(block->getParentOp())) {
      if (index == 0)
        return Known::none();
      return carried(fn, arg, loop.getInitArgs()[index - 1], loop.getBody()->getTerminator()->getOperand(index - 1));
    }
    return Known::none();
  }

  // A loop argument: its initial value, which what the loop yields for it
  // must agree with, under the hypothesis that the argument is that value.
  Known carried(func::FuncOp fn, BlockArgument arg, Value init, Value yielded) {
    Known initial = argumentOf(fn, init);
    if (initial.kind != Known::Argument)
      return initial;
    assumed[arg] = initial;
    Known joined = initial.meet(argumentOf(fn, yielded));
    assumed.erase(arg);
    return joined;
  }

  const llvm::DenseMap<StringAttr, unsigned> &slots;
  ArrayRef<SmallVector<Known>> results;
  llvm::DenseMap<Value, Known> assumed;
};

} // namespace

bool Returned::Function::drops() const {
  return llvm::any_of(results, [](Known known) { return known.kind == Known::Argument; });
}

SmallVector<unsigned> Returned::Function::kept() const {
  SmallVector<unsigned> kept;
  for (auto [i, known] : llvm::enumerate(results))
    if (known.kind != Known::Argument)
      kept.push_back(static_cast<unsigned>(i));
  return kept;
}

const Returned::Function *Returned::dropping(StringAttr name) const {
  auto it = functions.find(name);
  return it != functions.end() && it->second.drops() ? &it->second : nullptr;
}

Returned::Returned(Operation *op) {
  auto module = cast<ModuleOp>(op);
  // Eligible: every use is a direct call, so the calls are all the users.
  SymbolTableCollection tables;
  SymbolUserMap users(tables, module);
  SmallVector<func::FuncOp> eligible;
  SmallVector<ArrayRef<Operation *>> calls;
  llvm::DenseMap<StringAttr, unsigned> slots;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal() || fn.isPublic() || fn.getNumResults() == 0)
      continue;
    ArrayRef<Operation *> uses = users.getUsers(fn);
    if (!llvm::all_of(uses, [](Operation *user) { return isa<func::CallOp>(user); }))
      continue;
    slots[fn.getSymNameAttr()] = static_cast<unsigned>(eligible.size());
    eligible.push_back(fn);
    calls.push_back(uses);
  }

  // What a function returns depends on what its callees return, never on
  // its callers, so the cycles of the call graph are solved callees first,
  // each once every function it calls outside it is final. Within one, a
  // function is walked again only when a callee on it changed: a result
  // only meets down from unconstrained, twice at most, so the walks end, and
  // the greatest fixpoint does not depend on their order.
  SmallVector<SmallVector<Known>> results;
  for (func::FuncOp fn : eligible)
    results.emplace_back(fn.getNumResults(), Known());
  Solver solver(slots, results);
  const CallGraph graph(module);
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc) {
    llvm::SetVector<unsigned> cycle;
    for (const CallGraphNode *node : *scc)
      if (!node->isExternal())
        if (auto fn = dyn_cast<func::FuncOp>(node->getCallableRegion()->getParentOp()))
          if (auto it = slots.find(fn.getSymNameAttr()); it != slots.end())
            cycle.insert(it->second);
    llvm::SetVector<unsigned> work;
    for (unsigned i : llvm::reverse(cycle))
      work.insert(i);
    while (!work.empty()) {
      unsigned i = work.pop_back_val();
      func::FuncOp fn = eligible[i];
      // A func.return ends a block of the body, so the returns are the
      // terminators of its blocks.
      SmallVector<Known> now(fn.getNumResults(), Known());
      for (Block &block : fn.getBody())
        if (auto ret = dyn_cast<func::ReturnOp>(block.getTerminator()))
          for (auto [r, operand] : llvm::enumerate(ret.getOperands()))
            now[r] = now[r].meet(solver.argumentOf(fn, operand));
      if (now == results[i])
        continue;
      results[i] = std::move(now);
      for (Operation *call : calls[i])
        if (auto caller = call->getParentOfType<func::FuncOp>())
          if (auto it = slots.find(caller.getSymNameAttr());
              it != slots.end() && cycle.contains(it->second))
            work.insert(it->second);
    }
  }

  for (auto [i, fn] : llvm::enumerate(eligible)) {
    Function &function = functions[fn.getSymNameAttr()];
    function.results = std::move(results[i]);
    function.types.assign(fn.getResultTypes().begin(), fn.getResultTypes().end());
    if (!function.drops())
      continue;
    numDropped += static_cast<unsigned>(function.results.size() - function.kept().size());
    changed.insert(fn.getSymNameAttr());
    for (Operation *call : calls[i])
      if (auto caller = call->getParentOfType<func::FuncOp>())
        changed.insert(caller.getSymNameAttr());
  }
}

} // namespace idr::tail
