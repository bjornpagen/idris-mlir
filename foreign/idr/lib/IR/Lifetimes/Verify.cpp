// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lifetimes' rules of one function (verify::lifetimes), in one walk
// down its regions with the lifetimes open where the walk stands, each at
// its depth. Outlives is dominance: a lifetime bound inside another's region
// is deeper, a function's lifetime parameters are at depth 0 and outlive
// every lifetime it binds, and two parameters outlive each other only as the
// signature's bounds say. A scoped value's lifetime is one hop from it
// (statedLifetime), so no rule follows a def-use chain: each reads an op,
// the lifetimes its values state, a call's copy of its callee's signature,
// and a lifetime's own direct users.
//
// The walk keeps its own stack, never the C++ one, so a deep nest of
// regions costs memory, not native frames.

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Verify.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <optional>
#include <variant>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The spine: a root used again after every allocation
//===----------------------------------------------------------------------===//

// One backward scan from `last` to the root, carrying whether the root is
// used again on every path from where the scan stands; a region's block is
// scanned with what holds after its op, so a use inside it covers only the
// ops before it there. The blocks still to scan are kept on a list, never
// on the C++ stack.
bool idr::verify::usedAfterEveryAllocation(Value root, Operation *last) {
  Operation *maker = root.getDefiningOp();
  if (!maker || maker->getBlock() != last->getBlock())
    return false;
  // The values that are the root: it, and each value made from it as
  // itself (a match's refined argument, a cast), met in program order.
  SmallVector<Value, 4> same{root};
  auto join = [&](Value value) {
    Source source = sourceOf(value);
    if (const auto *of = std::get_if<Same>(&source); of && llvm::is_contained(same, of->value))
      same.push_back(value);
  };
  for (Operation *op = maker->getNextNode(); op; op = op == last ? nullptr : op->getNextNode())
    op->walk<WalkOrder::PreOrder>([&](Operation *nested) {
      for (Region &region : nested->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            join(arg);
      for (Value result : nested->getResults())
        join(result);
    });
  auto uses = [&](Operation *op) {
    return llvm::any_of(op->getOperands(), [&](Value operand) { return llvm::is_contained(same, operand); });
  };
  auto acquires = [](Operation *op) { return effects::own(op).row().contains(effects::Atom::alloc); };

  struct Pending {
    Operation *from;
    bool covered;
  };
  SmallVector<Pending, 8> pending{{last, false}};
  while (!pending.empty()) {
    auto [from, covered] = pending.pop_back_val();
    for (Operation *op = from; op && op != maker; op = op->getPrevNode()) {
      for (Region &region : op->getRegions())
        for (Block &block : region)
          if (!block.empty())
            pending.push_back({&block.back(), covered});
      if (!covered && acquires(op))
        return false;
      covered = covered || uses(op);
    }
  }
  return true;
}

namespace {

// Whether region `index` of `op` may run more than once per run of `op`:
// a repeated region of a region branch, or any region of an op that says
// nothing of how its regions run.
bool repeated(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return !branch || branch.isRepetitiveRegion(index);
}

// Whether `user` may run more than once per run of `extent`, a region that
// holds it: some region between them runs again.
bool runsAgainIn(Operation *user, Region *extent) {
  for (Region *region = user->getParentRegion(); region && region != extent;
       region = region->getParentRegion())
    if (repeated(region->getParentOp(), region->getRegionNumber()))
      return true;
  return false;
}

// A lifetime open where the walk stands: the value, its depth, and whether
// nothing older on its stack may be put into inside it (a stack lifetime's
// discipline). The block it was opened in closes it when the walk leaves
// that block.
enum class Discipline : std::uint8_t { Free, Stack };

struct Open {
  Value lifetime;
  unsigned depth;
  Discipline discipline;
};

// A block the walk has yet to finish: where it stands in it, how many
// lifetimes were open when it began, and whether its beginning has bound
// its region's lifetime yet.
struct Frame {
  Block *block;
  Block::iterator next;
  size_t openAt;
  bool begun;
};

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

UseOf useOf(Operation *user) {
  if (isa<CellStackOp>(user))
    return Slot{};
  if (isa<LifetimePutOpInterface>(user))
    return Puts{};
  if (auto call = dyn_cast<CallOp>(user))
    return PassesOn{call};
  return Names{};
}

class Walk {
public:
  explicit Walk(FuncOp fn)
      : fn(fn), entry(fn.getBody().front()), lives(fn.getLivesInAttr()) {}

  LogicalResult run() {
    for (BlockArgument parameter : entry.getArguments())
      if (auto lifetime = dyn_cast<LifetimeType>(parameter.getType());
          lifetime && lifetime.getKind().admitsPuts() && failed(proof(parameter, nullptr)))
        return failure();
    SmallVector<Frame, 16> frames{{&entry, entry.begin(), 0, true}};
    while (!frames.empty()) {
      Frame &frame = frames.back();
      if (!frame.begun) {
        frame.begun = true;
        if (failed(begin(*frame.block)))
          return failure();
      }
      if (frame.next == frame.block->end()) {
        open.truncate(frame.openAt);
        frames.pop_back();
        continue;
      }
      Operation &op = *frame.next++;
      if (failed(visit(op)))
        return failure();
      for (Region &region : llvm::reverse(op.getRegions()))
        for (Block &block : llvm::reverse(region))
          frames.push_back({&block, block.begin(), open.size(), false});
    }
    return success();
  }

private:
  unsigned depth() const { return open.empty() ? 0 : open.back().depth; }

  // The depth of a lifetime in scope: its extent's, a parameter's 0.
  std::optional<unsigned> depthOf(Value lifetime) const {
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
  // bounds are few, one per pair a caller must keep, so a pass over them
  // per step is the whole cost.
  bool bounded(unsigned longer, unsigned shorter) const {
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
  bool outlives(Value a, Value b) const {
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

  // A block that begins a region binding a lifetime (an opener's, a loan's,
  // an unpack's) opens it one deeper than everything open around it.
  LogicalResult begin(Block &block) {
    if (!block.isEntryBlock() || block.getNumArguments() == 0 ||
        !isa<LifetimeType>(block.getArgument(0).getType()) ||
        !isa<StatesLifetimeOpInterface>(block.getParentOp()))
      return success();
    Value lifetime = block.getArgument(0);
    open.push_back({lifetime, depth() + 1,
                    lifetimes::packedOf(lifetime) == Packed::FromStack ? Discipline::Stack
                                                                       : Discipline::Free});
    return proof(lifetime, block.getParent());
  }

  // The innermost open stack lifetime's depth, if one is open.
  std::optional<unsigned> stackDepth() const {
    for (const Open &held : llvm::reverse(open))
      if (held.discipline == Discipline::Stack)
        return held.depth;
    return std::nullopt;
  }

  // Whether `op` states `lifetime` for some value it makes: the operand
  // names where a value lives, and puts nothing into it.
  static bool states(Operation &op, Value lifetime) {
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

  // Whether `value` lives at least as long as `into`, the lifetime the
  // place it goes to names: a scoped value by its stated lifetime; any
  // other value outlives every lifetime, or its own count frees it.
  bool livesAsLong(Value value, Value into) const {
    if (!freedBy(value.getType(), Release::Scoped))
      return true;
    Value from = lifetimes::statedLifetime(value);
    return from && outlives(from, into);
  }

  LogicalResult visit(Operation &op) {
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

    // This activation's lifetime is the rest of its block.
    if (auto activation = dyn_cast<ActivationOp>(&op)) {
      open.push_back({activation.getLifetime(), depth() + 1, Discipline::Free});
      if (failed(proof(activation.getLifetime(), op.getParentRegion())))
        return failure();
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
      if (static_cast<bool>(home) != scoped || (home && init.getLifetime() != home))
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
        if (isCursorLifetime(operand.getType()) && depthOf(operand) < stack &&
            !states(op, operand))
          return op.emitOpError("puts into an older cursor inside a stack lifetime");

    // What an op makes of a scoped value lives no longer than it: a field,
    // a cast, a constructor holding it. A call's results live where its
    // callee's signature says (below), and a region op's results are its
    // yields (the merges).
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
    // lifetime it outlives: so no value of a region's own lifetime leaves it,
    // and none of an iteration's crosses its back edge.
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

  // The frame-limited rule for one lifetime's cells, over the lifetime's
  // direct users and those of each room reserved in it; `extent` is the
  // lifetime's region, a parameter's none. A slot runs once per run of its
  // lifetime: it is rewritten at each run, so a second would free what the
  // first still holds. A room's every put runs once per run, so its bytes
  // are a static sum (a callee given a room puts a bounded amount, which
  // its call's symbol use holds). A parameter of any other kind puts into
  // its caller's memory for as long as the caller's lifetime lasts, so
  // every value made in it is taken into what the function gives back, on
  // every path. An opener's cell put once per run is a static amount, and
  // one put again is taken into one of the lifetime's own; a call that
  // puts there stands at the top of the region, and each value it gives
  // there is used again after every allocation that follows it, so nothing
  // the call put is dead while memory is taken.
  LogicalResult proof(Value lifetime, Region *extent) {
    Region *within = extent ? extent : &fn.getBody();
    SmallVector<Value, 2> into{lifetime};
    for (Operation *user : lifetime.getUsers())
      if (auto reserved = dyn_cast<LifetimeReserveOp>(user))
        into.push_back(reserved.getRoom());
    auto inLifetime = [&](Value value) {
      Value stated = lifetimes::statedLifetime(value);
      return stated && lifetimes::extentOf(stated) == lifetime;
    };
    auto returnedHere = [&](unsigned result) {
      std::optional<std::uint32_t> in = lives ? lives.lifetimeOfResult(result) : std::nullopt;
      return in && entry.getArgument(*in) == lifetime;
    };
    for (Value target : into)
      for (OpOperand &use : target.getUses()) {
        LifetimeKind kind = lifetimes::kindOf(target);
        Operation *user = use.getOwner();
        bool again = runsAgainIn(user, within);
        UseOf what = useOf(user);
        if (std::holds_alternative<Slot>(what)) {
          if (again)
            return user->emitOpError("is a slot in a region that runs again inside its lifetime");
          continue;
        }
        if (!kind.admitsPuts())
          continue;
        if (kind.isRoom()) {
          if (again && !std::holds_alternative<Names>(what))
            return user->emitOpError("puts into a room in a region that runs again inside it");
          continue;
        }
        // A parameter: what each op stating it makes is taken into the result.
        if (!extent) {
          if (!states(*user, target))
            continue;
          for (Value made : user->getResults())
            if (holdsReferences(made.getType()) && inLifetime(made) &&
                !verify::takenIntoResult(made, inLifetime, returnedHere))
              return user->emitOpError("makes a value in its caller's lifetime that is not taken "
                                       "into what it gives back on every path");
          continue;
        }
        if (std::holds_alternative<Puts>(what)) {
          if (again && !keptHere(*user, target))
            return user->emitOpError("puts cells again into a lifetime that nothing it still uses "
                                     "reaches");
          continue;
        }
        if (const auto *passes = std::get_if<PassesOn>(&what)) {
          if (user->getBlock() != &extent->front())
            return user->emitOpError("puts into a lifetime of its function from inside a region "
                                     "the lifetime holds");
          Operation *last = extent->front().getTerminator();
          for (Value result : passes->call->getResults())
            if (inLifetime(result) && !verify::usedAfterEveryAllocation(result, last))
              return user->emitOpError("puts into a lifetime a value that is dead there while "
                                       "memory is taken");
        }
      }
    return success();
  }

  // Whether each cell `user` puts into `lifetime`, put again and again, is
  // taken into one of the lifetime's own: the box its cell becomes is an
  // operand of an op that states the lifetime for what it makes, or is
  // carried on by a merge.
  static bool keptHere(Operation &user, Value lifetime) {
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

  FuncOp fn;
  Block &entry;
  LivesInAttr lives;
  SmallVector<Open, 8> open;
};

} // namespace

LogicalResult idr::verify::lifetimes(FuncOp fn) { return Walk(fn).run(); }
