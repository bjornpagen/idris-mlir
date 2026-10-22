// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rewrites of the control-flow ops, which the specification declares as
// skeleton rules of the e-graph pass (IdrisMLIR.Spec.Control.Rules): one-way,
// since a match or a join point is an op of the skeleton, never a pure
// value; case-of-case alone leaves a choice, per arm, to the extraction.
// The specification holds which op each is rooted at; these classes
// (idr/IR/Control/Control.h) rewrite, each checking the condition it needs
// and failing, with nothing changed, where it does not hold.

#include "idr/IR/Control/Control.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr::egraph;

namespace idr {

namespace {

// Whether `region` gives its op's results: it ends in a yield.
bool yields(Region &region) {
  return !region.empty() && isa<YieldOp>(region.front().getTerminator());
}

// Removes the results of `op` that `keep` leaves out, from the op and from
// each of its regions' yields: a new op of the same name with the kept
// results, the regions moved over.
Operation *keepResults(RewriterBase &rewriter, Operation *op, const llvm::BitVector &keep) {
  for (Region &region : op->getRegions())
    if (yields(region)) {
      auto yield = cast<YieldOp>(region.front().getTerminator());
      SmallVector<Value> kept;
      for (auto [index, value] : llvm::enumerate(yield.getResults()))
        if (keep.test(index))
          kept.push_back(value);
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<YieldOp>(yield, kept);
    }
  SmallVector<Type> types;
  SmallVector<Value> survivors;
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      types.push_back(result.getType());
  rewriter.setInsertionPoint(op);
  OperationState state(op->getLoc(), op->getName(), op->getOperands(), types, op->getAttrs(),
                       /*successors=*/{}, /*regions=*/{});
  state.propertiesAttr = op->getPropertiesAsAttribute();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *fresh = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), fresh->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  unsigned next = 0;
  SmallVector<Value> replacements;
  for (OpResult result : op->getResults())
    replacements.push_back(keep.test(result.getResultNumber()) ? fresh->getResult(next++)
                                                                : Value());
  for (auto [result, replacement] : llvm::zip_equal(op->getResults(), replacements))
    if (replacement)
      rewriter.replaceAllUsesWith(result, replacement);
  rewriter.eraseOp(op);
  return fresh;
}

// Erases what follows `op` in its block, last first: control never gets
// past `op`.
void eraseAfter(RewriterBase &rewriter, Operation *op) {
  for (Operation *after = &op->getBlock()->back(); after != op;) {
    Operation *previous = after->getPrevNode();
    after->dropAllUses();
    rewriter.eraseOp(after);
    after = previous;
  }
}

// A match none of whose regions yields gives nothing: its results go, what
// follows it in its block is dead, and the block ends in ub.unreachable.
void exits(RewriterBase &rewriter, Operation *op) {
  eraseAfter(rewriter, op);
  Operation *kept = op;
  if (op->getNumResults())
    kept = keepResults(rewriter, op, llvm::BitVector(op->getNumResults(), false));
  rewriter.setInsertionPointAfter(kept);
  ub::UnreachableOp::create(rewriter, kept->getLoc());
}

// A result no op uses goes from the op and from every yield that gives it.
LogicalResult unused(RewriterBase &rewriter, Operation *op) {
  llvm::BitVector keep(op->getNumResults());
  for (OpResult result : op->getResults())
    if (!result.use_empty())
      keep.set(result.getResultNumber());
  if (keep.all())
    return failure();
  keepResults(rewriter, op, keep);
  return success();
}

// A join region no jump reaches goes with its token and its binders; a
// group left with none is its body, whose yield gives the results.
template <typename Group>
LogicalResult unreached(RewriterBase &rewriter, Group op) {
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  llvm::BitVector dead(targets, true);
  for (Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    Block::BlockArgListType tokens = op.getTokens(region);
    for (unsigned i = 0, e = static_cast<unsigned>(tokens.size()); i < e; ++i)
      if (!tokens[i].use_empty())
        dead.reset(i);
  }
  if (dead.none())
    return failure();
  if (dead.all()) {
    Block &body = op.getBody().front();
    auto yield = dyn_cast<YieldOp>(body.getTerminator());
    body.eraseArguments(0, body.getNumArguments());
    rewriter.inlineBlockBefore(&body, op);
    if (yield) {
      rewriter.replaceOp(op, yield.getResults());
      rewriter.eraseOp(yield);
      return success();
    }
    // The body jumps out or never ends: nothing reaches what follows.
    eraseAfter(rewriter, op);
    rewriter.eraseOp(op);
    return success();
  }
  SmallVector<Attribute> binders;
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i))
      binders.push_back(op.getBinders()[i]);
  for (Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    Block &entry = region.front();
    unsigned leading = static_cast<unsigned>(op.getTokens(region).size());
    for (unsigned i = leading; i-- > 0;)
      if (dead.test(i))
        entry.eraseArgument(i);
  }
  // A region inlined at its one jump is empty already.
  for (unsigned i = targets; i-- > 0;)
    if (dead.test(i) && !op.getJoinRegions()[i].empty())
      rewriter.eraseBlock(&op.getJoinRegions()[i].front());
  rewriter.setInsertionPoint(op);
  OperationState state(op.getLoc(), op->getName().getStringRef(), ValueRange(),
                       op->getResultTypes());
  state.template getOrAddProperties<typename Group::Properties>().binders =
      rewriter.getArrayAttr(binders);
  state.addRegion();
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i))
      state.addRegion();
  Operation *fresh = rewriter.create(state);
  rewriter.inlineRegionBefore(op.getBody(), fresh->getRegion(0), fresh->getRegion(0).end());
  unsigned next = 1;
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i)) {
      Region &into = fresh->getRegion(next++);
      rewriter.inlineRegionBefore(op.getJoinRegions()[i], into, into.end());
    }
  rewriter.replaceOp(op, fresh->getResults());
  return success();
}

