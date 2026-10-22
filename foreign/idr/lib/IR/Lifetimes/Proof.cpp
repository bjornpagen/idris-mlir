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

#include <variant>

using namespace mlir;
using namespace idr;
using State = verify::LifetimeRules::State;

namespace {

// What a use of a lifetime does with it: names it as where a value the op
// makes lives, or as the base of a stack opened on it, or is the cast to its
// view or the pack that ends its region, putting nothing into it; is a slot
// of the frame stated in it; puts cells into it itself; or is a call that
// may put into it what its results hold.
struct Names {};
struct Slot {};
struct Puts {};
struct PassesOn {
  CallOp call;
};
using UseOf = std::variant<Names, Slot, Puts, PassesOn>;

UseOf useOf(Operation &user) {
  if (isa<CellStackOp>(&user))
    return Slot{};
  if (isa<LifetimePutOpInterface>(&user))
    return Puts{};
  if (auto call = dyn_cast<CallOp>(&user))
    return PassesOn{call};
  return Names{};
}

} // namespace

// The lifetime itself as the walk holds it: open where it stands, or a
// parameter of the function, whose extent is its caller's. A lifetime
// derived from another by a view's cast is no lifetime this rule reads.
std::optional<State::Open> State::recordOf(Value lifetime) const {
  if (auto arg = dyn_cast<BlockArgument>(lifetime); arg && arg.getOwner() == &entry)
    return Open{lifetime, 0, Discipline::Free, 0, nullptr};
  for (const Open &held : llvm::reverse(open))
    if (held.lifetime == lifetime)
      return held;
  return std::nullopt;
}

LogicalResult State::proof(Operation &user) {
  for (Value target : user.getOperands()) {
    if (!isa<LifetimeType>(target.getType()))
      continue;
    auto reserved = target.getDefiningOp<LifetimeReserveOp>();
    Value lifetime = reserved ? reserved.getLifetime() : target;
    std::optional<Open> held = recordOf(lifetime);
    if (!held)
      continue;
    LifetimeKind kind = lifetimes::kindOf(target);
    bool again = levels.back().again > held->again;
    UseOf what = useOf(user);
    auto inLifetime = [&](Value value) {
      Value stated = lifetimes::statedLifetime(value);
      return stated && lifetimes::extentOf(stated) == lifetime;
    };

    if (std::holds_alternative<Slot>(what)) {
      if (again)
        return user.emitOpError("is a slot in a region that runs again inside its lifetime");
      continue;
    }
    if (!kind.admitsPuts())
      continue;
    if (kind.isRoom()) {
      if (again && !std::holds_alternative<Names>(what))
        return user.emitOpError("puts into a room in a region that runs again inside it");
      continue;
    }
    // A parameter: what each op stating it makes is taken into the result.
    if (!held->region) {
      if (!states(user, target))
        continue;
      auto returnedHere = [&](unsigned result) {
        std::optional<std::uint32_t> in = lives ? lives.lifetimeOfResult(result) : std::nullopt;
        return in && entry.getArgument(*in) == lifetime;
      };
      for (Value made : user.getResults())
        if (holdsReferences(made.getType()) && inLifetime(made) &&
            !verify::takenIntoResult(made, inLifetime, returnedHere))
          return user.emitOpError("makes a value in its caller's lifetime that is not taken into "
                                  "what it gives back on every path");
      continue;
    }
    if (std::holds_alternative<Puts>(what)) {
      if (again && !keptHere(user, target))
        return user.emitOpError("puts cells again into a lifetime that nothing it still uses "
                                "reaches");
      continue;
    }
    if (const auto *passes = std::get_if<PassesOn>(&what)) {
      Block &top = held->region->front();
      if (user.getBlock() != &top)
        return user.emitOpError("puts into a lifetime of its function from inside a region the "
                                "lifetime holds");
      for (Value result : passes->call->getResults())
        if (inLifetime(result) && !verify::usedAfterEveryAllocation(result, top.getTerminator()))
          return user.emitOpError("puts into a lifetime a value that is dead there while memory "
                                  "is taken");
    }
  }
  return success();
}

// Whether each cell `user` puts into `lifetime`, put again and again, is
// taken into one of the lifetime's own: the box its cell becomes is an
// operand of an op that states the lifetime for what it makes, or is
// carried on by a merge.
bool State::keptHere(Operation &user, Value lifetime) {
  auto cell = dyn_cast<CellArenaOp>(&user);
  if (!cell)
    return false;
  for (Operation *init : cell.getCell().getUsers())
    for (Value box : init->getResults())
      if (freedBy(box.getType(), Release::Scoped) &&
          llvm::none_of(box.getUsers(), [&](Operation *next) {
            return next->hasTrait<OpTrait::IsTerminator>() || states(*next, lifetime);
          }))
        return false;
  return true;
}
