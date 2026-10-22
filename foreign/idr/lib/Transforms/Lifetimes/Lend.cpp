// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lending to upstream's ops (Lend.h): each holder an op of upstream's reads
// given to it as a loan, by who frees the holder. A loan's region is the
// smallest a region can be that holds the reads and every use of their
// aliases: in the innermost block holding them all, from the first of them
// there to the last, as the walk of a loan's aliases finds them
// (Lifetimes/Loans.h). Where none can, the holder is shared into the read,
// which costs a duplicate and a drop and never a meaning.

#include "idr/Transforms/Lifetimes/Lend.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Lifetimes/Loans.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Lifetimes/Plan.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <optional>

using namespace mlir;
using namespace idr;
using namespace idr::lifetimes;
using solver::FunctionId;

// A value a write stores is taken over by the memory it goes into, which
// own.give hands its reference: no read.
bool idr::lifetimes::readByUpstream(OpOperand &use) {
  return ownership::carriersOnly(use.getOwner()) && !ownership::storedBy(use);
}

namespace {

// Where a loan's region stands: the ops from `first` to `last`, siblings.
struct Span {
  Operation *first;
  Operation *last;
};

// Whether the op of upstream's that reads `use` takes it over: a tensor it
// writes, whose result is the tensor's next version. Only a tensor can be,
// so bufferization is asked of a tensor alone.
bool takenOver(OpOperand &use, std::optional<bufferization::AnalysisState> &state) {
  if (!isa<bufferization::TensorLikeType>(use.get().getType()))
    return false;
  if (!state)
    state.emplace(aliasOptions());
  return state->bufferizesToMemoryWrite(use);
}

// The op that makes `value`: the one that defines it, or the one whose
// region binds it (a function, for its parameter).
Operation *makerOf(Value value) {
  if (Operation *def = value.getDefiningOp())
    return def;
  return cast<BlockArgument>(value).getOwner()->getParentOp();
}

// The smallest region that holds the reads `reads` of `holder` and every
// use of their aliases, or none where no region can: an alias goes on
// through a region branch (counting would then give it a reference of its
// own) or out of the loan; the holder is made inside the ops the region
// would hold, which it must outlive; or those ops hold a call in tail
// position, a jump out of them, or a call that continues on a frame, which
// splits its function where no region can be split.
std::optional<Span> spanOf(Value holder, ArrayRef<OpOperand *> reads, FunctionId self,
                           const solver::ProgramGraph &graph) {
  SmallVector<Operation *, 8> users;
  enum class Kept : std::uint8_t { InLoan, Out } kept = Kept::InLoan;
  forEachLoanUse(
      reads, [](Value) {},
      [&](OpOperand &use, LoanUse kind) {
        users.push_back(use.getOwner());
        if (kind != LoanUse::Reads)
          kept = Kept::Out;
      });
  if (kept == Kept::Out)
    return std::nullopt;

  // The innermost block holding every use: the function's body holds all.
  Block *block = users.front()->getBlock();
  for (Operation *user : users)
    while (!block->findAncestorOpInBlock(*user))
      block = block->getParentOp()->getBlock();
  Operation *first = nullptr;
  Operation *last = nullptr;
  for (Operation *user : users) {
    Operation *top = block->findAncestorOpInBlock(*user);
    if (!first || top->isBeforeInBlock(first))
      first = top;
    if (!last || last->isBeforeInBlock(top))
      last = top;
  }
  auto within = [&](Operation *op) {
    Operation *top = block->findAncestorOpInBlock(*op);
    return top && !top->isBeforeInBlock(first) && !last->isBeforeInBlock(top);
  };
  if (within(makerOf(holder)) || last->hasTrait<OpTrait::IsTerminator>())
    return std::nullopt;

  SmallVector<Operation *, 16> held;
  for (Operation *op = first;; op = op->getNextNode()) {
    op->walk([&](Operation *nested) { held.push_back(nested); });
    if (op == last)
      break;
  }
  auto framed = [&](Operation *op) {
    auto call = dyn_cast<CallOp>(op);
    return call && decide::continuesOnFrame(graph, self, call);
  };
  if (!decide::regionMayHold(*block, first, last, held) || llvm::any_of(held, framed))
    return std::nullopt;
  return Span{first, last};
}

// The view of `lifetime`, of its extent, which is all a loan reads of it:
// the lifetime itself where it is a view, else its view made where `b`
// stands.
Value viewOf(OpBuilder &b, Location loc, Value lifetime) {
  if (isViewLifetime(lifetime.getType()))
    return lifetime;
  return LifetimeForgetOp::create(b, loc, LifetimeType::get(b.getContext(), LifetimeKind::view()),
                                  lifetime);
}

// A carrier for each read of `holder`, right before the op that reads it,
// under `lifetime`'s view, so a loan's aliases live no longer than its read
// needs them.
void project(Value holder, Value lifetime, ArrayRef<OpOperand *> reads) {
  for (OpOperand *read : reads) {
    Operation *user = read->getOwner();
    OpBuilder b(user);
    read->set(CarrierOp::create(b, user->getLoc(), holder, viewOf(b, user->getLoc(), lifetime))
                  .getResult());
  }
}

// A view lifetime opened at `span`, and the reads lent under it.
void openLoan(Value holder, const Span &span, ArrayRef<OpOperand *> reads) {
  Value lifetime =
      decide::openLifetime(decide::Opening::NoMemory, span.first, span.last, Value());
  OpBuilder b = OpBuilder::atBlockBegin(cast<BlockArgument>(lifetime).getOwner());
  Value lent =
      CarrierOp::create(b, reads.front()->getOwner()->getLoc(), holder, lifetime).getResult();
  for (OpOperand *read : reads)
    read->set(lent);
}

// The holder shared into one read: its reference given up into a value no
// flow explains, which no pass grades; placement duplicates the holder
// first where it is used after.
void share(Value holder, OpOperand &read) {
  Operation *user = read.getOwner();
  OpBuilder b(user);
  read.set(
      CountShareOp::create(b, user->getLoc(), shared(holder.getType()), holder).getResult());
}

// A counted holder's reads: one loan for all where a region can hold them,
// else one per read, else a share into it.
Lending lendCounted(Value holder, ArrayRef<OpOperand *> reads, FunctionId self,
                    const solver::ProgramGraph &graph) {
  Lending made;
  made.rewritten = static_cast<unsigned>(reads.size());
  if (std::optional<Span> span = spanOf(holder, reads, self, graph)) {
    openLoan(holder, *span, reads);
    made.opened = 1;
    return made;
  }
  for (OpOperand *read : reads) {
    if (std::optional<Span> span = spanOf(holder, read, self, graph)) {
      openLoan(holder, *span, read);
      ++made.opened;
    } else {
      share(holder, *read);
    }
  }
  return made;
}

} // namespace

