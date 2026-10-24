// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the skeleton says of the values it gives, which the e-graph does not
// see through: the region graph of a function's region-branch ops, read
// once after the walk, and, at the start of each round, the facts it gives
// the leaves.
//
// A region-branch op enters its regions and leaves them through their
// terminators, as MLIR's RegionBranchOpInterface and
// RegionBranchTerminatorOpInterface say, a terminator that leaves several
// regions at once among them (a jump to a join point the match it ends is
// nested in). Each branch point, the op entering or a terminator leaving,
// has an edge to each successor it may take, passing one value per input of
// the successor: a region's argument, or a result of the op. Which edges may
// run is read each round, from the body down: an edge runs where its
// point's region does and its point may take it, as the point's own choice
// says over the constants the classes of its operands hold; a region runs
// where an edge that runs enters it. The choice is asked of attributes,
// and a constant the graph computed holds none, so where no operand's class
// holds one, every successor the point may take is taken.
//
// Each input of a target is one of the values the edges that run pass it,
// so what holds of each of them holds of it: their join is met into its
// class. A value of the input's own class (a loop's parameter passed on
// unchanged) adds nothing, since on every path the input is what another
// edge passed it first. Where every edge passes it one class that holds a
// constant, the input is that class. So a region-branch op's result that
// every running region yields one constant to is that constant, and so is a
// loop's parameter every jump passes it, or passes on.
//
// Each skeleton op's results take the intervals its own transfer function
// gives over its operands'. A guard whose condition holds of what the graph
// knows gives its checked operand, as its fold says, so its result takes
// that operand's facts, where the two are of one type and so of one
// representation.
#include "idr/Transforms/EGraph/Engine.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::egraph::detail {

//===----------------------------------------------------------------------===//
// The region graph
//===----------------------------------------------------------------------===//

// The op's regions are numbered one after another, so its first is the one
// its k-th region's number less k.
std::optional<RegionId> Function::firstRegionOf(RegionId from, Operation *owner) const {
  for (std::optional<RegionId> place = from; place; place = at(*place).parent) {
    const Region &region = at(*place);
    if (region.ir->getParentOp() == owner)
      return RegionId(place->index() - region.ir->getRegionNumber());
  }
  return std::nullopt;
}

