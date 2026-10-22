// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's frame bound: what an active call of it holds that it no
// longer needs, at most, wherever memory may be acquired while it is
// active. Counting's part of it is two kinds of value held dead:
//   - a reuse token holds the emptied cell of a take from where it is made
//     to where it is consumed (a recycle or a free), passing through a
//     region op that carries it out as a result, and held across a region
//     op whose regions consume it. A cell's size is a fact of the token's
//     type on the target, and a token that may be null counts at its cell's
//     size;
//   - an owner lent to a call and needed by nothing after its loan is held
//     from the loan, past the callee's last read of its view, which only
//     the run knows, until it is given up: everything it reaches, which its
//     type bounds.
// So the bound is computed from types and never below what a run holds.
//
// One forward walk over the function, read two ways: the bound, the most
// held at any op that may acquire, on the function as reuse leaves it; and
// the points where what is held rises or falls, on the function as the
// lowering finds it, which the checked runtime's account follows. A token
// moved on unchanged changes nothing, so it has no point: the use that
// forwards it and the value that receives it are the two sides of one
// region-branch edge, or of an op that gives its operand back. The walk's
// blocks wait on a stack on the heap, so a nesting of any depth costs no
// native stack.
#include "idr/Transforms/Counting/Bound.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>

using namespace mlir;