Lending idr::lifetimes::lend(FuncOp fn, FunctionId self, const solver::ProgramGraph &graph,
                             ArrayRef<Value> holders) {
  Lending made;
  std::optional<bufferization::AnalysisState> state;
  for (Value holder : holders) {
    SmallVector<OpOperand *, 4> reads;
    SmallVector<OpOperand *, 4> taken;
    for (OpOperand &use : holder.getUses())
      if (readByUpstream(use))
        (takenOver(use, state) ? taken : reads).push_back(&use);
    // A tensor taken over meets its value at the bare grade, which a holder
    // at a grade past it is shared down to.
    if (holder.getType() != unrestricted(holder.getType()))
      for (OpOperand *use : taken) {
        share(holder, *use);
        ++made.rewritten;
      }
    if (reads.empty())
      continue;
    switch (holdOf(holder.getType())->release()) {
    case Release::Scoped: {
      Value own = statedLifetime(holder);
      assert(own && "the verifier holds every scoped value to the lifetime it states");
      project(holder, own, reads);
      made.rewritten += static_cast<unsigned>(reads.size());
      break;
    }
    case Release::Static:
      project(holder, decide::activationOf(fn), reads);
      made.rewritten += static_cast<unsigned>(reads.size());
      break;
    case Release::Counted: {
      Lending counted = lendCounted(holder, reads, self, graph);
      made.opened += counted.opened;
      made.rewritten += counted.rewritten;
      break;
    }
    }
  }
  return made;
}

Lending idr::lifetimes::lendReads(FuncOp fn, FunctionId self, const solver::ProgramGraph &graph,
                                  Holders which) {
  // A type at a grade past its carrier's bare one is not its carrier.
  auto taken = [&](Type type) { return which == Holders::Every || type != unrestricted(type); };
  SmallVector<Value> holders;
  solver::inWalkOrder(fn, [&](Value value) {
    if (isLendable(value.getType()) && taken(value.getType()) && !loanOf(value) &&
        llvm::any_of(value.getUses(), readByUpstream))
      holders.push_back(value);
  });
  return lend(fn, self, graph, holders);
}

// A loan's region is an opener of no memory; one whose lifetime a slot, a
// cell or another loan still names stays where it is.
void idr::lifetimes::reproject(CarrierOp loan, Value lifetime) {
  Value before = loan.getLifetime();
  OpBuilder b(loan);
  loan.getLifetimeMutable().assign(viewOf(b, loan.getLoc(), lifetime));
  auto arg = dyn_cast<BlockArgument>(before);
  if (!arg || !before.use_empty())
    return;
  auto opener = dyn_cast<LifetimeOp>(arg.getOwner()->getParentOp());
  if (!opener)
    return;
  Block &body = opener.getBody().front();
  Operation *yield = body.getTerminator();
  opener->replaceAllUsesWith(yield->getOperands());
  yield->erase();
  opener->getBlock()->getOperations().splice(Block::iterator(opener), body.getOperations());
  opener->erase();
}