// A parameter no op of its join region uses goes, with every jump's
// argument for it.
template <typename Group>
LogicalResult unread(RewriterBase &rewriter, Group op) {
  bool changed = false;
  for (Region &region : op.getJoinRegions()) {
    Block::BlockArgListType parameters = op.getParameters(region);
    unsigned leading = static_cast<unsigned>(op.getTokens(region).size());
    for (unsigned i = static_cast<unsigned>(parameters.size()); i-- > 0;) {
      if (!parameters[i].use_empty())
        continue;
      unsigned target = region.getRegionNumber() - 1;
      for (Region &from : op->getRegions()) {
        Block::BlockArgListType tokens = op.getTokens(from);
        if (target >= tokens.size())
          continue;
        for (Operation *user : llvm::make_early_inc_range(tokens[target].getUsers()))
          rewriter.modifyOpInPlace(user, [&] { cast<JumpOp>(user).getArgsMutable().erase(i); });
      }
      region.front().eraseArgument(leading + i);
      changed = true;
    }
  }
  return success(changed);
}

// The match on `scrutinee` whose cases all jump, one per region of
// `consumer`, each to its member through `targets`, passing what the
// region binds: the dispatch case-of-case copies into an arm. A case
// binds its constructor's index variables at the copy's depth, so its
// types are the consumer's renumbered there, and the jump passes them as
// the terms of the join region's binders.
void dispatch(RewriterBase &rewriter, MatchOp consumer, Value scrutinee,
              const joins::Targets &targets) {
  Location loc = consumer.getLoc();
  SmallVector<Tag> tags = llvm::map_to_vector(
      consumer.getCases(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; });
  auto copy = MatchOp::create(rewriter, loc, TypeRange(), scrutinee, consumer.getForwarded(), tags);
  unsigned from = joins::scopeDepth(consumer->getParentRegion());
  unsigned to = joins::scopeDepth(copy->getParentRegion());
  unsigned member = 0;
  for (auto [source, into] : llvm::zip_equal(consumer->getRegions(), copy->getRegions())) {
    if (source.empty())
      continue;
    Block *block = rewriter.createBlock(&into, {}, source.getArgumentTypes(),
                                        llvm::map_to_vector(source.getArguments(), [](Value arg) {
                                          return arg.getLoc();
                                        }));
    unsigned binders = static_cast<unsigned>(consumer.getBoundSorts(source).size());
    IndexArgsAttr terms;
    if (binders) {
      if (from != to)
        families::renumber(into, from, binders, to);
      terms = families::levelArgs(rewriter.getContext(), to, binders);
    }
    rewriter.setInsertionPointToEnd(block);
    JumpOp::create(rewriter, loc, targets.tokenFor(member++, &into), block->getArguments(), terms);
  }
  rewriter.setInsertionPointAfter(copy);
  ub::UnreachableOp::create(rewriter, loc);
}

