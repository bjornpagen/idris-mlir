// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lifetimes' rules of one function (verify::LifetimeRules), a rule of
// the function's one walk: the scope it keeps as the walk enters and
// leaves regions, and the rules each op is held to where it stands. Each
// reads the op, the lifetimes its values state, a call's copy of its
// callee's signature, and the lifetimes open around it.

#include "idr/IR/Lifetimes/Rules.h"

#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using State = verify::LifetimeRules::State;

static_assert(families::FunctionRule<verify::LifetimeRules>);

verify::LifetimeRules::LifetimeRules(FuncOp fn) : state(std::make_unique<State>(fn)) {}
verify::LifetimeRules::~LifetimeRules() = default;

LogicalResult verify::LifetimeRules::enter(Operation *op, Region &region) {
  return state->enter(op, region);
}
LogicalResult verify::LifetimeRules::check(Operation *op) { return state->check(*op); }
void verify::LifetimeRules::leave() { state->leave(); }

//===----------------------------------------------------------------------===//
// The scope where the walk stands
//===----------------------------------------------------------------------===//

namespace {

// Whether region `index` of `op` may run more than once per run of `op`:
// a repeated region of a region branch, or any region of an op that says
// nothing of how its regions run.
bool repeated(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return !branch || branch.isRepetitiveRegion(index);
}

} // namespace

// The function's body is where every count starts; a region below it runs
// again when its op says so or says nothing. A region that binds a
// lifetime (an opener's, a loan's, an unpack's) opens it one deeper than
// everything open around it, its extent that region.
LogicalResult State::enter(Operation *op, Region &region) {
  if (op == fn.getOperation()) {
    levels.push_back({open.size(), 0});
    return success();
  }
  unsigned again = levels.back().again + (repeated(op, region.getRegionNumber()) ? 1 : 0);
  levels.push_back({open.size(), again});
  if (region.empty() || region.front().getNumArguments() == 0 ||
      !isa<LifetimeType>(region.front().getArgument(0).getType()) ||
      !isa<StatesLifetimeOpInterface>(op))
    return success();
  Value lifetime = region.front().getArgument(0);
  open.push_back({lifetime, depth() + 1,
                  lifetimes::packedOf(lifetime) == Packed::FromStack ? Discipline::Stack
                                                                     : Discipline::Free,
                  again, &region});
  return success();
}

void State::leave() {
  open.truncate(levels.back().openAt);
  levels.pop_back();
}

// This activation's lifetime is the rest of its region; then the op's own
// rules, and the frame-limited rule at each lifetime it uses.
LogicalResult State::check(Operation &op) {
  if (failed(local(op)))
    return failure();
  if (auto activation = dyn_cast<ActivationOp>(&op))
    open.push_back({activation.getLifetime(), depth() + 1, Discipline::Free, levels.back().again,
                    op.getParentRegion()});
  return proof(op);
}

// The depth of a lifetime in scope: its extent's, a parameter's 0.
std::optional<unsigned> State::depthOf(Value lifetime) const {
  Value extent = lifetimes::extentOf(lifetime);
  if (auto arg = dyn_cast<BlockArgument>(extent); arg && arg.getOwner() == &entry)
    return 0u;
  for (const Open &held : llvm::reverse(open))
    if (held.lifetime == extent)
      return held.depth;
  return std::nullopt;
}

// Whether the parameter at `longer` lives at least as long as the one at
// `shorter`, by the bounds the signature states, one after another. The
// bounds are few, one per pair a caller must keep, so a pass over them per
// step is the whole cost.
bool State::bounded(unsigned longer, unsigned shorter) const {
  if (!lives || longer == shorter)
    return longer == shorter;
  SmallVector<unsigned, 4> reached{longer};
  for (unsigned at = 0; at < reached.size(); ++at)
    for (const Outlives &bound : lives.getBounds())
      if (bound.longer == reached[at] && !llvm::is_contained(reached, bound.shorter)) {
        if (bound.shorter == shorter)
          return true;
        reached.push_back(bound.shorter);
      }
  return false;
}

