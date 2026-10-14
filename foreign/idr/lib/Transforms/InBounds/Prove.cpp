// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A guard is erased when its condition holds wherever it runs, so it can
// never crash. A guard of an index holds when no integers satisfy what is
// known at it together with an index outside its length, `i < 0` or
// `i >= length`. What is known: the path to it, the definitions of the
// integers it compares, the bounds its loops keep their counters in, and
// every integer in scope that is the length of an array in scope. MLIR's
// Presburger library decides the two systems exactly, so a proof is a proof
// over the integers and a failure only leaves the guard in place. Any guard
// also holds when one of its kind on the same operands runs before it on
// every path, and a guard of an integer when the ranges MLIR's integer
// range analysis gives its operands satisfy its condition.
//
// Base's arrays check an index against the size they keep beside the array,
// and the access's guard checks it again; once a record of the two is taken
// apart, only the knowledge that the size is the array's length lets the
// first check prove the second. The first guard's result is its index, and
// its array is the access's, so the length relation reaches both.
//
// One function at a time: what it needs of another function is a table of
// the module's Lengths, so the functions are proved side by side.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/IR/Dominance.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

namespace {

// Whether `guard`'s index is within its length whenever it runs, with what
// `carried` says of loop counters. A system no loop bound reached is one
// already found wanting, so it is not decided again.
bool provenInBounds(CheckInBoundsOp guard, const Lengths &analysis, DominanceInfo &dominance,
                    Lengths::Local &lengths, CarriedBounds carried) {
  Value index = guard.getIndex();
  bool bounded = !carried;
  // A length relation holds where both values are in scope, which a value
  // of a loop's before block is not in its body.
  auto related = [&](Value size, Value array) {
    return dominance.properlyDominates(size, guard) &&
           dominance.properlyDominates(arrayRoot(array), guard) && lengths.related(size, array);
  };
  System system(
      analysis, knownAt(guard, dominance),
      [&](Value value) -> std::optional<Bounds> {
        std::optional<Bounds> bounds = carried ? carried(value) : std::nullopt;
        bounded |= bounds.has_value();
        return bounds;
      },
      related);
  std::optional<Value> array = guardedArray(guard);
  Linear i = system.of(index);
  Linear length = system.sizeOf(guard.getLength(), array);
  if (array)
    system.lengthOf(*array);
  pathFacts(guard, system);
  for (Value root : system.roots()) {
    if (!dominance.properlyDominates(root, guard))
      continue;
    for (Value size : system.values())
      if (size.getType().isInteger(64) && related(size, root))
        system.lengthIs(size, root);
  }
  // Quotients are read after the path and the lengths, which are what can
  // show the dividend is non-negative. A mask is read after the same facts:
  // the path is what bounds a shift, and the length relation is what says
  // the array has that capacity.
  relateQuotients(system);
  if (array)
    relateMask(system, lengths, dominance, guard, *array, index);
  return bounded && system.emptyWith(Linear().plus(i, DynamicAPInt(-1)).plus(-1)) &&
         system.emptyWith(i - length);
}

// Whether a guard of the same kind on the same operands runs before `guard`
// on every path to it. The operands are the same values there, so that one
// checked this one's condition and did not crash.
bool checkedBefore(GuardOpInterface guard, DominanceInfo &dominance) {
  for (Operation *other : guard.getGuarded().getUsers())
    if (other != guard && other->getName() == guard->getName() &&
        llvm::equal(other->getOperands(), guard->getOperands()) &&
        dominance.properlyDominates(other, guard))
      return true;
  return false;
}

// Whether the ranges the analysis gives `guard`'s integer operands satisfy
// its condition. A range holds of every value its SSA value takes, so the
// condition holds wherever the guard runs. A value the analysis never
// reached proves nothing.
bool provenByRanges(Operation *guard, const Lengths &analysis) {
  auto range = [&](Value value) -> std::optional<ConstantIntRanges> {
    if (!isa<IntegerType>(value.getType()))
      return std::nullopt;
    return analysis.rangeOf(value);
  };
  if (auto nonzero = dyn_cast<CheckNonzeroOp>(guard)) {
    std::optional<ConstantIntRanges> v = range(nonzero.getValue());
    return v && (!v->umin().isZero() || v->smin().isStrictlyPositive() || v->smax().isNegative());
  }
  if (auto byte = dyn_cast<CheckByteOp>(guard)) {
    std::optional<ConstantIntRanges> v = range(byte.getValue());
    return v && v->smin().isNonNegative() && v->smax().sle(255);
  }
  if (auto index = dyn_cast<CheckInBoundsOp>(guard)) {
    std::optional<ConstantIntRanges> i = range(index.getIndex());
    std::optional<ConstantIntRanges> n = range(index.getLength());
    return i && n && i->smin().isNonNegative() && i->smax().slt(n->smin());
  }
  if (auto bytes = dyn_cast<CheckRangeOp>(guard)) {
    std::optional<ConstantIntRanges> offset = range(bytes.getOffset());
    std::optional<ConstantIntRanges> count = range(bytes.getCount());
    std::optional<ConstantIntRanges> size = range(bytes.getSize());
    if (!offset || !count || !size || !offset->smin().isNonNegative() ||
        !count->smin().isNonNegative())
      return false;
    // The end of the farthest range, in a word one bit wider, where the sum
    // of two non-negative words cannot overflow.
    unsigned wide = offset->smax().getBitWidth() + 1;
    APInt end = offset->smax().sext(wide) + count->smax().sext(wide);
    return end.sle(size->smin().sext(wide));
  }
  return false;
}

// The proofs of one function, under the Lengths and the SymbolTable
// idr-in-bounds computed for the module just before it ran this.
struct ProveInBounds : PassWrapper<ProveInBounds, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ProveInBounds)

  StringRef getArgument() const final { return "idr-in-bounds-prove"; }
  StringRef getDescription() const final {
    return "Remove the guards of one function that can never crash";
  }

  // Each guard is judged on the function as it is, and those that hold are
  // erased together: in every run each of them gives its operand, so the
  // function without them runs the same way. A guard erased this way is
  // still a fact of the guards after it, which held either way.
  void runOnOperation() override {
    FuncOp fn = getOperation();
    auto analysis = getCachedParentAnalysis<Lengths>();
    auto symbols = getCachedParentAnalysis<SymbolTable>();
    if (!analysis || !symbols) {
      fn.emitError("internal error: idr-in-bounds: the lengths of the module are not available "
                   "to its functions");
      return signalPassFailure();
    }
    const Lengths &whole = analysis->get();
    auto &dominance = getAnalysis<DominanceInfo>();
    Lengths::Local lengths = whole.local(fn, symbols->get(), dominance);
    Induction induction(whole, dominance);
    SmallVector<GuardOpInterface> proven;
    fn.walk([&](GuardOpInterface guard) {
      Operation *op = guard;
      auto index = dyn_cast<CheckInBoundsOp>(op);
      auto proves = [&](CarriedBounds carried) {
        return provenInBounds(index, whole, dominance, lengths, std::move(carried));
      };
      // The bounds the loops keep their counters in cost a system per back
      // edge, so they are proven only for a guard that needs them.
      if (checkedBefore(guard, dominance) || provenByRanges(op, whole) ||
          (index && (proves(nullptr) || proves(induction.asCarried()))))
        proven.push_back(guard);
    });
    if (proven.empty())
      return markAllAnalysesPreserved();
    IRRewriter rewriter(&getContext());
    for (GuardOpInterface guard : proven)
      rewriter.replaceOp(guard, guard.getGuarded());
    // Erasing an op inside a block changes no block.
    markAnalysesPreserved<DominanceInfo>();
  }
};

} // namespace

std::unique_ptr<Pass> createProveInBoundsPass() { return std::make_unique<ProveInBounds>(); }

} // namespace idr::inbounds