// Whether `value`, yielded by an arm, has a known constructor there, so the
// dispatch copied into the arm folds: a constant or an idr.con.
bool known(Value value) {
  if (value.getDefiningOp<ConOp>())
    return true;
  Attribute constant;
  return matchPattern(value, m_Constant(&constant)) && isa<ConAttr>(constant);
}

// The arms of `consumer`'s producer, an idr.match just before it whose one
// result is its scrutinee and nothing else, that yield a value of a known
// constructor: where the copied dispatch folds and the consumer's case runs
// with no test. The other arms share one dispatch after the producer.
SmallVector<unsigned> foldingArms(MatchOp consumer) {
  auto producer = dyn_cast_or_null<MatchOp>(consumer->getPrevNode());
  if (!producer || producer->getNumResults() != 1 ||
      consumer.getScrutinee() != producer->getResult(0) ||
      !producer->getResult(0).hasOneUse() ||
      llvm::any_of(consumer.getForwarded(),
                   [&](Value value) { return value.getDefiningOp() == producer.getOperation(); }))
    return {};
  SmallVector<unsigned> arms;
  for (Region &region : producer->getRegions())
    if (yields(region) &&
        known(cast<YieldOp>(region.front().getTerminator()).getResults().front()))
      arms.push_back(region.getRegionNumber());
  return arms;
}

} // namespace

