// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position: the one reading of where a function's tails are, down from
// its body; each call member's own check of where it stands and a tail
// call's of its result layout, its function's; the one map from a standing
// to its member; and the one reading of whether code may follow a call.
// Tail position modulo a context is Tail/Context.cpp's.

#include "idr/IR/Tail.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Enum.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/PatternMatch.h"
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
// exactly where it stands, and whether tail calls' layouts agree.
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

// The region a value may pass through `op` by, if `op` is a region op a
// break crosses that runs one region once: entered from the op with every
// operand it takes, each bound to an argument of the region's one block,
// which ends by giving its op's results back (rejoinOf). What enters is
// bound at the type the region asks, the value's own words where the two
// lay out alike (an `idr.index.assume` only states the equation its region
// assumes). Null for any other op.
Region *passedRegion(Operation *op) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  if (!branch || op->getNumRegions() != 1 ||
      !op->hasTrait<OpTrait::PropagateControlFlowBreak>())
    return nullptr;
  Region &region = op->getRegion(0);
  if (!region.hasOneBlock())
    return nullptr;
  SmallVector<RegionSuccessor, 2> entered;
  branch.getSuccessorRegions(RegionBranchPoint::parent(), entered);
  if (entered.size() != 1 || entered.front().getSuccessor() != &region)
    return nullptr;
  OperandRange forwarded = branch.getEntrySuccessorOperands(entered.front());
  if (forwarded.size() != op->getNumOperands() || forwarded.size() != region.getNumArguments() ||
      rejoinOf(region.front().getTerminator()) != op)
    return nullptr;
  return &region;
}

// Whether each value enters `op`'s region at its own layout, so entering
// does no run-time work.
bool entersFreely(Operation *op, Region &region) {
  return llvm::all_of(llvm::zip_equal(op->getOperands(), region.getArguments()), [](auto pair) {
    auto [operand, bound] = pair;
    return families::layoutMatch(operand.getType(), bound.getType()) == LayoutMatch::SameLayout;
  });
}

// What an op on the way to a block's end may cost: nothing at run time, or
// work, which a re-pack does.
enum class Passing : std::uint8_t { Freely, AtAnyCost };

// Whether `op` only gives values on toward its block's end, at no more
// than `passing`: an op that gives its operand on, or a region op values
// pass through whose region's ops only give values on in turn, entered at
// the values' own layouts where nothing may cost. What each takes is
// passageOf's to read; this reads the ops alone, one region at a time.
bool givesOnOnly(Operation *op, Passing passing) {
  SmallVector<Operation *, 4> pending{op};
  while (!pending.empty()) {
    Operation *next = pending.pop_back_val();
    if (std::optional<Carry> carry = carryOf(next)) {
      if (passing == Passing::Freely && *carry == Carry::Works)
        return false;
      continue;
    }
    Region *region = passedRegion(next);
    if (!region || (passing == Passing::Freely && !entersFreely(next, *region)))
      return false;
    for (Operation &inner : region->front().without_terminator())
      pending.push_back(&inner);
  }
  return true;
}

// The way from `op`'s results to its block's terminator, when the ops after
// `op` only give those values on, each that gives its operand on taking one
// as its first operand and each region op the values pass through taking
// only them, bound in its region, whose end gives them back as its
// results; and the terminator forwards exactly the values given, which
// `values` then holds: the terminator, and the first op on the way that
// re-packs a value it gives on (an op that works to give it on, or a
// region op it enters at another layout), null where every one is free.
// None when another op runs after `op`, so that what `op` gives is not yet
// what the block gives, or when the terminator forwards anything else.
struct Passage {
  Operation *terminator;
  Operation *repack;
};

