// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lifetimes' rules of one function (verify::LifetimeRules), a rule of
// the function's one walk: the lifetimes open where it stands
// (OpenLifetimes), kept as the walk enters and leaves regions, and the
// rules each op is held to there. The rules every op keeps are the walk's;
// an op with a rule of its own states it through LifetimeUseOpInterface,
// which the walk asks with the lifetimes open around the op. Each rule
// reads the op, the lifetimes its values state, a call's copy of its
// callee's signature, and the lifetimes open around it.

#include "idr/IR/Lifetimes/Rules.h"

#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Regions.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using State = verify::LifetimeRules::State;
using Discipline = OpenLifetimes::Discipline;

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

// The function's body is where every count starts; a region below it runs
// again when its op says so or says nothing. A region that binds a
// lifetime (an opener's, a loan's, an unpack's) opens it one deeper than
// everything open around it, its extent that region.
LogicalResult State::enter(Operation *op, Region &region) {
  if (op == fn.getOperation()) {
    levels.push_back({open.size(), 0});
    return success();
  }
  unsigned again =
      levels.back().again + (regionRuns(op, region.getRegionNumber()) == Runs::Repeatedly ? 1 : 0);
  levels.push_back({open.size(), again});
  if (region.empty() || region.front().getNumArguments() == 0 ||
      !isa<LifetimeType>(region.front().getArgument(0).getType()) ||
      !isa<StatesLifetimeOpInterface>(op))
    return success();
  Value lifetime = region.front().getArgument(0);
  open.push({lifetime, open.depth() + 1,
             lifetimes::packedOf(lifetime) == Packed::FromStack ? Discipline::Stack
                                                                : Discipline::Free,
             again, &region});
  return success();
}

void State::leave() {
  open.popTo(levels.back().openAt);
  levels.pop_back();
}

// The op's own rules, and a loan's; then each lifetime the op gives that
// is its own extent (this activation's) is open for the rest of its
// region, one derived from another (a view's cast) being of its operand's
// extent, which is open already; then the frame-limited
// rule at each lifetime the op uses.
LogicalResult State::check(Operation &op) {
  if (failed(local(op)) || failed(loans(op)))
    return failure();
  for (Value given : op.getResults())
    if (isa<LifetimeType>(given.getType()) && lifetimes::extentOf(given) == given)
      open.push({given, open.depth() + 1, Discipline::Free, levels.back().again,
                 op.getParentRegion()});
  return proof(op);
}

std::optional<unsigned> OpenLifetimes::depthOf(Value lifetime) const {
  Value extent = lifetimes::extentOf(lifetime);
  if (auto arg = dyn_cast<BlockArgument>(extent); arg && arg.getOwner() == &entry)
    return 0u;
  for (const Open &each : llvm::reverse(held))
    if (each.lifetime == extent)
      return each.depth;
  return std::nullopt;
}

