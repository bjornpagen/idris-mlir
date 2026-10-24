// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Lending to upstream's ops (Lend.h): each holder an op of upstream's reads
// given to it as a loan, by who frees the holder, and no loan changes a
// count. A counted holder's loan stands on its stretch: the ops of the
// innermost block holding its reads and every use of their aliases, as the
// walk of a loan's aliases finds them (Lifetimes/Loans.h), from the first of
// them there to the last. The stretch is cut at each op there that no
// loan's region may hold: one holding a call that runs on a frame, after
// which frames move the code on into a function of its own, where a frame
// would hold an alias of the loan and a lifetime with no memory has nothing
// to carry; a call in tail position; a jump out. The reads on each side of
// the cuts are one loan, under a view lifetime opened around them; a view
// made on one side and read on another is made again on that side, of that
// side's own loan, as frames lend static data again (remakeAlias); and the
// reads inside a cut are lent again inside it. A read one of whose aliases
// goes out of the loan is no loan: counting gives that alias a reference of
// its own, so the holder is shared into the read. A scoped holder's loan
// lies inside its own lifetime, and static data, which nothing frees, is
// lent at each read.

#include "idr/Transforms/Lifetimes/Lend.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Lifetimes/Loans.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Lifetimes/Plan.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <cstdint>
#include <iterator>
#include <optional>
#include <utility>

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

// A loan's walk from its reads: every use of the loan, the reads among
// them, and every alias it reaches, the walk's own and sized by the loan.
struct Walked {
  SmallVector<OpOperand *, 16> uses;
  llvm::SmallDenseSet<Value, 8> aliases;
};

Walked walkLoan(ArrayRef<OpOperand *> reads) {
  Walked walked;
  forEachLoanUse(
      reads, [&](Value alias) { walked.aliases.insert(alias); },
      [&](OpOperand &use, LoanUse) { walked.uses.push_back(&use); });
  return walked;
}

// Whether the loan of `read` keeps every alias of it among reads, or one
// goes out: forwarded on through a region branch (counting would then give
// it a reference of its own, and an opener's yield is one, so no alias
// leaves the region of a lifetime it was lent under), returned, stored as
// the value a write puts into memory, or adopted by an op of ours.
enum class Kept : std::uint8_t { InLoan, Out };

Kept keptOf(OpOperand *read) {
  Kept kept = Kept::InLoan;
  forEachLoanUse(
      read, [](Value) {},
      [&](OpOperand &, LoanUse kind) {
        if (kind != LoanUse::Reads)
          kept = Kept::Out;
      });
  return kept;
}

// The innermost block holding every one of `uses`: the function's body
// holds all.
Block *innermost(ArrayRef<OpOperand *> uses) {
  Block *block = uses.front()->getOwner()->getBlock();
  for (OpOperand *use : uses)
    while (!block->findAncestorOpInBlock(*use->getOwner()))
      block = block->getParentOp()->getBlock();
  return block;
}

