// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lending to upstream's ops (Lend.h): each holder an op of upstream's reads
// given to it as a loan, by who frees the holder. A loan of a holder a
// lifetime or a count frees stands on a span: the stretch of the innermost
// block holding its reads and every use of their aliases, from the first of
// them there to the last, as the walk of a loan's aliases finds them
// (Lifetimes/Loans.h), with no call in it that continues on a frame. A
// counted holder's span becomes the loan's own region where a region can
// hold it, else the holder is shared into the read, which costs a duplicate
// and a drop and never a meaning; a scoped holder's lies inside its own
// lifetime. Static data, which nothing frees, is lent at each read.

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

// Where a loan's aliases stand: the ops from `first` to `last`, siblings in
// `block`, and `held`, those ops and everything in them.
struct Span {
  Block *block;
  Operation *first;
  Operation *last;
  SmallVector<Operation *, 16> held;
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

// The span of the reads `reads`: the stretch that holds them and every use
// of their aliases, or none where no stretch does. None where an alias goes
// on through a region branch (counting would then give it a reference of
// its own, and an opener's yield is one, so no alias leaves the region of a
// lifetime it was lent under) or out of the loan; and none where a call
// that continues on a frame stands in the stretch, after which frames move
// the code on into a function of its own, where a frame would hold the
// alias, a reference of no one's that no rule follows across.
std::optional<Span> spanOf(ArrayRef<OpOperand *> reads, FunctionId self,
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
  Span span{block, nullptr, nullptr, {}};
  for (Operation *user : users) {
    Operation *top = block->findAncestorOpInBlock(*user);
    if (!span.first || top->isBeforeInBlock(span.first))
      span.first = top;
    if (!span.last || span.last->isBeforeInBlock(top))
      span.last = top;
  }
  for (Operation *op = span.first;; op = op->getNextNode()) {
    op->walk([&](Operation *nested) { span.held.push_back(nested); });
    if (op == span.last)
      break;
  }
  auto framed = [&](Operation *op) {
    auto call = dyn_cast<CallOp>(op);
    return call && decide::continuesOnFrame(graph, self, call);
  };
  if (llvm::any_of(span.held, framed))
    return std::nullopt;
  return span;
}

// Whether a loan's own region can hold `span`, lending `holder`: the
// holder is made outside it, since it outlives the loan; the span ends
// before its block's terminator, where a region's own end goes; and it
// holds no call in tail position and no jump out of it, which no region
// the pass opens holds.
bool regionHolds(Value holder, const Span &span) {
  if (Operation *maker = span.block->findAncestorOpInBlock(*makerOf(holder));
      maker && !maker->isBeforeInBlock(span.first) && !span.last->isBeforeInBlock(maker))
    return false;
  return !span.last->hasTrait<OpTrait::IsTerminator>() &&
         decide::regionMayHold(*span.block, span.first, span.last, span.held);
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

// `holder` lent under `lifetime`'s view where `b` stands: every loan the
// pass makes, whoever frees the holder.
Value lendHere(OpBuilder &b, Location loc, Value holder, Value lifetime) {
  return CarrierOp::create(b, loc, holder, viewOf(b, loc, lifetime)).getResult();
}

// A view lifetime opened at `span`, and the reads lent under it.
void openLoan(Value holder, const Span &span, ArrayRef<OpOperand *> reads) {
  Value lifetime =
      decide::openLifetime(decide::Opening::NoMemory, span.first, span.last, Value());
  OpBuilder b = OpBuilder::atBlockBegin(cast<BlockArgument>(lifetime).getOwner());
  Value lent = lendHere(b, reads.front()->getOwner()->getLoc(), holder, lifetime);
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
  auto region = [&](ArrayRef<OpOperand *> some) -> std::optional<Span> {
    std::optional<Span> span = spanOf(some, self, graph);
    if (!span || !regionHolds(holder, *span))
      return std::nullopt;
    return span;
  };
  Lending made;
  made.rewritten = static_cast<unsigned>(reads.size());
  if (std::optional<Span> span = region(reads)) {
    openLoan(holder, *span, reads);
    made.opened = 1;
    return made;
  }
  for (OpOperand *read : reads) {
    if (std::optional<Span> span = region(read)) {
      openLoan(holder, *span, read);
      ++made.opened;
    } else {
      share(holder, *read);
    }
  }
  return made;
}

// A scoped holder's reads, each projected under the holder's own lifetime
// on its span, at the span's start: the read itself, since every alias of
// it is made after it, in its region. No region is opened, so the span is
// the whole of what keeps the loan's aliases to the lifetime: none leaves
// the stretch, so none leaves the lifetime's region, and none outlives a
// call that continues on a frame, so no frame holds one, and no loan of a
// scoped holder is lent again from outside the code frames move, whatever
// the holder lives in (this activation's slots, which the code after such a
// call no longer has, among them). The decide step counts every holder an
// op of upstream's reads into a value that holds references, since it
// counts every value no op states a lifetime for and every operand of an
// op that declares no flow, so a scoped holder's read gives no alias and
// its span is the read alone.
void projectScoped(Value holder, ArrayRef<OpOperand *> reads, FunctionId self,
                   const solver::ProgramGraph &graph) {
  Value own = statedLifetime(holder);
  assert(own && "the verifier holds every scoped value to the lifetime it states");
  for (OpOperand *read : reads) {
    std::optional<Span> span = spanOf(read, self, graph);
    assert(span && "a scoped holder's read gives no alias: the decide step counts a holder an "
                   "op of upstream's reads into a value that holds references");
    OpBuilder b(span->first);
    read->set(lendHere(b, read->getOwner()->getLoc(), holder, own));
  }
}

// Static data's reads, each lent right before it under this activation's
// lifetime: nothing frees static data, so its loan stands in any lifetime,
// and its aliases may go wherever the program takes them; code that frames
// move lends it again under that code's own activation.
void projectStatic(FuncOp fn, Value holder, ArrayRef<OpOperand *> reads) {
  Value activation = decide::activationOf(fn);
  for (OpOperand *read : reads) {
    OpBuilder b(read->getOwner());
    read->set(lendHere(b, read->getOwner()->getLoc(), holder, activation));
  }
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
    case Release::Scoped:
      projectScoped(holder, reads, self, graph);
      made.rewritten += static_cast<unsigned>(reads.size());
      break;
    case Release::Static:
      projectStatic(fn, holder, reads);
      made.rewritten += static_cast<unsigned>(reads.size());
      break;
    case Release::Counted:
      made += lendCounted(holder, reads, self, graph);
      break;
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
