// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position, and tail position modulo a context.

#include "idr/IR/Tail.h"

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <variant>

using namespace mlir;

namespace idr::tail {

bool endsTail(Block &block) {
  Operation *terminator = block.getTerminator();
  if (isa<ReturnOp>(terminator))
    return true;
  Operation *match = block.getParentOp();
  return isa<YieldOp>(terminator) && isTailMatch(match) && inTailPosition(match);
}

bool inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  return next && next->hasTrait<OpTrait::IsTerminator>() &&
         llvm::equal(op->getResults(), next->getOperands()) && endsTail(*op->getBlock());
}

bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<ReturnOp, YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}

bool isTailMatch(Operation *op) { return isa_and_nonnull<MatchOpInterface>(op); }

Operation *tailMatch(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return passesOnPrevious(terminator) && isTailMatch(prev) ? prev : nullptr;
}

bool isSelfCall(Operation *op, FuncOp fn) {
  auto call = dyn_cast_or_null<CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

namespace {

// Where the call's result is in a value the walk carries: the value is
// the result itself, before its hole; or the holed box is inside it, at
// the field of each constructor down to it, outermost first (the empty
// path is the box itself); or it is inside at a path the regions of a join
// do not agree on, which no read follows.
struct Part {
  Tag tag;
  unsigned index;
  bool operator==(const Part &) const = default;
};
using Parts = SmallVector<Part, 2>;
struct Result {
  bool operator==(const Result &) const = default;
};
struct Inside {
  Parts parts;
  bool operator==(const Inside &) const = default;
};
struct Somewhere {
  bool operator==(const Somewhere &) const = default;
};
using Where = std::variant<Result, Inside, Somewhere>;

// The place a value holds the box in once it is moved into field `index`
// of a constructor `tag`.
Where movedInto(Tag tag, unsigned index, const Where &at) {
  if (const auto *inside = std::get_if<Inside>(&at)) {
    Parts parts{{tag, index}};
    parts.append(inside->parts);
    return Inside{std::move(parts)};
  }
  return Somewhere{};
}

// The regions of `match` that may run: an exhaustive match's default is
// empty.
size_t runningRegions(Operation *match) {
  return static_cast<size_t>(
      llvm::count_if(match->getRegions(), [](Region &r) { return !r.empty(); }));
}

// The field of `init`'s constructor that `use` gives.
unsigned fieldOf(CellInitOp init, OpOperand &use) {
  unsigned given = use.getOperandNumber() - init.getFields().getBeginOperandIndex();
  ArrayRef<int32_t> holes = init.getHoles();
  unsigned index = 0;
  for (;; ++index)
    if (!llvm::is_contained(holes, static_cast<int32_t>(index)) && given-- == 0)
      return index;
}

// The walk from the call's result to the terminator, through every use of
// every value it carries.
class Walk {
public:
  Walk(Block &block, FuncOp fn, CallOp call) : block(block), fn(fn), context{call, {}, {}, {}} {}

  std::optional<Context> run() {
    if (!carry(context.call->getResult(0), Result{}) || !rooted)
      return std::nullopt;
    // Every match the result reached is a join: each of its regions gave it
    // the result.
    for (auto &[match, arrival] : arrivals)
      if (arrival.regions.size() != runningRegions(match))
        return std::nullopt;
    if (!deliver())
      return std::nullopt;
    return context;
  }

private:
  struct Arrival {
    unsigned result;
    Where at;
    llvm::SmallPtrSet<Region *, 4> regions;
  };

  bool carry(Value value, const Where &at) {
    for (OpOperand &use : value.getUses()) {
      Operation *user = use.getOwner();
      if (!seen.insert(user).second && !isa<YieldOp>(user))
        return false;
      if (!step(use, at))
        return false;
    }
    return true;
  }

  bool step(OpOperand &use, const Where &at) {
    Operation *user = use.getOwner();
    bool result = std::holds_alternative<Result>(at);
    if (user == block.getTerminator()) {
      if (result || rooted)
        return false;
      rooted = true;
      return true;
    }
    // A change of grade carries the value on.
    if (user->hasTrait<ResultCarriesOperand>() && use.getOperandNumber() == 0) {
      if (result)
        context.grades.push_back(user);
      return carry(user->getResult(0), at);
    }
    // Into a field of a cell: the holed cell, a fresh one on the heap whose
    // field is a box of what the function returns, or one that holds it.
    if (auto init = dyn_cast<CellInitOp>(user)) {
      if (&use == &init.getCellMutable())
        return false;
      unsigned index = fieldOf(init, use);
      if (!result)
        return carry(init.getResult(), movedInto(init.getTag(), index, at));
      if (init.getCell().getDefiningOp<CellStackOp>() ||
          unrestricted(use.get().getType()) != unrestricted(fn.getResultTypes()[0]))
        return false;
      context.holes.push_back({init, index});
      return carry(init.getResult(), Inside{});
    }
    if (result)
      return false;
    // Into a field of a constructor without a cell; through a yield to the
    // result of a match; or read back out of a constructor without a cell
    // as the part that holds it, where a read of another part takes none of
    // it.
    if (auto con = dyn_cast<ConOp>(user))
      return carry(con.getResult(), movedInto(con.getTag(), use.getOperandNumber(), at));
    if (isa<YieldOp>(user))
      return join(use, at);
    const auto *inside = std::get_if<Inside>(&at);
    if (!inside || inside->parts.empty() || isBoxed(use.get().getType()))
      return false;
    Part part = inside->parts.front();
    Inside rest{Parts(llvm::drop_begin(inside->parts))};
    if (auto unpack = dyn_cast<UnpackOp>(user))
      return unpack.getTag() != part.tag || carry(unpack.getResult(part.index), rest);
    if (auto field = dyn_cast<FieldOp>(user))
      return field.getTag() != part.tag || field.getIndex() != part.index ||
             carry(field.getResult(), rest);
    return false;
  }

  // A yield of a match in the block: the match's result carries the value
  // once every region has given it, at one place or at places only moves
  // tell apart.
  bool join(OpOperand &use, const Where &at) {
    Operation *match = use.getOwner()->getParentOp();
    if (!isa<MatchOpInterface>(match) || !block.findAncestorOpInBlock(*match))
      return false;
    unsigned index = use.getOperandNumber();
    auto [it, fresh] = arrivals.try_emplace(match, Arrival{index, at, {}});
    Arrival &arrival = it->second;
    if (!fresh && arrival.result != index)
      return false;
    if (!fresh && !(arrival.at == at))
      arrival.at = Somewhere{};
    if (!arrival.regions.insert(use.getOwner()->getParentRegion()).second)
      return false;
    if (arrival.regions.size() < runningRegions(match))
      return true;
    return carry(match->getResult(index), arrival.at);
  }

  // Each hole's destination reaches the block: a region of a join that
  // holds a hole, or a join that gives one, gives its destination to the
  // match, which then gives one where it is, when every region does.
  bool deliver() {
    llvm::DenseMap<Block *, unsigned> given;
    for (const Hole &hole : context.holes)
      if (++given[hole.init->getBlock()] > 1)
        return false;
    SmallVector<Operation *> matches;
    for (auto &[match, arrival] : arrivals)
      matches.push_back(match);
    // Innermost first: a match nested in another's region is deeper.
    auto depth = [](Operation *op) {
      unsigned d = 0;
      for (; op; op = op->getParentOp())
        ++d;
      return d;
    };
    llvm::stable_sort(matches, [&](Operation *a, Operation *b) { return depth(a) > depth(b); });
    for (Operation *match : matches) {
      unsigned regions = 0, giving = 0;
      for (Region &region : match->getRegions()) {
        if (region.empty())
          continue;
        ++regions;
        unsigned count = given.lookup(&region.front());
        if (count > 1)
          return false;
        giving += count;
      }
      if (giving == 0)
        continue;
      if (giving != regions || ++given[match->getBlock()] > 1)
        return false;
      context.joins.push_back(match);
    }
    return given.lookup(&block) == 1;
  }

  Block &block;
  FuncOp fn;
  Context context;
  llvm::SmallPtrSet<Operation *, 8> seen;
  llvm::MapVector<Operation *, Arrival> arrivals;
  bool rooted = false;
};

} // namespace

std::optional<Context> contextAt(Block &block, FuncOp fn) {
  Operation *terminator = block.getTerminator();
  if (!isa<ReturnOp, YieldOp>(terminator) || terminator->getNumOperands() != 1)
    return std::nullopt;
  for (Operation &op : block) {
    auto call = dyn_cast<CallOp>(op);
    if (!call || !isSelfCall(call, fn) || call->getNumResults() != 1 ||
        !mayRunAt(call, terminator))
      continue;
    if (std::optional<Context> context = Walk(block, fn, call).run())
      return context;
  }
  return std::nullopt;
}

bool inTailPositionModuloContext(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  if (!fn || !isSelfCall(call, fn))
    return false;
  Block &block = *call->getBlock();
  std::optional<Context> context = contextAt(block, fn);
  return context && context->call == call && endsTail(block);
}

} // namespace idr::tail
