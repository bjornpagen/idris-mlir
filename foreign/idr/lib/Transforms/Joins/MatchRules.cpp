// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the matches that keep or drop what a known
// scrutinee, a known literal or the scrutinee's type decides: the region a
// known key takes, the literal in its own case, the case of the empty
// string a string that is never empty never takes, a default no
// constructor reaches, a match none of whose regions yields, and a result
// no op uses.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Control/KeyTests.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ops/Rules.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins/Rules.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/Support/ErrorHandling.h"

#include <array>
#include <cassert>
#include <concepts>
#include <optional>
#include <variant>

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

// The region of `op` whose case is `tag`, else its default; none where it
// has no default.
Region *takenByTag(DataMatchOp op, Tag tag) {
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
    if (op.getCaseTag(i) == tag)
      return &op.getCaseRegion(i);
  Region &fallback = op.getDefaultRegion();
  return fallback.empty() ? nullptr : &fallback;
}

// The region of `op` a known scrutinee takes, from what the e-graph knows
// of it (the idr.data.con that made its chosen form, or the constructor
// constant it is, held by an op or built by the graph) where how it was
// built still says its constructor at the match (builtStateHolds, which
// the match's own choice of region asks too: a memo cell a force rewrote
// says none), or from its type's one constructor; none where it is not
// known.
Region *takenByFacts(DataMatchOp op, const OperandFacts &facts) {
  Value scrutinee = op.getScrutinee();
  if (DataConOp con = constructorOf(scrutinee, facts);
      con && builtStateHolds(con.getResult(), op.getOperation()))
    return takenByTag(op, con.getTag());
  if (std::optional<Tag> tag = facts.constructorTag(scrutinee);
      tag && builtStateHolds(scrutinee, op.getOperation()))
    return takenByTag(op, *tag);
  SmallVector<RegionSuccessor> taken;
  SmallVector<Attribute> constants(op->getNumOperands(), Attribute());
  constants.front() = facts.held(scrutinee);
  op.getEntrySuccessorRegions(constants, taken);
  return taken.size() == 1 ? taken.front().getSuccessor() : nullptr;
}

// A literal match's region in the match's place, the scrutinee for what
// it binds, as every region binds it; what follows is dead where the
// region jumps or never ends.
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
// case whose key is that integer (keyInteger), else the default. A key is
// compared by its signed value, at any width: a big's is held at its
// fewest bits.
Region *takenByInteger(LitMatchOp op, const APInt &value) {
  unsigned width = value.getBitWidth();
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    std::optional<APInt> integer = keyInteger(key);
    if (integer && integer->getSignificantBits() <= width && integer->sextOrTrunc(width) == value)
      return &region;
  }
  return &op.getDefaultRegion();
}

// The two operands of a key test the graph decides, each as the runtime's
// value of its kind: the constant the scrutinee is, borrowed from its
// class, and the key, read as the one fold reads a constant an op holds
// and kept until the decision ends. A key test gives a truth.
class KeyOperands {
public:
  using Operand = std::variant<const Text *, const Big *, Attribute>;
  using Result = bool;

  explicit KeyOperands(MLIRContext *context) : keys(context) {}

  std::optional<APInt> integerOf(const Operand &operand) {
    return idr::match(
        operand,
        [](OneOf<const Text *, const Big *> auto) -> std::optional<APInt> { return std::nullopt; },
        [&](Attribute key) { return keys.integerOf(key); });
  }
  std::optional<double> realOf(const Operand &operand) {
    return idr::match(
        operand,
        [](OneOf<const Text *, const Big *> auto) -> std::optional<double> { return std::nullopt; },
        [&](Attribute key) { return keys.realOf(key); });
  }
  std::optional<const idris_rt_str *> strOf(const Operand &operand) {
    return idr::match(
        operand,
        [](const Text *text) -> std::optional<const idris_rt_str *> { return text->get(); },
        [](const Big *) -> std::optional<const idris_rt_str *> { return std::nullopt; },
        [&](Attribute key) { return keys.strOf(key); });
  }
  std::optional<idris_rt_big> bigOf(const Operand &operand) {
    return idr::match(
        operand, [](const Text *) -> std::optional<idris_rt_big> { return std::nullopt; },
        [](const Big *big) -> std::optional<idris_rt_big> { return big->get(); },
        [&](Attribute key) { return keys.bigOf(key); });
  }

  std::optional<bool> integer(Type, const APInt &truth) const { return truth.getBoolValue(); }
  std::optional<bool> real(Type, double) const {
    llvm_unreachable("a key test gives a truth, never a Double");
  }
  std::optional<bool> str(Type, const idris_rt_str *) const {
    llvm_unreachable("a key test gives a truth, never a string");
  }
  std::optional<bool> big(Type, idris_rt_big) const {
    llvm_unreachable("a key test gives a truth, never a big");
  }

  // A key test has no guard and no condition of its own.
  template <class Op>
  bool admits(llvm::ArrayRef<Operand>) const {
    static_assert(!fold::HasFoldCondition<Op>, "a key test folds on any two constants");
    return true;
  }

private:
  fold::InAttributes keys;
};
static_assert(fold::Where<KeyOperands>, "a key test's operands are a place constants live");

