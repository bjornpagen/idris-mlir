// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position: the one definition, the call's own check of its fact and
// of its result layout, its function's, and the one reading of the fact a
// call holds. Tail position modulo a context is Tail/Context.cpp's.

#include "idr/IR/Tail.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Enum.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/ErrorHandling.h"

#include <concepts>
#include <cstddef>
#include <optional>
#include <utility>

// What each stage of a program implies: whether every call's tail fact is
// the decider's.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::tail {

namespace {

// What `op` does at run time to give its first operand on, as it answers
// through the carrying interface; none for an op without it, which gives
// nothing on: the ops that may follow a call are every op there is, an
// open set.
std::optional<Carry> carryOf(Operation *op) {
  auto carry = dyn_cast<CarriesOnOpInterface>(op);
  return carry ? std::optional(carry.getCarry()) : std::nullopt;
}

} // namespace

// One that works does so after the value it takes, so what it takes is no
// tail.
bool carriesOn(Operation *op) { return carryOf(op) == Carry::Free; }

namespace {

// The way from `op`'s results to its block's terminator, when the ops after
// `op` only give those values on, each taking one as its first operand, and
// the terminator forwards exactly the values given, which `values` then
// holds: the terminator, and the first op on the way that re-packs the
// value it gives on, null where every one is free. None when another op
// runs after `op`, so that what `op` gives is not yet what the block gives,
// or when the terminator forwards anything else.
struct Passage {
  Operation *terminator;
  Operation *repack;
};

std::optional<Passage> passageOf(Operation *op, SmallVectorImpl<Value> &values) {
  values.assign(op->result_begin(), op->result_end());
  Operation *repack = nullptr;
  Operation *next = op->getNextNode();
  for (; next && !next->hasTrait<OpTrait::IsTerminator>(); next = next->getNextNode()) {
    std::optional<Carry> carry = carryOf(next);
    if (!carry)
      return std::nullopt;
    auto *carried = llvm::find(values, next->getOperand(0));
    if (carried == values.end())
      return std::nullopt;
    *carried = next->getResult(0);
    if (*carry == Carry::Works && !repack)
      repack = next;
  }
  if (!next || !llvm::equal(next->getOperands(), values))
    return std::nullopt;
  return Passage{next, repack};
}

// The block's terminator, when the way there from `op` does no run-time
// work, so that what `op` gives is what the block gives; null otherwise.
Operation *passesOn(Operation *op, SmallVectorImpl<Value> &values) {
  std::optional<Passage> passage = passageOf(op, values);
  return passage && !passage->repack ? passage->terminator : nullptr;
}

// `type`, and the layout a value of it has, for a message: a data type's
// as its class laid it out when the type was made (in place, a cell, a
// number of a width); any other type is its own words, which its printed
// form names.
void nameLayout(InFlightDiagnostic &diag, Type type) {
  diag << type;
  DataType data = dataTypeOf(type);
  if (!data)
    return;
  auto name = [](auto value) {
    using E = decltype(value);
    auto at = static_cast<std::size_t>(std::to_underlying(value));
    return llvm::StringRef(EnumTraits<E>::names[at]);
  };
  diag << " (laid out " << name(data.layout()) << ", its class " << name(data.cls()) << ")";
}

// A call where a tail would be but for `repack`, which converts the value
// it gives between two layouts after it: the call's result layout is not
// its caller's, so it is a jump the compiler fails to make.
LogicalResult lostToRepack(CallOp call, Operation *repack) {
  InFlightDiagnostic diag =
      call.emitOpError("internal error: a call in tail position but for a re-pack after it, of ");
  nameLayout(diag, repack->getOperand(0).getType());
  diag << " as ";
  nameLayout(diag, repack->getResult(0).getType());
  diag << ": its result layout is not its caller's, a jump the compiler fails to make";
  diag.attachNote(repack->getLoc()) << "the re-pack";
  return diag;
}

// Whether `terminator` gives its operands to its function's callers. It
// returns control to its parent, as upstream's dataflow reads a return:
// return-like, in a callable's own region. A yield returns to its parent
// too, but its parent is the op whose region it ends, which rejoinOf reads.
bool returnsFromFunction(Operation *terminator) {
  return terminator->hasTrait<OpTrait::ReturnLike>() &&
         isa<CallableOpInterface>(terminator->getParentOp());
}

} // namespace

Operation *rejoinOf(Operation *terminator) {
  Operation *parent = terminator->getParentOp();
  auto branch = dyn_cast<RegionBranchTerminatorOpInterface>(terminator);
  if (!branch || !parent || !parent->hasTrait<OpTrait::PropagateControlFlowBreak>())
    return nullptr;
  SmallVector<RegionSuccessor, 2> successors;
  branch.getSuccessorRegions(SmallVector<Attribute>(terminator->getNumOperands()), successors);
  if (successors.size() != 1 || successors.front().getSuccessorOp() != parent ||
      branch.getMutableSuccessorOperands(successors.front()).size() !=
          terminator->getNumOperands() ||
      parent->getNumResults() != terminator->getNumOperands())
    return nullptr;
  return parent;
}

