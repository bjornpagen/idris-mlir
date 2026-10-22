// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rewrites of the control-flow ops, which the specification declares as
// skeleton rules of the e-graph pass (IdrisMLIR.Spec.Control.Rules): one-way,
// since a match or a join point is an op of the skeleton, never a pure
// value. Each `decide` reads the extracted e-graph and the root, and what it
// chose (a region, the cases kept, the arms a dispatch goes into) rides in
// its Rewrite; `rewrite` carries that out between the engine's two rounds,
// on the root as it then is, checking that the shape it rewrites still
// stands and leaving the root as it is where it does not.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ops/Rules.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstddef>
#include <cstdint>
#include <optional>

// What each stage implies (holdsAt among it), printed from the
// specification.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;
using namespace idr::egraph;

namespace idr {

namespace {

// Whether `region` gives its op's results: it ends in a yield.
bool yields(Region &region) {
  return !region.empty() && isa<YieldOp>(region.front().getTerminator());
}

// `op` made again with results of `types`, its operands, properties and
// regions moved over, at the rewriter's insertion point.
Operation *withResults(RewriterBase &rewriter, Operation *op, TypeRange types) {
  rewriter.setInsertionPoint(op);
  OperationState state(op->getLoc(), op->getName(), op->getOperands(), types, op->getAttrs(),
                       /*successors=*/{}, /*regions=*/{});
  state.propertiesAttr = op->getPropertiesAsAttribute();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *fresh = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), fresh->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  return fresh;
}

// Removes the results of `op` that `keep` leaves out, from the op and from
// each of its regions' yields.
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
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      types.push_back(result.getType());
  Operation *fresh = withResults(rewriter, op, types);
  unsigned next = 0;
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      rewriter.replaceAllUsesWith(result, fresh->getResult(next++));
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
void unused(RewriterBase &rewriter, Operation *op) {
  llvm::BitVector keep(op->getNumResults());
  for (OpResult result : op->getResults())
    if (!result.use_empty())
      keep.set(result.getResultNumber());
  if (!keep.all())
    keepResults(rewriter, op, keep);
}

// A join region no jump reaches goes with its token and its binders; a
// group left with none is its body, whose yield gives the results.
template <typename Group>
void unreached(RewriterBase &rewriter, Group op) {
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
    return;
  if (dead.all()) {
    Block &body = op.getBody().front();
    auto yield = dyn_cast<YieldOp>(body.getTerminator());
    body.eraseArguments(0, body.getNumArguments());
    rewriter.inlineBlockBefore(&body, op);
    if (yield) {
      rewriter.replaceOp(op, yield.getResults());
      rewriter.eraseOp(yield);
      return;
    }
    // The body jumps out or never ends: nothing reaches what follows.
    eraseAfter(rewriter, op);
    rewriter.eraseOp(op);
    return;
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
  OperationState state(op.getLoc(), op->getName().getStringRef(), op->getOperands(),
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
}

// A parameter no op of its join region uses goes, with every jump's
// argument for it.
template <typename Group>
void unread(RewriterBase &rewriter, Group op) {
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
    }
  }
}

// The idr.data.con that made the chosen form of `value`, seen through a
// cast that only changes its type (a yield gives a match's results at
// their own types, so a constructor an arm built leaves it cast); a cast
// of a cast is one, so one step suffices. Null where none did.
DataConOp constructorOf(Value value, const OperandFacts &facts) {
  Operation *origin = facts.origin(value);
  if (auto cast = dyn_cast_or_null<DataReindexOp>(origin))
    origin = facts.origin(cast.getValue());
  return dyn_cast_or_null<DataConOp>(origin);
}

// Whether `value` has a known constructor in what the e-graph chose for
// it: a constant constructor, or a value an idr.data.con made.
bool knownConstructor(Value value, const OperandFacts &facts) {
  return isa_and_nonnull<ConAttr>(facts.constant(value)) ||
         static_cast<bool>(constructorOf(value, facts));
}

// The producer of `consumer`: the idr.data.match just before it whose one
// result is the consumer's scrutinee and nothing else's, and which makes
// none of the values the consumer forwards. Null where there is none.
DataMatchOp producerOf(DataMatchOp consumer) {
  auto producer = dyn_cast_or_null<DataMatchOp>(consumer->getPrevNode());
  if (!producer || producer->getNumResults() != 1 ||
      consumer.getScrutinee() != producer->getResult(0) ||
      !producer->getResult(0).hasOneUse() ||
      llvm::any_of(consumer.getForwarded(),
                   [&](Value value) { return value.getDefiningOp() == producer.getOperation(); }))
    return DataMatchOp();
  return producer;
}

// The match on `scrutinee` whose cases all jump, one per region of
// `consumer`, each to its member through `targets`, passing what the
// region binds: the dispatch case-of-case copies into an arm. A case
// binds its constructor's index variables at the copy's depth, so its
// types are the consumer's renumbered there, and the jump passes them as
// the terms of the join region's binders.
void dispatch(RewriterBase &rewriter, DataMatchOp consumer, Value scrutinee,
              const joins::Targets &targets, Value outer) {
  Location loc = consumer.getLoc();
  SmallVector<Tag> tags = llvm::map_to_vector(
      consumer.getCases(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; });
  auto copy =
      DataMatchOp::create(rewriter, loc, TypeRange(), scrutinee, consumer.getForwarded(), tags);
  if (outer)
    copy.getOuterMutable().assign(outer);
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

// The region a constant literal takes.
Region *literalTaken(LitMatchOp op, Attribute value) {
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

//===----------------------------------------------------------------------===//
// Identical regions
//===----------------------------------------------------------------------===//

// Whether a region reads none of its arguments.
bool readsNothingBound(Region &region) {
  return llvm::all_of(region.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
}

// Whether two regions that read none of their arguments do the same thing.
bool sameBody(Region &a, Region &b) {
  Block &x = a.front(), &y = b.front();
  if (x.getOperations().size() != y.getOperations().size())
    return false;
  // Values each body makes, matched as the comparison meets them: a
  // comparison's own scratch, gone when it returns.
  llvm::DenseMap<Value, Value> same;
  return llvm::all_of_zip(x, y, [&](Operation &l, Operation &r) {
    return OperationEquivalence::isEquivalentTo(
        &l, &r,
        [&](Value lv, Value rv) { return success(lv == rv || same.lookup(lv) == rv); },
        [&](Value lv, Value rv) { same[lv] = rv; }, OperationEquivalence::IgnoreLocations);
  });
}

// The operations a region holds, hashed as sameBody compares them but for
// their regions, so only regions of one shape are compared body to body;
// equal shapes still are, since the hash can collide.
llvm::hash_code shape(Region &region) {
  return llvm::hash_combine_range(llvm::map_range(region.front(), [](Operation &op) {
    return OperationEquivalence::computeHash(&op, OperationEquivalence::ignoreHashValue,
                                             OperationEquivalence::ignoreHashValue,
                                             OperationEquivalence::IgnoreLocations);
  }));
}

// What the rule keeps of `op`: the region that is the default afterwards,
// by its number, the default's own 0, so a case that takes the default's
// place is written as the default is; then the index of each case kept.
// None where no case goes.
//
// A case that does what a running default does, reading nothing it binds,
// is left to the default. With no default, the first case some other case
// repeats becomes it, the others like it going too, where it reads nothing
// it binds, binds no index variable and assumes no equation, so its body
// means the same in the scope around the match.
std::optional<SmallVector<unsigned>> identicalRegions(MatchOpInterface op) {
  Region &given = op.getDefaultRegion();
  auto binders = dyn_cast<ErasedBinderOpInterface>(op.getOperation());
  auto movable = [&](Region &region) {
    return readsNothingBound(region) &&
           (!binders || (binders.getBoundSorts(region).empty() && !binders.getRefinement(region)));
  };
  Region *fallback = nullptr;
  if (!given.empty()) {
    if (readsNothingBound(given))
      fallback = &given;
  } else {
    llvm::DenseMap<llvm::hash_code, SmallVector<unsigned, 2>> buckets;
    for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
      if (movable(op.getCaseRegion(i)))
        buckets[shape(op.getCaseRegion(i))].push_back(i);
    std::optional<unsigned> first;
    for (auto &bucket : buckets) {
      ArrayRef<unsigned> ids = bucket.second;
      for (unsigned a = 0; a < ids.size() && (!first || ids[a] < *first); ++a)
        if (llvm::any_of(ids.drop_front(a + 1), [&](unsigned b) {
              return sameBody(op.getCaseRegion(ids[a]), op.getCaseRegion(b));
            })) {
          first = ids[a];
          break;
        }
    }
    if (first)
      fallback = &op.getCaseRegion(*first);
  }
  if (!fallback)
    return std::nullopt;
  SmallVector<unsigned> kept{fallback->getRegionNumber()};
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i) {
    Region &region = op.getCaseRegion(i);
    if (&region != fallback && !(movable(region) && sameBody(region, *fallback)))
      kept.push_back(i);
  }
  if (kept.size() == op.getNumCases() + 1)
    return std::nullopt;
  return kept;
}

//===----------------------------------------------------------------------===//
// Yielded fields
//===----------------------------------------------------------------------===//

// The constructors the regions of `op` that yield give as `result`, when
// the result is one to split: a data value read only through its fields,
// so of a type refined to one constructor, which every region that yields
// builds there of fields of one list of types, for the yield alone.
std::optional<SmallVector<DataConOp>> yieldedConstructors(OpResult result) {
  if (!isMatchable(result.getType()) || result.use_empty() ||
      !llvm::all_of(result.getUsers(), llvm::IsaPred<DataFieldOp>))
    return std::nullopt;
  SmallVector<DataConOp> built;
  for (Region &region : result.getOwner()->getRegions()) {
    if (!yields(region))
      continue;
    auto yield = cast<YieldOp>(region.front().getTerminator());
    Value given = yield->getOperand(result.getResultNumber());
    auto con = given.getDefiningOp<DataConOp>();
    if (!con || con->getBlock() != yield->getBlock() || !given.hasOneUse() ||
        (!built.empty() &&
         !llvm::equal(built.front().getFields().getTypes(), con.getFields().getTypes())))
      return std::nullopt;
    built.push_back(con);
  }
  if (built.empty())
    return std::nullopt;
  return built;
}

// Whether the holds of `op`'s function are still undecided: once they are,
// each field's is fixed at its constructor's, and the constructor stays
// where it was built.
bool holdsUndecided(Operation *op) {
  Stage stage = op->getParentOfType<FuncOp>().getProgram().getStage();
  return holdsAt[static_cast<std::size_t>(stage)] == StageHolds::Undecided;
}

//===----------------------------------------------------------------------===//
// Case-of-case
//===----------------------------------------------------------------------===//

// What a copy of the consumer's dispatch costs in an arm that yields
// `value`: one jump where the e-graph knows its constructor, since the
// copy folds there; otherwise the whole dispatch, its test and a jump per
// region.
Cost copyCost(Value value, unsigned regions, const OperandFacts &facts) {
  return knownConstructor(value, facts) ? Cost::of(1) : Cost::of(1 + regions);
}

// Whether an arm shares the dispatch after the producer with other arms,
// or would keep it alive for itself alone.
enum class Sharing : std::uint8_t { WithOthers, Alone };

// What sharing the dispatch after the producer costs an arm: its yield
// into it and the test it runs; and, for an arm alone in sharing it, the
// shared dispatch itself, which no arm needs once every arm has its copy.
Cost shareCost(unsigned regions, Sharing sharing) {
  Cost own = Cost::of(2);
  return sharing == Sharing::Alone ? own.plus(Cost::of(1 + regions)) : own;
}

} // namespace

//===----------------------------------------------------------------------===//
// The matches
//===----------------------------------------------------------------------===//

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
  Region *taken = literalTaken(op, facts.constant(op.getScrutinee()));
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
  return rewriteIf(llvm::any_of(op.getCaseRegions(), [&](Region &region) {
    return llvm::any_of(scrutinee.getUses(), [&](OpOperand &use) { return inside(region, use); });
  }));
}

void egraph::LiteralInCase::rewrite(LitMatchOp op, const Rewrite &, RewriterBase &rewriter) {
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

// Identical regions merge into the default.
std::optional<Edit> egraph::IdenticalRegions::decide(MatchOpInterface op, const OperandFacts &) {
  std::optional<SmallVector<unsigned>> kept = identicalRegions(op);
  if (!kept)
    return std::nullopt;
  return Edit(Rewrite{std::move(*kept)});
}

void egraph::IdenticalRegions::rewrite(MatchOpInterface op, const Rewrite &chosen,
                                       RewriterBase &rewriter) {
  // Recomputed on the root as it now is, since what it compares is the
  // regions' bodies, which an earlier rewrite may have changed.
  std::optional<SmallVector<unsigned>> kept = identicalRegions(op);
  if (!kept || *kept != chosen.chosen)
    return;
  unsigned fallback = kept->front();
  Region *region = fallback == 0 ? &op.getDefaultRegion() : &op.getCaseRegion(fallback - 1);
  (void)op.keepCases(rewriter, ArrayRef<unsigned>(*kept).drop_front(), region);
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

// A result that every region that yields builds as one constructor, and
// that is only ever read through its fields, is yielded as the
// constructor's fields, and the constructor is built once after the match,
// where each read of a field folds to the field the regions gave. A field
// is then the value its region built it of, a linear one the thread it
// was, never a read of a value the match built: a linear array passed back
// beside a value stays the one buffer each region wrote. Only while the
// holds are undecided.
std::optional<Edit> egraph::YieldedFields::decide(MatchOpInterface op, const OperandFacts &) {
  if (!holdsUndecided(op))
    return std::nullopt;
  for (OpResult result : op->getResults())
    if (yieldedConstructors(result))
      return Edit(Rewrite{{result.getResultNumber()}});
  return std::nullopt;
}

void egraph::YieldedFields::rewrite(MatchOpInterface op, const Rewrite &chosen,
                                    RewriterBase &rewriter) {
  unsigned index = chosen.chosen.front();
  if (index >= op->getNumResults())
    return;
  OpResult result = op->getResult(index);
  std::optional<SmallVector<DataConOp>> built = yieldedConstructors(result);
  if (!built)
    return;
  TypeRange fieldTypes = built->front().getFields().getTypes();
  SmallVector<Type> types;
  for (auto [i, type] : llvm::enumerate(op->getResultTypes()))
    if (i != index)
      types.push_back(type);
  unsigned kept = static_cast<unsigned>(types.size());
  llvm::append_range(types, fieldTypes);
  Type type = result.getType();
  Location loc = result.getLoc();
  // Each yield gives its constructor's fields in its place.
  for (DataConOp con : *built) {
    auto yield = cast<YieldOp>(con->getBlock()->getTerminator());
    SmallVector<Value> given;
    for (auto [i, value] : llvm::enumerate(yield.getResults()))
      if (i != index)
        given.push_back(value);
    llvm::append_range(given, con.getFields());
    rewriter.setInsertionPoint(yield);
    rewriter.replaceOpWithNewOp<YieldOp>(yield, given);
    rewriter.eraseOp(con);
  }
  Operation *fresh = withResults(rewriter, op, types);
  rewriter.setInsertionPointAfter(fresh);
  Value rebuilt =
      DataConOp::create(rewriter, loc, type, fresh->getResults().drop_front(kept)).getResult();
  SmallVector<Value> replacements(fresh->getResults().take_front(kept));
  replacements.insert(replacements.begin() + index, rebuilt);
  rewriter.replaceOp(op, replacements);
}

// Case-of-case: the consumer's regions become the join regions of one flat
// idr.join in its place, and the producer moves into its body. Each arm
// takes a copy of the consumer's dispatch where that costs less than
// sharing the one after the producer: where the e-graph knows the arm's
// constructor the copy folds to a jump, and the last arm left to share
// would keep the shared dispatch alive for itself alone. The other arms
// still yield, and one dispatch after the producer serves them. Each copy
// moves a dispatch deeper, so case-of-case ends by construction; the
// growth is one jump per case per arm.
std::optional<Edit> egraph::CaseOfCase::decide(DataMatchOp consumer, const OperandFacts &facts) {
  DataMatchOp producer = producerOf(consumer);
  if (!producer)
    return std::nullopt;
  unsigned regions = static_cast<unsigned>(
      llvm::count_if(consumer->getRegions(), [](Region &region) { return !region.empty(); }));
  SmallVector<std::pair<unsigned, Value>> arms;
  for (Region &region : producer->getRegions())
    if (yields(region))
      arms.emplace_back(region.getRegionNumber(),
                        cast<YieldOp>(region.front().getTerminator()).getResults().front());
  if (llvm::none_of(arms, [&](const auto &arm) { return knownConstructor(arm.second, facts); }))
    return std::nullopt;
  Rewrite chosen;
  SmallVector<unsigned> sharing;
  for (auto [region, value] : arms) {
    if (copyCost(value, regions, facts) < shareCost(regions, Sharing::WithOthers))
      chosen.chosen.push_back(region);
    else
      sharing.push_back(region);
  }
  if (sharing.size() == 1) {
    Value value = llvm::find_if(arms, [&](const auto &arm) {
                    return arm.first == sharing.front();
                  })->second;
    if (copyCost(value, regions, facts) < shareCost(regions, Sharing::Alone))
      chosen.chosen.push_back(sharing.front());
  }
  llvm::sort(chosen.chosen);
  return Edit(std::move(chosen));
}

void egraph::CaseOfCase::rewrite(DataMatchOp consumer, const Rewrite &chosen,
                                 RewriterBase &rewriter) {
  DataMatchOp producer = producerOf(consumer);
  if (!producer)
    return;
  // The arms the decision chose that still yield, as the root now is.
  SmallVector<unsigned> arms;
  for (unsigned arm : chosen.chosen)
    if (arm < producer->getNumRegions() && yields(producer->getRegion(arm)))
      arms.push_back(arm);
  if (arms.empty())
    return;
  Value outer = consumer.getOuter();
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
  auto shell = DataMatchOp::create(rewriter, consumer.getLoc(), TypeRange(),
                                   consumer.getScrutinee(), consumer.getForwarded(), tags);
  for (auto [from, into] : llvm::zip_equal(consumer->getRegions(), shell->getRegions()))
    if (!from.empty())
      rewriter.createBlock(&into, {}, from.getArgumentTypes(),
                           llvm::map_to_vector(from.getArguments(),
                                               [](Value arg) { return arg.getLoc(); }));
  rewriter.setInsertionPoint(consumer);
  joins::Group group = joins::build(rewriter, consumer.getLoc(), consumer->getResultTypes(),
                                    members, {});
  // The join regions bind what the consumer's regions bound, and give its
  // results: they live where the consumer said.
  if (outer)
    cast<JoinOp>(group.outermost).getOuterMutable().assign(outer);
  rewriter.replaceAllUsesWith(consumer->getResults(), group.outermost->getResults());
  rewriter.moveOpBefore(producer, group.body, group.body->end());
  for (unsigned arm : arms) {
    auto yield = cast<YieldOp>(producer->getRegion(arm).front().getTerminator());
    Value value = yield.getResults().front();
    rewriter.eraseOp(yield);
    rewriter.setInsertionPointToEnd(&producer->getRegion(arm).front());
    dispatch(rewriter, shell, value, group.targets, outer);
  }
  rewriter.setInsertionPointToEnd(group.body);
  if (llvm::any_of(producer->getRegions(), yields))
    dispatch(rewriter, shell, producer->getResult(0), group.targets, outer);
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

void egraph::DeadJoinResults::rewrite(JoinPointsOpInterface op, const Rewrite &,
                                      RewriterBase &rewriter) {
  unused(rewriter, op.getOperation());
}

// An idr.loop whose join regions never jump to its own op repeats nothing:
// it is an idr.join, its join regions' tokens dropped.
std::optional<Edit> egraph::LoopToJoin::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(llvm::none_of(op.getJoinRegions(), [&](Region &region) {
    return llvm::any_of(op.getTokens(region),
                        [](BlockArgument token) { return !token.use_empty(); });
  }));
}

void egraph::LoopToJoin::rewrite(LoopOp op, const Rewrite &, RewriterBase &rewriter) {
  rewriter.setInsertionPoint(op);
  OperationState state(op.getLoc(), JoinOp::getOperationName(), op->getOperands(),
                       op->getResultTypes());
  state.getOrAddProperties<JoinOp::Properties>().binders = op.getBinders();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *join = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), join->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  for (Region &region : llvm::drop_begin(join->getRegions()))
    region.front().eraseArguments(0, targets);
  rewriter.replaceOp(op, join->getResults());
}

// A join region no jump reaches goes with its token and its binders; a
// group left with none is its body.
std::optional<Edit> egraph::DeadJoinRegions::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(someRegionUnreached(op));
}

void egraph::DeadJoinRegions::rewrite(JoinOp op, const Rewrite &, RewriterBase &rewriter) {
  unreached(rewriter, op);
}

std::optional<Edit> egraph::DeadLoopRegions::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(someRegionUnreached(op));
}

