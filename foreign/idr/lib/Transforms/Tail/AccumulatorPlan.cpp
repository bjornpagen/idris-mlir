// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- AccumulatorPlan.cpp - What an accumulator tail is ------------------===//
//
// `length (x :: xs) = 1 + length xs` combines the recursive result in its
// tail. When the operation is exactly associative and has an identity, as
// the runtime defines it (Integer's and Int's addition and multiplication,
// a fixed width wrapping; the bitwise and, or and xor; string
// concatenation), combining on the way down gives what combining on the
// way back gives: the function seeds a clone with the identity, and the
// clone combines before it calls itself, which is then its tail. The
// clone keeps the combination on the side the call was on, so the
// operation need not commute. A floating-point operation is never one,
// and neither is a user's Semigroup or Monoid, whose laws Idris does not
// prove: only an operation the specification gives its law is.
//
// `&&` and `||` are base's functions of a lazy second operand, so what
// reaches the pass, once they are inlined and the force of a suspension
// built for it alone is the suspension's body, is a match on the first.
// With the self call second (`p x && all p xs`), its region returns the
// call, which is then already a tail call: idr-tail-loops makes the loop,
// and the region of the absorbing constructor leaves it as soon as one
// decides. With the self call first (`all p xs && p x`), the call is the
// match's scrutinee and no tail call: that is the combination read here.
// Where they are not inlined, the second operand's self call is its
// suspension's function's, not this one's, and the frames keep the depth.
// The shape is the law:
// on a type of two constructors that hold nothing, a match whose region
// for one gives that constructor back and whose other region gives a
// second operand is "a, else b", associative with the other constructor
// its identity; no name of `&&` or `||` is read.
//
// Eager evaluation's order stays: the other operand is computed before
// the call, or computes only (no effect, no crash), so it may run first;
// the call may run where the combination is; and a self call anywhere but
// such a site or a tail call (`f l ⊕ f r`) leaves the function as it is,
// for the frames to keep its depth. A short circuit's second operand runs
// only where the first does not decide, so it moves before the call only
// where it may run on every path; the recursion then runs to its base
// case, as the source's does, and gives what the source gives.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Control/MatchFamily.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Match.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include <array>

using namespace mlir;

