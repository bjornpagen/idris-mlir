// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the matches that keep or drop what a known
// scrutinee, a known literal or the scrutinee's type decides: the region a
// known key takes, the literal in its own case, the case of the empty
// string a string that is never empty never takes, a default no
// constructor reaches, a match none of whose regions yields, and a result
// no op uses.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ops/Rules.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins/Rules.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

// The region of `op` a known scrutinee takes, from what the e-graph knows
// of it (its constant, or the idr.data.con that made its chosen form) or
// from its type's one constructor; none where it is not known.
Region *takenByFacts(DataMatchOp op, const OperandFacts &facts) {
  Value scrutinee = op.getScrutinee();
  if (DataConOp con = constructorOf(scrutinee, facts)) {
    for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
      if (op.getCaseTag(i) == con.getTag())
        return &op.getCaseRegion(i);
    Region &fallback = op.getDefaultRegion();
    return fallback.empty() ? nullptr : &fallback;
  }
  SmallVector<RegionSuccessor> taken;
  SmallVector<Attribute> constants(op->getNumOperands(), Attribute());
  constants.front() = facts.constant(scrutinee);
  op.getEntrySuccessorRegions(constants, taken);
  return taken.size() == 1 ? taken.front().getSuccessor() : nullptr;
}

// A literal match's region in the match's place, the scrutinee for what
// the default binds; what follows is dead where the region jumps or never
// ends.
void inlineLiteral(RewriterBase &rewriter, LitMatchOp op, Region &kept) {
  Block &block = kept.front();
  Operation *terminator = block.getTerminator();
  rewriter.inlineBlockBefore(&block, op,
                             op->getOperands().take_front(block.getNumArguments()));
  if (auto yield = dyn_cast<YieldOp>(terminator)) {
    rewriter.replaceOp(op, yield.getResults());
    rewriter.eraseOp(yield);
    return;
  }
  eraseAfter(rewriter, op);
  rewriter.eraseOp(op);
}

// The region of a literal match whose scrutinee is the integer `value`: the
// case whose key is that integer, else the default. Essential: a word's key
// and a big's or a natural's are two attributes; a big's is compared by its
// signed value, at any width.
Region *takenByInteger(LitMatchOp op, const APInt &value) {
  unsigned width = value.getBitWidth();
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    std::optional<APInt> integer;
    if (auto word = dyn_cast<IntegerAttr>(key))
      integer = word.getValue();
    else if (auto big = dyn_cast<BigAttr>(key))
      integer = big.getValue();
    if (integer && integer->getSignificantBits() <= width && integer->sextOrTrunc(width) == value)
      return &region;
  }
  return &op.getDefaultRegion();
}

// The region a literal match on a known scrutinee takes. An integer the
// graph knows is the one value of its range, never an attribute, so it
// finds its key by value; a range of width 0 is of a value that holds no
// integer. A string, a double or a big past the small range is known by the
// constant an op holds, which the match's own lookup reads.
Region *literalTaken(LitMatchOp op, const OperandFacts &facts) {
  Value scrutinee = op.getScrutinee();
  if (std::optional<ConstantIntRanges> range = facts.range(scrutinee);
      range && range->getBitWidth() != 0)
    if (std::optional<APInt> value = range->getConstantValue())
      return takenByInteger(op, *value);
  Attribute held = facts.constant(scrutinee);
  if (!held)
    return nullptr;
  SmallVector<RegionSuccessor> taken;
  op.getEntrySuccessorRegions({held}, taken);
  return taken.size() == 1 ? taken.front().getSuccessor() : nullptr;
}

// Whether a use lies inside `region`.
bool inside(Region &region, OpOperand &use) {
  return region.isAncestor(use.getOwner()->getParentRegion());
}

// Whether the scrutinee's uses in the case of `key`, its region, may read
// the key: some lie there, and the scrutinee is the key itself there.
// Essential: a double's zero key is taken by both zeros, which ordered
// equality does not tell apart.
bool readsKeyIn(Value scrutinee, Attribute key, Region &region) {
  auto real = dyn_cast<FloatAttr>(key);
  return !(real && real.getValue().isZero()) &&
         llvm::any_of(scrutinee.getUses(), [&](OpOperand &use) { return inside(region, use); });
}

// Whether no case of the match leaves a constructor for its non-empty
// default, the scrutinee's type agreeing with Idris's coverage.
bool defaultDead(DataMatchOp op) {
  Region &fallback = op.getDefaultRegion();
  if (fallback.empty())
    return false;
  const auto &possible = op.getDataType().possibleTags();
  return llvm::all_of(possible, [&](Tag tag) {
    return llvm::is_contained(op.getCases(), static_cast<int32_t>(tag));
  });
}

// Whether a match none of whose regions yields is not yet in the form that
// gives nothing and ends its block.
bool exitsPending(Operation *op) {
  return llvm::none_of(op->getRegions(), yields) &&
         (op->getNumResults() || !isa<ub::UnreachableOp>(op->getNextNode()));
}

} // namespace

