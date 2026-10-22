// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-place rule's terms read off one body (Rule.h): where a
// requirement on one of its values ends, by the rule of each value's
// definition. Every walk is iterative, over an explicit stack, so a long
// chain of definitions costs no native stack.
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/IR/Flow.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::inplace {

namespace {

void sortUnique(SmallVectorImpl<Target> &targets) {
  llvm::sort(targets);
  targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
}

// The operand of `op` that holds `value`.
OpOperand *operandOf(Operation *op, Value value) {
  for (OpOperand &operand : op->getOpOperands())
    if (operand.get() == value)
      return &operand;
  return nullptr;
}

} // namespace

Chains::Chains(FuncOp fn, const solver::ProgramGraph &graph, const Summaries &summaries,
               const Keeps &keeps)
    : fn(fn), graph(graph), summaries(summaries), keeps(keeps), values(fn),
      callAt(values.size()), known(values.size()), open(values.size()), seen(values.size()) {
  footprint::Vector<std::pair<std::uint32_t, OpOperand *>> pending;
  fn.walk([&](Operation *op) {
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      pending.emplace_back(values.at(input).index(), &operand);
    });
  });
  std::stable_sort(pending.begin(), pending.end(),
                   [](const auto &a, const auto &b) { return a.first < b.first; });
  std::uint32_t count = values.size().value();
  forwardStart.assign(count + 1, 0);
  for (const auto &[at, operand] : pending)
    ++forwardStart[at + 1];
  for (std::uint32_t at = 1; at <= count; ++at)
    forwardStart[at] += forwardStart[at - 1];
  for (const auto &[at, operand] : pending)
    forwards.push_back(operand);
  std::uint32_t place = 0;
  ownership::forEachCall(fn, [&](CallOp call) {
    if (call->getNumResults() != 0)
      callAt[values.at(call->getResult(0))] = place;
    ++place;
  });
}

Target Chains::cause(Operation *at, Why why) {
  causeList.push_back({at, why});
  return {Target::Kind::Cause, static_cast<std::uint32_t>(causeList.size() - 1), Asks::Self};
}

bool Chains::borrowedBefore(OpOperand &use, Operation *requirer) const {
  SmallVector<OpOperand *> work{&use};
  while (!work.empty()) {
    OpOperand *at = work.pop_back_val();
    Operation *owner = at->getOwner();
    if (owner->hasTrait<SameValue>()) {
      for (Value result : owner->getResults())
        for (OpOperand &next : result.getUses())
          work.push_back(&next);
      continue;
    }
    auto call = dyn_cast<CallOp>(owner);
    if (!call || keeps.test(graph.id(call.getCalleeAttr()), at->getOperandNumber()) ||
        ownership::runsAfter(owner, requirer))
      return false;
  }
  return true;
}

std::optional<Target> Chains::usedOnce(Value value, OpOperand *use) {
  // Idris proved a value of quantity 1 used once, and the verifier holds
  // every pass to it.
  if (usesOf(value.getType()) == Uses::Once)
    return std::nullopt;
  for (OpOperand &other : value.getUses()) {
    if (&other == use || ownership::readsPart(other))
      continue;
    Operation *owner = other.getOwner();
    if (use) {
      Operation *requirer = use->getOwner();
      if (insideMutuallyExclusiveRegions(owner, requirer))
        continue;
      // A read by a callee that keeps nothing of it, made before the use
      // that requires it, seen through the positions that hand it on as
      // itself: its lifetime has ended there.
      if (borrowedBefore(other, requirer))
        continue;
    }
    return cause(owner, Why::UsedAgain);
  }
  return std::nullopt;
}