namespace idr::tail {
namespace {

bool isSelfCall(CallOp call, FuncOp fn) {
  return call.getCalleeAttr().getAttr() == fn.getSymNameAttr();
}

// Whether `op`, or anything in it, calls `fn`.
bool callsItself(Operation *op, FuncOp fn) {
  return op
      ->walk([&](CallOp call) {
        return isSelfCall(call, fn) ? WalkResult::interrupt() : WalkResult::advance();
      })
      .wasInterrupted();
}

// Whether `call` may run where `combine`, later in its block, is: each op
// between them may cross it, so neither may tell.
bool mayMoveTo(CallOp call, Operation *combine) {
  for (Operation *op = call->getNextNode(); op != combine; op = op->getNextNode())
    if (!effects::mayMoveAcross(call, op))
      return false;
  return true;
}

// Whether `value` is computed before `call`: in a block around the call's,
// or in its block before it.
bool before(Value value, CallOp call) {
  Operation *def = value.getDefiningOp();
  if (!def || def->getBlock() != call->getBlock())
    return true;
  return def->isBeforeInBlock(call);
}

// Whether `other`, the value the combination at `call` takes beside the
// call's, may be ready where the combination is once the call goes there:
// computed before the call, or computing only on values that are. A self
// call's result is no other operand but a site of its own (`f l ⊕ f r`).
bool otherMayLead(Value other, CallOp call, FuncOp fn) {
  auto from = other.getDefiningOp<CallOp>();
  if (other == call->getResult(0) || (from && isSelfCall(from, fn)))
    return false;
  if (before(other, call))
    return true;
  Operation *def = other.getDefiningOp();
  return effects::whole(def).onlyComputes() &&
         llvm::all_of(def->getOperands(), [&](Value v) { return before(v, call); });
}

// `combine` as a law on the function's result type `result`: a binary
// operation the specification calls exactly associative with an identity,
// on that one type alone.
std::optional<Law> lawOf(Operation *combine, Type result) {
  if (combine->getNumOperands() != 2 || combine->getNumResults() != 1 ||
      combine->getResult(0).getType() != result || combine->getOperand(0).getType() != result ||
      combine->getOperand(1).getType() != result)
    return std::nullopt;
  std::optional<Attribute> identity = laws::identityOf(combine);
  if (!identity)
    return std::nullopt;
  return Law{combine->getName(), combine->getPropertiesAsAttribute(),
             combine->getDiscardableAttrDictionary(), *identity};
}

// Whether `region` gives back the constructor `tag` it is entered on: what
// it yields is that constructor by its type (its refined scrutinee, or the
// constructor built again); and nothing it computes is lost when the match
// goes.
bool givesBack(Region &region, Tag tag) {
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield || yield->getNumOperands() != 1 || statedConstructor(yield->getOperand(0)) != tag)
    return false;
  return llvm::all_of(region.front().without_terminator(),
                      [](Operation &op) { return effects::whole(&op).onlyComputes(); });
}

// Whether what `region` computes for its yield may run before `call`, on
// every path: it reads nothing the region is entered with; every op in it
// only computes, may run where it would not have, and calls no self call,
// each of which is a site of its own; and a value it yields from outside
// may lead as a law's other operand may.
bool mayLead(Region &region, CallOp call, FuncOp fn) {
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield || yield->getNumOperands() != 1 ||
      llvm::any_of(region.getArguments(), [](BlockArgument arg) { return !arg.use_empty(); }))
    return false;
  for (Operation &op : region.front().without_terminator())
    if (!effects::whole(&op).onlyComputes() || !mlir::isSpeculatable(&op) || callsItself(&op, fn))
      return false;
  Value other = yield->getOperand(0);
  return region.isAncestor(other.getParentRegion()) || otherMayLead(other, call, fn);
}

// `match`, whose scrutinee is `call`'s result, as a short circuit on the
// function's result type `result`: two constructors that hold and bind
// nothing, a region for each and no other that runs, one giving back its
// constructor (which absorbs) and the other's second operand free to
// lead.
std::optional<ShortCircuit> shortCircuitOf(DataMatchOp match, CallOp call, FuncOp fn,
                                           Type result) {
  if (match->getNumResults() != 1 || match->getResult(0).getType() != result ||
      match.getScrutinee().getType() != result || !match.getForwarded().empty())
    return std::nullopt;
  DataType data = match.getDataType();
  const families::TagSet &tags = data.possibleTags();
  if (data.kind() != MemberKind::Data || tags.size() != 2 ||
      llvm::count_if(match->getRegions(), [](Region &region) { return !region.empty(); }) != 2)
    return std::nullopt;
  std::array<Region *, 2> regions{};
  for (unsigned at = 0; at < 2; ++at) {
    if (!data.ctor(tags[at]).fields.empty() || !data.binderSorts(tags[at]).empty())
      return std::nullopt;
    regions[at] = control::takenRegion(match, static_cast<int32_t>(tags[at]));
    if (!regions[at] || regions[at]->empty())
      return std::nullopt;
  }
  for (unsigned absorbs = 0; absorbs < 2; ++absorbs) {
    unsigned other = 1 - absorbs;
    if (givesBack(*regions[absorbs], tags[absorbs]) && mayLead(*regions[other], call, fn))
      return ShortCircuit{tags[absorbs], tags[other], regions[absorbs]->getArgument(0).getType(),
                          regions[other]->getArgument(0).getType()};
  }
  return std::nullopt;
}

