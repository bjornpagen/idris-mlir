// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rule of case-of-case: a match on another's one result has
// its cases made the join regions of one flat idr.join in its place, and
// each arm of the producer takes a copy of the dispatch where that costs
// less than sharing the one after the producer, as the extracted e-graph
// says per arm. The join points are built by the one construction of them
// (idr/Transforms/Joins.h).

#include "Rules.h"

#include "idr/IR/Control/Control.h"
#include "idr/IR/Control/Stated.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

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
// the terms of the join region's binders. Its regions bind the consumer's
// positions, so it states `bindings`, the consumer's entries for them.
void dispatch(RewriterBase &rewriter, DataMatchOp consumer, Value scrutinee,
              const joins::Targets &targets, ValueRange bindings) {
  Location loc = consumer.getLoc();
  SmallVector<Tag> tags = llvm::map_to_vector(
      consumer.getCases(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; });
  auto copy =
      DataMatchOp::create(rewriter, loc, TypeRange(), scrutinee, consumer.getForwarded(), tags);
  copy.getOutersMutable().assign(bindings);
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
  // What the consumer states, read before its regions move: the join
  // point's op gives its results and binds, in each join region, what that
  // region bound in the consumer, so it states the same lifetimes, results
  // first; a copy of the dispatch binds the consumer's positions.
  unsigned results = scopedResultCount(consumer);
  SmallVector<Value> bindings(consumer.getOuters().drop_front(results));
  SmallVector<Value> stated(consumer.getOuters().take_front(results));
  for (Region &region : consumer->getRegions())
    if (!region.empty())
      for (BlockArgument arg : region.getArguments())
        if (scoped(arg))
          stated.push_back(bindings[*consumer.getBindingEntry(arg)]);
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
  rewriter.modifyOpInPlace(group.outermost, [&] {
    cast<JoinOp>(group.outermost).getOutersMutable().assign(stated);
  });
  rewriter.replaceAllUsesWith(consumer->getResults(), group.outermost->getResults());
  rewriter.moveOpBefore(producer, group.body, group.body->end());
  for (unsigned arm : arms) {
    auto yield = cast<YieldOp>(producer->getRegion(arm).front().getTerminator());
    Value value = yield.getResults().front();
    rewriter.eraseOp(yield);
    rewriter.setInsertionPointToEnd(&producer->getRegion(arm).front());
    dispatch(rewriter, shell, value, group.targets, bindings);
  }
  rewriter.setInsertionPointToEnd(group.body);
  if (llvm::any_of(producer->getRegions(), yields))
    dispatch(rewriter, shell, producer->getResult(0), group.targets, bindings);
  else
    ub::UnreachableOp::create(rewriter, producer.getLoc());
  rewriter.eraseOp(shell);
  rewriter.eraseOp(consumer);
}

} // namespace idr