Operation *tailSource(Block &block) {
  Operation *terminator = block.getTerminator();
  Operation *source = terminator->getPrevNode();
  while (source && carriesOn(source))
    source = source->getPrevNode();
  llvm::SmallVector<Value, 4> values;
  return source && passesOn(source, values) == terminator ? source : nullptr;
}

namespace {

// The entry block of each region of `op`, a region op a break crosses,
// whose end gives on to `op`'s results: where a tail that reaches `op`
// goes on.
template <std::invocable<Block &> Visit>
void forEachRejoining(Operation *op, Visit &&visit) {
  for (Region &region : op->getRegions())
    if (!region.empty() && rejoinOf(region.front().getTerminator()) == op)
      visit(region.front());
}

// What `block` gives: the op whose results its terminator gives on through
// ops that only give a value on, re-packs among them, and the first
// re-pack on the way, null where none stands there; none where no one op
// gives them all.
struct Given {
  Operation *source;
  Operation *repack;
};

std::optional<Given> givenBy(Block &block) {
  Operation *source = block.getTerminator()->getPrevNode();
  while (source && carryOf(source))
    source = source->getPrevNode();
  if (!source)
    return std::nullopt;
  llvm::SmallVector<Value, 4> values;
  std::optional<Passage> passage = passageOf(source, values);
  if (!passage)
    return std::nullopt;
  return Given{source, passage->repack};
}

} // namespace

llvm::SmallVector<Block *> tailEnds(FuncOp fn) {
  llvm::SmallVector<Block *> ends;
  llvm::SmallVector<Block *, 8> spine{&fn.getBody().front()};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      ends.push_back(block);
      continue;
    }
    forEachRejoining(source, [&](Block &entry) { spine.push_back(&entry); });
  }
  return ends;
}

namespace {

// The way `op`'s results go to their function's return, read up through
// each region op a break crosses whose results they become: the first
// re-pack on it, null where every op on it gives them on freely; none where
// they reach no return, another op running after one on the way or a
// terminator forwarding anything else. The one climb: tail position is a
// way with no re-pack on it, and a tail lost to a layout one with a re-pack.
struct Way {
  Operation *repack;
};

std::optional<Way> wayOf(Operation *op) {
  llvm::SmallVector<Value, 4> values;
  Operation *repack = nullptr;
  for (Operation *at = op;;) {
    std::optional<Passage> passage = passageOf(at, values);
    if (!passage)
      return std::nullopt;
    if (!repack)
      repack = passage->repack;
    if (returnsFromFunction(passage->terminator))
      return Way{repack};
    at = rejoinOf(passage->terminator);
    if (!at)
      return std::nullopt;
  }
}

} // namespace

bool inTailPosition(Operation *op) {
  std::optional<Way> way = wayOf(op);
  return way && !way->repack;
}

TailKind decide(CallOp call) {
  if (inTailPosition(call))
    return TailKind::tail;
  if (contextOf(call))
    return TailKind::modulo_context;
  return TailKind::nontail;
}

bool decided(FuncOp fn) { return tailsAt[fn.getProgram().getStage()] == StageTails::Decided; }

namespace {

// Whether an operand of a call that becomes a jump is, or lives in, a
// lifetime that ends with the call: that lifetime, through the views and
// rooms it is the extent of, is any but a parameter of the function, so its
// region encloses the call or it is this call's activation, and its memory
// would be gone when the callee reads it. So no lifetime is handed over at
// a tail call: every lifetime ends in the function that opened it.
bool endsWithCall(Value operand, FuncOp fn) {
  Value lifetime =
      isa<LifetimeType>(operand.getType()) ? operand : lifetimes::statedLifetime(operand);
  if (!lifetime)
    return false;
  auto root = dyn_cast<BlockArgument>(lifetimes::extentOf(lifetime));
  return !root || root.getOwner() != &fn.getBody().front();
}

// The lifetime rule for a call that becomes a jump.
LogicalResult verifyOperands(CallOp call, FuncOp fn) {
  for (OpOperand &operand : call->getOpOperands())
    if (endsWithCall(operand.get(), fn))
      return call.emitOpError("internal error: operand #")
             << operand.getOperandNumber()
             << " is or lives in a lifetime that ends with this call, which goes in its place";
  return success();
}

} // namespace

