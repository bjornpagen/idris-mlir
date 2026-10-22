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
// One forward walk over the function as reuse leaves it, every token's span
// decided; its blocks wait on a stack on the heap, so a nesting of any depth
// costs no native stack.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <variant>

using namespace mlir;

namespace idr::counting {
namespace {

// A value the call holds that it no longer needs, and the bytes it holds.
struct Held {
  Value value;
  std::uint64_t bytes;
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

// Whether `use` gives its value up: the op takes its reference over, gives
// nothing of it back, and carries it whole into no callee, no caller and no
// field. It ends it there (a drop, a store into memory no edge follows) or
// takes it apart into its token and fields (a take, placement's where a
// part outlives it, or reuse's where its cell is recycled, fused or not)
// or into its fields (an unpack). A use that reads it, lends it again,
// forwards it into a region or passes it on keeps it needed.
bool givesUp(OpOperand &use) {
  Operation *op = use.getOwner();
  if (!effects::consumes(use) || (use.getOperandNumber() == 0 && givesOperandBack(op)))
    return false;
  FlowEdges edges;
  flowEdgesOf(op, edges);
  return llvm::none_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    const auto *flow = std::get_if<FlowEdges::Flow>(&edge.move);
    if (!flow || !edge.carries(Carrier::Reference))
      return false;
    const auto *taken = std::get_if<FlowPoint::Taken>(&flow->from.at);
    return taken && taken->use == &use && !std::holds_alternative<FlowPoint::Whole>(flow->to.at);
  });
}

} // namespace

std::uint64_t frameBound(FuncOp fn, const Layouts &layouts) {
  // Every source of a token is a cell of one size, which its recycle's
  // verifier holds, so the first one sizes it.
  auto holdToken = [&](Holding &held, Value value) {
    auto token = dyn_cast<TokenType>(unrestricted(value.getType()));
    if (!token)
      return;
    auto source = cast<DataType>(token.getSources().front());
    held.push_back(Held{value, layouts.cells(source).cell(*source.singleTag()).size});
  };
  // Each owner `loan` gives back that every later use only gives up (none
  // at all on a path that ends the process with nothing allocated after
  // it), held from the loan on, its region included, until it is given up.
  auto holdOwners = [&](Holding &held, Operation &loan) {
    for (Value owner : loan.getResults()) {
      if (!givenBack(owner) || !llvm::all_of(owner.getUses(), givesUp))
        continue;
      // Borrowing lends a value no later use needs only where its type
      // bounds what it reaches, and passes any other owned; so an owner
      // whose type bounds nothing is needed after its loan, reachable from
      // what the program will use, and no frame holds it past its last use.
      if (std::optional<std::uint64_t> bytes = layouts.reachedBytes(owner.getType()))
        held.push_back(Held{owner, *bytes});
    }
  };
  auto release = [](Holding &held, Value value) {
    auto at = llvm::find_if(held, [&](const Held &each) { return each.value == value; });
    if (at != held.end())
      held.erase(at);
  };
  std::uint64_t bound = 0;
  llvm::SmallVector<Pending, 8> pending;
  pending.push_back(Pending{&fn.getBody().front(), {}});
  while (!pending.empty()) {
    Pending at = pending.pop_back_val();
    Holding held = std::move(at.held);
    for (BlockArgument arg : at.block->getArguments())
      holdToken(held, arg);
    for (Operation &op : *at.block) {
      // What the op takes it consumes, or forwards into a region that binds
      // it again; a region op acquires on entry, with all of it held. The
      // op's own effects alone: the walk meets the ops in its regions in
      // turn.
      std::uint64_t entering = total(held);
      for (Value operand : op.getOperands())
        release(held, operand);
      if (op.hasTrait<RunsOnceGivingBack>())
        holdOwners(held, op);
      if (effects::mayAcquire(effects::own(&op)))
        bound = std::max(bound, op.getNumRegions() == 0 ? total(held) : entering);
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
        holdToken(held, result);
    }
  }
  return bound;
}

} // namespace idr::counting
