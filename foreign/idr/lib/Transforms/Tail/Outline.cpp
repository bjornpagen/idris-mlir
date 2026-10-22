// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: code moved into a function of its own. A function the pass
// makes stands beside the one its code comes from, with that one's facts,
// binding the index variables in scope where the code was; it takes what
// the code reads, then the component's lifetimes, and states where each
// scoped value it takes or gives lives as it is made, before any call of
// it is built, so no function made names a position it does not have and
// each call of one passes the lifetimes as operands.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

IndexArgsAttr concatArgs(MLIRContext *ctx, IndexArgsAttr a, IndexArgsAttr b) {
  llvm::SmallVector<families::TermNode> nodes(a.getTerms());
  llvm::append_range(nodes, b.getTerms());
  return IndexArgsAttr::get(ctx, nodes, a.getCount() + b.getCount());
}

llvm::SmallVector<families::Sort> scopeSorts(Region *region) {
  llvm::SmallVector<Region *> path;
  for (; region; region = region->getParentRegion())
    path.push_back(region);
  llvm::SmallVector<families::Sort> sorts;
  for (Region *at : llvm::reverse(path))
    if (auto binder = dyn_cast<ErasedBinderOpInterface>(at->getParentOp()))
      llvm::append_range(sorts, binder.getBoundSorts(*at));
  return sorts;
}

// Each value in scope at `first` is met once, and kept when an op of its
// block from `first` on, or one inside such an op, reads it: so nothing is
// counted twice and no set of values is kept.
llvm::SmallVector<Value> liveIns(Operation *first) {
  Block *block = first->getBlock();
  auto readByRest = [&](Operation *user) {
    Operation *top = block->findAncestorOpInBlock(*user);
    return top && !top->isBeforeInBlock(first);
  };
  llvm::SmallVector<Value> in;
  forEachInScope(first, [&](Value value) {
    if (llvm::any_of(value.getUsers(), readByRest))
      in.push_back(value);
  });
  return in;
}

llvm::SmallVector<Value> withoutLifetimes(llvm::ArrayRef<Value> values) {
  return llvm::to_vector(llvm::make_filter_range(
      values, [](Value value) { return !isa<LifetimeType>(value.getType()); }));
}

