// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: code moved into a function of its own. A function the pass
// makes stands beside the one its code comes from, with that one's facts,
// binding the index variables in scope where the code was; it takes what
// the code reads (a loan's holder, never the loan, which the code lends
// again), then the component's lifetimes, and states where each
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
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>

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

// A loan costs nothing at run time and a view of one is a function of its
// operands, so the code reads the holder and lends it again, where an
// alias handed to the function would be plain data no rule follows. Only
// static data's loan is read from outside code that frames move: the
// lifetime pass stands every other loan on a span no call on frames is in,
// so such code holds every use of that loan's aliases or none. Static data
// outlives every lifetime, so its loan, made again before the code, stands
// under the owner's activation, a view, whose place the function's own
// takes (adoptLifetimes), and an alias of it no view makes (a region chose
// it, or an op of upstream's gives it as its operand's alias), which cannot
// be made again, is handed over as it is. Each loan and view is made again
// once however many ops read it, in the order the originals were made.
Operation *lendAgain(Operation *first) {
  Block *block = first->getBlock();
  // Whether `value` is made by the code: by one of its ops, or bound by a
  // region of one.
  auto moves = [&](Value value) {
    Operation *maker = isa<OpResult>(value)
                           ? value.getDefiningOp()
                           : cast<BlockArgument>(value).getOwner()->getParentOp();
    Operation *top = block->findAncestorOpInBlock(*maker);
    return top && !top->isBeforeInBlock(first);
  };
  // Every read, made outside the code, of a loan or a view of one: a tensor
  // or a buffer at no grade, the only type a loan's alias has.
  llvm::SmallVector<OpOperand *, 8> reads;
  for (Operation *op = first; op; op = op->getNextNode())
    op->walk([&](Operation *nested) {
      for (OpOperand &use : nested->getOpOperands()) {
        Value value = use.get();
        if (isa<TensorType, BaseMemRefType>(value.getType()) && !moves(value) &&
            lifetimes::loanOf(value))
          reads.push_back(&use);
      }
    });
  if (reads.empty())
    return first;

  OpBuilder b(first);
  IRMapping again;
  Operation *start = first;
  llvm::SmallVector<Operation *, 8> originals;
  for (OpOperand *read : reads) {
    Value alias = read->get();
    if (again.contains(alias))
      continue;
    CarrierOp loan = lifetimes::loanOf(alias);
    assert(freedBy(loan.getValue().getType(), Release::Static) &&
           "the lifetime pass stands every loan but static data's on a span no call on frames "
           "is in, so no other is read from outside code that frames move");
    // What the alias stands on, from itself up to the loan.
    llvm::SmallVector<Operation *, 4> standsOn;
    for (Value at = alias; at != loan.getResult();) {
      auto view = at.getDefiningOp<ViewLikeOpInterface>();
      standsOn.push_back(view.getOperation());
      at = view.getViewSource();
    }
    standsOn.push_back(loan.getOperation());
    for (Operation *op : llvm::reverse(standsOn)) {
      if (again.contains(op->getResult(0)))
        continue;
      assert(isPure(op) &&
             "a loan and a view of one are pure, so made again they mean what they meant");
      Operation *made = b.clone(*op, again);
      if (start == first)
        start = made;
      originals.push_back(op);
    }
  }
  for (OpOperand *read : reads)
    read->set(again.lookup(read->get()));
  // An original nothing reads now goes, each after what stands on it.
  for (Operation *op : llvm::reverse(originals))
    if (op->use_empty())
      op->erase();
  return start;
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
// names owner's positions and goes; what owner's extents say of a value it
// takes of owner's signature, or of a result, moves to its position. A
// value taken or given that lives in a lifetime ending with owner's call is
// one the decide step keeps out of a function that runs a call on frames,
// so meeting one is its invariant broken.
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

  // It takes what its call passes, in order: the values, then owner's
  // lifetimes.
  llvm::SmallVector<Value> args(takes);
  llvm::append_range(args, ownLifetimes);
  llvm::SmallVector<Type> inputs =
      llvm::map_to_vector(args, [](Value value) { return value.getType(); });

  // Its extents are owner's for what it holds of owner's signature. An
  // input that is a parameter of owner's keeps what owner says of it; one
  // owner's code made has no entry, its axes `?` and named by no term,
  // which its call meets, passing that very value: the less optimized
  // form, never a wrong one. It is the rest of owner's activation,
  // tail-called where owner's results are its own, so each result is
  // owner's at its position and keeps owner's entries. It binds owner's
  // binders first, then those of the ops around the code, and its call
  // passes owner's levels for them, so every term means in it what it
  // meant in owner.
  llvm::ArrayRef<families::Sort> ownBinders = owner.getBoundSorts(owner.getBody());
  assert(binders.size() >= ownBinders.size() &&
         llvm::equal(ownBinders, binders.take_front(ownBinders.size())) &&
         "a function made of owner's code binds owner's binders first");
  assert(results.size() == owner.getNumResults() &&
         llvm::all_of(llvm::zip_equal(results, owner.getResultTypes()),
                      [](auto pair) {
                        return unrestricted(std::get<0>(pair)) == unrestricted(std::get<1>(pair));
                      }) &&
         "a function made of owner's code gives what owner gives, each result at owner's carrier");
  auto ownersParameter = [&](Value value) -> std::optional<std::uint32_t> {
    auto parameter = dyn_cast<BlockArgument>(value);
    if (!parameter || parameter.getOwner() != &ownEntry)
      return std::nullopt;
    return parameter.getArgNumber();
  };
  llvm::SmallVector<std::optional<std::uint32_t>> fromInputs =
      llvm::map_to_vector(args, ownersParameter);
  llvm::SmallVector<std::optional<std::uint32_t>> fromResults;
  for (std::uint32_t at = 0, given = static_cast<std::uint32_t>(results.size()); at < given; ++at)
    fromResults.push_back(at);
  ExtentsAttr extents = extentsFrom(owner.getExtentsAttr(), fromInputs, fromResults);

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
  fn.setExtentsAttr(extents);
  Block *entry = new Block();
  fn.getBody().push_back(entry);
  for (Type input : inputs)
    entry->addArgument(input, owner.getLoc());
  symbols.insert(fn, std::next(owner->getIterator()));

  return Made{fn, std::move(args)};
}

// The ops of `first`'s block from `first` on moved into a function of
// their own, each loan they read from outside lent again first, which
// takes `params` (values `first`'s code receives) and then what the code
// reads, and gives what the block's terminator gives, each scoped value
// where it goes; in their place a tail call of it, whose results the
// terminator gives.
FailureOr<CallOp> Component::outline(FuncOp owner, unsigned row, Operation *first,
                                     ValueRange params, llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  first = lendAgain(first);
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
