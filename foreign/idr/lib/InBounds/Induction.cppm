// idr.inbounds:induction: the bounds an scf.while keeps the integers it
// carries in, at every iteration. MLIR's integer range analysis gives a
// carried value the join of the value it starts with and of every value a
// back edge passes, but not the condition under which the back edge passes
// it: to the analysis, the `i` of a counter that goes round as `i + 1`
// while `i < n` may be the largest word, whose successor wraps to the
// smallest, so every word is the only range it can give (and its widening
// reaches that after its budget of rounds). The guard that excludes the
// wrap is a fact of the path, which the systems here hold.
//
// A candidate is a bound of the value a carried integer `x` starts with:
// `x >= lo`, or `x <= hi`, of the range of the loop's operand for it. The
// candidates of `x` are proven together by induction over the iterations.
// They hold of the first, whose `x` is that operand. Given that they hold
// of the `x` an iteration starts with, each holds of the value passed back
// as the next `x` when, on every path that goes round again (what its
// branches took, the accesses that ran on it, the condition that
// continues the loop), the system with that value outside the bound has no
// integer solution. Wrapping is encoded exactly, so a back edge that may
// overflow fails the proof unless the path itself excludes the overflow. A
// candidate that fails is dropped and the rest are proven again, until all
// that remain hold together: by induction, each holds at every iteration.
// What a value passed back is made of beyond `x` is known by its range and
// its path, never by a bound still to be proven, so no proof assumes what
// it proves. The operand of an inner loop may be a value of an outer one,
// whose own bounds then give the inner candidates.
export module idr.inbounds:induction;

import idr.mlir;

import :joins;
import :linear;
import :paths;
import :system;

using namespace mlir;
using llvm::DynamicAPInt;
using namespace mlir::dataflow;

namespace idr::inbounds {

namespace {

// Past this many places a loop goes round from, its values get no bounds.
constexpr unsigned edgeLimit = 64;

// A place the loop goes round from: at `at`, `next` is passed back when
// `again` holds (always, when null).
struct BackEdge {
  Operation *at;
  Value again;
  Value next;
};

// A bound to prove of the carried value `value`: at least `bound` when
// `lower`, else at most `bound`.
struct Candidate {
  BlockArgument value;
  DynamicAPInt bound;
  bool lower;
};

bool isTrue(Value value) {
  APInt k;
  return matchPattern(value, m_ConstantInt(&k)) && !k.isZero();
}

// The places `next`, passed back at `at` when `again` holds, comes from.
// A result of a region op that runs at most one of its regions, once, is
// what that region yields, under what it yields as the condition (a result
// of the same op), or under `again` when that is true wherever it is.
void backEdges(Operation *at, Value again, Value next, SmallVectorImpl<BackEdge> &edges) {
  if (edges.size() > edgeLimit)
    return;
  auto result = dyn_cast<OpResult>(next);
  auto branch = result ? dyn_cast<RegionBranchOpInterface>(result.getOwner()) : nullptr;
  auto flag = dyn_cast<OpResult>(again);
  bool together = result && flag && flag.getOwner() == result.getOwner();
  if (!branch || branch.hasLoop() || !(together || isTrue(again))) {
    edges.push_back({at, again, next});
    return;
  }
  RegionSuccessor results(branch.getOperation());
  ValueRange inputs = branch.getSuccessorInputs(results);
  std::optional<unsigned> nextAt = positionIn(inputs, next);
  std::optional<unsigned> againAt = together ? positionIn(inputs, again) : std::nullopt;
  if (!nextAt || (together && !againAt)) {
    edges.push_back({at, again, next});
    return;
  }
  SmallVector<RegionBranchPoint> points;
  branch.getPredecessors(results, points);
  for (RegionBranchPoint point : points) {
    OperandRange operands = branch.getSuccessorOperands(point, results);
    Operation *from = point.isParent() ? branch.getOperation() : point.getTerminatorPredecessorOrNull();
    backEdges(from, together ? operands[*againAt] : again, operands[*nextAt], edges);
  }
}

// Whether `value` is the carried `x` of this iteration: `x` itself, or what
// the condition forwarded of it to the after region.
bool isCurrent(scf::WhileOp loop, BlockArgument x, Value value) {
  if (value == x)
    return true;
  auto arg = dyn_cast<BlockArgument>(value);
  return arg && arg.getOwner() == loop.getAfterBody() &&
         loop.getConditionOp().getArgs()[arg.getArgNumber()] == x;
}

// Whether `next` may keep the candidate's bound of the carried `x`: a
// constant, `x`, or `x` plus or minus some amount, whose overflow the proof
// then decides; an amount whose sign the analysis knows keeps no upper
// bound when it only grows `x`, and no lower bound when it only shrinks it.
// Any other back edge (`10 x + d`) keeps no bound the proof could find
// without wrapping, and leaves systems that take seconds to decide.
bool isStep(scf::WhileOp loop, const System &ranges, const Candidate &c, Value next) {
  BlockArgument x = c.value;
  if (matchPattern(next, m_Constant()) || isCurrent(loop, x, next))
    return true;
  Value amount;
  bool adds = true;
  if (auto add = next.getDefiningOp<arith::AddIOp>()) {
    if (isCurrent(loop, x, add.getLhs()))
      amount = add.getRhs();
    else if (isCurrent(loop, x, add.getRhs()))
      amount = add.getLhs();
  } else if (auto sub = next.getDefiningOp<arith::SubIOp>(); sub && isCurrent(loop, x, sub.getLhs())) {
    amount = sub.getRhs();
    adds = false;
  }
  if (!amount)
    return false;
  std::optional<Bounds> sign = ranges.rangeOf(amount);
  bool grows = sign && (adds ? sign->first > 0 : sign->second < 0);
  bool shrinks = sign && (adds ? sign->second < 0 : sign->first > 0);
  return !(c.lower ? shrinks : grows);
}

// `e >= 0` exactly when `v` is within the candidate's bound.
Linear within(const Candidate &c, const Linear &v) {
  Linear bound = Linear::constantOf(c.bound);
  return c.lower ? v - bound : bound - v;
}

} // namespace

// The bounds each scf.while keeps its carried integers in, each proven the
// first time it is asked about.
export class Induction {
public:
  Induction(DataFlowSolver &solver, DominanceInfo &dominance)
      : solver(solver), dominance(dominance) {}

