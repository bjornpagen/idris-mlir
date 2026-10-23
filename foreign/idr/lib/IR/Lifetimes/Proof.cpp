// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The frame-limited rule for a lifetime's cells, checked at each use of the
// lifetime, or of a room reserved in it, where the walk meets the use.
//
// A slot runs once per run of its lifetime: it is rewritten at each run, so
// a second would free what the first still holds. A room's every put runs
// once per run, so its bytes are a static sum (a callee given a room puts a
// bounded amount, which its call's symbol use holds). A parameter of any
// other kind puts into its caller's memory for as long as the caller's
// lifetime lasts, so every value made in it is taken into what the function
// gives back, on every path. An opener's cell put once per run is a static
// amount, and one put again is taken into one of the lifetime's own; a call
// that puts there stands at the top of the region, and each value it gives
// there is used again after every allocation that follows it, so nothing
// the call put is dead while memory is taken.

#include "idr/IR/Lifetimes/Rules.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"

#include "llvm/ADT/STLExtras.h"

#include <concepts>

using namespace mlir;
using namespace idr;
using State = verify::LifetimeRules::State;

// What each use of a lifetime does with it is the op's answer
// (LifetimeUseOpInterface): it names it, as where a value the op makes
// lives, as the base of a stack opened on it, or as the cast to its view or
// the pack that ends its region, putting nothing into it; it is a slot of
// the frame stated in it; it puts cells into it itself; or it is a call
// that may put into it what its results hold.
LogicalResult State::proof(Operation &user) {
  for (OpOperand &use : user.getOpOperands()) {
    Value target = use.get();
    if (!isa<LifetimeType>(target.getType()))
      continue;
    auto reserved = target.getDefiningOp<LifetimeReserveOp>();
    Value lifetime = reserved ? reserved.getLifetime() : target;
    std::optional<OpenLifetimes::Open> held = open.recordOf(lifetime);
    if (!held)
      continue;
    LifetimeKind kind = lifetimes::kindOf(target);
    bool again = levels.back().again > held->again;
    auto inLifetime = [&](Value value) {
      Value stated = lifetimes::statedLifetime(value);
      return stated && lifetimes::extentOf(stated) == lifetime;
    };
    // A parameter: what each op stating it makes is taken into the result,
    // whatever else the op does with it.
    auto intoResult = [&]() -> LogicalResult {
      if (!states(user, target))
        return success();
      auto returnedHere = [&](unsigned result) { return open.resultLifetime(result) == lifetime; };
      for (Value made : user.getResults())
        if (holdsReferences(made.getType()) && inLifetime(made) &&
            !verify::takenIntoResult(made, inLifetime, returnedHere))
          return user.emitOpError("makes a value in its caller's lifetime that is not taken into "
                                  "what it gives back on every path");
      return success();
    };
    // A put into a room, put into once per run, or into a parameter is
    // decided by the lifetime alone; one opened here leaves it to the put,
    // given the region the lifetime is the extent of.
    auto put = [&](std::invocable<Region &> auto &&opened) -> LogicalResult {
      if (!kind.admitsPuts())
        return success();
      if (kind.isRoom()) {
        if (again)
          return user.emitOpError("puts into a room in a region that runs again inside it");
        return success();
      }
      if (!held->region)
        return intoResult();
      return opened(*held->region);
    };

    LogicalResult checked = success();
    switch (lifetimes::useOf(use)) {
    case LifetimeUse::Slot:
      if (again)
        checked = user.emitOpError("is a slot in a region that runs again inside its lifetime");
      break;
    // Naming a lifetime puts nothing into it; only a parameter's takes in
    // what the op makes there.
    case LifetimeUse::Names:
      if (kind.admitsPuts() && !kind.isRoom() && !held->region)
        checked = intoResult();
      break;
    case LifetimeUse::Puts:
      checked = put([&](Region &) -> LogicalResult {
        if (again && !keptHere(user, target))
          return user.emitOpError("puts cells again into a lifetime that nothing it still uses "
                                  "reaches");
        return success();
      });
      break;
    case LifetimeUse::PassesOn:
      checked = put([&](Region &region) -> LogicalResult {
        Block &top = region.front();
        if (user.getBlock() != &top)
          return user.emitOpError("puts into a lifetime of its function from inside a region "
                                  "the lifetime holds");
        for (Value result : user.getResults())
          if (inLifetime(result) && !verify::usedAfterEveryAllocation(result, top.getTerminator()))
            return user.emitOpError("puts into a lifetime a value that is dead there while "
                                    "memory is taken");
        return success();
      });
      break;
    }
    if (failed(checked))
      return failure();
  }
  return success();
}

// Whether each cell `user` puts into `lifetime`, put again and again, is
// taken into one of the lifetime's own: the box its cell becomes is an
// operand of an op that states the lifetime for what it makes, or is
// carried on by a merge. The put says what cell it puts there
// (LifetimePutOpInterface); bytes put as no cell, a room's, are kept by
// nothing.
bool State::keptHere(Operation &user, Value lifetime) {
  auto put = dyn_cast<LifetimePutOpInterface>(&user);
  TypedValue<CellType> cell = put ? put.getPutCell() : nullptr;
  if (!cell)
    return false;
  for (Operation *init : cell.getUsers())
    for (Value box : init->getResults())
      if (freedBy(box.getType(), Release::Scoped) &&
          llvm::none_of(box.getUsers(), [&](Operation *next) {
            return next->hasTrait<OpTrait::IsTerminator>() || states(*next, lifetime);
          }))
        return false;
  return true;
}