// The bounds are few, one per pair a caller must keep, so a pass over them
// per step, one after another, is the whole cost.
bool OpenLifetimes::bounded(unsigned longer, unsigned shorter) const {
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

bool OpenLifetimes::outlives(Value a, Value b) const {
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

bool OpenLifetimes::livesAsLong(Value value, Value into) const {
  if (!freedBy(value.getType(), Release::Scoped))
    return true;
  Value from = lifetimes::statedLifetime(value);
  return from && outlives(from, into);
}

Value OpenLifetimes::resultLifetime(unsigned index) const {
  std::optional<std::uint32_t> in =
      lives ? lives.lifetimeOfResult(static_cast<std::uint32_t>(index)) : std::nullopt;
  return in ? Value(entry.getArgument(*in)) : Value();
}

std::optional<unsigned> OpenLifetimes::stackDepth() const {
  for (const Open &each : llvm::reverse(held))
    if (each.discipline == Discipline::Stack)
      return each.depth;
  return std::nullopt;
}

std::optional<OpenLifetimes::Open> OpenLifetimes::recordOf(Value lifetime) const {
  if (auto arg = dyn_cast<BlockArgument>(lifetime); arg && arg.getOwner() == &entry)
    return Open{lifetime, 0, Discipline::Free, 0, nullptr};
  for (const Open &each : llvm::reverse(held))
    if (each.lifetime == lifetime)
      return each;
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

//===----------------------------------------------------------------------===//
// The rules every op keeps
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
      return stated && stated != own && !open.depthOf(stated);
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

  // The op's own rule, against the lifetimes open where it stands: a
  // slot's, a cell's, a call's, a return's.
  if (auto uses = dyn_cast<LifetimeUseOpInterface>(&op); uses && failed(uses.verifyLifetimeUse(open)))
    return failure();

  // Inside a stack lifetime every put lands at the top of the stack: no op
  // puts into an older cursor, takes a slot of it, passes it on or opens a
  // stack on it, unless the cursor is where a value the op makes lives.
  // Naming a cursor, as its view's cast does, puts nothing.
  if (std::optional<unsigned> stack = open.stackDepth()) {
    auto binder = dyn_cast<CursorBinderOpInterface>(&op);
    Value base = binder ? binder.getCursorBase() : Value();
    for (OpOperand &use : op.getOpOperands()) {
      Value operand = use.get();
      if (isCursorLifetime(operand.getType()) && open.depthOf(operand) < stack &&
          !states(op, operand) &&
          (operand == base || lifetimes::useOf(use) != LifetimeUse::Names))
        return op.emitOpError("puts into an older cursor inside a stack lifetime");
    }
  }

  // What an op makes of a scoped value lives no longer than it: a value it
  // passes through lives where its operand does or in a lifetime that one
  // encloses, and a constructor's scoped fields all outlive it. A call's
  // results live where its callee's signature says (its own rule), and a
  // region op's results are its yields (the merges).
  if (op.getNumRegions() == 0 && !isa<CallOpInterface>(&op) &&
      !op.hasTrait<OpTrait::IsTerminator>())
    for (Value result : op.getResults()) {
      if (!freedBy(result.getType(), Release::Scoped))
        continue;
      Value into = lifetimes::statedLifetime(result);
      if (!into)
        return op.emitOpError("makes a scoped value whose lifetime it states nowhere");
      for (Value operand : op.getOperands())
        if (!open.livesAsLong(operand, into))
          return op.emitOpError("makes a value of a lifetime that outlives one it holds");
    }

  // A value crosses a merge (a region's entry, a yield, a jump) only into a
  // lifetime it outlives, each value a region binds stating its own: so no
  // value of a region's own lifetime leaves it, and none of an iteration's
  // crosses its back edge.
  LogicalResult merged = success();
  forwardedValues(&op, [&](OpOperand &use, Value input) {
    if (failed(merged) || !freedBy(input.getType(), Release::Scoped))
      return;
    // An upstream region op (scf's) states no lifetime for what it makes,
    // so a scoped value never passes through one: the decide step counts it.
    Value into = lifetimes::statedLifetime(input);
    if (!into)
      merged = op.emitOpError("passes a scoped value on through a region op that states no "
                              "lifetime for it, as no upstream region op does");
    else if (!open.livesAsLong(use.get(), into))
      merged = op.emitOpError("passes a value on into a lifetime it does not outlive");
  });
  return merged;
}

//===----------------------------------------------------------------------===//
// The rules of the ops that have their own
//===----------------------------------------------------------------------===//

// A slot is this frame's: its lifetime is bound in this function, never a
// parameter, whose memory is its caller's.
LogicalResult idr::CellStackOp::verifyLifetimeUse(const OpenLifetimes &open) {
  if (open.depthOf(getLifetime()) == 0u)
    return emitOpError("is a slot of a lifetime its function does not bind");
  return success();
}

// A cell lives where its source says: a cell of a lifetime gives a value
// of that lifetime, holding no counted field, since a lifetime's end frees
// its memory and drops nothing; a cell its count frees gives a value its
// count frees.
LogicalResult idr::CellInitOp::verifyLifetimeUse(const OpenLifetimes &) {
  Value home = lifetimes::cellLifetime(getCell());
  Value result = getResult();
  if (!home) {
    if (freedBy(result.getType(), Release::Scoped))
      return emitOpError("fills a cell its count frees but gives a scoped value");
    return success();
  }
  if (!freedBy(result.getType(), Release::Scoped) || getStatedLifetime(result) != home)
    return emitOpError("fills a cell of a lifetime but gives no value of it");
  if (llvm::any_of(getFields(),
                   [](Value field) { return freedBy(field.getType(), Release::Counted); }))
    return emitOpError("puts a counted field into a cell of a lifetime, which no end drops");
  return success();
}

// A call passes each scoped argument into the lifetime its callee's
// signature names for it, and the lifetimes it passes keep the bounds that
// signature states: both read off the call's own copy of it.
LogicalResult idr::CallOp::verifyLifetimeUse(const OpenLifetimes &open) {
  LivesInAttr callee = getLivesInAttr();
  auto args = getArgs();
  auto lifetimeAt = [&](std::uint32_t position) -> Value {
    return position < args.size() && isa<LifetimeType>(args[position].getType()) ? args[position]
                                                                                 : Value();
  };
  for (auto [index, arg] : llvm::enumerate(args)) {
    if (!freedBy(arg.getType(), Release::Scoped))
      continue;
    std::optional<std::uint32_t> in =
        callee ? callee.lifetimeOfParameter(static_cast<std::uint32_t>(index)) : std::nullopt;
    Value into = in ? lifetimeAt(*in) : Value();
    if (!into)
      return emitOpError("passes scoped argument ")
             << index << ", whose lifetime its callee's signature names nowhere";
    if (!open.livesAsLong(arg, into))
      return emitOpError("passes argument ")
             << index << " into a lifetime it does not live as long as";
  }
  if (callee)
    for (const Outlives &bound : callee.getBounds()) {
      Value longer = lifetimeAt(bound.longer);
      Value shorter = lifetimeAt(bound.shorter);
      if (!longer || !shorter || !open.outlives(longer, shorter))
        return emitOpError("passes lifetimes ")
               << bound.longer << " and " << bound.shorter
               << ", which do not keep the bound its callee states between them";
    }
  return success();
}

// What the function gives back lives where its signature says.
LogicalResult idr::ReturnOp::verifyLifetimeUse(const OpenLifetimes &open) {
  for (auto [index, operand] : llvm::enumerate(getOperands())) {
    if (!freedBy(operand.getType(), Release::Scoped))
      continue;
    Value into = open.resultLifetime(static_cast<unsigned>(index));
    if (!into || !open.livesAsLong(operand, into))
      return emitOpError("returns result ")
             << index << " from a lifetime that does not outlive the one its signature names";
  }
  return success();
}
