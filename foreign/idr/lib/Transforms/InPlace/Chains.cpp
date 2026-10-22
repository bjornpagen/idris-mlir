// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-place rule's terms read off one body (Rule.h): its rebuild sites
// and the rewrite of each, and where a requirement on one of its values
// ends, by the rule of each value's definition. Every walk is iterative,
// over an explicit stack, so a long chain of definitions costs no native
// stack.
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/IR/Flow.h"
#include "idr/Support/Match.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

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

llvm::SmallVector<RebuildSite> rebuildSites(FuncOp fn) {
  SmallVector<RebuildSite> sites;
  // The constructions already paired, outer cells first: this body's own,
  // gone with the walk.
  llvm::DenseSet<Operation *> paired;
  fn->walk<WalkOrder::PreOrder>([&](DataMatchOp match) {
    // The argument each case binds the scrutinee refined to.
    SmallVector<BlockArgument> bound(match->getNumRegions(), BlockArgument());
    forwardedValues(match, [&](OpOperand &operand, Value input) {
      auto arg = dyn_cast<BlockArgument>(input);
      if (arg && operand.get() == match.getScrutinee() && arg.getOwner()->getParentOp() == match)
        bound[arg.getOwner()->getParent()->getRegionNumber()] = arg;
    });
    for (auto [index, region] : llvm::enumerate(match->getRegions())) {
      BlockArgument taken = bound[index];
      if (!taken)
        continue;
      Type type = taken.getType();
      DataType family = ownership::familyOf(type);
      std::optional<Tag> tag = ownership::refinedTag(type);
      std::optional<Asks> promised = ownership::promisedAsks(family);
      // A cell of an in-place family, bound at quantity 1: a parameter's,
      // or a field's a linear match binds.
      if (!tag || !ownership::isCell(type) || !promised || usesOf(type) != Uses::Once)
        continue;
      DataConOp found;
      region.walk<WalkOrder::PreOrder>([&](Operation *op) {
        // A region that may run again would rebuild the one cell twice.
        if (ownership::repeats(op))
          return WalkResult::skip();
        auto con = dyn_cast<DataConOp>(op);
        if (!con || paired.contains(con))
          return WalkResult::advance();
        Type built = con.getResult().getType();
        if (ownership::sameFamily(ownership::familyOf(built), family) &&
            ownership::refinedTag(built) == tag && ownership::isCell(built)) {
          found = con;
          return WalkResult::interrupt();
        }
        return WalkResult::advance();
      });
      if (!found)
        continue;
      paired.insert(found);
      sites.push_back({match, static_cast<unsigned>(index), found, taken, *promised});
    }
  });
  return sites;
}

void rebuild(DataMatchOp match, unsigned caseIndex, unsigned taken, DataConOp construction) {
  Block &entry = match->getRegion(caseIndex).front();
  BlockArgument cell = entry.getArgument(taken);
  OpBuilder builder = OpBuilder::atBlockBegin(&entry);
  auto take = CountTakeOp::create(builder, match.getLoc(), cell);
  for (OpOperand &use : llvm::make_early_inc_range(cell.getUses()))
    if (auto field = dyn_cast<DataFieldOp>(use.getOwner())) {
      field.getResult().replaceAllUsesWith(
          take.getFields()[static_cast<unsigned>(field.getIndex())]);
      field.erase();
    }
  builder.setInsertionPoint(construction);
  auto rebuilt = TokenRebuildOp::create(builder, construction.getLoc(),
                                        construction.getResult().getType(), take.getToken(),
                                        construction.getFields());
  construction.getResult().replaceAllUsesWith(rebuilt.getResult());
  construction.erase();
}

