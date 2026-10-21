// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The marking of exclusivity's solve over its graph (ExclusivityGraph.cpp
// builds it; Exclusivity.cpp says what the solve proves): which functions
// run, and what each value holds. A value's answer only ever rises
// (unknown, exclusive, shared), a function only ever starts to run, and
// a call of a specialization key goes from the copy to the original at
// most once, as an argument of it is found shared, so the marking ends.
// The functions that run are those some call that runs goes to, from the
// roots, whose callers the program does not show; a value in a function
// that runs nowhere is never reached. Optimistic as SCCP is: a value is
// exclusive until a path shares it.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ownership.h"

#include "llvm/ADT/STLExtras.h"

#include <deque>
#include <variant>
#include <vector>

using namespace mlir;

namespace idr::detail::exclusivity {
namespace {

class Solve {
public:
  Solve(ProgramOp program, const Calls &calls, const Captures &captures)
      : graph(program, calls), calls(calls), captures(captures),
        queued(graph.items.size(), false) {
    for (FuncOp fn : program.getOps<FuncOp>())
      if (!Calls::showsEveryCall(fn))
        startRun(fn);
  }

  DenseMap<Value, Sharing> run() {
    while (!work.empty()) {
      unsigned id = work.front();
      work.pop_front();
      queued[id] = false;
      execute(graph.items[id]);
    }
    return std::move(sharing);
  }

private:
  Sharing get(Value value) const {
    auto it = sharing.find(value);
    return it == sharing.end() ? Sharing::Unknown : it->second;
  }

  // What a value holds, optimistically: unknown counts as exclusive until
  // a path shares it.
  bool exclusive(Value value) const { return get(value) != Sharing::Shared; }
  Sharing held(Value value) const {
    return exclusive(value) ? Sharing::Exclusive : Sharing::Shared;
  }

  void joinValue(Value value, Sharing more) {
    if (more == Sharing::Unknown)
      return;
    auto [it, fresh] = sharing.try_emplace(value, more);
    if (!fresh) {
      if (more <= it->second)
        return;
      it->second = more;
    }
    auto found = graph.dependents.find(value);
    if (found != graph.dependents.end())
      for (unsigned id : found->second)
        enqueue(id);
  }

  void enqueue(unsigned id) {
    if (!queued[id]) {
      queued[id] = true;
      work.push_back(id);
    }
  }

  bool live(const Item &item) const {
    auto it = liveOf.find(item.fn);
    return it != liveOf.end() && it->second.contains(item.block);
  }

  void startRun(FuncOp fn) {
    auto [it, fresh] = liveOf.try_emplace(fn);
    if (!fresh)
      return;
    liveBlocksOf(fn, it->second);
    // A value the program does not show every source of is shared.
    if (llvm::any_of(calls.namesOf(fn),
                     [](FuncOp named) { return !Calls::showsEveryCall(named); }))
      for (BlockArgument param : fn.getArguments())
        joinValue(param, Sharing::Shared);
    for (unsigned id : graph.itemsOf[fn])
      enqueue(id);
  }

  void execute(const Item &item) {
    switch (item.kind) {
    case Item::Kind::Op:
      return execOp(item);
    case Item::Kind::Call:
      return execCall(item);
    case Item::Kind::Successor:
      return execSuccessor(item);
    case Item::Kind::BlockArgs:
      return execBlockArgs(item);
    case Item::Kind::EntryArgs:
      return execEntryArgs(item);
    }
  }

  // What a flow from `from` brings a result it reaches whole: a use moved
  // into it, whole or out of a part, what that value holds; a copy of a
  // value read shares its cells, unless it is static data that reaches no
  // cell but atoms, which no take hands out; a part read, a parameter and a
  // result are shared.
  Sharing wholeFrom(const FlowPoint &from) const {
    if (std::optional<OpOperand *> use = from.taken())
      return held((*use)->get());
    const auto *read = std::get_if<FlowPoint::Whole>(&from.at);
    return read && ownership::reachesOnlyAtoms(read->value) ? Sharing::Exclusive
                                                             : Sharing::Shared;
  }

  // What a cell moved into a part of a result brings: a followed use what
  // it holds; anything else no cell a take could hand out.
  Sharing intoPart(const FlowPoint &from) const {
    std::optional<OpOperand *> use = from.taken();
    if (!use)
      return Sharing::Shared;
    if (!ownership::followed((*use)->get()))
      return Sharing::Unknown;
    return held((*use)->get());
  }

  // Each followed result is what reaches it whole (new, a use of a value
  // moved into it or out of a part of one, a copy, a constant), joined with
  // the cells moved into its parts; a result nothing reaches whole is not
  // new to anyone, and shared.
  void execOp(const Item &item) {
    if (!live(item))
      return;
    Operation *op = item.op;
    FlowEdges edges;
    if (declaresFlow(op))
      flowEdgesOf(op, edges);
    for (Value result : op->getResults()) {
      if (!ownership::followed(result))
        continue;
      Sharing whole = Sharing::Unknown, parts = Sharing::Unknown;
      // A flow into the result whole or into a part of it; a fresh result
      // is exclusive, a constant shared. A unification and a source are of
      // labels, and a use given up or a dispatch gives the result nothing.
      auto into = [&](const FlowEdges::Flow &move) {
        if (move.to.value() != result)
          return;
        if (std::holds_alternative<FlowPoint::Part>(move.to.at))
          parts = std::max(parts, intoPart(move.from));
        else
          whole = std::max(whole, wholeFrom(move.from));
      };
      for (const FlowEdges::Edge &edge : edges.edges())
        if (edge.carries(Carrier::Reference))
          std::visit(llvm::makeVisitor(into, [](const FlowEdges::Unify &) {},
                                       [](const FlowEdges::Source &) {},
                                       [&](const FlowEdges::Fresh &move) {
                                         if (move.to == result)
                                           whole = std::max(whole, Sharing::Exclusive);
                                       },
                                       [](const FlowEdges::Release &) {},
                                       [](const FlowEdges::Overwrite &) {},
                                       [&](const FlowEdges::Constant &move) {
                                         if (move.to == result)
                                           whole = std::max(whole, Sharing::Shared);
                                       },
                                       [](const FlowEdges::Dispatch &) {}),
                     edge.move);
      joinValue(result, whole == Sharing::Unknown ? Sharing::Shared : std::max(whole, parts));
    }
    if (auto init = dyn_cast<CellInitOp>(op))
      fillCaptures(init);
  }