// The ops of `block`, which holds every one of `uses`, from the first that
// holds one to the last.
Span spanIn(Block *block, ArrayRef<OpOperand *> uses) {
  Span span{block, nullptr, nullptr, {}};
  for (OpOperand *use : uses) {
    Operation *top = block->findAncestorOpInBlock(*use->getOwner());
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
  return span;
}

// Whether `op`, or a call in it, runs on a frame, as the graph decides for
// a call made in function `self`.
bool holdsCallOnFrame(Operation *op, FunctionId self, const solver::ProgramGraph &graph) {
  solver::SccId from = graph.sccOf(self);
  return op
      ->walk([&](FunctionCallOpInterface call) {
        return graph.runsOnFrame(from, call) ? WalkResult::interrupt() : WalkResult::advance();
      })
      .wasInterrupted();
}

// Whether a loan's region may hold `top`, an op of `block`, with everything
// in it: no call in it runs on a frame, after which frames move the code on
// into a function of its own, where a frame would hold an alias of the
// loan, a reference of no one's that no rule follows across, and a lifetime
// with no memory has nothing a frame could carry; it is not the block's
// terminator, before which a region's own end goes; and the rule every
// region the pass opens keeps holds of it alone. A jump in it goes to a
// join point around it or outside the block, since a join point's token is
// bound in its own region, so what holds of each op holds of a stretch.
bool mayHold(Block &block, Operation *top, FunctionId self, const solver::ProgramGraph &graph) {
  if (top->hasTrait<OpTrait::IsTerminator>() || holdsCallOnFrame(top, self, graph))
    return false;
  SmallVector<Operation *, 16> held;
  top->walk([&](Operation *nested) { held.push_back(nested); });
  return decide::regionMayHold(block, top, top, held);
}

// Whether a loan's region may hold every op of `span`.
bool mayHoldAll(const Span &span, FunctionId self, const solver::ProgramGraph &graph) {
  for (Operation *op = span.first;; op = op->getNextNode()) {
    if (!mayHold(*span.block, op, self, graph))
      return false;
    if (op == span.last)
      return true;
  }
}

// Whether a loan's own region can hold `span`, lending `holder`: the holder
// is made outside it, since it outlives the loan, and the rule every region
// the pass opens keeps holds of it.
bool regionHolds(Value holder, const Span &span) {
  if (Operation *maker = span.block->findAncestorOpInBlock(*makerOf(holder));
      maker && !maker->isBeforeInBlock(span.first) && !span.last->isBeforeInBlock(maker))
    return false;
  return !span.last->hasTrait<OpTrait::IsTerminator>() &&
         decide::regionMayHold(*span.block, span.first, span.last, span.held);
}

// Where an op of a loan's stretch stands among the stretch's cuts, the ops
// no loan's region may hold, in their order: on the side after the first
// `cutsBefore` of them, or at the next one itself.
enum class At : std::uint8_t { Side, Cut };

struct Piece {
  unsigned cutsBefore;
  At at;
  bool operator==(const Piece &) const = default;
};

Piece pieceOf(ArrayRef<Operation *> cuts, Operation *top) {
  auto next =
      llvm::partition_point(cuts, [&](Operation *cut) { return cut->isBeforeInBlock(top); });
  return {static_cast<unsigned>(next - cuts.begin()),
          next != cuts.end() && *next == top ? At::Cut : At::Side};
}

// The op of a region of `cut` that holds `op`, which `cut` holds.
Operation *directlyIn(Operation *cut, Operation *op) {
  assert(op != cut && cut->isProperAncestor(op) && "an op inside the cut");
  while (op->getParentOp() != cut)
    op = op->getParentOp();
  return op;
}

// The operand by which the op that makes `alias` stands on the loan: its
// one operand that is the holder or an alias of it; null where it reads
// none or more than one.
OpOperand *throughLoan(Value alias, Value holder, const llvm::SmallDenseSet<Value, 8> &aliases) {
  Operation *maker = alias.getDefiningOp();
  if (!maker)
    return nullptr;
  OpOperand *through = nullptr;
  for (OpOperand &operand : maker->getOpOperands()) {
    if (operand.get() != holder && !aliases.contains(operand.get()))
      continue;
    if (through)
      return nullptr;
    through = &operand;
  }
  return through;
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

// A view lifetime opened at `span`, and the reads lent under it: the span
// holds no op no loan's region may hold.
void openLoan(Value holder, const Span &span, ArrayRef<OpOperand *> reads, FunctionId self,
              const solver::ProgramGraph &graph) {
  assert(mayHoldAll(span, self, graph) && regionHolds(holder, span) &&
         "a loan's region holds a side of its stretch, which no cut is in");
  Value lifetime =
      decide::openLifetime(decide::Opening::NoMemory, span.first, span.last, Value());
  OpBuilder b = OpBuilder::atBlockBegin(cast<BlockArgument>(lifetime).getOwner());
  Value lent = lendHere(b, reads.front()->getOwner()->getLoc(), holder, lifetime);
  for (OpOperand *read : reads)
    read->set(lent);
}

// The holder shared into one read, as it would be with no lifetime: its
// reference given up into a value no flow explains, which no pass grades;
// placement duplicates the holder first where it is used after.
void share(Value holder, OpOperand &read) {
  Operation *user = read.getOwner();
  OpBuilder b(user);
  read.set(
      CountShareOp::create(b, user->getLoc(), shared(holder.getType()), holder).getResult());
}

// What is left to lend of a counted holder: reads of it whose loans lie in
// one block, a part of the stretch or the whole, each set lent in turn.
using Parts = SmallVector<SmallVector<OpOperand *, 4>, 4>;

// The reads `given` of a counted holder, none of whose aliases goes out of
// the loan, lent in the innermost block that holds their loan, the block's
// stretch cut at each op no loan's region may hold (mayHold): one loan for
// the whole where nothing cuts it; else one for each side of the cuts, each
// alias that one side reads of another made again on it (remakeAlias), and
// the reads inside each cut, by the block of its region they are in, given
// to `parts` to be lent there. No loan changes a count.
//
// A use of the loan by a cut itself, an op whose own region holds what no
// loan's region may, is an internal error naming the op: no loan's region
// can hold it and frames do not split it, and no program reaches lending
// with one, since idr-structure-loops keeps every region that calls as an
// op of ours, which reads no loan, and frames stop at such an op. So is an
// alias read across a cut whose op cannot be made again, which no shape the
// frontend writes reaches.
void lendPart(Value holder, ArrayRef<OpOperand *> given, FunctionId self,
              const solver::ProgramGraph &graph, Parts &parts, Lending &made) {
  Walked loan = walkLoan(given);
  Block *block = innermost(loan.uses);
  auto topOf = [&](Operation *op) { return block->findAncestorOpInBlock(*op); };
  Span stretch = spanIn(block, loan.uses);
  SmallVector<Operation *, 4> cuts;
  for (Operation *op = stretch.first;; op = op->getNextNode()) {
    if (!mayHold(*block, op, self, graph))
      cuts.push_back(op);
    if (op == stretch.last)
      break;
  }
  if (cuts.empty()) {
    openLoan(holder, stretch, given, self, graph);
    ++made.opened;
    made.rewritten += static_cast<unsigned>(given.size());
    return;
  }
  auto pieceAt = [&](Operation *op) { return pieceOf(cuts, topOf(op)); };

  // Each use of an alias on another piece than the one it is made on, and
  // where each side's are made again: before the first op of the side that
  // holds one.
  std::size_t sides = cuts.size() + 1;
  SmallVector<Operation *, 4> sideStart(sides, nullptr);
  SmallVector<OpOperand *, 8> crossing;
  for (OpOperand *use : loan.uses) {
    Operation *user = use->getOwner();
    Operation *top = topOf(user);
    Piece here = pieceOf(cuts, top);
    if (here.at == At::Cut && top == user)
      lifetimes::brokenAt(user, "a loan is read by an op whose own region holds what no loan's "
                                "region may, a call that runs on a frame among them, which "
                                "idr-structure-loops keeps out of every op of upstream's");
    Value value = use->get();
    if (value == holder || pieceAt(makerOf(value)) == here)
      continue;
    crossing.push_back(use);
    if (here.at == At::Side) {
      Operation *&start = sideStart[here.cutsBefore];
      if (!start || top->isBeforeInBlock(start))
        start = top;
    }
  }

  // Every alias read across a cut made again, before any use is given it,
  // so each is made again from the originals: on its side, or inside the
  // cut, before the op of the cut's region that holds the use, where the
  // cut's own reads are lent. What each side, or each such op, has made
  // again is kept while this part is lent, sized by what it reads across.
  SmallVector<OpOperand *, 4> reads(given.begin(), given.end());
  SmallVector<IRMapping, 4> sideAgain(sides);
  SmallVector<std::pair<Operation *, IRMapping>, 4> cutAgain;
  SmallVector<OpOperand *, 8> remade;
  SmallVector<Operation *, 8> copies;
  SmallVector<Operation *, 8> originals;
  SmallVector<std::pair<OpOperand *, Value>, 8> rewired;
  auto stepOf = [&](Value alias) { return throughLoan(alias, holder, loan.aliases); };
  // Each op made again that reads the holder is a read of the loan lent
  // where it now stands.
  auto onMade = [&](OpOperand &by, Operation *copy) {
    copies.push_back(copy);
    if (by.get() == holder)
      remade.push_back(&copy->getOpOperand(by.getOperandNumber()));
    if (!llvm::is_contained(originals, by.getOwner()))
      originals.push_back(by.getOwner());
  };
  for (OpOperand *use : crossing) {
    Operation *top = topOf(use->getOwner());
    Piece here = pieceOf(cuts, top);
    Operation *at = nullptr;
    IRMapping *again = nullptr;
    if (here.at == At::Side) {
      at = sideStart[here.cutsBefore];
      again = &sideAgain[here.cutsBefore];
    } else {
      at = directlyIn(top, use->getOwner());
      auto entry = llvm::find_if(cutAgain, [&](const auto &each) { return each.first == at; });
      if (entry == cutAgain.end()) {
        cutAgain.emplace_back(at, IRMapping());
        entry = std::prev(cutAgain.end());
      }
      again = &entry->second;
    }
    rewired.emplace_back(use, remakeAlias(use->get(), holder, at, *again, stepOf, onMade));
  }
  for (auto [use, value] : rewired)
    use->set(value);

  // What nothing reads any more goes, an original before what it was made
  // again from, since a use given what was made again may be an original's,
  // and each after what stands on it; with it, its read of the holder.
  auto drop = [&](Operation *op) {
    if (!op->use_empty())
      return;
    auto owned = [&](OpOperand *read) { return read->getOwner() == op; };
    llvm::erase_if(reads, owned);
    llvm::erase_if(remade, owned);
    op->erase();
  };
  for (Operation *op : llvm::reverse(originals))
    drop(op);
  for (Operation *op : llvm::reverse(copies))
    drop(op);

  // The reads of each side, one loan each; those inside a cut, by the block
  // of its region that holds them, a part lent there.
  llvm::append_range(reads, remade);
  Parts onSide(sides);
  SmallVector<std::pair<Block *, SmallVector<OpOperand *, 4>>, 4> inCut;
  for (OpOperand *read : reads) {
    Operation *top = topOf(read->getOwner());
    Piece here = pieceOf(cuts, top);
    if (here.at == At::Side) {
      onSide[here.cutsBefore].push_back(read);
      continue;
    }
    Block *inside = directlyIn(top, read->getOwner())->getBlock();
    auto entry = llvm::find_if(inCut, [&](const auto &each) { return each.first == inside; });
    if (entry == inCut.end()) {
      inCut.emplace_back(inside, SmallVector<OpOperand *, 4>{});
      entry = std::prev(inCut.end());
    }
    entry->second.push_back(read);
  }
  for (SmallVector<OpOperand *, 4> &side : onSide) {
    if (side.empty())
      continue;
    openLoan(holder, spanIn(block, walkLoan(side).uses), side, self, graph);
    ++made.opened;
    made.rewritten += static_cast<unsigned>(side.size());
  }
  for (auto &entry : inCut)
    parts.push_back(std::move(entry.second));
}

// A counted holder's reads, none of whose aliases goes out of the loan,
// lent part by part: each part's cuts hold the parts after it, each in a
// block inside the one before, so the parts end.
Lending lendCounted(Value holder, ArrayRef<OpOperand *> reads, FunctionId self,
                    const solver::ProgramGraph &graph) {
  Lending made;
  Parts parts;
  parts.emplace_back(reads.begin(), reads.end());
  while (!parts.empty()) {
    SmallVector<OpOperand *, 4> part = parts.pop_back_val();
    lendPart(holder, part, self, graph, parts, made);
  }
  return made;
}

// Whether the loan of a scoped holder's read stays where its lifetime
// keeps it: no alias of it goes out, and no call in its stretch runs on a
// frame.
bool keptScoped(OpOperand *read, FunctionId self, const solver::ProgramGraph &graph) {
  if (keptOf(read) == Kept::Out)
    return false;
  Walked walked = walkLoan(read);
  Span span = spanIn(innermost(walked.uses), walked.uses);
  for (Operation *op = span.first;; op = op->getNextNode()) {
    if (holdsCallOnFrame(op, self, graph))
      return false;
    if (op == span.last)
      return true;
  }
}

// A scoped holder's reads, each projected under the holder's own lifetime
// right before it: every alias of it is made after it, in its region. No
// region is opened, so the read's stretch is the whole of what keeps the
// loan's aliases to the lifetime: none leaves the stretch, so none leaves
// the lifetime's region, and none outlives a call that runs on a frame, so
// no frame holds one, and no loan of a scoped holder is lent again from
// outside the code frames move, whatever the holder lives in (this
// activation's slots, which the code after such a call no longer has,
// among them). The decide step counts every holder an op of upstream's
// reads into a value that holds references, since it counts every value
// no op states a lifetime for and every operand of an op that declares no
// flow, so a scoped holder's read gives no alias that holds one and its
// stretch is the read alone.
void projectScoped(Value holder, ArrayRef<OpOperand *> reads, FunctionId self,
                   const solver::ProgramGraph &graph) {
  Value own = statedLifetime(holder);
  assert(own && "the verifier holds every scoped value to the lifetime it states");
  for (OpOperand *read : reads) {
    assert(keptScoped(read, self, graph) &&
           "a scoped holder's read gives no alias: the decide step counts a holder an op of "
           "upstream's reads into a value that holds references");
    Operation *user = read->getOwner();
    OpBuilder b(user);
    read->set(lendHere(b, user->getLoc(), holder, own));
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
    case Release::Counted: {
      // A read one of whose aliases goes out of the loan is no loan: the
      // alias takes a reference of its own, which counting gives it.
      SmallVector<OpOperand *, 4> lent;
      for (OpOperand *read : reads) {
        if (keptOf(read) == Kept::InLoan) {
          lent.push_back(read);
          continue;
        }
        share(holder, *read);
        ++made.rewritten;
      }
      if (!lent.empty())
        made += lendCounted(holder, lent, self, graph);
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