// Each region's points are laid out together, in the order of its skeleton:
// every region-branch op of it entering its regions, and its terminator
// leaving it. A point's edges are the successors it may take where nothing
// is known of its operands, the most it ever takes. A target is made where
// an edge first enters it, a region's by the region and an op's results by
// the op's first region, and holds the classes of the successor's inputs.
// A region of an op that is no region-branch op (a structured op's body) is
// entered by no edge, so it never runs here, and nothing is joined in it:
// its values keep what their own ops say.
void Function::connectRegions() {
  footprint::Vector<std::optional<TargetId>> regionTarget(regions.size());
  footprint::Vector<std::optional<TargetId>> resultsTarget(regions.size());
  // The edges entering each target, gathered as they are made.
  footprint::Vector<footprint::Vector<EdgeId>> into;

  auto targetFor = [&](RegionBranchOpInterface owner, RegionId first,
                       const RegionSuccessor &successor) {
    std::optional<RegionId> region;
    if (successor.isRegion())
      region = RegionId(first.index() + successor.getSuccessor()->getRegionNumber());
    std::optional<TargetId> &slot =
        region ? regionTarget[region->index()] : resultsTarget[first.index()];
    if (slot)
      return *slot;
    TargetId made(static_cast<std::uint32_t>(targets.size()));
    Run run{static_cast<std::uint32_t>(received.size()), 0};
    for (Value input : owner.getSuccessorInputs(successor)) {
      received.push_back(*classOf[numbering.at(input)]);
      ++run.count;
    }
    targets.push_back({region, run, {}});
    into.emplace_back();
    slot = made;
    return made;
  };
  auto connect = [&](Point &point, RegionBranchOpInterface owner, RegionId first,
                     const RegionSuccessor &successor, OperandRange values) {
    TargetId target = targetFor(owner, first, successor);
    assert(values.size() == targets[target.index()].inputs.count &&
           "the interface's verifier holds an edge's values to its successor's inputs");
    EdgeId made(static_cast<std::uint32_t>(edges.size()));
    Run run{static_cast<std::uint32_t>(passed.size()), static_cast<std::uint32_t>(values.size())};
    for (Value value : values)
      passed.push_back(*classOf[numbering.at(value)]);
    edges.push_back({successor, target, run});
    into[target.index()].push_back(made);
    ++point.edges.count;
  };

  SmallVector<Attribute, 4> unknown;
  SmallVector<RegionSuccessor, 4> successors;
  for (std::uint32_t r = 0; r < regions.size(); ++r) {
    Region &region = regions[r];
    region.points = {static_cast<std::uint32_t>(points.size()), 0};
    for (std::uint32_t place = region.skeleton.first;
         place < region.skeleton.first + region.skeleton.count; ++place) {
      const Skeletal &entry = skeleton[place];
      Operation *op = entry.op;
      unknown.assign(op->getNumOperands(), Attribute());
      if (auto branch = dyn_cast<RegionBranchOpInterface>(op); branch && entry.regions) {
        Point point{op, Branching::Enters, {static_cast<std::uint32_t>(edges.size()), 0}};
        successors.clear();
        branch.getEntrySuccessorRegions(unknown, successors);
        for (const RegionSuccessor &successor : successors)
          connect(point, branch, *entry.regions, successor,
                  branch.getEntrySuccessorOperands(successor));
        points.push_back(point);
        ++region.points.count;
      }
      // A terminator leaves its region through the region-branch op that
      // holds it; one that ends the body of anything else (the function's
      // return, a structured op's yield) leaves no region of the graph.
      if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op);
          terminator && isa<RegionBranchOpInterface>(op->getParentOp())) {
        Point point{op, Branching::Leaves, {static_cast<std::uint32_t>(edges.size()), 0}};
        successors.clear();
        terminator.getSuccessorRegions(unknown, successors);
        for (const RegionSuccessor &successor : successors) {
          RegionBranchOpInterface branch = getRegionBranchSuccessorOwner(successor);
          std::optional<RegionId> first = firstRegionOf(RegionId(r), branch.getOperation());
          assert(first && "a terminator leaves only regions of ops it is nested in");
          connect(point, branch, *first, successor, terminator.getSuccessorOperands(successor));
        }
        points.push_back(point);
        ++region.points.count;
      }
    }
  }

  for (auto [target, list] : llvm::enumerate(into)) {
    targets[target].entering = {static_cast<std::uint32_t>(entering.size()),
                                static_cast<std::uint32_t>(list.size())};
    llvm::append_range(entering, list);
  }
}

//===----------------------------------------------------------------------===//
// The rounds' reading of it
//===----------------------------------------------------------------------===//

Attribute Function::heldIn(ClassId c) const {
  const Class &cls = at(forest.rootOf(c));
  for (std::optional<NodeId> member = cls.first; member; member = nextMember[member->index()]) {
    Attribute held = match(
        at(*member).what, [](const node::Held &constant) { return constant.value; },
        [](const OneOf<node::Input, node::Built, node::Leaf, node::Integer, node::Known> auto &) {
          return Attribute();
        });
    if (held)
      return held;
  }
  return {};
}

bool Function::holdsConstant(ClassId c) const {
  const Class &cls = at(forest.rootOf(c));
  for (std::optional<NodeId> member = cls.first; member; member = nextMember[member->index()])
    if (match(
            at(*member).what,
            [](const OneOf<node::Held, node::Integer, node::Known> auto &) { return true; },
            [](const OneOf<node::Input, node::Built, node::Leaf> auto &) { return false; }))
      return true;
  return false;
}

// A constant is known already and nothing narrows it, as a rebuild's repair
// leaves it.
void Function::narrow(ClassId c, const Facts &said) {
  ClassId root = forest.find(c);
  if (at(root).facts.isConstant() || at(root).facts.meet(said) == Changed::No)
    return;
  joinConstant(root);
  carried.push_back(forest.find(root));
}

