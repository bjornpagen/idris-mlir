// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What exclusivity's solve reads of a program before it marks anything
// (ExclusivityDetail.h): how each call goes, which blocks of a function
// may run, and the graph of writers and the values each reads. The
// questions the solve asks are reachability and joins over a lattice of
// height two, so the representation is the graph itself, built once;
// ExclusivityAnalyses.cpp marks it. Reachability is unconditional
// beyond control flow: every region an op may enter can run, which
// region a constant would skip being the canonicalizer's to fold.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/Analysis/Ownership.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::detail::exclusivity {

Calls::Calls(ProgramOp program, const ownership::Copies &copies) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    callees.try_emplace(fn.getSymNameAttr(), fn);
    // The body's one block ends in its return, or in ub.unreachable when
    // the function never returns.
    SmallVector<ReturnOp> &returns = returnsOf[fn];
    if (auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator()))
      returns.push_back(ret);
  }
  for (auto [original, copy] : copies.of) {
    callees[original.getSymNameAttr()] = Pair{original, copy};
    callees[copy.getSymNameAttr()] = Pair{original, copy};
  }
}

const Calls::Callee &Calls::calleeOf(CallOp call) const {
  return callees.at(call.getCalleeAttr().getAttr());
}

SmallVector<FuncOp, 2> Calls::namesOf(FuncOp fn) const {
  return std::visit(
      llvm::makeVisitor([](FuncOp alone) { return SmallVector<FuncOp, 2>{alone}; },
                        [](Pair pair) { return SmallVector<FuncOp, 2>{pair.original, pair.copy}; }),
      callees.at(fn.getSymNameAttr()));
}

FuncOp Calls::target(CallOp call, function_ref<bool(Value)> isExclusive) const {
  return std::visit(
      llvm::makeVisitor([](FuncOp alone) { return alone; },
                        [&](Pair pair) {
                          for (auto [param, arg] : llvm::zip_equal(pair.original.getArguments(),
                                                                   call.getArgOperands()))
                            if (ownership::followed(param) && !isExclusive(arg))
                              return pair.original;
                          return pair.copy;
                        }),
      calleeOf(call));
}

void liveBlocksOf(FuncOp fn, DenseSet<Block *> &live) {
  SmallVector<Block *> work{&fn.getBody().front()};
  auto regionEntries = [&](Operation *op, RegionBranchPoint point) {
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    if (!branch) {
      if (point.isParent())
        for (Region &region : op->getRegions())
          if (!region.empty())
            work.push_back(&region.front());
      return;
    }
    SmallVector<RegionSuccessor> successors;
    branch.getSuccessorRegions(point, successors);
    for (RegionSuccessor successor : successors)
      if (Region *region = successor.getSuccessor(); region && !region->empty())
        work.push_back(&region->front());
  };
  while (!work.empty()) {
    Block *block = work.pop_back_val();
    if (!live.insert(block).second)
      continue;
    for (Operation &op : *block)
      if (op.getNumRegions())
        regionEntries(&op, RegionBranchPoint::parent());
    Operation *terminator = block->getTerminator();
    if (!terminator)
      continue;
    for (Block *successor : block->getSuccessors())
      work.push_back(successor);
    if (auto end = dyn_cast<RegionBranchTerminatorOpInterface>(terminator))
      if (Operation *parent = block->getParentOp())
        regionEntries(parent, RegionBranchPoint(end));
  }
}

Graph::Graph(ProgramOp program, const Calls &calls) {
  for (FuncOp fn : program.getOps<FuncOp>())
    scan(fn.getBody(), fn, calls);
}

unsigned Graph::addItem(Item item) {
  unsigned id = static_cast<unsigned>(items.size());
  items.push_back(item);
  itemsOf[item.fn].push_back(id);
  return id;
}

void Graph::reads(unsigned id, Value value) { dependents[value].push_back(id); }

void Graph::readsAll(unsigned id, ValueRange values) {
  for (Value value : values)
    reads(id, value);
}

void Graph::readsReturns(unsigned id, FuncOp callee, const Calls &calls) {
  for (ReturnOp ret : calls.returns(callee))
    readsAll(id, ret.getOperands());
}