namespace {

// The region of `op` a known scrutinee takes, from what the e-graph knows
// of it (its constant, or the idr.con that made its chosen form) or from
// its type's one constructor; none where it is not known, or where the
// match keeps one region already.
Region *takenByFacts(MatchOp op, Attribute constant, Operation *origin) {
  unsigned running = static_cast<unsigned>(
      llvm::count_if(op->getRegions(), [](Region &region) { return !region.empty(); }));
  if (running == 1)
    return nullptr;
  if (auto con = dyn_cast_or_null<ConOp>(origin)) {
    for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
      if (op.getCaseTag(i) == con.getTag())
        return &op.getCaseRegion(i);
    Region &fallback = op.getDefaultRegion();
    return fallback.empty() ? nullptr : &fallback;
  }
  SmallVector<RegionSuccessor> taken;
  SmallVector<Attribute> constants(op->getNumOperands(), Attribute());
  constants.front() = constant;
  op.getEntrySuccessorRegions(constants, taken);
  return taken.size() == 1 ? taken.front().getSuccessor() : nullptr;
}

// The region of `op` its scrutinee takes as the IR now holds it.
Region *takenNow(MatchOp op) {
  Attribute constant;
  (void)matchPattern(op.getScrutinee(), m_Constant(&constant));
  return takenByFacts(op, constant, op.getScrutinee().getDefiningOp());
}

// Keeps `kept` alone: the match's one case, or its default, the scope of
// the refined value, which lowers with no test.
void keepRegion(RewriterBase &rewriter, MatchOp op, Region &kept) {
  bool fallback = &kept == &op.getDefaultRegion();
  SmallVector<Tag> tags;
  if (!fallback)
    tags.push_back(op.getCaseTag(op.caseOf(kept)));
  rewriter.setInsertionPoint(op);
  auto fresh = MatchOp::create(rewriter, op.getLoc(), op->getResultTypes(), op.getScrutinee(),
                               op.getForwarded(), tags);
  Region &into = fallback ? fresh.getDefaultRegion() : fresh.getCaseRegion(0);
  rewriter.inlineRegionBefore(kept, into, into.end());
  rewriter.replaceOp(op, fresh->getResults());
}

// A literal match's region, which binds nothing, in the match's place;
// what follows is dead where the region jumps or never ends.
void inlineLiteral(RewriterBase &rewriter, MatchLitOp op, Region &kept) {
  Block &block = kept.front();
  Operation *terminator = block.getTerminator();
  rewriter.inlineBlockBefore(&block, op);
  if (auto yield = dyn_cast<YieldOp>(terminator)) {
    rewriter.replaceOp(op, yield.getResults());
    rewriter.eraseOp(yield);
    return;
  }
  eraseAfter(rewriter, op);
  rewriter.eraseOp(op);
}

// The region a constant literal takes.
Region *literalTaken(MatchLitOp op, Attribute value) {
  if (!value)
    return nullptr;
  SmallVector<RegionSuccessor> taken;
  op.getEntrySuccessorRegions({value}, taken);
  return taken.size() == 1 ? taken.front().getSuccessor() : nullptr;
}

// Whether a use lies inside `region`.
bool inside(Region &region, OpOperand &use) {
  return region.isAncestor(use.getOwner()->getParentRegion());
}

// Whether no case of the match leaves a constructor for its non-empty
// default, the scrutinee's type agreeing with Idris's coverage.
bool defaultDead(MatchOp op) {
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

bool someResultUnused(Operation *op) {
  return llvm::any_of(op->getResults(), [](OpResult result) { return result.use_empty(); });
}

// Whether some join region of `op` no jump reaches.
template <typename Group>
bool someRegionUnreached(Group op) {
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  llvm::BitVector reached(targets, false);
  for (Region &region : op->getRegions()) {
    Block::BlockArgListType tokens = op.getTokens(region);
    for (unsigned i = 0, e = static_cast<unsigned>(tokens.size()); i < e; ++i)
      if (!tokens[i].use_empty())
        reached.set(i);
  }
  return !reached.all();
}

// Whether some parameter of a join region of `op` is never read.
template <typename Group>
bool someParameterUnread(Group op) {
  return llvm::any_of(op.getJoinRegions(), [&](Region &region) {
    return llvm::any_of(op.getParameters(region),
                        [](BlockArgument parameter) { return parameter.use_empty(); });
  });
}

// The jump that ends `op`'s body, when it is the one jump to its target
// and the target binds no index variable: the region runs in its place.
JumpOp singleJump(JoinOp op) {
  auto jump = dyn_cast<JumpOp>(op.getBody().front().getTerminator());
  if (!jump || !jump.getTarget().hasOneUse())
    return JumpOp();
  Region *target = op.getTarget(cast<BlockArgument>(jump.getTarget()));
  return target && op.getBoundSorts(*target).empty() ? jump : JumpOp();
}

std::optional<Edit> rewriteIf(bool holds) {
  return holds ? std::optional<Edit>(Rewrite{}) : std::nullopt;
}

} // namespace

//===----------------------------------------------------------------------===//
// The matches
//===----------------------------------------------------------------------===//

// A match whose region a known scrutinee takes: where the scrutinee's type
// leaves that constructor alone, the refined value is the scrutinee itself
// and the region takes the match's place; otherwise the match keeps that
// region alone, the scope of its refined value.
std::optional<Edit> egraph::TakenCase::decide(MatchOp op, const OperandFacts &facts) {
  Region *taken = takenByFacts(op, facts.constant(0), facts.origin(0));
  if (!taken)
    return std::nullopt;
  if (TypeRange(taken->getArgumentTypes()) == TypeRange(op->getOperandTypes())) {
    Take take{taken->getRegionNumber(), {}};
    for (unsigned i = 0, e = op->getNumOperands(); i < e; ++i)
      take.operandOfArgument.push_back(i);
    return Edit(take);
  }
  return Edit(Rewrite{});
}

void egraph::TakenCase::rewrite(MatchOp op, RewriterBase &rewriter) {
  if (Region *taken = takenNow(op))
    keepRegion(rewriter, op, *taken);
}

// A literal match on a constant runs the region its literal takes.
std::optional<Edit> egraph::TakenLiteral::decide(MatchLitOp op, const OperandFacts &facts) {
  Region *taken = literalTaken(op, facts.constant(0));
  if (!taken)
    return std::nullopt;
  if (yields(*taken))
    return Edit(Take{taken->getRegionNumber(), {}});
  return Edit(Rewrite{});
}

void egraph::TakenLiteral::rewrite(MatchLitOp op, RewriterBase &rewriter) {
  Attribute value;
  if (matchPattern(op.getScrutinee(), m_Constant(&value)))
    if (Region *taken = literalTaken(op, value))
      inlineLiteral(rewriter, op, *taken);
}

// In case k of a literal match, the scrutinee is the literal k.
std::optional<Edit> egraph::LiteralInCase::decide(MatchLitOp op, const OperandFacts &) {
  Value scrutinee = op.getScrutinee();
  return rewriteIf(llvm::any_of(op.getCaseRegions(), [&](Region &region) {
    return llvm::any_of(scrutinee.getUses(), [&](OpOperand &use) { return inside(region, use); });
  }));
}

void egraph::LiteralInCase::rewrite(MatchLitOp op, RewriterBase &rewriter) {
  Value scrutinee = op.getScrutinee();
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    if (llvm::none_of(scrutinee.getUses(), [&](OpOperand &use) { return inside(region, use); }))
      continue;
    rewriter.setInsertionPointToStart(&region.front());
    Value literal = ConstantOp::create(rewriter, op.getLoc(), scrutinee.getType(), key);
    rewriter.replaceUsesWithIf(scrutinee, literal,
                               [&](OpOperand &use) { return inside(region, use); });
  }
}

