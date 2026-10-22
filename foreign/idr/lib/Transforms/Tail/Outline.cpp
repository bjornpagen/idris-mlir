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
#include "idr/IR/Lifetimes/Loans.h"

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

namespace {

// Fails, having reported it, where one of `reads`, made outside the code
// that moves, reads an alias of a loan that no view makes (a region chose
// it, or an op of upstream's gives it as its operand's alias) and the
// loan's lifetime ends before that code runs. Such an alias is the run's
// choice, not a function of the holder, so it cannot be lent again and is
// handed over as it is: sound where the loan's lifetime outlives the call
// the code continues, as each of `owner`'s lifetimes does, every function
// on the stack taking them, or where the loan is of static data, which
// outlives every lifetime; only the other loans' aliases are followed. The
// lifetime pass keeps a holder out of a lifetime that ends before a use of
// its loan, so meeting one is its invariant broken.
LogicalResult handedOver(FuncOp owner, llvm::ArrayRef<OpOperand *> reads) {
  WalkResult walked = owner.walk([&](CarrierOp loan) {
    if (freedBy(loan.getValue().getType(), Release::Static) || placeOf(loan.getLifetime(), owner))
      return WalkResult::advance();
    llvm::SmallVector<OpOperand *, 4> starts = llvm::map_to_vector(
        loan.getResult().getUses(), [](OpOperand &use) { return &use; });
    OpOperand *met = nullptr;
    lifetimes::forEachLoanUse(
        starts,
        [&](Value alias) {
          for (OpOperand *read : reads)
            if (!met && read->get() == alias)
              met = read;
        },
        [](OpOperand &, lifetimes::LoanUse) {});
    if (!met)
      return WalkResult::advance();
    InFlightDiagnostic error = met->getOwner()->emitOpError(
        "internal error: an invariant of idr-lifetimes is broken (idr-frames): code that runs "
        "after a call on frames reads a loan's alias only under a lifetime that outlives the "
        "call, but this op reads one no view makes, lent under a lifetime that ends before "
        "that code runs");
    error.attachNote(loan.getLoc()) << "lent here";
    return WalkResult::interrupt();
  });
  return failure(walked.wasInterrupted());
}

} // namespace

// A loan costs nothing at run time and a view of one is a function of its
// operands, so the code reads the holder and lends it again, where an
// alias handed to the function would be plain data no rule follows. Made
// again before the code, a loan stands under a lifetime the function takes:
// a view of one of the component's lifetimes, which every function on the
// stack takes; the per-level lifetime around a call, which the call's rest
// reopens; or, for static data, which outlives every lifetime, the owner's
// activation, whose place the function's own takes (adoptLifetimes). Its
// holder lives in that lifetime, at its place among the function's or in
// the package, or is static, which the function made of the code holds it
// to. Each loan and view is made again once however many ops read it, in
// the order the originals were made.
FailureOr<Operation *> lendAgain(Operation *first) {
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
  // Every read, made outside the code, of a tensor or a buffer at no grade,
  // the only type a loan's alias has: of a loan or a view of one, which is
  // lent again; or of another such value, which a loan's alias no view
  // makes may be.
  llvm::SmallVector<OpOperand *, 8> reads, others;
  for (Operation *op = first; op; op = op->getNextNode())
    op->walk([&](Operation *nested) {
      for (OpOperand &use : nested->getOpOperands()) {
        Value value = use.get();
        if (!isa<TensorType, BaseMemRefType>(value.getType()) || moves(value))
          continue;
        (lifetimes::loanOf(value) ? reads : others).push_back(&use);
      }
    });
  if (!others.empty() && failed(handedOver(first->getParentOfType<FuncOp>(), others)))
    return failure();
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
    // A counted holder is lent only in a region the lifetime pass opens,
    // around every use of the loan's aliases and over no call on frames, so
    // no code that moves around such a call reads its loan from outside.
    assert(!freedBy(loan.getValue().getType(), Release::Counted) &&
           "no code frames move reads a counted value's loan from outside it");
    // What the alias stands on, from itself up to the loan and the view
    // the loan is lent under, where that is taken of another lifetime.
    llvm::SmallVector<Operation *, 4> standsOn;
    for (Value at = alias; at != loan.getResult();) {
      auto view = at.getDefiningOp<ViewLikeOpInterface>();
      standsOn.push_back(view.getOperation());
      at = view.getViewSource();
    }
    standsOn.push_back(loan.getOperation());
    if (auto forget = loan.getLifetime().getDefiningOp<LifetimeForgetOp>())
      standsOn.push_back(forget.getOperation());
    for (Operation *op : llvm::reverse(standsOn)) {
      if (again.contains(op->getResult(0)))
        continue;
      assert(isPure(op) && "a loan, the view it is lent under and a view of a loan are pure, so "
                           "made again they mean what they meant");
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
// their own, each loan they read from outside lent again first, which
// takes `params` (values `first`'s code receives) and then what the code
// reads, and gives what the block's terminator gives, each scoped value
// where it goes; in their place a tail call of it, whose results the
// terminator gives.
FailureOr<CallOp> Component::outline(FuncOp owner, unsigned row, Operation *first,
                                     ValueRange params, llvm::StringRef kind) {
  MLIRContext *ctx = owner.getContext();
  FailureOr<Operation *> lent = lendAgain(first);
  if (failed(lent))
    return failure();
  first = *lent;
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