void egraph::DeadLoopRegions::rewrite(LoopOp op, const Rewrite &, RewriterBase &rewriter) {
  unreached(rewriter, op);
}

// A join region of an idr.join reached by one jump, the body's own end,
// runs there: its block takes the jump's place, the jump's arguments its
// parameters, and the region, now empty, goes.
std::optional<Edit> egraph::InlineSingleJump::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(static_cast<bool>(singleJump(op)));
}

void egraph::InlineSingleJump::rewrite(JoinOp op, const Rewrite &, RewriterBase &rewriter) {
  JumpOp jump = singleJump(op);
  if (!jump)
    return;
  Region *target = op.getTarget(cast<BlockArgument>(jump.getTarget()));
  SmallVector<Value> args(jump.getArgs());
  Block &from = target->front();
  rewriter.eraseOp(jump);
  rewriter.mergeBlocks(&from, &op.getBody().front(), args);
  unreached(rewriter, op);
}

// A parameter its join region never reads goes, with every jump's argument
// for it.
std::optional<Edit> egraph::DeadJoinParameters::decide(JoinOp op, const OperandFacts &) {
  return rewriteIf(someParameterUnread(op));
}

void egraph::DeadJoinParameters::rewrite(JoinOp op, const Rewrite &, RewriterBase &rewriter) {
  unread(rewriter, op);
}

std::optional<Edit> egraph::DeadLoopParameters::decide(LoopOp op, const OperandFacts &) {
  return rewriteIf(someParameterUnread(op));
}

void egraph::DeadLoopParameters::rewrite(LoopOp op, const Rewrite &, RewriterBase &rewriter) {
  unread(rewriter, op);
}

} // namespace idr