void Chains::define(Value value, Asks asks, SmallVectorImpl<Target> &ends,
                    SmallVectorImpl<Step> &next, SmallVectorImpl<Demand> &demands) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    if (arg.getOwner() == &fn.getBody().front()) {
      if (fn.isRoot())
        ends.push_back(cause(fn, Why::FromOutside));
      else
        ends.push_back({Target::Kind::Parameter, arg.getArgNumber(), asks});
      return;
    }
  // A region's argument or a branch's result: what every predecessor
  // forwards. A branch whose every case ends where control never comes
  // back forwards nothing, and asks nothing.
  std::uint32_t row = values.at(value).index();
  if (forwardStart[row] != forwardStart[row + 1]) {
    for (std::uint32_t at = forwardStart[row]; at != forwardStart[row + 1]; ++at)
      next.push_back({forwards[at]->get(), asks, forwards[at]});
    return;
  }
  if (auto arg = dyn_cast<BlockArgument>(value)) {
    ends.push_back(cause(arg.getOwner()->getParentOp(), Why::Unexplained));
    return;
  }
  Operation *op = value.getDefiningOp();
  // An element an op of upstream's reads out of an array keeps its type's
  // grade, which no pass of ours rewrites: the rule neither raises it nor
  // follows it into the array, which keeps its own reference beside it.
  if (ownership::carriersOnly(op) && ownership::readOutOfElements(value)) {
    if (!claims(value.getType(), ownership::claimFor(asks)))
      ends.push_back(cause(op, Why::Shared));
    return;
  }
  if (std::optional<Value> same = ownership::sameValueSource(value)) {
    next.push_back({*same, asks, &op->getOpOperand(0)});
    return;
  }
  if (auto call = dyn_cast<CallOp>(op)) {
    unsigned result = cast<OpResult>(value).getResultNumber();
    demands.push_back({call, *callAt[values.at(call->getResult(0))], result, asks});
    const Need &need = summaries.of(graph.id(call.getCalleeAttr()), result, asks);
    if (!need) {
      ends.push_back(cause(call, Why::ReturnShared));
      return;
    }
    for (auto [param, strength] : *need)
      next.push_back({call.getArgOperands()[param], strength, &call->getOpOperand(param)});
    return;
  }
  if (isa<RegionBranchOpInterface>(op))
    return;
  auto declared = dyn_cast<FlowOpInterface>(op);
  if (!declared) {
    ends.push_back(cause(op, Why::Unexplained));
    return;
  }
  FlowEdges edges;
  declared.getFlowEdges(edges);
  bool explained = false;
  for (const FlowEdges::Edge &edge : edges.edges()) {
    if (!edge.carries(Carrier::Reference))
      continue;
    match(
        edge.move,
        [&](const FlowEdges::Fresh &fresh) { explained |= fresh.to == value; },
        [&](const FlowEdges::Constant &constant) {
          if (constant.to != value)
            return;
          explained = true;
          ends.push_back(cause(op, Why::Shared));
        },
        [&](const FlowEdges::Flow &flow) {
          if (flow.to.value() != value)
            return;
          match(
              flow.to.at,
              // A field moved into the value: the requirement reaches it
              // where it reaches the field.
              [&](const FlowPlace::Part &into) {
                std::optional<FlowAnchor::Field> field = ownership::fieldOf(into.anchor);
                Value moved = *flow.from.value();
                if (!field || !reachesField(asks, into.anchor, moved.getType()))
                  return;
                match(
                    flow.from.at,
                    [&](const FlowSource::Taken &taken) {
                      next.push_back({moved, asks, taken.use});
                    },
                    // Read and left its reference, or a part: the value
                    // holds a reference another keeps.
                    [&](const ownership::NotTaken auto &) {
                      ends.push_back(cause(op, Why::Shared));
                    });
              },
              // The value whole: moved, moved out of a part, or copied.
              [&](const FlowSource::Whole &) {
                explained = true;
                match(
                    flow.from.at,
                    [&](const FlowSource::Taken &taken) {
                      next.push_back({taken.use->get(), asks, taken.use});
                    },
                    // Out of a part: what the holder must claim for its
                    // read of the part to meet the requirement.
                    [&](const FlowSource::Part &part) {
                      Value whole = *flow.from.value();
                      Asks of = ownership::holderAsks(asks, ownership::reachAt(part.anchor));
                      OpOperand *use = ownership::reachOf(part) == ownership::Reach::Taken
                                           ? *flow.from.taken()
                                           : operandOf(op, whole);
                      next.push_back({whole, of, use});
                    },
                    [&](const OneOf<FlowSource::Whole, FlowSource::Parameter,
                                    FlowSource::Result> auto &) {
                      ends.push_back(cause(op, Why::Shared));
                    });
              },
              [](const OneOf<FlowSource::Parameter, FlowSource::Result> auto &) {});
        },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Release,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Dispatch> auto &) {});
  }
  if (!explained)
    ends.push_back(cause(op, Why::Unexplained));
}