namespace idr::counting {
namespace {

// How far a held value's hold reaches: a token's follows it through every
// op that moves it on unchanged, into the value that receives it, which
// holds it again, and ends where it is consumed; a lent owner's ends at its
// first use, each of which gives it up, one that moves it on included,
// since nothing that receives it holds it again.
enum class Span : std::uint8_t { ToConsumption, ToFirstUse };

// A value the call holds that it no longer needs, the bytes it holds, and
// how far it holds them.
struct Held {
  Value value;
  std::uint64_t bytes;
  Span span;
};

using Holding = llvm::SmallVector<Held, 4>;

// A block to walk, holding what was held where its region was entered.
struct Pending {
  Block *block;
  Holding held;
};

std::uint64_t total(const Holding &held) {
  std::uint64_t bytes = 0;
  for (const Held &each : held)
    bytes += each.bytes;
  return bytes;
}

// Whether `value` is an owner a loan gives back: a loan's first result, or
// a later result whose value its region yields there and that is itself
// such an owner. A site that lends two values is lent again from outside,
// so the loan around another gives back the inner loan's owner too, and
// only the outermost gives it back to the code after the nest.
bool givenBack(Value value) {
  for (auto result = dyn_cast<OpResult>(value); result;) {
    Operation *loan = result.getOwner();
    if (!loan->hasTrait<RunsOnceGivingBack>())
      return false;
    unsigned at = result.getResultNumber();
    if (at == 0)
      return true;
    auto yield = cast<RegionBranchTerminatorOpInterface>(loan->getRegion(0).front().getTerminator());
    result = dyn_cast<OpResult>(yield.getSuccessorOperands(RegionSuccessor(loan))[at - 1]);
  }
  return false;
}

// Whether `edge` carries the reference `use` holds on, kept: a move of the
// use itself into a part of a value, a callee's parameter or a caller's
// result. A move into a value whole hands it to a value that holds it
// again, so it keeps nothing of the use's.
bool keepsReference(const FlowEdges::Edge &edge, OpOperand &use) {
  if (!edge.carries(Carrier::Reference))
    return false;
  return match(
      edge.move,
      [&](const FlowEdges::Flow &flow) {
        bool fromUse = match(
            flow.from.at, [&](const FlowSource::Taken &taken) { return taken.use == &use; },
            [](const OneOf<FlowSource::Whole, FlowSource::Part, FlowSource::Parameter,
                           FlowSource::Result> auto &) { return false; });
        bool kept = match(
            flow.to.at, [](const FlowSource::Whole &) { return false; },
            [](const OneOf<FlowPlace::Part, FlowSource::Parameter, FlowSource::Result> auto &) {
              return true;
            });
        return fromUse && kept;
      },
      [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh, FlowEdges::Release,
                     FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Constant, FlowEdges::Dispatch> auto &) {
        return false;
      });
}

// Whether `use` gives its value up: the op takes its reference over, gives
// nothing of it back, and carries it whole into no callee, no caller and no
// field. It ends it there (a drop, a store into memory no edge follows) or
// takes it apart into its token and fields (a take, placement's where a
// part outlives it, or reuse's where its cell is recycled, fused or not)
// or into its fields (an unpack); the match on its uniqueness, the take's
// expansion, takes it over and moves it into its shared region. A use that
// reads it, lends it again, or moves it on without taking it over keeps it
// needed.
bool givesUp(OpOperand &use) {
  Operation *op = use.getOwner();
  if (!effects::consumes(use) || (use.getOperandNumber() == 0 && givesOperandBack(op)))
    return false;
  FlowEdges edges;
  flowEdgesOf(op, edges);
  return llvm::none_of(edges.edges(),
                       [&](const FlowEdges::Edge &edge) { return keepsReference(edge, use); });
}

// The operands `op` moves on unchanged: what a region branch forwards, as
// upstream's interface says, and the first operand of an op that gives it
// back, which its trait says it has.
llvm::SmallBitVector forwardedOperands(Operation *op) {
  llvm::SmallBitVector forwarded(op->getNumOperands());
  forwardedValues(op, [&](OpOperand &use, Value) { forwarded.set(use.getOperandNumber()); });
  if (givesOperandBack(op))
    forwarded.set(0);
  return forwarded;
}

// Whether `value` receives unchanged what a forwarded operand held: a
// region's argument or a result a region branch forwards into, or the
// result an op gives its first operand back as. The other side of
// forwardedOperands, read off the same interfaces.
bool receivesForwarded(Value value) {
  if (auto argument = dyn_cast<BlockArgument>(value)) {
    Block *block = argument.getOwner();
    auto branch = dyn_cast<RegionBranchOpInterface>(block->getParentOp());
    return branch && block->isEntryBlock() &&
           llvm::is_contained(branch.getSuccessorInputs(RegionSuccessor(block->getParent())),
                              value);
  }
  auto result = cast<OpResult>(value);
  Operation *op = result.getOwner();
  if (result.getResultNumber() == 0 && givesOperandBack(op))
    return true;
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return branch && llvm::is_contained(branch.getSuccessorInputs(RegionSuccessor(op)), value);
}

// A reader of the walk states what it reads by what it can be told: each
// point where what is held changes, or what is held at each op that may
// acquire memory. The walk works out only what its reader reads.
template <typename Reader>
concept ReadsPoints = requires(Reader &reader, const HoldPoint &point) { reader.changes(point); };

template <typename Reader>
concept ReadsPeaks = requires(Reader &reader, std::uint64_t held) { reader.acquires(held); };

template <typename Reader>
concept ReadsHolding = ReadsPoints<Reader> || ReadsPeaks<Reader>;

template <ReadsHolding Reader>
void walkHolding(FuncOp fn, const Layouts &layouts, Reader &reader) {
  auto changes = [&](Where where, Direction direction, std::uint64_t bytes) {
    if constexpr (ReadsPoints<Reader>)
      reader.changes(HoldPoint{where, direction, bytes});
  };
  // Every source of a token is a cell of one size, which its recycle's
  // verifier holds, so the first one sizes it. A token that receives a
  // forwarded one was held already.
  auto holdToken = [&](Holding &held, Value value, Where where) {
    auto token = dyn_cast<ReuseTokenType>(unrestricted(value.getType()));
    if (!token)
      return;
    auto source = cast<DataType>(token.getSources().front());
    std::uint64_t bytes = layouts.cells(source).cell(*source.singleTag()).size;
    held.push_back(Held{value, bytes, Span::ToConsumption});
    if constexpr (ReadsPoints<Reader>)
      if (!receivesForwarded(value))
        changes(where, Direction::Rises, bytes);
  };
  // Each owner `loan` gives back that every later use only gives up (none
  // at all on a path that ends the process with nothing allocated after
  // it), held from the start of the loan's region on, until it is given up.
  auto holdOwners = [&](Holding &held, Operation &loan) {
    for (Value owner : loan.getResults()) {
      if (!givenBack(owner) || !llvm::all_of(owner.getUses(), givesUp))
        continue;
      // Borrowing lends a value no later use needs only where its type
      // bounds what it reaches, and passes any other owned; so an owner
      // whose type bounds nothing is needed after its loan, reachable from
      // what the program will use, and no frame holds it past its last use.
      std::optional<std::uint64_t> bytes = layouts.reachedBytes(owner.getType());
      if (!bytes)
        continue;
      held.push_back(Held{owner, *bytes, Span::ToFirstUse});
      changes(Where::atStart(loan.getRegion(0).front()), Direction::Rises, *bytes);
    }
  };
  // A use of a held value ends its hold there, unless the value is a token
  // the op moves on unchanged into one that holds it again.
  auto release = [&](Holding &held, Operation &op) {
    llvm::SmallBitVector forwarded;
    if constexpr (ReadsPoints<Reader>)
      forwarded = forwardedOperands(&op);
    for (OpOperand &use : op.getOpOperands()) {
      auto at = llvm::find_if(held, [&](const Held &each) { return each.value == use.get(); });
      if (at == held.end())
        continue;
      if constexpr (ReadsPoints<Reader>)
        if (at->span == Span::ToFirstUse || !forwarded.test(use.getOperandNumber()))
          changes(Where::before(&op), Direction::Falls, at->bytes);
      held.erase(at);
    }
  };
  llvm::SmallVector<Pending, 8> pending;
  pending.push_back(Pending{&fn.getBody().front(), {}});
  while (!pending.empty()) {
    Pending at = pending.pop_back_val();
    Holding held = std::move(at.held);
    for (BlockArgument arg : at.block->getArguments())
      holdToken(held, arg, Where::atStart(*at.block));
    for (Operation &op : *at.block) {
      // A region op acquires on entry, with all of it held. The op's own
      // effects alone: the walk meets the ops in its regions in turn.
      std::uint64_t entering = total(held);
      release(held, op);
      if (op.hasTrait<RunsOnceGivingBack>())
        holdOwners(held, op);
      if constexpr (ReadsPeaks<Reader>)
        if (effects::mayAcquire(effects::own(&op)))
          reader.acquires(op.getNumRegions() == 0 ? total(held) : entering);
      if (op.getNumRegions() != 0) {
        for (Region &region : op.getRegions())
          for (Block &block : region)
            pending.push_back(Pending{&block, held});
        // A value its regions consume is held while they run, and gone
        // after the op.
        llvm::erase_if(held, [&](const Held &each) {
          return llvm::any_of(each.value.getUses(), [&](OpOperand &use) {
            return op.isProperAncestor(use.getOwner());
          });
        });
      }
      for (Value result : op.getResults())
        holdToken(held, result, Where::past(&op));
    }
  }
}

// The bound reads the most held where memory may be acquired.
struct Peak {
  std::uint64_t bound = 0;
  void acquires(std::uint64_t held) { bound = std::max(bound, held); }
};

// The account reads the points.
struct Points {
  llvm::SmallVector<HoldPoint> points;
  void changes(const HoldPoint &point) { points.push_back(point); }
};

} // namespace

std::int64_t frameBound(FuncOp fn, const Layouts &layouts) {
  Peak peak;
  walkHolding(fn, layouts, peak);
  // Bytes held at once in one address space: below 2^63, the signed word's
  // range, by the address space's size.
  assert(peak.bound <= static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max()) &&
         "a frame holds more bytes than an address space");
  return static_cast<std::int64_t>(peak.bound);
}

llvm::SmallVector<HoldPoint> holdPoints(FuncOp fn, const Layouts &layouts) {
  Points points;
  walkHolding(fn, layouts, points);
  return std::move(points.points);
}

} // namespace idr::counting