// The combination `call` is a site of, if any: its one result's one use is
// a law's operand, or a short circuit's scrutinee, where that op's result
// is what the function gives, its other operand may lead, and the call may
// move to its place.
std::optional<Combined> combinedAt(CallOp call, FuncOp fn) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  OpOperand &use = *call->getResult(0).getUses().begin();
  Operation *combine = use.getOwner();
  Type result = fn.getFunctionType().getResult(0);
  if (combine->getBlock() != call->getBlock() || !inTailPosition(combine) ||
      !mayMoveTo(call, combine))
    return std::nullopt;
  if (std::optional<Law> law = lawOf(combine, result)) {
    Side side = use.getOperandNumber() == 0 ? Side::Left : Side::Right;
    Value other = combine->getOperand(use.getOperandNumber() == 0 ? 1 : 0);
    if (!otherMayLead(other, call, fn))
      return std::nullopt;
    return Combined{call, combine, *law, side};
  }
  auto match = dyn_cast<DataMatchOp>(combine);
  if (!match || match.getScrutinee() != call->getResult(0))
    return std::nullopt;
  if (std::optional<ShortCircuit> circuit = shortCircuitOf(match, call, fn, result))
    return Combined{call, combine, *circuit, Side::Left};
  return std::nullopt;
}

// Whether `site` combines by the plan's operation: the same op with the
// same attributes, or a short circuit absorbing on the same constructor
// (of the one result type every site has).
bool sameOperation(const Combination &plan, const Combination &site) {
  return idr::match(
      plan,
      [&](const Law &law) {
        return idr::match(
            site,
            [&](const Law &other) {
              return other.name == law.name && other.properties == law.properties &&
                     other.discardable == law.discardable;
            },
            [](const ShortCircuit &) { return false; });
      },
      [&](const ShortCircuit &circuit) {
        return idr::match(
            site, [](const Law &) { return false; },
            [&](const ShortCircuit &other) { return other.absorbing == circuit.absorbing; });
      });
}

// Whether the plan's operation commutes, so its sites may stand on either
// side: a law's op by its trait; a short circuit's call is always first.
bool commutes(const Combination &by) {
  return idr::match(
      by, [](const Law &law) { return law.name.hasTrait<OpTrait::IsCommutative>(); },
      [](const ShortCircuit &) { return false; });
}

// Whether every use of `fn` in its own body is a call: a reference that is
// no call would keep running the function the program calls, which seeds
// the combination with the identity.
bool refersToItselfOnlyByCall(FuncOp fn) {
  std::optional<SymbolTable::UseRange> uses =
      SymbolTable::getSymbolUses(fn.getSymNameAttr(), &fn.getBody());
  return !uses || llvm::all_of(*uses, [](const SymbolTable::SymbolUse &use) {
           return isa<CallOp>(use.getUser());
         });
}

} // namespace

std::optional<Tag> statedConstructor(Value value) {
  for (Operation *def = value.getDefiningOp(); def && carriesOn(def); def = value.getDefiningOp())
    value = def->getOperand(0);
  DataType data = dataTypeOf(value.getType());
  return data ? data.singleTag() : std::nullopt;
}

std::optional<Accumulator> accumulatorOf(FuncOp fn) {
  if (fn.getNumResults() != 1 || !refersToItselfOnlyByCall(fn))
    return std::nullopt;
  llvm::SmallVector<Site> sites;
  std::optional<Accumulator> plan;
  WalkResult walk = fn.walk([&](CallOp call) {
    if (!isSelfCall(call, fn))
      return WalkResult::advance();
    if (call.getTailKind() == TailKind::tail) {
      sites.push_back(call);
      return WalkResult::advance();
    }
    std::optional<Combined> combined = combinedAt(call, fn);
    if (!combined)
      return WalkResult::interrupt();
    // One operation for every site, and one side unless it commutes.
    if (!plan) {
      plan = Accumulator{{}, combined->by, combined->side};
    } else if (!sameOperation(plan->by, combined->by) ||
               (!commutes(plan->by) && combined->side != plan->side)) {
      return WalkResult::interrupt();
    }
    sites.push_back(*combined);
    return WalkResult::advance();
  });
  if (walk.wasInterrupted() || !plan)
    return std::nullopt;
  plan->sites = std::move(sites);
  return plan;
}

} // namespace idr::tail