std::optional<Passage> passageOf(Operation *op, SmallVectorImpl<Value> &values) {
  values.assign(op->result_begin(), op->result_end());
  Operation *repack = nullptr;
  // The region ops the way has entered and not yet left, innermost last.
  SmallVector<Operation *, 2> entered;
  Operation *next = op->getNextNode();
  while (next) {
    if (next->hasTrait<OpTrait::IsTerminator>()) {
      if (entered.empty())
        break;
      // The region's end gives the values back as its op's results.
      if (!llvm::equal(next->getOperands(), values))
        return std::nullopt;
      Operation *left = entered.pop_back_val();
      values.assign(left->result_begin(), left->result_end());
      next = left->getNextNode();
      continue;
    }
    if (std::optional<Carry> carry = carryOf(next)) {
      auto *carried = llvm::find(values, next->getOperand(0));
      if (carried == values.end())
        return std::nullopt;
      *carried = next->getResult(0);
      if (*carry == Carry::Works && !repack)
        repack = next;
      next = next->getNextNode();
      continue;
    }
    Region *region = passedRegion(next);
    if (!region)
      return std::nullopt;
    for (auto [operand, bound] : llvm::zip_equal(next->getOperands(), region->getArguments())) {
      auto *carried = llvm::find(values, operand);
      if (carried == values.end())
        return std::nullopt;
      *carried = bound;
    }
    if (!repack && !entersFreely(next, *region))
      repack = next;
    entered.push_back(next);
    next = &region->front().front();
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

// The two types `repack` converts a value between: an op that works to
// give its operand on converts its operand into its result; a region op
// re-packs the first value it binds at another layout.
std::pair<Type, Type> repackedTypes(Operation *repack) {
  if (Region *region = passedRegion(repack))
    for (auto [operand, bound] : llvm::zip_equal(repack->getOperands(), region->getArguments()))
      if (families::layoutMatch(operand.getType(), bound.getType()) != LayoutMatch::SameLayout)
        return {operand.getType(), bound.getType()};
  return {repack->getOperand(0).getType(), repack->getResult(0).getType()};
}

// A call where a tail would be but for `repack`, which converts the value
// it gives between two layouts after it: the call's result layout is not
// its caller's, so it is a jump the compiler fails to make.
LogicalResult lostToRepack(Operation *call, Operation *repack) {
  InFlightDiagnostic diag =
      call->emitOpError("internal error: a call in tail position but for a re-pack after it, of ");
  auto [from, to] = repackedTypes(repack);
  nameLayout(diag, from);
  diag << " as ";
  nameLayout(diag, to);
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
  while (source && givesOnOnly(source, Passing::Freely))
    source = source->getPrevNode();
  llvm::SmallVector<Value, 4> values;
  return source && passesOn(source, values) == terminator ? source : nullptr;
}

std::optional<llvm::SmallVector<Operation *>> freeWayAfter(Operation *op) {
  llvm::SmallVector<Value, 4> values;
  if (!passesOn(op, values))
    return std::nullopt;
  llvm::SmallVector<Operation *> way;
  for (Operation *next = op->getNextNode(); !next->hasTrait<OpTrait::IsTerminator>();
       next = next->getNextNode())
    way.push_back(next);
  return way;
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
  while (source && givesOnOnly(source, Passing::AtAnyCost))
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

llvm::SmallVector<Tail> tailsOf(Block &block) {
  llvm::SmallVector<Tail> tails;
  // Each block still to read, with the re-pack between what it gives and
  // the return, null where none stands there.
  struct Leg {
    Block *block;
    Operation *repack;
  };
  llvm::SmallVector<Leg, 8> spine{{&block, nullptr}};
  while (!spine.empty()) {
    Leg leg = spine.pop_back_val();
    std::optional<Given> given = givenBy(*leg.block);
    if (!given)
      continue;
    // The re-pack nearest what the block gives names that value's layout.
    Operation *repack = given->repack ? given->repack : leg.repack;
    tails.push_back({given->source, repack});
    if (given->source->hasTrait<OpTrait::PropagateControlFlowBreak>())
      forEachRejoining(given->source, [&](Block &entry) { spine.push_back({&entry, repack}); });
  }
  return tails;
}

// A body that ends in no return (a crash, an exit) gives its callers
// nothing, so nothing in it is a tail.
llvm::SmallVector<Tail> tailsOf(FuncOp fn) {
  Block &body = fn.getBody().front();
  if (!returnsFromFunction(body.getTerminator()))
    return {};
  return tailsOf(body);
}

llvm::SmallVector<Operation *> sourcesOf(FuncOp fn) {
  llvm::SmallVector<Operation *> sources;
  for (const Tail &each : tailsOf(fn))
    if (!each.repack)
      sources.push_back(each.source);
  return sources;
}

// A tail call's result goes to its function's return, never into a cell,
// so the rule admits a context only of a call that ends no tail.
CallStanding offTail(FunctionCallOpInterface call) {
  return contextOf(call) ? CallStanding::ModuloContext : CallStanding::Returns;
}

namespace {

// The member of `Members` whose constant is `standing`, made of `call`:
// a fold over the family's list, so no member is named here.
template <CallFamily... Members>
FunctionCallOpInterface restandAmong(RewriterBase &rewriter, FunctionCallOpInterface call,
                                     CallStanding standing) {
  FunctionCallOpInterface made;
  ((standingOf<Members> == standing ? (void)(made = restand<Members>(rewriter, call)) : (void)0),
   ...);
  return made;
}

} // namespace

FunctionCallOpInterface restand(RewriterBase &rewriter, FunctionCallOpInterface call,
                                CallStanding standing) {
  return restandAmong<
#define GET_CALLS_FAMILY_LIST
#include "idr/IR/Generated/CallsFamily.h.inc"
      >(rewriter, call, standing);
}

bool decided(FuncOp fn) { return tailsAt[fn.getProgram().getStage()] == StageTails::Decided; }

namespace {

// Whether every tail call's results are laid out as its caller's at the
// program's stage: from Graded on. Before it, a call whose result is
// re-packed on its way to the return is no tail call, and idr-optimize's
// specializer makes it one by keying its callee's copy to the caller's
// layout.
bool layoutsAgree(FuncOp fn) {
  return tailLayoutsAt[fn.getProgram().getStage()] == StageTailLayouts::Agree;
}

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

// The lifetime rule for a call that is its caller's last act.
LogicalResult verifyOperands(Operation *call, FuncOp fn) {
  for (OpOperand &operand : call->getOpOperands())
    if (endsWithCall(operand.get(), fn))
      return call->emitOpError("internal error: operand #")
             << operand.getOperandNumber()
             << " is or lives in a lifetime that ends with this call, which goes in its place";
  return success();
}

} // namespace

// A self call the rule admits, left an ordinary call, is a loop with a
// destination the compiler fails to make. One in tail position is its
// function's to show.
LogicalResult verify(CallOp call) {
  if (decided(call->getParentOfType<FuncOp>()) && contextOf(call))
    return call.emitOpError("internal error: a call modulo a context left an ordinary call, a "
                            "loop with a destination the compiler fails to make");
  return success();
}

LogicalResult verify(TailCallOp call) {
  llvm::SmallVector<Value, 4> values;
  std::optional<Passage> passage = passageOf(call, values);
  if (!passage || (!returnsFromFunction(passage->terminator) && !rejoinOf(passage->terminator)))
    return call.emitOpError(
        "internal error: a tail call whose results its block does not give on unchanged");
  if (passage->repack)
    return lostToRepack(call, passage->repack);
  return verifyOperands(call, call->getParentOfType<FuncOp>());
}

LogicalResult verify(ContextCallOp call) {
  if (!contextOf(call))
    return call.emitOpError("internal error: a call modulo a context whose result goes "
                            "elsewhere than into cells built for it that its function returns");
  return verifyOperands(call, call->getParentOfType<FuncOp>());
}

LogicalResult verify(FuncOp fn) {
  // The calls among the function's tails, each with the re-pack, if any,
  // between it and the return. Each with none is in tail position, so,
  // once every fact is decided, one that is no tail call is a jump the
  // compiler fails to make; each with one is where a tail would be, and,
  // once tail calls' layouts agree with their callers', a jump the
  // compiler fails to make too, whichever fact it holds.
  bool exact = decided(fn);
  bool agree = layoutsAgree(fn);
  llvm::SmallVector<TailCallOp> reached;
  for (const Tail &each : tailsOf(fn)) {
    auto call = dyn_cast<FunctionCallOpInterface>(each.source);
    if (!call)
      continue;
    if (each.repack) {
      if (agree)
        return lostToRepack(call, each.repack);
      continue;
    }
    if (auto tail = dyn_cast<TailCallOp>(call.getOperation()))
      reached.push_back(tail);
    else if (exact)
      return call->emitOpError("internal error: a call in tail position that is no tail call, a "
                               "jump the compiler fails to make");
  }
  // Each tail reached is one tail call, so as many tail calls as reached
  // are each among them.
  unsigned tails = 0;
  fn.walk([&](TailCallOp) { ++tails; });
  if (reached.size() == tails)
    return success();
  // Some tail call is no tail of the function: name it.
  LogicalResult result = success();
  fn.walk([&](TailCallOp call) {
    if (!llvm::is_contained(reached, call)) {
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
LogicalResult verifyLayouts(TailCallOp call, FuncOp caller) {
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

FunctionCallOpInterface lastActOf(Operation *op) {
  auto call = dyn_cast<FunctionCallOpInterface>(op);
  return call && !returnsToCaller(call.getStanding()) ? call : FunctionCallOpInterface();
}

} // namespace idr