  // The bounds of `value` at every iteration of the loop that carries it,
  // or of the value its condition forwarded as `value` to its body; none
  // for any other value, or one being proven.
  std::optional<Bounds> boundsOf(Value value) {
    auto x = dyn_cast<BlockArgument>(value);
    auto loop = x ? dyn_cast<scf::WhileOp>(x.getOwner()->getParentOp()) : nullptr;
    if (!loop)
      return std::nullopt;
    if (x.getOwner() == loop.getAfterBody())
      return boundsOf(loop.getConditionOp().getArgs()[x.getArgNumber()]);
    if (auto it = proven.find(x); it != proven.end())
      return it->second;
    proven[x] = std::nullopt;
    std::optional<Bounds> bounds = prove(loop, x);
    proven[x] = bounds;
    return bounds;
  }

  // `boundsOf`, as a system reads it.
  CarriedBounds asCarried() {
    return [this](Value value) { return boundsOf(value); };
  }

private:
  // The bounds of `x`, carried by `loop`, that hold at every iteration.
  // Each is proven on its own: what the proof asks of other values is
  // their range, which for a value of a loop around this one is its own
  // induction, and never one of this loop's or of a loop inside it, which
  // the back edges do not reach into.
  std::optional<Bounds> prove(scf::WhileOp loop, BlockArgument x) {
    System ranges(solver, [](Value) { return false; }, asCarried());
    std::optional<Bounds> start = ranges.rangeOf(loop.getInits()[x.getArgNumber()]);
    std::optional<Bounds> now = ranges.rangeOf(x);
    if (!start || !now)
      return std::nullopt;
    SmallVector<Candidate> candidates;
    if (start->first > now->first)
      candidates.push_back({x, start->first, true});
    if (start->second < now->second)
      candidates.push_back({x, start->second, false});
    // The after region passes back what it yields; what it yields
    // unchanged of what the condition forwarded comes from the before
    // region.
    scf::ConditionOp condition = loop.getConditionOp();
    Operation *yield = loop.getAfterBody()->getTerminator();
    SmallVector<BackEdge> edges;
    Value next = yield->getOperand(x.getArgNumber());
    if (auto arg = dyn_cast<BlockArgument>(next); arg && arg.getOwner() == loop.getAfterBody())
      backEdges(condition, condition.getCondition(), condition.getArgs()[arg.getArgNumber()], edges);
    else
      edges.push_back({yield, Value(), next});
    if (edges.size() > edgeLimit)
      return std::nullopt;
    llvm::erase_if(candidates, [&](const Candidate &c) {
      return llvm::any_of(edges, [&](const BackEdge &edge) { return !isStep(loop, ranges, c, edge.next); });
    });
    auto holds = [&](const Candidate &c) {
      for (const BackEdge &edge : edges) {
        System system(solver, knownAt(edge.at, dominance), asCarried());
        pathFacts(edge.at, system);
        if (edge.again)
          system.assume(edge.again, true);
        for (const Candidate &h : candidates)
          system.atLeastZero(within(h, system.of(h.value)));
        // Outside the bound: `within < 0`, that is `-within - 1 >= 0`.
        if (!system.emptyWith((Linear() - within(c, system.of(edge.next))).plus(-1)))
          return false;
      }
      return true;
    };
    while (!candidates.empty()) {
      SmallVector<Candidate> kept;
      for (const Candidate &c : candidates)
        if (holds(c))
          kept.push_back(c);
      if (kept.size() == candidates.size())
        break;
      candidates = std::move(kept);
    }
    if (candidates.empty())
      return std::nullopt;
    Bounds bounds = *now;
    for (const Candidate &c : candidates)
      (c.lower ? bounds.first : bounds.second) = c.bound;
    return bounds;
  }

  DataFlowSolver &solver;
  DominanceInfo &dominance;
  DenseMap<Value, std::optional<Bounds>> proven;
};

} // namespace idr::inbounds