// A default the scrutinee's type leaves no constructor for never runs.
std::optional<Edit> egraph::DeadDefault::decide(MatchOp op, const OperandFacts &) {
  return rewriteIf(defaultDead(op));
}

void egraph::DeadDefault::rewrite(MatchOp op, RewriterBase &rewriter) {
  if (defaultDead(op))
    rewriter.eraseBlock(&op.getDefaultRegion().front());
}

// A match none of whose regions yields gives nothing.
std::optional<Edit> egraph::AllExits::decide(MatchOpInterface op, const OperandFacts &) {
  return rewriteIf(exitsPending(op));
}

void egraph::AllExits::rewrite(MatchOpInterface op, RewriterBase &rewriter) {
  if (exitsPending(op))
    exits(rewriter, op.getOperation());
}

// A result of a match no op uses goes, with every yield's operand for it.
std::optional<Edit> egraph::DeadResults::decide(MatchOpInterface op, const OperandFacts &) {
  return rewriteIf(someResultUnused(op));
}

void egraph::DeadResults::rewrite(MatchOpInterface op, RewriterBase &rewriter) {
  (void)unused(rewriter, op);
}

// Case-of-case: the consumer's regions become the join regions of one flat
// idr.join in its place, and the producer moves into its body; each arm
// whose yielded value has a known constructor ends in a copy of the
// consumer's dispatch, which folds there, so that arm runs its case with no
// test; the other arms still yield, and one dispatch after the producer
// serves them. Each step moves a dispatch deeper, so case-of-case ends by
// construction; the growth is one jump per case per arm.
std::optional<Edit> egraph::CaseOfCase::decide(MatchOp consumer, const OperandFacts &) {
  return rewriteIf(!foldingArms(consumer).empty());
}

void egraph::CaseOfCase::rewrite(MatchOp consumer, RewriterBase &rewriter) {
  SmallVector<unsigned> chosen = foldingArms(consumer);
  if (chosen.empty())
    return;
  auto producer = cast<MatchOp>(consumer->getPrevNode());
  unsigned depth = joins::scopeDepth(consumer->getParentRegion());
  SmallVector<joins::Member> members;
  for (Region &region : consumer->getRegions())
    if (!region.empty())
      members.push_back(
          {&region, IndexBindersAttr::get(consumer.getContext(), consumer.getBoundSorts(region)),
           depth});
  // The dispatch reads the consumer's shape after its regions moved: a
  // shell of it whose regions are empty blocks of the same signatures.
  rewriter.setInsertionPoint(consumer);
  SmallVector<Tag> tags = llvm::map_to_vector(
      consumer.getCases(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; });
  auto shell = MatchOp::create(rewriter, consumer.getLoc(), TypeRange(), consumer.getScrutinee(),
                               consumer.getForwarded(), tags);
  for (auto [from, into] : llvm::zip_equal(consumer->getRegions(), shell->getRegions()))
    if (!from.empty())
      rewriter.createBlock(&into, {}, from.getArgumentTypes(),
                           llvm::map_to_vector(from.getArguments(),
                                               [](Value arg) { return arg.getLoc(); }));
  rewriter.setInsertionPoint(consumer);
  joins::Group group = joins::build(rewriter, consumer.getLoc(), consumer->getResultTypes(),
                                    members, {}, joins::Origin::Terminates);
  rewriter.replaceAllUsesWith(consumer->getResults(), group.outermost->getResults());
  rewriter.moveOpBefore(producer, group.body, group.body->end());
  for (unsigned arm : chosen) {
    auto yield = cast<YieldOp>(producer->getRegion(arm).front().getTerminator());
    Value value = yield.getResults().front();
    rewriter.eraseOp(yield);
    rewriter.setInsertionPointToEnd(&producer->getRegion(arm).front());
    dispatch(rewriter, shell, value, group.targets);
  }
  rewriter.setInsertionPointToEnd(group.body);
  if (llvm::any_of(producer->getRegions(), yields))
    dispatch(rewriter, shell, producer->getResult(0), group.targets);
  else
    ub::UnreachableOp::create(rewriter, producer.getLoc());
  rewriter.eraseOp(shell);
  rewriter.eraseOp(consumer);
}