// A match whose region a known scrutinee takes. Where that region yields
// and what enters it enters unrefined (the type leaves that constructor
// alone), the region takes the match's place. Otherwise a case is kept
// alone, the scope of its refined value; a default is kept as it is, since
// alone it would run for constructors its refined value excludes.
std::optional<Edit> egraph::TakenCase::decide(DataMatchOp op, const OperandFacts &facts) {
  Region *taken = takenByFacts(op, facts);
  if (!taken)
    return std::nullopt;
  if (yields(*taken) &&
      TypeRange(taken->getArgumentTypes()) == TypeRange(op.getEntering().getTypes())) {
    Take take{taken->getRegionNumber(), {}};
    for (unsigned i = 0, e = taken->getNumArguments(); i < e; ++i)
      take.operandOfArgument.push_back(i);
    return Edit(take);
  }
  unsigned running = static_cast<unsigned>(
      llvm::count_if(op->getRegions(), [](Region &region) { return !region.empty(); }));
  if (running == 1 || taken == &op.getDefaultRegion())
    return std::nullopt;
  return Edit(Rewrite{{op.caseOf(*taken)}});
}

void egraph::TakenCase::rewrite(DataMatchOp op, const Rewrite &chosen, RewriterBase &rewriter) {
  unsigned kept = chosen.chosen.front();
  if (kept < op.getNumCases() && !op.getCaseRegion(kept).empty())
    (void)op.keepCases(rewriter, {kept}, nullptr);
}

// A literal match on a constant runs the region its literal takes.
std::optional<Edit> egraph::TakenLiteral::decide(LitMatchOp op, const OperandFacts &facts) {
  Region *taken = literalTaken(op, facts);
  if (!taken)
    return std::nullopt;
  if (yields(*taken)) {
    Take take{taken->getRegionNumber(), {}};
    if (taken->getNumArguments())
      take.operandOfArgument.push_back(0);
    return Edit(take);
  }
  return Edit(Rewrite{{taken->getRegionNumber()}});
}

void egraph::TakenLiteral::rewrite(LitMatchOp op, const Rewrite &chosen,
                                   RewriterBase &rewriter) {
  unsigned region = chosen.chosen.front();
  if (region < op->getNumRegions() && !op->getRegion(region).empty())
    inlineLiteral(rewriter, op, op->getRegion(region));
}

// In case k of a literal match, the scrutinee is the literal k.
std::optional<Edit> egraph::LiteralInCase::decide(LitMatchOp op, const OperandFacts &) {
  Value scrutinee = op.getScrutinee();
  bool reads = false;
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions()))
    reads = reads || readsKeyIn(scrutinee, key, region);
  return rewriteIf(reads);
}

// The key's constant is the one its carrier holds, as the dialect makes it:
// upstream's for a word or a double, ours for a string, a big or a natural.
// Where no constant op holds the key at the scrutinee's type, its uses stay.
void egraph::LiteralInCase::rewrite(LitMatchOp op, const Rewrite &, RewriterBase &rewriter) {
  Value scrutinee = op.getScrutinee();
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    if (!readsKeyIn(scrutinee, key, region))
      continue;
    rewriter.setInsertionPointToStart(&region.front());
    Operation *literal =
        op->getDialect()->materializeConstant(rewriter, key, scrutinee.getType(), op.getLoc());
    if (!literal)
      continue;
    rewriter.replaceUsesWithIf(scrutinee, literal->getResult(0),
                               [&](OpOperand &use) { return inside(region, use); });
  }
}

// A string that is never empty never takes the case of the empty string,
// whose index the rule carries.
std::optional<Edit> egraph::EmptyStringCase::decide(LitMatchOp op, const OperandFacts &) {
  if (!isa<StrType>(unrestricted(op.getScrutinee().getType())))
    return std::nullopt;
  auto cases = op.getCases();
  const auto *empty = llvm::find_if(cases, [](Attribute key) {
    auto text = dyn_cast<StringAttr>(key);
    return text && text.getValue().empty();
  });
  if (empty == cases.end() || !neverEmpty(op.getScrutinee()))
    return std::nullopt;
  return Edit(Rewrite{{static_cast<unsigned>(empty - cases.begin())}});
}

void egraph::EmptyStringCase::rewrite(LitMatchOp op, const Rewrite &chosen,
                                      RewriterBase &rewriter) {
  unsigned dropped = chosen.chosen.front();
  SmallVector<unsigned> kept;
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
    if (i != dropped)
      kept.push_back(i);
  (void)op.keepCases(rewriter, kept, &op.getDefaultRegion());
}

// A default the scrutinee's type leaves no constructor for never runs.
std::optional<Edit> egraph::DeadDefault::decide(DataMatchOp op, const OperandFacts &) {
  return rewriteIf(defaultDead(op));
}

void egraph::DeadDefault::rewrite(DataMatchOp op, const Rewrite &, RewriterBase &rewriter) {
  if (defaultDead(op))
    rewriter.eraseBlock(&op.getDefaultRegion().front());
}

// A match none of whose regions yields gives nothing.
std::optional<Edit> egraph::AllExits::decide(MatchOpInterface op, const OperandFacts &) {
  return rewriteIf(exitsPending(op));
}

void egraph::AllExits::rewrite(MatchOpInterface op, const Rewrite &, RewriterBase &rewriter) {
  if (exitsPending(op))
    exits(rewriter, op.getOperation());
}

// A result of a match no op uses goes, with every yield's operand for it.
std::optional<Edit> egraph::DeadResults::decide(MatchOpInterface op, const OperandFacts &) {
  return rewriteIf(someResultUnused(op));
}

void egraph::DeadResults::rewrite(MatchOpInterface op, const Rewrite &, RewriterBase &rewriter) {
  unused(rewriter, op.getOperation());
}

} // namespace idr