// A function the pass makes beside `owner`: owner's facts (its row, what
// Idris proved of its loops), the index binders of the scope its code comes
// from, and a signature of its own: the values `takes`, none a lifetime,
// then owner's lifetimes, the component's, giving `results`. Where each
// scoped parameter and result lives is stated as it is made, before any
// call of it is built, at the place among its own lifetimes of the one
// owner's statement names: a value taken, where the op that made it says;
// a result, `resultsIn`'s lifetime at its position. Owner's bounds between
// its lifetimes hold between the same lifetimes here. Its row and
// per-parameter record are the writer's to make exact; what owner gave back
// names owner's positions and goes. A value taken or given that lives in a
// lifetime ending with owner's call is one the decide step keeps out of a
// function that runs a call on frames, so meeting one is its invariant
// broken.
FailureOr<Made> Component::makeFunction(FuncOp owner, llvm::StringRef kind,
                                        llvm::ArrayRef<Value> takes, TypeRange results,
                                        llvm::ArrayRef<Value> resultsIn,
                                        llvm::ArrayRef<families::Sort> binders) {
  MLIRContext *ctx = owner.getContext();
  llvm::SmallVector<BlockArgument> ownLifetimes = lifetimesOf(owner);
  auto first = static_cast<std::uint32_t>(takes.size());
  auto parameterFor = [&](Value lifetime) -> std::optional<std::uint32_t> {
    std::optional<unsigned> place = lifetime ? placeOf(lifetime, owner) : std::nullopt;
    return place ? std::optional<std::uint32_t>(first + *place) : std::nullopt;
  };
  llvm::SmallVector<LivesIn> parameters, scopedResults;
  llvm::SmallVector<Outlives> outlives;
  for (auto [index, value] : llvm::enumerate(takes)) {
    if (!freedBy(value.getType(), Release::Scoped))
      continue;
    std::optional<std::uint32_t> in = parameterFor(lifetimes::statedLifetime(value));
    if (!in)
      return owner.emitOpError(
          "internal error: an invariant of idr-lifetimes is broken (idr-frames): a function "
          "that runs a call on frames states nothing but in its own lifetimes and the "
          "per-level ones directly around such calls, but code that runs after one reads a "
          "value of another");
    parameters.push_back({static_cast<std::uint32_t>(index), *in});
  }
  for (auto [index, type] : llvm::enumerate(results)) {
    if (!freedBy(type, Release::Scoped))
      continue;
    std::optional<std::uint32_t> in = parameterFor(resultsIn[index]);
    if (!in)
      return owner.emitOpError(
          "internal error: an invariant of idr-lifetimes is broken (idr-frames): what a "
          "function gives at a tail lives in its own lifetimes, but code that runs after a call "
          "on frames gives a value of another");
    scopedResults.push_back({static_cast<std::uint32_t>(index), *in});
  }
  Block &ownEntry = owner.getBody().front();
  if (LivesInAttr lives = owner.getLivesInAttr())
    for (const Outlives &bound : lives.getBounds())
      outlives.push_back({*parameterFor(ownEntry.getArgument(bound.longer)),
                          *parameterFor(ownEntry.getArgument(bound.shorter))});

  llvm::SmallVector<Type> inputs =
      llvm::map_to_vector(takes, [](Value value) { return value.getType(); });
  for (BlockArgument lifetime : ownLifetimes)
    inputs.push_back(lifetime.getType());
  auto fn = cast<FuncOp>(owner->cloneWithoutRegions());
  fn.setSymNameAttr(StringAttr::get(ctx, owner.getSymName() + "." + kind));
  fn.setFunctionTypeAttr(TypeAttr::get(FunctionType::get(ctx, inputs, results)));
  fn.setArgAttrsAttr(nullptr);
  fn.setResAttrsAttr(nullptr);
  fn.setUntouchedAttr(nullptr);
  fn.setBoundedAttr(nullptr);
  fn.setLivesInAttr(parameters.empty() && scopedResults.empty() && outlives.empty()
                        ? LivesInAttr()
                        : LivesInAttr::get(ctx, parameters, scopedResults, outlives));
  fn.setGivenBackAttr(nullptr);
  fn.setBindersAttr(binders.empty() ? IndexBindersAttr() : IndexBindersAttr::get(ctx, binders));
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : inputs)
    entry->addArgument(input, owner.getLoc());
  symbols.insert(fn, std::next(owner->getIterator()));

  Made out{fn, llvm::to_vector(takes)};
  llvm::append_range(out.args, ownLifetimes);
  return out;
}

// The ops of `first`'s block from `first` on moved into a function of
// their own, which takes `params` (values `first`'s code receives) and
// then what the code reads, and gives what the block's terminator gives,
// each scoped value where it goes; in their place a tail call of it, whose
// results the terminator gives.
FailureOr<CallOp> Component::outline(FuncOp owner, unsigned row, Operation *first,
                                     ValueRange params, llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  Block *block = first->getBlock();
  Operation *terminator = block->getTerminator();
  llvm::SmallVector<Value> read(params);
  for (Value value : liveIns(first))
    if (!llvm::is_contained(params, value))
      read.push_back(value);
  llvm::SmallVector<Value> takes = withoutLifetimes(read);
  llvm::SmallVector<Value> resultsIn;
  for (unsigned at = 0, given = terminator->getNumOperands(); at < given; ++at)
    resultsIn.push_back(givenIn(terminator, at));
  llvm::SmallVector<families::Sort> binders = scopeSorts(block->getParent());
  FailureOr<Made> moved =
      makeFunction(owner, kind, takes, terminator->getOperandTypes(), resultsIn, binders);
  if (failed(moved))
    return failure();
  FuncOp fn = moved->fn;
  Block *entry = &fn.getBody().front();

  // The code moves, so the ops the pass recorded stay the ops they are.
  entry->getOperations().splice(entry->end(), block->getOperations(), first->getIterator(),
                                terminator->getIterator());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, terminator->getLoc(), terminator->getOperands());
  for (auto [value, arg] : llvm::zip(takes, entry->getArguments()))
    rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
      return fn->isProperAncestor(use.getOwner());
    });
  llvm::SmallVector<Value> lifetimesRead = llvm::to_vector(llvm::make_filter_range(
      read, [](Value value) { return isa<LifetimeType>(value.getType()); }));
  if (failed(adoptLifetimes(owner, fn, lifetimesRead)))
    return failure();

  rewriter.setInsertionPoint(terminator);
  auto call = CallOp::create(rewriter, terminator->getLoc(), fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             moved->args, TailKind::tail);
  rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(call.getResults()); });
  made.push_back(call);
  functions.push_back({fn, row});
  return call;
}

} // namespace idr::tail::frames