//===----------------------------------------------------------------------===//
// The join points
//===----------------------------------------------------------------------===//

// A result of a join point's op no op uses goes, with every yield's operand.
std::optional<Edit> egraph::DeadJoinResults::decide(JoinPointsOpInterface op,
                                                    const OperandFacts &) {
  return rewriteIf(someResultUnused(op));
}

void egraph::DeadJoinResults::rewrite(JoinPointsOpInterface op, RewriterBase &rewriter) {
  (void)unused(rewriter, op);
}

// An idr.loop whose join regions never jump to its own op repeats nothing:
// it is an idr.join, its join regions' tokens and loop markers dropped.
std::optional<Edit> egraph::LoopToJoin::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(llvm::none_of(op.getJoinRegions(), [&](Region &region) {
    return llvm::any_of(op.getTokens(region),
                        [](BlockArgument token) { return !token.use_empty(); });
  }));
}

void egraph::LoopToJoin::rewrite(LoopOp op, RewriterBase &rewriter) {
  rewriter.setInsertionPoint(op);
  OperationState state(op.getLoc(), JoinOp::getOperationName(), ValueRange(),
                       op->getResultTypes());
  state.getOrAddProperties<JoinOp::Properties>().binders = op.getBinders();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *join = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), join->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  for (Region &region : llvm::drop_begin(join->getRegions())) {
    Block &entry = region.front();
    entry.eraseArguments(0, targets);
    if (auto marker = dyn_cast<MayLoopOp>(entry.front()))
      rewriter.eraseOp(marker);
  }
  rewriter.replaceOp(op, join->getResults());
}

// A join region no jump reaches goes with its token and its binders; a
// group left with none is its body.
std::optional<Edit> egraph::DeadJoinRegions::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(someRegionUnreached(op));
}

void egraph::DeadJoinRegions::rewrite(JoinOp op, RewriterBase &rewriter) {
  (void)unreached(rewriter, op);
}

std::optional<Edit> egraph::DeadLoopRegions::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(someRegionUnreached(op));
}

void egraph::DeadLoopRegions::rewrite(LoopOp op, RewriterBase &rewriter) {
  (void)unreached(rewriter, op);
}

// A join region of an idr.join reached by one jump, the body's own end,
// runs there: its block takes the jump's place, the jump's arguments its
// parameters, and the region, now empty, goes.
std::optional<Edit> egraph::InlineSingleJump::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(static_cast<bool>(singleJump(op)));
}

void egraph::InlineSingleJump::rewrite(JoinOp op, RewriterBase &rewriter) {
  JumpOp jump = singleJump(op);
  if (!jump)
    return;
  Region *target = op.getTarget(cast<BlockArgument>(jump.getTarget()));
  SmallVector<Value> args(jump.getArgs());
  Block &from = target->front();
  rewriter.eraseOp(jump);
  rewriter.mergeBlocks(&from, &op.getBody().front(), args);
  (void)unreached(rewriter, op);
}

// A parameter its join region never reads goes, with every jump's argument
// for it.
std::optional<Edit> egraph::DeadJoinParameters::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(someParameterUnread(op));
}

void egraph::DeadJoinParameters::rewrite(JoinOp op, RewriterBase &rewriter) {
  (void)unread(rewriter, op);
}

std::optional<Edit> egraph::DeadLoopParameters::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(someParameterUnread(op));
}

void egraph::DeadLoopParameters::rewrite(LoopOp op, RewriterBase &rewriter) {
  (void)unread(rewriter, op);
}

} // namespace idr