// The carrier whose key test tests a constant the graph knows a literal
// match's scrutinee is: a string's, and a big's past the small range,
// which a natural's key test tests alike.
template <class Known>
struct TestedAs;
template <>
struct TestedAs<const Text *> {
  using Carrier = StrType;
};
template <>
struct TestedAs<const Big *> {
  using Carrier = BigType;
};
static_assert(std::same_as<KeyTest<BigType>, KeyTest<NatType>>,
              "a natural is tested against its keys as an Integer is");

// The region of a literal match whose scrutinee is the string or the big
// past the small range `value`, as the graph knows it, whether an op held
// it or the graph computed it: the case whose key its carrier's key test,
// folded, finds it equal to, else the default.
template <class Known>
Region *takenByKey(LitMatchOp op, Known value) {
  KeyOperands operands(op.getContext());
  Type truth = IntegerType::get(op.getContext(), 1);
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    std::optional<bool> equal =
        foldKeyTest<typename TestedAs<Known>::Carrier>(operands, value, key, truth);
    assert(equal && "a verified match's keys are literals its carrier's key test reads");
    if (*equal)
      return &region;
  }
  return &op.getDefaultRegion();
}

// The region a literal match on a constant the graph knows takes: an
// integer, the one value of its range, finds its key by value, and a
// string or a big by its key test; none where the graph knows no constant.
// A Double has no literals, so no literal match is on one.
Region *literalTaken(LitMatchOp op, const OperandFacts &facts) {
  std::optional<KnownConstant> known = facts.constant(op.getScrutinee());
  if (!known)
    return nullptr;
  return idr::match(
      *known, [&](const APInt &value) { return takenByInteger(op, value); },
      [&](OneOf<const Text *, const Big *> auto value) { return takenByKey(op, value); },
      [](Real) -> Region * { llvm_unreachable("a literal match is never on a Double"); });
}

// Whether a use lies inside `region`.
bool inside(Region &region, OpOperand &use) {
  return region.isAncestor(use.getOwner()->getParentRegion());
}

// The values that are the scrutinee in `region`, a case of a literal
// match: the binding the case moved it into, and the scrutinee itself
// where the region reads it from outside.
std::array<Value, 2> scrutineesIn(LitMatchOp op, Region &region) {
  return {region.getArgument(0), op.getScrutinee()};
}

// Whether a case's region, where the scrutinee is the case's key, reads
// what is the scrutinee there.
bool readsKeyIn(LitMatchOp op, Region &region) {
  return llvm::any_of(scrutineesIn(op, region), [&](Value read) {
    return llvm::any_of(read.getUses(), [&](OpOperand &use) { return inside(region, use); });
  });
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

// In case k of a literal match, the scrutinee is the literal k, its
// binding there and itself alike. The rule chooses the cases whose regions
// read it.
std::optional<Edit> egraph::LiteralInCase::decide(LitMatchOp op, const OperandFacts &) {
  SmallVector<unsigned, 4> reading;
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
    if (readsKeyIn(op, op.getCaseRegions()[i]))
      reading.push_back(i);
  return choose(std::move(reading));
}

// The key's constant is the one its carrier holds, as the dialect makes it:
// upstream's for a word, ours for a string, a big or a natural.
// Where no constant op holds the key at the scrutinee's type, its uses stay,
// as they do in a case the root no longer has or whose region no longer
// reads the key.
void egraph::LiteralInCase::rewrite(LitMatchOp op, const Rewrite &chosen,
                                    RewriterBase &rewriter) {
  Type scrutinee = op.getScrutinee().getType();
  for (unsigned at : chosen.chosen) {
    if (at >= op.getNumCases())
      continue;
    Attribute key = op.getCases()[at];
    Region &region = op.getCaseRegions()[at];
    if (!readsKeyIn(op, region))
      continue;
    rewriter.setInsertionPointToStart(&region.front());
    Operation *literal =
        op->getDialect()->materializeConstant(rewriter, key, scrutinee, op.getLoc());
    if (!literal)
      continue;
    for (Value read : scrutineesIn(op, region))
      rewriter.replaceUsesWithIf(read, literal->getResult(0),
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
  if (!defaultDead(op))
    return std::nullopt;
  return Edit(Rewrite{});
}

void egraph::DeadDefault::rewrite(DataMatchOp op, const Rewrite &, RewriterBase &rewriter) {
  if (defaultDead(op))
    rewriter.eraseBlock(&op.getDefaultRegion().front());
}

// A match none of whose regions yields gives nothing.
std::optional<Edit> egraph::AllExits::decide(MatchOpInterface op, const OperandFacts &) {
  if (!exitsPending(op))
    return std::nullopt;
  return Edit(Rewrite{});
}

void egraph::AllExits::rewrite(MatchOpInterface op, const Rewrite &, RewriterBase &rewriter) {
  if (exitsPending(op))
    exits(rewriter, op.getOperation());
}

// A result of a match no op uses goes, with every yield's operand for it.
std::optional<Edit> egraph::DeadResults::decide(MatchOpInterface op, const OperandFacts &) {
  return choose(unusedResults(op));
}

void egraph::DeadResults::rewrite(MatchOpInterface op, const Rewrite &chosen,
                                  RewriterBase &rewriter) {
  dropUnused(rewriter, op.getOperation(), chosen.chosen);
}

} // namespace idr
