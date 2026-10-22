// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lifetimes' rules of one function (verify::lifetimes), in one walk
// down its regions with the lifetimes open where the walk stands, each at
// its depth. Outlives is dominance: a lifetime bound inside another's region
// is deeper, a function's lifetime parameters are at depth 0 and outlive
// every lifetime it binds, and two parameters outlive only themselves. A
// scoped value's lifetime is one hop from it (statedLifetime), so no rule
// follows a def-use chain: each reads an op, the lifetimes its values
// state, and a lifetime's own direct users.
//
// The walk keeps its own stack, never the C++ one, so a deep nest of
// regions costs memory, not native frames.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Verify.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace idr;

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

class Walk {
public:
  explicit Walk(FuncOp fn) : fn(fn), entry(fn.getBody().front()) {}

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

  // Whether `a` lives at least as long as `b`, both in scope.
  bool outlives(Value a, Value b) const {
    if (lifetimes::extentOf(a) == lifetimes::extentOf(b))
      return true;
    std::optional<unsigned> da = depthOf(a);
    std::optional<unsigned> db = depthOf(b);
    return da && db && *da < *db;
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

  LogicalResult visit(Operation &op) {
    // A lifetime is never yielded, returned or passed to a join point, and
    // no op gives one but those that say so: so none leaves its region.
    if (op.hasTrait<OpTrait::IsTerminator>() &&
        llvm::any_of(op.getOperandTypes(), [](Type type) { return isa<LifetimeType>(type); }))
      return op.emitOpError("passes a lifetime out of its region");
    if (!op.hasTrait<GivesLifetime>() &&
        llvm::any_of(op.getResultTypes(), [](Type type) { return isa<LifetimeType>(type); }))
      return op.emitOpError("gives a lifetime, which only a lifetime's own ops give");

    // This activation's lifetime is the rest of its block.
    if (auto activation = dyn_cast<ActivationOp>(&op)) {
      open.push_back({activation.getLifetime(), depth() + 1, Discipline::Free});
      if (failed(proof(activation.getLifetime(), op.getParentRegion())))
        return failure();
    }

    // A slot is this frame's: its lifetime is bound in this function.
    if (auto slot = dyn_cast<CellStackOp>(&op); slot && depthOf(slot.getLifetime()) == 0u)
      return op.emitOpError("is a slot of a lifetime its function does not bind");

    // Inside a stack lifetime, nothing is put into an older cursor: every
    // put lands at the top of the stack.
    if (std::optional<unsigned> stack = stackDepth(); stack && !isa<LifetimeForgetOp>(&op))
      for (Value operand : op.getOperands())
        if (isCursorLifetime(operand.getType()) && depthOf(operand) < stack &&
            !states(op, operand))
          return op.emitOpError("puts into an older cursor inside a stack lifetime");

    // What an op makes of a scoped value lives no longer than it: a field,
    // a cast, a constructor holding it. A call's results relate to its
    // arguments by its callee's signature (its own verifier), and a region
    // op's results are its yields (below).
    if (op.getNumRegions() == 0 && !isa<CallOpInterface>(&op) &&
        !op.hasTrait<OpTrait::IsTerminator>())
      for (Value result : op.getResults()) {
        if (!freedBy(result.getType(), Release::Scoped))
          continue;
        Value into = lifetimes::statedLifetime(result);
        if (!into)
          return op.emitOpError("makes a scoped value whose lifetime it states nowhere");
        for (Value operand : op.getOperands()) {
          if (!freedBy(operand.getType(), Release::Scoped))
            continue;
          Value from = lifetimes::statedLifetime(operand);
          if (!from || !outlives(from, into))
            return op.emitOpError("makes a value of a lifetime that outlives one it holds");
        }
      }

    // A value crosses a merge (a region's entry, a yield, a jump) only into a
    // lifetime it outlives: so no value of a region's own lifetime leaves it,
    // and none of an iteration's crosses its back edge.
    LogicalResult merged = success();
    forwardedValues(&op, [&](OpOperand &use, Value input) {
      if (failed(merged) || !freedBy(use.get().getType(), Release::Scoped) ||
          !freedBy(input.getType(), Release::Scoped))
        return;
      Value from = lifetimes::statedLifetime(use.get());
      Value into = lifetimes::statedLifetime(input);
      if (!from || !into || !outlives(from, into))
        merged = op.emitOpError("passes a value on into a lifetime it does not outlive");
    });
    return merged;
  }

  // The frame-limited rule for one lifetime's cells, over the lifetime's
  // direct users. A slot runs once per run of its lifetime: it is rewritten
  // at each run, so a second would free what the first still holds. A
  // room's every put runs once per run, so its bytes are a static sum (a
  // callee given a room puts a bounded amount, its own verifier's rule). In
  // any other lifetime, a cell put once per run is a static amount; a cell
  // put again and again, or the cells a call puts there (unbounded), are
  // each taken into one of the lifetime's own (a field of a cell it states,
  // a value a merge carries on), or are the last put into the lifetime on
  // their path, so at every allocation each cell is reachable from what is
  // still used. `extent` is the lifetime's region; a parameter's is its
  // function's body.
  LogicalResult proof(Value lifetime, Region *extent) {
    Region *within = extent ? extent : &fn.getBody();
    LifetimeKind kind = lifetimes::kindOf(lifetime);
    SmallVector<Value, 2> into{lifetime};
    for (Operation *user : lifetime.getUsers())
      if (auto reserved = dyn_cast<LifetimeReserveOp>(user))
        into.push_back(reserved.getRoom());
    for (Value target : into)
      for (OpOperand &use : target.getUses()) {
        Operation *user = use.getOwner();
        if (states(*user, target) || isa<LifetimeForgetOp>(user))
          continue;
        bool again = runsAgainIn(user, within);
        if (isa<CellStackOp>(user)) {
          if (again)
            return user->emitOpError("is a slot in a region that runs again inside its lifetime");
          continue;
        }
        if (!kind.admitsPuts())
          continue;
        if (kind.isRoom()) {
          if (again)
            return user->emitOpError("puts into a room in a region that runs again inside it");
          continue;
        }
        if (isa<CellArenaOp>(user) && !again)
          continue;
        if (!keptOrLast(*user, target, within, again))
          return user->emitOpError("puts cells into a lifetime that nothing it still uses reaches "
                                   "while it allocates there again");
      }
    return success();
  }

  // Whether `op` puts into `lifetime`, or holds an op that does: a lifetime
  // operand it does not merely state.
  static bool puts(Operation &op, Value lifetime) {
    WalkResult found = op.walk([&](Operation *inner) {
      return llvm::is_contained(inner->getOperands(), lifetime) && !states(*inner, lifetime) &&
                     !isa<LifetimeForgetOp>(inner)
                 ? WalkResult::interrupt()
                 : WalkResult::advance();
    });
    return found.wasInterrupted();
  }

  // Whether each cell `user` puts into `lifetime` is taken into one of the
  // lifetime's own: the box its cell becomes, or a call's scoped result, is
  // an operand of an op that states the lifetime for what it makes, or is
  // carried on by a merge; or, put once per run, whether nothing after it
  // up to the lifetime's end puts into the lifetime again.
  bool keptOrLast(Operation &user, Value lifetime, Region *within, bool again) {
    SmallVector<Value, 2> boxes;
    if (auto cell = dyn_cast<CellArenaOp>(&user)) {
      for (Operation *init : cell.getCell().getUsers())
        boxes.append(init->getResults().begin(), init->getResults().end());
    } else {
      for (Value result : user.getResults())
        if (lifetimes::statedLifetime(result) == lifetime)
          boxes.push_back(result);
    }
    bool kept = llvm::all_of(boxes, [&](Value box) {
      return !freedBy(box.getType(), Release::Scoped) ||
             llvm::any_of(box.getUsers(), [&](Operation *next) {
               return next->hasTrait<OpTrait::IsTerminator>() || states(*next, lifetime);
             });
    });
    if (kept || again)
      return kept;
    for (Operation *at = &user; at && at->getParentRegion() != nullptr;) {
      for (Operation *next = at->getNextNode(); next; next = next->getNextNode())
        if (puts(*next, lifetime))
          return false;
      if (at->getParentRegion() == within)
        return true;
      at = at->getParentOp();
    }
    return true;
  }

  FuncOp fn;
  Block &entry;
  SmallVector<Open, 8> open;
};

} // namespace

LogicalResult idr::verify::lifetimes(FuncOp fn) { return Walk(fn).run(); }