// Whether `a` lives at least as long as `b`, both in scope.
bool State::outlives(Value a, Value b) const {
  Value ea = lifetimes::extentOf(a);
  Value eb = lifetimes::extentOf(b);
  if (ea == eb)
    return true;
  std::optional<unsigned> da = depthOf(a);
  std::optional<unsigned> db = depthOf(b);
  if (!da || !db)
    return false;
  if (*da == 0 && *db == 0)
    return bounded(cast<BlockArgument>(ea).getArgNumber(), cast<BlockArgument>(eb).getArgNumber());
  return *da < *db;
}

// The innermost open stack lifetime's depth, if one is open.
std::optional<unsigned> State::stackDepth() const {
  for (const Open &held : llvm::reverse(open))
    if (held.discipline == Discipline::Stack)
      return held.depth;
  return std::nullopt;
}

// Whether `op` states `lifetime` for some value it makes: the operand
// names where a value lives, and puts nothing into it.
bool State::states(Operation &op, Value lifetime) {
  auto statesLifetime = dyn_cast<StatesLifetimeOpInterface>(&op);
  if (!statesLifetime)
    return false;
  auto stated = [&](Value made) { return statesLifetime.getStatedLifetime(made) == lifetime; };
  if (llvm::any_of(op.getResults(), stated))
    return true;
  return llvm::any_of(op.getRegions(), [&](Region &region) {
    return !region.empty() && llvm::any_of(region.front().getArguments(), stated);
  });
}

// Whether `value` lives at least as long as `into`, the lifetime the place
// it goes to names: a scoped value by its stated lifetime; any other value
// outlives every lifetime, or its own count frees it.
bool State::livesAsLong(Value value, Value into) const {
  if (!freedBy(value.getType(), Release::Scoped))
    return true;
  Value from = lifetimes::statedLifetime(value);
  return from && outlives(from, into);
}

//===----------------------------------------------------------------------===//
// The rules of one op
//===----------------------------------------------------------------------===//