// Each region is read once, as it first runs; its points ask their own
// choice only where an operand's class holds an attribute.
BitSet<EdgeId> Function::runningEdges() const {
  BitSet<EdgeId> running(Count<EdgeId>(static_cast<std::uint32_t>(edges.size())));
  BitSet<RegionId> live(Count<RegionId>(static_cast<std::uint32_t>(regions.size())));
  RegionId body(0);
  footprint::Vector<RegionId> work{body};
  (void)live.raise(body);
  SmallVector<Attribute, 4> held;
  while (!work.empty()) {
    const Region &region = at(work.back());
    work.pop_back();
    for (std::uint32_t p = region.points.first; p < region.points.first + region.points.count;
         ++p) {
      const Point &point = points[p];
      held.clear();
      for (Value operand : point.op->getOperands())
        held.push_back(heldIn(*classOf[numbering.at(operand)]));
      // The successors the point's own choice takes, where it is asked;
      // none where no operand's class holds an attribute: every edge.
      std::optional<SmallVector<RegionSuccessor, 4>> chosen;
      if (llvm::any_of(held, [](Attribute value) { return static_cast<bool>(value); })) {
        chosen.emplace();
        switch (point.branching) {
        case Branching::Enters:
          cast<RegionBranchOpInterface>(point.op).getEntrySuccessorRegions(held, *chosen);
          break;
        case Branching::Leaves:
          cast<RegionBranchTerminatorOpInterface>(point.op).getSuccessorRegions(held, *chosen);
          break;
        }
      }
      for (std::uint32_t e = point.edges.first; e < point.edges.first + point.edges.count; ++e) {
        const Edge &edge = edges[e];
        if (chosen && !llvm::is_contained(*chosen, edge.successor))
          continue;
        (void)running.raise(EdgeId(e));
        const Target &target = targets[edge.target.index()];
        if (target.region && live.raise(*target.region) == Changed::Yes)
          work.push_back(*target.region);
      }
    }
  }
  return running;
}

void Function::skeletonSays() {
  BitSet<EdgeId> running = runningEdges();
  SmallVector<ClassId, 4> given;
  for (const Target &target : targets)
    for (std::uint32_t i = 0; i < target.inputs.count; ++i) {
      ClassId input = forest.find(received[target.inputs.first + i]);
      given.clear();
      for (std::uint32_t k = target.entering.first;
           k < target.entering.first + target.entering.count; ++k) {
        EdgeId e = entering[k];
        if (!running.test(e))
          continue;
        ClassId value = forest.find(passed[edges[e.index()].passed.first + i]);
        if (value != input && !llvm::is_contained(given, value))
          given.push_back(value);
      }
      if (given.empty())
        continue;
      if (given.size() == 1 && holdsConstant(given.front()) &&
          at(given.front()).type == at(input).type) {
        (void)unite(input, given.front());
        continue;
      }
      Facts joined = at(given.front()).facts;
      for (ClassId value : llvm::drop_begin(given)) {
        joined = joined.joined(at(value).facts);
        if (joined.empty())
          break;
      }
      // An edge may pass a value of another type than its input's, as the
      // interface's compatibility admits, whose interval is of its own width.
      unsigned width = ConstantIntRanges::getStorageBitwidth(at(input).type);
      if (joined.range && width != 0 && joined.range->umin().getBitWidth() != width)
        joined.range.reset();
      if (!joined.empty())
        narrow(input, joined);
    }

  SmallVector<ClassId, 4> operands;
  SmallVector<IntegerValueRange, 4> intervals;
  SmallVector<const Class *, 3> decided;
  for (const Skeletal &entry : skeleton) {
    Operation *op = entry.op;
    // A repeated read gives the earlier op's values, which that op's entry
    // reads.
    if (!std::holds_alternative<Kept>(entry.fate) || op->getNumResults() == 0)
      continue;
    operands.clear();
    for (Value operand : op->getOperands())
      operands.push_back(forest.find(*classOf[numbering.at(operand)]));
    if (auto ranges = dyn_cast<InferIntRangeInterface>(op)) {
      intervals.clear();
      for (auto [operand, value] : llvm::zip_equal(operands, op->getOperands())) {
        const Facts &known = at(operand).facts;
        intervals.push_back(known.range ? IntegerValueRange(*known.range)
                                        : IntegerValueRange::getMaxRange(value));
      }
      ranges.inferResultRangesFromOptional(intervals,
                                           [&](Value result, const IntegerValueRange &range) {
                                             if (!range.isUninitialized())
                                               narrow(*classOf[numbering.at(result)],
                                                      {range.getValue(), std::nullopt});
                                           });
    }
    if (std::optional<Decision> decides = kinds.of(op).decision) {
      decided.clear();
      for (ClassId operand : operands)
        decided.push_back(&at(operand));
      Value checked = op->getOperand(0), result = op->getResult(0);
      if ((*decides)(decided) == numeric::Known::Holds && checked.getType() == result.getType())
        narrow(*classOf[numbering.at(result)], Facts(at(operands.front()).facts));
    }
  }
}

} // namespace idr::egraph::detail
