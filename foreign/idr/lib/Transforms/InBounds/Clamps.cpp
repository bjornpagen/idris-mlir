// A size the array was made from relates when it is that operand, or the
// same integer clamped at 0, on either side. A branch (a match, an if) or a
// select or a max has that clamp when every side does, which for a side is
// either the values themselves or what the conditions choosing that side
// force. Those conditions are how the value was built, so the equality
// holds wherever the value is in scope, not only on the path that built it.
// A loop's own guard is not part of it: a fact that holds only while the
// loop runs is not a length everywhere the values are in scope.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/ScopeExit.h"

#include <algorithm>

using namespace mlir;

namespace idr::inbounds {

namespace {

// Past this many values followed while walking one clamp, the rest fail:
// an answer is then only weaker. Past this many places a branch is entered
// from, the same.
constexpr unsigned walkLimit = 64;
constexpr unsigned edgeLimit = 64;

int64_t clampedConst(const APInt &size) { return std::max<int64_t>(size.getSExtValue(), 0); }

} // namespace

// Whether `max(size, 0)` and `max(made, 0)` are the same integer, from how
// `made` is built. A side that already is agrees without the conditions;
// one that is not must be forced by the conditions that choose it. A loop
// is not walked: its guard holds on its iterations, and the length is
// claimed wherever both values are in scope.
bool Lengths::Local::clampsEqual(Value size, Value made) {
  std::pair<Value, Value> key{size, made};
  if (auto it = clampCache.find(key); it != clampCache.end())
    return it->second;
  if (!clampOpen.insert(key).second)
    return false;
  DenseSet<Value> seen;
  bool equal = agrees(size, made, seen);
  clampOpen.erase(key);
  clampCache[key] = equal;
  return equal;
}

bool Lengths::Local::agrees(Value size, Value made, DenseSet<Value> &seen) {
  if (size == made)
    return true;
  APInt a, b;
  if (matchPattern(size, m_ConstantInt(&a)) && matchPattern(made, m_ConstantInt(&b)))
    return clampedConst(a) == clampedConst(b);
  if (!size.getType().isInteger(64) || !made.getType().isInteger(64))
    return false;
  // A size already clamped at 0 has the clamp of what it clamps: the
  // dimension of an array made here folds to its size clamped so.
  if (std::optional<Value> clamps = clampOf(size))
    return agrees(*clamps, made, seen);
  if (seen.size() >= walkLimit || !seen.insert(made).second)
    return false;
  // Leaving `made` lets a walk down another side visit it again.
  llvm::scope_exit forget([&] { seen.erase(made); });
  if (std::optional<Value> clamps = clampOf(made))
    return agrees(size, *clamps, seen);
  if (auto max = made.getDefiningOp<arith::MaxSIOp>())
    return agrees(size, max.getLhs(), seen) && agrees(size, max.getRhs(), seen);
  if (auto select = made.getDefiningOp<arith::SelectOp>(); select && select.getCondition().getType().isInteger(1))
    return atPoint(select, select.getCondition(), true, size, select.getTrueValue(), seen) &&
           atPoint(select, select.getCondition(), false, size, select.getFalseValue(), seen);
  auto branch = dyn_cast_or_null<RegionBranchOpInterface>(made.getDefiningOp());
  if (branch && !branch.hasLoop())
    return eachEdge(branch, size, made, seen);
  return false;
}

// `made`, at `at`, agrees with `size`. `condition` chose this side when it
// is set. A side that agrees on its own needs no condition.
bool Lengths::Local::atPoint(Operation *at, Value condition, bool holds, Value size, Value made,
                             DenseSet<Value> &seen) {
  if (agrees(size, made, seen))
    return true;
  System system(lengths(), knownAt(at, dominance()));
  pathFacts(at, system);
  if (condition)
    system.assume(condition, holds);
  return system.sameClamp(size, made);
}

bool Lengths::Local::eachEdge(RegionBranchOpInterface branch, Value size, Value made,
                              DenseSet<Value> &seen) {
  RegionSuccessor successor(branch.getOperation());
  std::optional<unsigned> position = positionIn(branch.getSuccessorInputs(successor), made);
  if (!position)
    return false;
  SmallVector<Value> values;
  branch.getPredecessorValues(successor, static_cast<int>(*position), values);
  SmallVector<RegionBranchPoint> points;
  branch.getPredecessors(successor, points);
  if (values.empty() || values.size() != points.size() || values.size() > edgeLimit)
    return false;
  for (auto [i, point] : llvm::enumerate(points)) {
    Operation *at = point.isParent() ? branch.getOperation() : point.getTerminatorPredecessorOrNull();
    if (!at || !atPoint(at, Value(), true, size, values[i], seen))
      return false;
  }
  return true;
}

} // namespace idr::inbounds
