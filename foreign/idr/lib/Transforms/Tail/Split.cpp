// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: a call to frame in the region of a per-level lifetime splits
// the region around it, so no lifetime outlives its region while the call
// runs: the region packs its lifetime before the call, and the call's rest
// reopens it.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Remake.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

// A call to frame directly in the region of a per-level lifetime (a stack
// or a chain): the region ends before the call by packing its lifetime
// and the values living in it, the call runs after it, and its rest
// reopens the lifetime from the package (a stack's on the cursor its stack
// lies on) and runs the rest of the region, then what followed the opener.
// No lifetime of the region leaves it: the call, which runs after the
// region, is given that cursor wherever it took the lifetime, and the rest
// reads the reopened lifetime in its place. Every other lifetime is the
// component's, which the rest takes as every function of the component
// does: the cursor below the stack, and the lifetimes the opener's results
// live in, which the unpack states for its own, among them.
//
// Every other shape is one the decide step keeps out, so meeting one is
// its invariant broken: the call given a value living in the lifetime, the
// rest reading a room carved from it, the region lying on or giving into a
// lifetime that ends with its function's call.
LogicalResult Component::split(FuncOp owner, unsigned row, CallOp site, Operation *opener,
                               Packed packed) {
  MLIRContext *ctx = owner.getContext();
  Block *inside = site->getBlock();
  Value lifetime = inside->getArgument(0);
  // A value of the region's lifetime: the lifetime itself, or a view or a
  // room of it made in the region.
  auto ofLifetime = [&](Value value) {
    return isa<LifetimeType>(value.getType()) && lifetimes::extentOf(value) == lifetime;
  };
  // The cursor a stack's region lies on, which the call takes in the
  // lifetime's place, as its own level opens on it in turn. The cycle's one
  // arrangement of lifetimes, read before any function was made, lets a
  // call on it take of the region's lifetime only a stack's own, at the
  // place of the cursor it lies on, which so stands for it.
  Value base = lifetimes::baseOf(lifetime);
  for (OpOperand &operand : site->getOpOperands())
    if (ofLifetime(operand.get()))
      rewriter.modifyOpInPlace(site, [&] { operand.set(base); });
  // Neither the rest of the region nor what follows the opener reads a
  // loan from outside it: static data's, the only loan read across the
  // call, is lent again where that code begins, so the rest takes the
  // holder, never its loan.
  Operation *afterSite = lendAgain(site->getNextNode());
  lendAgain(opener->getNextNode());
  // What the rest of the region reads that the region made before the
  // call: what lives in the lifetime goes into the package, the rest out
  // of the region beside it; the call's operands go out too. A lifetime
  // from outside the region is the component's, which the rest takes.
  llvm::SmallVector<Value> restReads = liveIns(afterSite);
  llvm::SmallVector<Value> scoped, plain, outside, reopenedAs, lifetimesRead;
  for (Value value : restReads) {
    // The call's results are the rest's first parameters.
    if (llvm::is_contained(site->getResults(), value))
      continue;
    // The lifetime, and a view of it, is the reopened lifetime in the rest;
    // a room carved before the call is memory the rest cannot name.
    if (ofLifetime(value)) {
      if (!lifetimes::passesAs(lifetime.getType(), value.getType()))
        return site.emitOpError(
                   "internal error: an invariant of idr-lifetimes is broken (idr-frames): "
                   "nothing after a call on frames reads a room carved before it from the "
                   "per-level lifetime around it, but the rest of this call's region reads ")
               << value.getType();
      reopenedAs.push_back(value);
      continue;
    }
    if (isa<LifetimeType>(value.getType())) {
      lifetimesRead.push_back(value);
      continue;
    }
    bool fromRegion = value.getParentRegion() == inside->getParent();
    if (!fromRegion)
      outside.push_back(value);
    else if (lifetimes::statedLifetime(value) == lifetime)
      scoped.push_back(value);
    else
      plain.push_back(value);
  }
  for (Value arg : site.getArgs())
    if (arg.getParentRegion() == inside->getParent() &&
        lifetimes::statedLifetime(arg) == lifetime)
      return site.emitOpError(
          "internal error: an invariant of idr-lifetimes is broken (idr-frames): a call on "
          "frames is given no value living in the per-level lifetime around it, which ends "
          "before the call runs, but this call is given one");

  // The rest of the region and what followed the opener, into the rest's
  // function: an unpack reopening the lifetime, the region's code in it,
  // then the opener's continuation.
  Block *outer = opener->getBlock();
  Operation *outerEnd = outer->getTerminator();
  llvm::SmallVector<Type> held = llvm::map_to_vector(scoped, [](Value v) { return v.getType(); });
  auto package = LifetimePackageType::get(ctx, packed, held);

  llvm::SmallVector<Value> regionArgs;
  for (Value arg : site.getArgs())
    if (arg.getParentRegion() == inside->getParent())
      regionArgs.push_back(arg);
  llvm::SmallVector<Value> carried(plain);
  for (Value arg : regionArgs)
    if (!llvm::is_contained(carried, arg))
      carried.push_back(arg);

  // The region now ends at the pack, giving the package and what the call
  // and the rest need of it.
  rewriter.setInsertionPoint(site);
  auto pack = LifetimePackOp::create(rewriter, site.getLoc(), package, lifetime, scoped);
  llvm::SmallVector<Value> yielded{pack.getResult()};
  llvm::append_range(yielded, carried);
  llvm::SmallVector<Operation *> rest;
  for (Operation *op = afterSite; op; op = op->getNextNode())
    rest.push_back(op);
  Operation *regionEnd = inside->getTerminator();
  llvm::SmallVector<Value> regionGives(regionEnd->getOperands());
  Location loc = site.getLoc();

  // The rest's function: (call results, package, carried, outside, what
  // the opener's continuation reads, the component's lifetimes) -> what
  // the outer block gives, each scoped value where it goes.
  llvm::SmallVector<Value> passedOuter;
  for (Value value : liveIns(opener->getNextNode())) {
    if (llvm::is_contained(opener->getResults(), value))
      continue;
    if (isa<LifetimeType>(value.getType()))
      lifetimesRead.push_back(value);
    else
      passedOuter.push_back(value);
  }
  // The lifetime each scoped result of the opener lives in, in result
  // order, which the unpack states for its own results in turn: each the
  // component's, as the base cursor is.
  llvm::SmallVector<Value> outers;
  for (Value result : opener->getResults())
    if (Value stated = lifetimes::statedLifetime(result))
      outers.push_back(stated);
  llvm::SmallVector<Value> takes(site.getResults());
  takes.push_back(pack.getResult());
  llvm::append_range(takes, carried);
  llvm::append_range(takes, outside);
  llvm::append_range(takes, passedOuter);
  llvm::SmallVector<Value> resultsIn;
  for (unsigned at = 0, given = outerEnd->getNumOperands(); at < given; ++at)
    resultsIn.push_back(givenIn(outerEnd, at));
  llvm::SmallVector<families::Sort> binders = scopeSorts(outer->getParent());
  FailureOr<Made> moved =
      makeFunction(owner, "resumed", takes, outerEnd->getOperandTypes(), resultsIn, binders);
  if (failed(moved))
    return failure();
  FuncOp fn = moved->fn;
  Block *entry = &fn.getBody().front();
  llvm::SmallVector<BlockArgument> own = lifetimesOf(fn);
  // A lifetime of owner's as fn's own: the component's at its place.
  auto ownOf = [&](Value theirs) -> Value {
    std::optional<unsigned> place = placeOf(theirs, owner);
    return place ? Value(own[*place]) : Value();
  };
  Value restBase = base ? ownOf(base) : Value();
  llvm::SmallVector<Value> restOuters = llvm::map_to_vector(outers, ownOf);
  if ((base && !restBase) || llvm::is_contained(restOuters, Value()))
    return site.emitOpError(
        "internal error: an invariant of idr-lifetimes is broken (idr-frames): a per-level "
        "lifetime around a call on frames lies on, and gives into, its function's own "
        "lifetimes, but this call's lies on or gives into another");
  unsigned at = 0;
  auto argsOf = [&](size_t n) {
    auto range = entry->getArguments().slice(at, n);
    at += static_cast<unsigned>(n);
    return range;
  };
  auto results = argsOf(site->getNumResults());
  BlockArgument pkgArg = argsOf(1).front();
  auto carriedArgs = argsOf(carried.size());
  auto outsideArgs = argsOf(outside.size());
  auto outerArgs = argsOf(passedOuter.size());

  // What the call puts into the cursor below the stack while the level is
  // packed lies above the level's mark, so the reopened level's end frees
  // it: each of the call's results living there enters the level, restated
  // in it. A chain lies on no cursor, so nothing enters its level.
  llvm::SmallVector<Value> landed;
  if (base)
    for (auto [result, arg] : llvm::zip_equal(site.getResults(), results))
      if (lifetimes::statedLifetime(result) == base)
        landed.push_back(arg);

  // The unpack, the region's rest inside it, on the rest's own lifetimes.
  rewriter.setInsertionPointToEnd(entry);
  auto unpack = LifetimeUnpackOp::create(rewriter, loc, opener->getResultTypes(), pkgArg,
                                         restBase, landed, restOuters);
  Block *reopened = rewriter.createBlock(&unpack.getBody());
  BlockArgument fresh = reopened->addArgument(lifetime.getType(), loc);
  llvm::SmallVector<BlockArgument> restated;
  for (Value value : scoped)
    restated.push_back(reopened->addArgument(value.getType(), loc));
  llvm::SmallVector<BlockArgument> entered;
  for (Value value : landed)
    entered.push_back(reopened->addArgument(value.getType(), loc));
  for (Operation *op : rest)
    if (op != regionEnd)
      op->moveBefore(reopened, reopened->end());
  rewriter.setInsertionPointToEnd(reopened);
  YieldOp::create(rewriter, regionEnd->getLoc(), regionGives);
  rewriter.eraseOp(regionEnd);

  // The opener's continuation after the unpack.
  rewriter.setInsertionPointAfter(unpack);
  llvm::SmallVector<Operation *> following;
  for (Operation *op = opener->getNextNode(); op != outerEnd; op = op->getNextNode())
    following.push_back(op);
  for (Operation *op : following)
    op->moveBefore(entry, entry->end());
  rewriter.setInsertionPointToEnd(entry);
  ReturnOp::create(rewriter, outerEnd->getLoc(), outerEnd->getOperands());

  // Every value the moved code reads, read from the function's own.
  auto within = [&](OpOperand &use) { return fn->isProperAncestor(use.getOwner()); };
  for (auto [value, arg] : llvm::zip_equal(site.getResults(), results))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(landed, entered))
    rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
      return unpack->isProperAncestor(use.getOwner());
    });
  for (Value value : reopenedAs)
    rewriter.replaceUsesWithIf(value, fresh, within);
  for (auto [value, arg] : llvm::zip_equal(scoped, restated))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(carried, carriedArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(outside, outsideArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(passedOuter, outerArgs))
    rewriter.replaceUsesWithIf(value, arg, within);
  for (auto [value, arg] : llvm::zip_equal(opener->getResults(), unpack.getResults()))
    rewriter.replaceUsesWithIf(value, arg, within);
  if (failed(adoptLifetimes(owner, fn, lifetimesRead)))
    return failure();

  // In the function the call stays in: the region ends at the pack, the
  // opener gives what it yields, then the call and the tail call of its
  // rest.
  rewriter.setInsertionPointToEnd(inside);
  YieldOp::create(rewriter, loc, yielded);
  // Its results are the package and what is carried out beside it, each
  // scoped one stated in the lifetime it lived in inside the region, one
  // of those around the opener.
  llvm::SmallVector<Type> openerResults =
      llvm::map_to_vector(yielded, [](Value v) { return v.getType(); });
  llvm::SmallVector<Value> carriedOuters;
  for (Value value : carried)
    if (Value stated = lifetimes::statedLifetime(value))
      carriedOuters.push_back(stated);
  Operation *remade = remakeOp(rewriter, opener, opener->getOperands(), openerResults);
  lifetimes::restateOuters(cast<StatesOutersOpInterface>(remade), carriedOuters);
  rewriter.moveOpAfter(site, remade);
  Value pkgOut = remade->getResult(0);
  for (auto [value, out] : llvm::zip_equal(carried, remade->getResults().drop_front()))
    rewriter.replaceUsesWithIf(value, out, [&](OpOperand &use) {
      return use.getOwner() == site.getOperation();
    });
  llvm::SmallVector<Value> passed(site.getResults());
  passed.push_back(pkgOut);
  llvm::append_range(passed, remade->getResults().drop_front());
  llvm::append_range(passed, outside);
  llvm::append_range(passed, passedOuter);
  llvm::append_range(passed, lifetimesOf(owner));
  rewriter.setInsertionPoint(outerEnd);
  auto call = CallOp::create(rewriter, loc, fn,
                             families::levelArgs(ctx, 0, static_cast<uint32_t>(binders.size())),
                             passed, TailKind::tail);
  rewriter.modifyOpInPlace(outerEnd, [&] { outerEnd->setOperands(call.getResults()); });
  rewriter.eraseOp(opener);
  made.push_back(call);
  functions.push_back({fn, row});
  framed.push_back({site, call});
  return success();
}

} // namespace idr::tail::frames