LogicalResult verify(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  switch (call.getTailKind()) {
  case TailKind::nontail:
    // A self call the rule admits, left an ordinary call, is a loop with a
    // destination the compiler fails to make. One in tail position is its
    // function's to show.
    if (decided(fn) && contextOf(call))
      return call.emitOpError("internal error: a call modulo a context left nontail, a loop with "
                              "a destination the compiler fails to make");
    return success();
  case TailKind::tail: {
    llvm::SmallVector<Value, 4> values;
    std::optional<Passage> passage = passageOf(call, values);
    if (!passage ||
        (!returnsFromFunction(passage->terminator) && !rejoinOf(passage->terminator)))
      return call.emitOpError(
          "internal error: a tail call whose results its block does not give on unchanged");
    if (passage->repack)
      return lostToRepack(call, passage->repack);
    return verifyOperands(call, fn);
  }
  case TailKind::modulo_context:
    if (!contextOf(call))
      return call.emitOpError("internal error: a call modulo a context whose result goes "
                              "elsewhere than into cells built for it that its function returns");
    return verifyOperands(call, fn);
  }
  return success();
}

LogicalResult verify(FuncOp fn) {
  // The tail calls of the function, and the calls its spine reaches: each
  // block whose terminator gives what the function gives, but for the
  // layouts a re-pack on the way converts between, from the body down
  // through every region op a break crosses whose results the block gives
  // on, read once, with the re-pack, if any, between it and the return.
  // Each call there with no re-pack on its way is in tail position, so,
  // once every fact is decided, one that is no tail call is a jump the
  // compiler fails to make; each with one is where a tail would be, and a
  // jump the compiler fails to make too, whichever fact it holds.
  unsigned tails = 0;
  fn.walk([&](CallOp call) {
    if (tailCallOf(call))
      ++tails;
  });
  bool exact = decided(fn);
  unsigned reached = 0;
  struct Leg {
    Block *block;
    Operation *repack;
  };
  llvm::SmallVector<Leg, 8> spine{{&fn.getBody().front(), nullptr}};
  while (!spine.empty()) {
    Leg leg = spine.pop_back_val();
    std::optional<Given> given = givenBy(*leg.block);
    if (!given)
      continue;
    // The re-pack nearest what the block gives names that value's layout.
    Operation *repack = given->repack ? given->repack : leg.repack;
    if (given->source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      forEachRejoining(given->source, [&](Block &entry) { spine.push_back({&entry, repack}); });
      continue;
    }
    auto call = dyn_cast<CallOp>(given->source);
    if (!call)
      continue;
    if (repack) {
      if (exact)
        return lostToRepack(call, repack);
      continue;
    }
    if (tailCallOf(call))
      ++reached;
    else if (exact)
      return call.emitOpError("internal error: a call in tail position that is no tail call, a "
                              "jump the compiler fails to make");
  }
  if (reached == tails)
    return success();
  // Some tail call is off the spine: name it, reading up from each.
  LogicalResult result = success();
  fn.walk([&](CallOp call) {
    if (tailCallOf(call) && !inTailPosition(call)) {
      result = call.emitOpError("internal error: a tail call that is not in tail position: an "
                                "op runs after a region op around it");
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  return result;
}

// The two lower to one return, so the results of the one are the other's
// as they are, one for one, as the call's own check of its fact holds.
LogicalResult verifyLayouts(CallOp call, FuncOp caller) {
  for (auto [index, types] :
       llvm::enumerate(llvm::zip_equal(call.getResultTypes(), caller.getResultTypes()))) {
    auto [given, returned] = types;
    if (families::layoutMatch(given, returned) == LayoutMatch::SameLayout)
      continue;
    InFlightDiagnostic diag = call.emitOpError("internal error: a tail call whose result ")
                              << index << " is ";
    nameLayout(diag, given);
    diag << ", but its caller returns ";
    nameLayout(diag, returned);
    diag << ": a re-pack between the two would run after the call, a jump the compiler fails "
            "to make";
    return diag;
  }
  return success();
}

} // namespace idr::tail

namespace idr {

CallOp tailCallOf(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  return call && call.getTailKind() == TailKind::tail ? call : CallOp();
}

CallOp repackedTailOf(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  if (!call)
    return CallOp();
  std::optional<tail::Way> way = tail::wayOf(call);
  return way && way->repack ? call : CallOp();
}

CallOp lastActOf(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  return call && !returnsToCaller(call.getTailKind()) ? call : CallOp();
}

CallOp contextCallOf(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  return call && call.getTailKind() == TailKind::modulo_context ? call : CallOp();
}

bool returnsToCaller(TailKind kind) {
  switch (kind) {
  case TailKind::nontail:
    return true;
  case TailKind::tail:
  case TailKind::modulo_context:
    return false;
  }
  llvm_unreachable("a tail kind of no case");
}

} // namespace idr