LogicalResult State::local(Operation &op) {
  // A lifetime is never yielded, returned or passed to a join point, and
  // no op gives one but those that say so: so none leaves its region.
  if (op.hasTrait<OpTrait::IsTerminator>() &&
      llvm::any_of(op.getOperandTypes(), [](Type type) { return isa<LifetimeType>(type); }))
    return op.emitOpError("passes a lifetime out of its region");
  if (!op.hasTrait<GivesLifetime>() &&
      llvm::any_of(op.getResultTypes(), [](Type type) { return isa<LifetimeType>(type); }))
    return op.emitOpError("gives a lifetime, which only a lifetime's own ops give");

  // A lifetime an op states for a value it makes is open where the op
  // stands, or is the one the op's own region binds: so every value lies
  // inside its lifetime's extent.
  if (auto states = dyn_cast<StatesLifetimeOpInterface>(&op)) {
    auto closed = [&](Value made, Value own) {
      Value stated = states.getStatedLifetime(made);
      return stated && stated != own && !depthOf(stated);
    };
    if (llvm::any_of(op.getResults(), [&](Value made) { return closed(made, Value()); }))
      return op.emitOpError("states a lifetime that is not open where it stands");
    for (Region &region : op.getRegions())
      if (!region.empty() && region.front().getNumArguments() != 0) {
        Value own = region.front().getArgument(0);
        if (llvm::any_of(region.front().getArguments(),
                         [&](Value made) { return closed(made, own); }))
          return op.emitOpError("states a lifetime that is not open where it stands");
      }
  }

  // A slot is this frame's: its lifetime is bound in this function.
  if (auto slot = dyn_cast<CellStackOp>(&op); slot && depthOf(slot.getLifetime()) == 0u)
    return op.emitOpError("is a slot of a lifetime its function does not bind");

  // A cell lives where its source says: a cell of a lifetime gives a value
  // of that lifetime, holding no counted field, since a lifetime's end
  // frees its memory and drops nothing; a cell its count frees gives a
  // value its count frees.
  if (auto init = dyn_cast<CellInitOp>(&op)) {
    Value home = lifetimes::cellLifetime(init.getCell());
    bool scoped = freedBy(init.getResult().getType(), Release::Scoped);
    if (static_cast<bool>(home) != scoped ||
        (home && init.getStatedLifetime(init.getResult()) != home))
      return op.emitOpError(home ? "fills a cell of a lifetime but gives no value of it"
                                 : "fills a cell its count frees but gives a scoped value");
    if (home && llvm::any_of(init.getFields(), [](Value field) {
          return freedBy(field.getType(), Release::Counted);
        }))
      return op.emitOpError("puts a counted field into a cell of a lifetime, which no end drops");
  }

  // Inside a stack lifetime, nothing is put into an older cursor: every
  // put lands at the top of the stack.
  if (std::optional<unsigned> stack = stackDepth(); stack && !isa<LifetimeForgetOp>(&op))
    for (Value operand : op.getOperands())
      if (isCursorLifetime(operand.getType()) && depthOf(operand) < stack && !states(op, operand))
        return op.emitOpError("puts into an older cursor inside a stack lifetime");

  // What an op makes of a scoped value lives no longer than it: a value it
  // passes through lives where its operand does or in a lifetime that one
  // encloses, and a constructor's scoped fields all outlive it. A call's
  // results live where its callee's signature says (below), and a region
  // op's results are its yields (the merges).
  if (op.getNumRegions() == 0 && !isa<CallOpInterface>(&op) &&
      !op.hasTrait<OpTrait::IsTerminator>())
    for (Value result : op.getResults()) {
      if (!freedBy(result.getType(), Release::Scoped))
        continue;
      Value into = lifetimes::statedLifetime(result);
      if (!into)
        return op.emitOpError("makes a scoped value whose lifetime it states nowhere");
      for (Value operand : op.getOperands())
        if (!livesAsLong(operand, into))
          return op.emitOpError("makes a value of a lifetime that outlives one it holds");
    }

  // A call passes each scoped argument into the lifetime its callee's
  // signature names for it, and the lifetimes it passes keep the bounds
  // that signature states: both read off the call's own copy of it.
  if (auto call = dyn_cast<CallOp>(&op)) {
    LivesInAttr callee = call.getLivesInAttr();
    auto args = call.getArgs();
    auto lifetimeAt = [&](std::uint32_t position) -> Value {
      return position < args.size() && isa<LifetimeType>(args[position].getType())
                 ? args[position]
                 : Value();
    };
    for (auto [index, arg] : llvm::enumerate(args)) {
      if (!freedBy(arg.getType(), Release::Scoped))
        continue;
      std::optional<std::uint32_t> in =
          callee ? callee.lifetimeOfParameter(static_cast<std::uint32_t>(index)) : std::nullopt;
      Value into = in ? lifetimeAt(*in) : Value();
      if (!into)
        return op.emitOpError("passes scoped argument ")
               << index << ", whose lifetime its callee's signature names nowhere";
      if (!livesAsLong(arg, into))
        return op.emitOpError("passes argument ")
               << index << " into a lifetime it does not live as long as";
    }
    if (callee)
      for (const Outlives &bound : callee.getBounds()) {
        Value longer = lifetimeAt(bound.longer);
        Value shorter = lifetimeAt(bound.shorter);
        if (!longer || !shorter || !outlives(longer, shorter))
          return op.emitOpError("passes lifetimes ")
                 << bound.longer << " and " << bound.shorter
                 << ", which do not keep the bound its callee states between them";
      }
  }

  // What the function gives back lives where its signature says.
  if (isa<ReturnOp>(&op))
    for (auto [index, operand] : llvm::enumerate(op.getOperands())) {
      if (!freedBy(operand.getType(), Release::Scoped))
        continue;
      std::optional<std::uint32_t> in =
          lives ? lives.lifetimeOfResult(static_cast<std::uint32_t>(index)) : std::nullopt;
      if (!in || !livesAsLong(operand, entry.getArgument(*in)))
        return op.emitOpError("returns result ")
               << index << " from a lifetime that does not outlive the one its signature names";
    }

  // A value crosses a merge (a region's entry, a yield, a jump) only into a
  // lifetime it outlives, each value a region binds stating its own: so no
  // value of a region's own lifetime leaves it, and none of an iteration's
  // crosses its back edge.
  LogicalResult merged = success();
  forwardedValues(&op, [&](OpOperand &use, Value input) {
    if (failed(merged) || !freedBy(input.getType(), Release::Scoped))
      return;
    Value into = lifetimes::statedLifetime(input);
    if (!into || !livesAsLong(use.get(), into))
      merged = op.emitOpError("passes a value on into a lifetime it does not outlive");
  });
  return merged;
}
