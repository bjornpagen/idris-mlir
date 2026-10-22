// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's frame bound: what an active call of it holds that it no
// longer needs, at most, wherever memory may be acquired while it is
// active. Counting's part of it is the reuse tokens: each holds the emptied
// cell of a take from where it is made to where it is consumed (a recycle
// or a free), passing through a region op that carries it out as a result,
// and held across a region op whose regions consume it. A cell's size is a
// fact of the token's type on the target, and a token that may be null
// counts at its cell's size, so the bound is computed from types and never
// below what a run holds.
//
// One forward walk over the function as reuse leaves it, every token's span
// decided; its blocks wait on a stack on the heap, so a nesting of any depth
// costs no native stack.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <cstdint>
#include <optional>

using namespace mlir;

namespace idr::counting {
namespace {

// A token held, and the bytes of the cell it may hold.
struct Held {
  Value token;
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

// Whether `op` itself may take memory, the ops in its regions apart, which
// the walk meets in turn: a cell or a value it makes, memory its runtime
// function holds, or what a call's callee acquires.
bool acquiresItself(Operation *op) {
  return effects::own(op).row().contains(effects::Atom::alloc);
}

} // namespace

std::uint64_t frameBound(FuncOp fn, const Layouts &layouts) {
  // Every source of a token is a cell of one size, which its recycle's
  // verifier holds, so the first one sizes it.
  auto hold = [&](Holding &held, Value value) {
    auto token = dyn_cast<TokenType>(unrestricted(value.getType()));
    if (!token)
      return;
    auto source = cast<DataType>(token.getSources().front());
    held.push_back(Held{value, layouts.cells(source).cell(*source.singleTag()).size});
  };
  auto release = [](Holding &held, Value value) {
    auto at = llvm::find_if(held, [&](const Held &each) { return each.token == value; });
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
      hold(held, arg);
    for (Operation &op : *at.block) {
      // What the op takes it consumes, or forwards into a region that binds
      // it again; a region op acquires on entry, with all of it held.
      std::uint64_t entering = total(held);
      for (Value operand : op.getOperands())
        release(held, operand);
      if (acquiresItself(&op))
        bound = std::max(bound, op.getNumRegions() == 0 ? total(held) : entering);
      if (op.getNumRegions() != 0) {
        for (Region &region : op.getRegions())
          for (Block &block : region)
            pending.push_back(Pending{&block, held});
        // A token its regions consume is held while they run, and gone
        // after the op.
        llvm::erase_if(held, [&](const Held &each) {
          return llvm::any_of(each.token.getUses(), [&](OpOperand &use) {
            return op.isProperAncestor(use.getOwner());
          });
        });
      }
      for (Value result : op.getResults())
        hold(held, result);
    }
  }
  return bound;
}

} // namespace idr::counting