void Graph::scan(Region &region, FuncOp fn, const Calls &calls) {
  for (Block &block : region) {
    if (&block != &region.front() && block.getNumArguments()) {
      unsigned id = addItem({Item::Kind::BlockArgs, nullptr, &block, fn, nullptr, 0});
      for (Block *pred : block.getPredecessors())
        if (auto branch = dyn_cast<BranchOpInterface>(pred->getTerminator()))
          for (unsigned i = 0, e = pred->getNumSuccessors(); i != e; ++i)
            if (pred->getSuccessor(i) == &block)
              for (Value operand : branch.getSuccessorOperands(i).getForwardedOperands())
                reads(id, operand);
    }
    for (Operation &op : block) {
      scanOp(&op, fn, calls);
      for (Region &inner : op.getRegions())
        scan(inner, fn, calls);
    }
  }
}

void Graph::scanOp(Operation *op, FuncOp fn, const Calls &calls) {
  Block *block = op->getBlock();
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op)) {
    scanBranch(branch, block, fn);
  } else if (auto call = dyn_cast<CallOp>(op)) {
    unsigned id = addItem({Item::Kind::Call, op, block, fn, nullptr, 0});
    readsAll(id, op->getOperands());
    std::visit(llvm::makeVisitor(
                   [&](FuncOp alone) { readsReturns(id, alone, calls); },
                   [&](Calls::Pair pair) {
                     readsReturns(id, pair.original, calls);
                     readsReturns(id, pair.copy, calls);
                   }),
               calls.calleeOf(call));
  } else if (op->getNumResults()) {
    unsigned id = addItem({Item::Kind::Op, op, block, fn, nullptr, 0});
    readsAll(id, op->getOperands());
  }
  if (op->getNumRegions() && !isa<RegionBranchOpInterface, CallableOpInterface>(op) &&
      llvm::any_of(op->getRegions(), [](Region &region) {
        return !region.empty() && region.front().getNumArguments();
      }))
    addItem({Item::Kind::EntryArgs, op, block, fn, nullptr, 0});
}

// One item per successor of `branch` (its results first, then each
// region's arguments), and where each successor's inputs come from:
// every point control may leave from is read once, for the successors it
// goes to, however many regions the branch has.
void Graph::scanBranch(RegionBranchOpInterface branch, Block *block, FuncOp fn) {
  Operation *op = branch.getOperation();
  struct Succ {
    Region *region;
    unsigned item;
    unsigned source;
  };
  SmallVector<Succ> succs;
  DenseMap<Region *, unsigned> byRegion;
  auto addSucc = [&](Region *region) {
    unsigned source = static_cast<unsigned>(successorSources.size());
    successorSources.emplace_back();
    unsigned item = addItem({Item::Kind::Successor, op, block, fn, region, source});
    if (region)
      byRegion[region] = static_cast<unsigned>(succs.size());
    succs.push_back({region, item, source});
  };
  addSucc(nullptr);
  for (Region &region : op->getRegions())
    if (!region.empty())
      addSucc(&region);
  auto addFrom = [&](RegionBranchPoint point, Block *pointBlock) {
    SmallVector<RegionSuccessor> targets;
    branch.getSuccessorRegions(point, targets);
    for (RegionSuccessor target : targets) {
      unsigned at = 0;
      if (!target.isOperation()) {
        auto it = byRegion.find(target.getSuccessor());
        if (it == byRegion.end())
          continue;
        at = it->second;
      }
      OperandRange operands = branch.getSuccessorOperands(point, target);
      successorSources[succs[at].source].from.push_back({pointBlock, operands});
      readsAll(succs[at].item, operands);
    }
  };
  addFrom(RegionBranchPoint::parent(), block);
  SmallVector<Block *> unknownFrom;
  for (Region &inner : op->getRegions())
    for (Block &innerBlock : inner) {
      Operation *terminator = innerBlock.getTerminator();
      if (auto end = dyn_cast<RegionBranchTerminatorOpInterface>(terminator))
        addFrom(RegionBranchPoint(end), &innerBlock);
      else if (terminator)
        unknownFrom.push_back(&innerBlock);
    }
  for (Succ succ : succs) {
    SuccessorSources &sources = successorSources[succ.source];
    RegionSuccessor successor = succ.region ? RegionSuccessor(succ.region) : RegionSuccessor(op);
    sources.inputs = branch.getSuccessorInputs(successor);
    sources.unforwarded = branch.getNonSuccessorInputs(successor);
    llvm::append_range(sources.unknownFrom, unknownFrom);
  }
}

} // namespace idr::detail::exclusivity