SmallVector<Target> Chains::targets(Value value, Asks asks, OpOperand *use) {
  SmallVector<Target> out;
  if (std::optional<Target> again = usedOnce(value, use))
    out.push_back(*again);
  auto knownEndsOf = [&](BodyValue at, Asks strength) -> std::optional<llvm::ArrayRef<Target>> {
    std::optional<Run> run = known[at][slot(strength)];
    if (!run)
      return std::nullopt;
    return llvm::ArrayRef<Target>(knownEnds).slice(run->first, run->count);
  };
  if (std::optional<llvm::ArrayRef<Target>> hit = knownEndsOf(values.at(value), asks)) {
    out.append(hit->begin(), hit->end());
    sortUnique(out);
    return out;
  }
  // Each frame a (value, strength) being read: its ends so far, the steps
  // still to take, and whether a cycle was cut short below it, which keeps
  // its ends out of `known`.
  struct Frame {
    BodyValue at;
    Asks asks;
    SmallVector<Step, 4> next;
    std::size_t nextAt = 0;
    SmallVector<Target> ends;
    bool cut = false;
  };
  SmallVector<Frame> stack;
  auto push = [&](Value at, Asks strength) {
    Frame frame{values.at(at), strength, {}, 0, {}, false};
    SmallVector<Demand> reached;
    define(at, strength, frame.ends, frame.next, reached);
    open[frame.at][slot(strength)] = Mark::Yes;
    stack.push_back(std::move(frame));
  };
  push(value, asks);
  while (true) {
    if (stack.back().nextAt < stack.back().next.size()) {
      Step step = stack.back().next[stack.back().nextAt++];
      if (std::optional<Target> again = usedOnce(step.value, step.use))
        stack.back().ends.push_back(*again);
      BodyValue at = values.at(step.value);
      if (std::optional<llvm::ArrayRef<Target>> hit = knownEndsOf(at, step.asks))
        stack.back().ends.append(hit->begin(), hit->end());
      else if (open[at][slot(step.asks)] == Mark::Yes)
        stack.back().cut = true;
      else
        push(step.value, step.asks);
      continue;
    }
    Frame done = std::move(stack.back());
    stack.pop_back();
    open[done.at][slot(done.asks)] = Mark::No;
    sortUnique(done.ends);
    if (!done.cut) {
      known[done.at][slot(done.asks)] = Run{static_cast<std::uint32_t>(knownEnds.size()),
                                            static_cast<std::uint32_t>(done.ends.size())};
      knownEnds.insert(knownEnds.end(), done.ends.begin(), done.ends.end());
    }
    if (stack.empty()) {
      out.append(done.ends);
      break;
    }
    stack.back().ends.append(done.ends);
    stack.back().cut |= done.cut;
  }
  sortUnique(out);
  return out;
}

void Chains::trace(Value value, Asks asks, Reached &reached) {
  SmallVector<std::pair<Value, Asks>> work{{value, asks}};
  SmallVector<std::pair<BodyValue, Asks>> marked;
  while (!work.empty()) {
    auto [at, strength] = work.pop_back_val();
    BodyValue node = values.at(at);
    if (seen[node][slot(strength)] == Mark::Yes)
      continue;
    seen[node][slot(strength)] = Mark::Yes;
    marked.emplace_back(node, strength);
    reached.values.push_back({node.index(), strength});
    SmallVector<Target> ends;
    SmallVector<Step> next;
    SmallVector<Demand> demands;
    define(at, strength, ends, next, demands);
    llvm::append_range(reached.demands, demands);
    for (const Step &step : next)
      work.push_back({step.value, step.asks});
  }
  for (auto [node, strength] : marked)
    seen[node][slot(strength)] = Mark::No;
}

} // namespace idr::inplace