Chains::Chains(FuncOp fn, const solver::ProgramGraph &graph, const Summaries &summaries,
               const Keeps &keeps)
    : fn(fn), graph(graph), summaries(summaries), keeps(keeps) {
  fn.walk([&](Operation *op) {
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      forwardedInto[input].push_back(&operand);
    });
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
  if (auto sources = forwardedInto.find(value); sources != forwardedInto.end()) {
    for (OpOperand *source : sources->second)
      next.push_back({source->get(), asks, source});
    return;
  }
  if (auto arg = dyn_cast<BlockArgument>(value)) {
    ends.push_back(cause(arg.getOwner()->getParentOp(), Why::Unexplained));
    return;
  }
  Operation *op = value.getDefiningOp();
  if (std::optional<Value> same = ownership::sameValueSource(value)) {
    next.push_back({*same, asks, &op->getOpOperand(0)});
    return;
  }
  if (auto call = dyn_cast<CallOp>(op)) {
    unsigned result = cast<OpResult>(value).getResultNumber();
    demands.push_back({call, result, asks});
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
              [&](const FlowPoint::Part &into) {
                std::optional<FlowAnchor::Field> field = ownership::fieldOf(into.anchor);
                Value moved = *flow.from.value();
                if (!field || !reachesField(asks, into.anchor, moved.getType()))
                  return;
                match(
                    flow.from.at,
                    [&](const FlowPoint::Taken &taken) {
                      next.push_back({moved, asks, taken.use});
                    },
                    // Read and left its reference, or a part: the value
                    // holds a reference another keeps.
                    [&](const auto &) { ends.push_back(cause(op, Why::Shared)); });
              },
              // The value whole: moved, moved out of a part, or copied.
              [&](const FlowPoint::Whole &) {
                explained = true;
                match(
                    flow.from.at,
                    [&](const FlowPoint::Taken &taken) {
                      next.push_back({taken.use->get(), asks, taken.use});
                    },
                    // Out of a part: what the holder must claim for its
                    // read of the part to meet the requirement.
                    [&](const FlowPoint::Part &part) {
                      Value whole = *flow.from.value();
                      Asks of = ownership::holderAsks(asks, ownership::reachAt(part.anchor));
                      OpOperand *use = ownership::reachOf(part) == ownership::Reach::Taken
                                           ? *flow.from.taken()
                                           : operandOf(op, whole);
                      next.push_back({whole, of, use});
                    },
                    [&](const auto &) { ends.push_back(cause(op, Why::Shared)); });
              },
              [](const auto &) {});
        },
        [](const auto &) {});
  }
  if (!explained)
    ends.push_back(cause(op, Why::Unexplained));
}

SmallVector<Target> Chains::targets(Value value, Asks asks, OpOperand *use) {
  SmallVector<Target> out;
  if (std::optional<Target> again = usedOnce(value, use))
    out.push_back(*again);
  using Key = std::pair<Value, unsigned>;
  auto keyOf = [](Value at, Asks strength) { return Key(at, static_cast<unsigned>(strength)); };
  if (auto hit = known.find(keyOf(value, asks)); hit != known.end()) {
    out.append(hit->second);
    sortUnique(out);
    return out;
  }
  // Each frame a (value, strength) being read: its ends so far, the steps
  // still to take, and whether a cycle was cut short below it, which keeps
  // its ends out of `known`.
  struct Frame {
    Key key;
    SmallVector<Step, 4> next;
    std::size_t at = 0;
    SmallVector<Target> ends;
    bool cut = false;
  };
  SmallVector<Frame> stack;
  llvm::DenseSet<Key> open;
  auto push = [&](Value at, Asks strength) {
    Frame frame{keyOf(at, strength), {}, 0, {}, false};
    SmallVector<Demand> reached;
    define(at, strength, frame.ends, frame.next, reached);
    open.insert(frame.key);
    stack.push_back(std::move(frame));
  };
  push(value, asks);
  while (true) {
    if (stack.back().at < stack.back().next.size()) {
      Step step = stack.back().next[stack.back().at++];
      if (std::optional<Target> again = usedOnce(step.value, step.use))
        stack.back().ends.push_back(*again);
      Key key = keyOf(step.value, step.asks);
      if (auto hit = known.find(key); hit != known.end())
        stack.back().ends.append(hit->second);
      else if (open.contains(key))
        stack.back().cut = true;
      else
        push(step.value, step.asks);
      continue;
    }
    Frame done = std::move(stack.back());
    stack.pop_back();
    open.erase(done.key);
    sortUnique(done.ends);
    if (!done.cut)
      known.try_emplace(done.key, done.ends);
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
  llvm::DenseSet<std::pair<Value, unsigned>> seen;
  while (!work.empty()) {
    auto [at, strength] = work.pop_back_val();
    if (!seen.insert({at, static_cast<unsigned>(strength)}).second)
      continue;
    reached.values.push_back({at, strength});
    SmallVector<Target> ends;
    SmallVector<Step> next;
    SmallVector<Demand> demands;
    define(at, strength, ends, next, demands);
    llvm::append_range(reached.demands, demands);
    for (const Step &step : next)
      work.push_back({step.value, step.asks});
  }
}

} // namespace idr::inplace