  // An init of a cell of a memoizing label moves each field into the
  // memory every force of that label moves it out of: each capture of
  // those forces holds what each init moves in.
  void fillCaptures(CellInitOp init) {
    DataType data = init.getDataType();
    if (!data.isMemo())
      return;
    for (MemoRunOp force : captures.forcesOf(data, init.getTag()))
      for (BlockArgument capture : force.getCaptures()) {
        if (!ownership::followed(capture))
          continue;
        Value field = init.getField(capture.getArgNumber());
        auto given = llvm::find_if(init->getOpOperands(),
                                   [&](OpOperand &operand) { return operand.get() == field; });
        if (!field || given == init->getOpOperands().end())
          continue;
        joinValue(capture, held(given->get()));
      }
  }

  // A call runs the function its arguments now send it to, gives that
  // function's parameters what it passes, and its results what the
  // function's returns give.
  void execCall(const Item &item) {
    if (!live(item))
      return;
    auto call = cast<CallOp>(item.op);
    FuncOp target = calls.target(call, [&](Value arg) { return exclusive(arg); });
    startRun(target);
    for (auto [arg, param] : llvm::zip_equal(call.getArgOperands(), target.getArguments()))
      joinValue(param, get(arg));
    for (ReturnOp ret : calls.returns(target))
      for (auto [value, result] : llvm::zip_equal(ret.getOperands(), call->getResults()))
        joinValue(result, get(value));
  }

  void execSuccessor(const Item &item) {
    auto found = liveOf.find(item.fn);
    if (found == liveOf.end())
      return;
    const DenseSet<Block *> &liveBlocks = found->second;
    const SuccessorSources &sources = graph.successorSources[item.source];
    // A way out of a region whose operands no interface says: nothing is
    // proved of what it gives.
    for (Block *block : sources.unknownFrom)
      if (liveBlocks.contains(block)) {
        ValueRange values =
            item.region ? ValueRange(item.region->getArguments()) : item.op->getResults();
        for (Value value : values)
          joinValue(value, Sharing::Shared);
        return;
      }
    bool reached = false;
    for (auto [block, operands] : sources.from) {
      if (!liveBlocks.contains(block))
        continue;
      reached = true;
      for (auto [input, operand] : llvm::zip_equal(sources.inputs, operands))
        joinValue(input, get(operand));
    }
    if (!reached)
      return;
    // What no predecessor forwards a value to is the op's own to make,
    // and no flow proves it: shared, but a memo cell's captures, which
    // its inits fill (fillCaptures), and which are shared where Captures
    // says no init decides one, or where no cell of the label is ever
    // made, so the force never runs and nothing is proved of it.
    auto force = dyn_cast<MemoRunOp>(item.op);
    for (Value value : sources.unforwarded) {
      if (force && item.region) {
        auto capture = cast<BlockArgument>(value);
        if (!ownership::followed(capture) ||
            captures.shared(force.getDataType(), force.getTag(), capture.getArgNumber()) ||
            !captures.made(force.getDataType(), force.getTag()))
          joinValue(value, Sharing::Shared);
        continue;
      }
      joinValue(value, Sharing::Shared);
    }
  }

  void execBlockArgs(const Item &item) {
    if (!live(item))
      return;
    Block *block = item.block;
    const DenseSet<Block *> &liveBlocks = liveOf[item.fn];
    for (Block *pred : block->getPredecessors()) {
      if (!liveBlocks.contains(pred))
        continue;
      auto branch = dyn_cast<BranchOpInterface>(pred->getTerminator());
      if (!branch) {
        for (BlockArgument arg : block->getArguments())
          joinValue(arg, Sharing::Shared);
        continue;
      }
      for (unsigned i = 0, e = pred->getNumSuccessors(); i != e; ++i) {
        if (pred->getSuccessor(i) != block)
          continue;
        SuccessorOperands operands = branch.getSuccessorOperands(i);
        for (auto [index, arg] : llvm::enumerate(block->getArguments())) {
          if (Value operand = operands[static_cast<unsigned>(index)])
            joinValue(arg, get(operand));
          else
            joinValue(arg, Sharing::Shared);
        }
      }
    }
  }

  void execEntryArgs(const Item &item) {
    if (!live(item))
      return;
    for (Region &region : item.op->getRegions())
      if (!region.empty())
        for (BlockArgument arg : region.front().getArguments())
          joinValue(arg, Sharing::Shared);
  }

  Graph graph;
  const Calls &calls;
  const Captures &captures;
  std::vector<char> queued;
  std::deque<unsigned> work;
  DenseMap<FuncOp, DenseSet<Block *>> liveOf;
  DenseMap<Value, Sharing> sharing;
};

} // namespace

DenseMap<Value, Sharing> solveOnce(ProgramOp program, const Calls &calls,
                                   const Captures &captures) {
  return Solve(program, calls, captures).run();
}

} // namespace idr::detail::exclusivity
