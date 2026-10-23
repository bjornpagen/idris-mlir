// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's result returned open: a data type marked open is laid out
// as at an index unknown at compile time, its indices kept. A tail call and
// its caller lower to one return, and a re-pack between them would run
// after the call, so a result is returned open where a tail of its function
// gives it so and its own layout would close it.
//
// Two ways come to it. A tail call whose caller lays its result out open
// asks its callee's copy keyed open: the caller's layout is a fact of the
// call, which the request reads (layoutsAsked), and openResult is the type
// that copy returns, which openTails gives from every tail of the copy. And
// the one rule here, for a result a tail gives at a layout the function's
// own type cannot agree with, decided once per function when the schedule
// takes it up: the function's result is marked open in its own type. The
// two cannot agree in the function where its type lays the result out
// closed and the tail gives it as at an unknown index (an index the
// language cannot express, a level of the function's own, a callee's
// result marked open), as a function declared at `Vect 3` meets; nor in a
// copy whose classes would close the result's levels where the tail holds
// what no substitution closes (an opaque index, an open mark), as one
// declared at `Vect n` meets in its copy at 3, whatever closed them, a
// parameter's class or the result's. Either way no copy of the callee
// closes what the tail gives, so the result opens: the tail call is kept
// and the program is less optimized, never refused. The mark is part of
// the type, so every copy of the function returns the result open by the
// one substitution, which keeps the mark, and its classes no longer change
// that result's layout; no request reads the function's tails.
//
// Every call of the function takes the opened type as its view and casts
// it back after itself to the type it gave, which its uses read: a call
// that is no tail pays the re-pack there, and a tail call in a caller whose
// own result is closed becomes a tail lost to a layout, which opens that
// caller's result in turn, now where the caller is of the function's own
// component, or when the schedule takes it up. A result opens once, so the
// rule ends by construction. Each caller outside the component waits on
// it, not taken up, so between waves, on the pass thread, nothing reads
// what the rule rewrites.
//
// A tail gives the open type by one reindex from what the reindexes that
// made its value cast, at the grade that reindex gives (a fresh cell,
// counted and claiming its own cells, where it builds one from words; the
// operand's hold where it builds nothing), and its claim forgotten by
// idr.count.share, the one op that forgets a claim, which the stage table
// admits from the first-order program on, where the open type claims less.
// So an opened result is at the weakest hold its tails give, which every
// tail fits: one that gives a cell no one claims and one that builds from
// words share it.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <optional>

using namespace mlir;

namespace idr::specialize {

Type openResult(Type type, Type held) {
  DataType data = dataTypeOf(type);
  if (!data)
    return type;
  return graded(gradeOf(held), data.marked(LayoutMark::Open));
}

namespace {

//===----------------------------------------------------------------------===//
// Giving a value at an opened type
//===----------------------------------------------------------------------===//

// The value the reindexes that made `value` cast, back to the first: what a
// value given at another layout is cast from, so a re-pack it went through
// is replaced, never followed by another.
Value uncast(Value value) {
  while (auto cast = value.getDefiningOp<DataReindexOp>())
    value = cast.getValue();
  return value;
}

// The type a reindex of a value of `from` to the carrier of `to` gives, by
// the reindex's own rule: the operand's uses; and where the carrier holds
// references, a fresh value, counted and claiming its own cells, where the
// re-pack builds a cell or an array, the operand's hold where it builds
// nothing, its memory the operand's.
Type reindexed(Type from, Type to) {
  Type carrier = unrestricted(to);
  auto laidOut = [](DataType type, Tag tag) { return Layouts::fieldsAt(type, tag); };
  std::optional<Hold> hold;
  if (holdsReferences(carrier)) {
    hold = families::builds(from, carrier, laidOut) ? Hold::counted(Unique::Self) : holdOf(from);
    assert(hold && "a re-pack into a value that holds references either builds it or holds "
                   "what its operand held");
  }
  return graded(Grade{usesOf(from), hold}, carrier);
}

// Whether a value of `from` can be given where `to` is asked: the reindex to
// it gives what `to` claims, or more, which a share forgets.
bool givable(Type from, Type to) { return from == to || forgets(reindexed(from, to), to); }

// `value` at `type`, given at `b`: one reindex from what the reindexes that
// made it cast, at the grade it gives, then that grade's claim forgotten
// down to `type`'s by a share where `type` claims less; the value itself
// where it is of `type` already.
Value giveAs(OpBuilder &b, Location loc, Type type, Value value) {
  Value from = uncast(value);
  if (from.getType() == type)
    return from;
  Type cast = reindexed(from.getType(), type);
  assert(forgets(cast, type) &&
         "a value is given open at a claim no greater than its reindex gives; a share forgets a "
         "claim, and nothing raises one");
  Value given =
      cast == from.getType() ? from : DataReindexOp::create(b, loc, cast, from).getResult();
  if (cast == type)
    return given;
  return CountShareOp::create(b, loc, type, given).getResult();
}

// The reindexes that made `value`, from it back, each erased once nothing
// reads it.
void eraseDeadCasts(Value value) {
  while (auto cast = value.getDefiningOp<DataReindexOp>()) {
    if (!cast->use_empty())
      return;
    value = cast.getValue();
    cast->erase();
  }
}

//===----------------------------------------------------------------------===//
// The tails
//===----------------------------------------------------------------------===//

// One walk down a function's tails from its body: each region op a break
// crosses whose results a tail gives on, in the order the walk meets them,
// and each block where a tail ends, giving its function's results from its
// own terminator. A block whose end never returns gives nothing, and is
// neither.
struct Spine {
  SmallVector<Operation *> rejoins;
  SmallVector<Block *> ends;
};

Spine spineOf(FuncOp fn) {
  Spine spine;
  Block &body = fn.getBody().front();
  SmallVector<Block *> work;
  if (body.getTerminator()->hasTrait<OpTrait::ReturnLike>())
    work.push_back(&body);
  while (!work.empty()) {
    Block *block = work.pop_back_val();
    Operation *source = tail::tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      spine.ends.push_back(block);
      continue;
    }
    spine.rejoins.push_back(source);
    for (Region &region : source->getRegions())
      if (!region.empty() && tail::rejoinOf(region.front().getTerminator()) == source)
        work.push_back(&region.front());
  }
  return spine;
}

// A function whose results at `opened` are now `results`, its tails read
// down from its body into `spine`, gives them so at every tail: a region op
// a break crosses whose results a block gives on takes the open type at
// each opened result, as does each op after it that only gives one on; a
// block that ends a tail otherwise gives what it gives there at the open
// type before its terminator (giveAs), so what the function gives at a
// tail it gives in its own block at the open type. Only those blocks change
// what follows a call, and each ends a tail, as the walk down found it:
// the tails below each say what each call there now is. A call that
// reached the return through a re-pack now reaches it through no cast, a
// tail call, and one that gave a closed value on now gives it to a re-pack,
// a tail lost to a layout, which a copy's own turn asks its callee open
// for; a region op that gave its value to a re-pack and now gives it
// freely makes a tail of each region's end.
void giveTails(ArrayRef<Type> results, ArrayRef<unsigned> opened, const Spine &spine) {
  for (Operation *source : spine.rejoins) {
    // The ops after it give its results on, each in its place, to the
    // terminator, which forwards them in order: tailSource found the way
    // so.
    SmallVector<Value> values(source->getResults());
    for (unsigned position : opened)
      source->getResult(position).setType(results[position]);
    Operation *terminator = source->getBlock()->getTerminator();
    for (Operation *op = source->getNextNode(); op != terminator; op = op->getNextNode()) {
      auto *at = llvm::find(values, op->getOperand(0));
      auto position = static_cast<unsigned>(std::distance(values.begin(), at));
      *at = op->getResult(0);
      if (llvm::is_contained(opened, position))
        op->getResult(0).setType(results[position]);
    }
  }
  for (Block *end : spine.ends) {
    Operation *terminator = end->getTerminator();
    OpBuilder b(terminator);
    for (unsigned position : opened) {
      Value given = terminator->getOperand(position);
      terminator->setOperand(position,
                             giveAs(b, terminator->getLoc(), results[position], given));
      eraseDeadCasts(given);
    }
  }
  for (Block *end : spine.ends)
    for (const tail::Tail &each : tail::tailsOf(*end))
      if (auto call = dyn_cast<CallOp>(each.source))
        call.setTailKind(each.repack ? TailKind::nontail : TailKind::tail);
}

// The positions where `types` differ from `had`.
SmallVector<unsigned> differing(ArrayRef<Type> had, ArrayRef<Type> types) {
  SmallVector<unsigned> positions;
  for (auto [position, pair] : llvm::enumerate(llvm::zip_equal(had, types)))
    if (std::get<0>(pair) != std::get<1>(pair))
      positions.push_back(static_cast<unsigned>(position));
  return positions;
}

} // namespace

void openTails(FuncOp fn, ArrayRef<Type> results) {
  SmallVector<unsigned> opened = differing(fn.getResultTypes(), results);
  if (opened.empty())
    return;
  Spine spine = spineOf(fn);
  fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), results));
  giveTails(results, opened, spine);
}

namespace {

//===----------------------------------------------------------------------===//
// Which results open
//===----------------------------------------------------------------------===//

// Whether `data` holds an index no substitution closes: one the language
// cannot express, which Emit writes `_`.
bool holdsOpaque(DataType data) {
  return llvm::any_of(data.getIndices(), [](const families::TermNode &node) {
    return node.kind == TermKind::Opaque;
  });
}

// Whether a tail giving `given` cannot agree with `result`, one of its
// function's results, where opening the result would agree: opening agrees
// only with a tail laid out as at an unknown index. They cannot agree in
// the function where its type lays the result out otherwise than the tail;
// nor in a copy whose classes close the result's levels, where the tail
// gives what no substitution closes (an index the language cannot express,
// a callee's result already open).
bool disagrees(Type given, Type result) {
  DataType gives = dataTypeOf(given);
  DataType returns = dataTypeOf(result);
  if (!gives || !returns || returns.getMark() == LayoutMark::Open)
    return false;
  if (families::layoutMatch(given, returns.marked(LayoutMark::Open)) != LayoutMatch::SameLayout)
    return false;
  if (families::layoutMatch(given, result) == LayoutMatch::OtherLayout)
    return true;
  return returns.freeLevels() != 0 && (gives.getMark() == LayoutMark::Open || holdsOpaque(gives));
}

// The strongest hold every one of `holds` fits, by the one order holds fit
// in (Hold::fits): the weakest claim among them, under the release they
// share. None where they share none.
std::optional<Hold> weakest(ArrayRef<Hold> holds) {
  std::optional<Hold> best;
  for (HoldCase kase : allOf<HoldCase>()) {
    Hold slot = Hold::fromCase(kase);
    if (llvm::all_of(holds, [&](Hold hold) { return hold.fits(slot); }) &&
        (!best || slot.fits(*best)))
      best = slot;
  }
  return best;
}

// The hold `fn`'s result `position` opens at, laid out as `open`: the
// weakest each tail's value gives there, the hold its reindex to `open`
// gives, so every tail fits it, a stronger one through a share. A value a
// call of `fn` itself gives is no tail's of its own: that call gives the
// opened type, whatever it is. Where no tail gives one, the result's own,
// or a counted one where it holds none.
Hold openHold(FuncOp fn, const Spine &spine, unsigned position, Type open) {
  StringAttr self = fn.getSymNameAttr();
  SmallVector<Hold> holds;
  for (Block *end : spine.ends) {
    Value given = uncast(end->getTerminator()->getOperand(position));
    if (auto call = given.getDefiningOp<CallOp>(); call && call.getCalleeAttr().getAttr() == self)
      continue;
    std::optional<Hold> hold = holdOf(reindexed(given.getType(), open));
    assert(hold && "an open value holds references");
    holds.push_back(*hold);
  }
  if (holds.empty())
    return holdOf(fn.getResultTypes()[position]).value_or(Hold::counted());
  std::optional<Hold> hold = weakest(holds);
  assert(hold && "a function's tails give holds of one release before lifetimes");
  return *hold;
}

// `fn`'s results with each one some tail cannot agree with opened, at the
// hold its tails give (openHold); none where every tail agrees. A tail here
// is a call whose results reach the function's return, freely or through a
// re-pack, each in its place: a call among the function's tails.
std::optional<SmallVector<Type>> openedResults(FuncOp fn, const Spine &spine) {
  ArrayRef<Type> own = fn.getResultTypes();
  SmallVector<bool> opens(own.size(), false);
  for (const tail::Tail &each : tail::tailsOf(fn)) {
    auto call = dyn_cast<CallOp>(each.source);
    if (!call)
      continue;
    assert(call->getNumResults() == own.size() && "a tail's results are its function's, one for one");
    for (auto [position, given] : llvm::enumerate(call.getResultTypes()))
      opens[position] = opens[position] || disagrees(given, own[position]);
  }
  if (llvm::none_of(opens, [](bool open) { return open; }))
    return std::nullopt;
  SmallVector<Type> results;
  for (auto [position, result] : llvm::enumerate(own)) {
    if (!opens[position]) {
      results.push_back(result);
      continue;
    }
    Type open = dataTypeOf(result).marked(LayoutMark::Open);
    Hold hold = openHold(fn, spine, static_cast<unsigned>(position), open);
    results.push_back(graded(Grade{usesOf(result), hold}, open));
  }
  return results;
}

// `call`, a call of `callee` whose results opened, takes its callee's types
// again, as every call holds its callee's; each result it gave at another
// type reaches its uses through one cast back after the call, and a use
// that cast the result on casts the call's result itself where the cast
// gives what that use claims.
void convertCall(CallOp call, FuncOp callee) {
  SmallVector<Type> had(call.getResultTypes());
  call.copyCallee(callee);
  OpBuilder b(call->getContext());
  b.setInsertionPointAfter(call);
  for (auto [result, type] : llvm::zip_equal(call->getResults(), had)) {
    if (result.getType() == type)
      continue;
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : result.getUses())
      uses.push_back(&use);
    SmallVector<OpOperand *> reading;
    for (OpOperand *use : uses) {
      auto on = dyn_cast<DataReindexOp>(use->getOwner());
      if (!on || !givable(result.getType(), on.getType())) {
        reading.push_back(use);
        continue;
      }
      OpBuilder at(on);
      on.getResult().replaceAllUsesWith(giveAs(at, on.getLoc(), on.getType(), result));
      on->erase();
    }
    if (reading.empty())
      continue;
    Value back = giveAs(b, call.getLoc(), type, result);
    for (OpOperand *use : reading)
      use->set(back);
  }
}

} // namespace

void openResults(optimize::Schedule &schedule, ArrayRef<FunctionId> starters) {
  // The functions the program held: a copy's results are its key's, which
  // its owner's type, decided when the owner was taken up, gave it.
  SmallVector<FunctionId> work;
  for (FunctionId id : starters)
    if (schedule.originOf(id) == id)
      work.push_back(id);
  while (!work.empty()) {
    FunctionId id = work.pop_back_val();
    FuncOp fn = schedule.function(id);
    Spine spine = spineOf(fn);
    std::optional<SmallVector<Type>> results = openedResults(fn, spine);
    if (!results)
      continue;
    SmallVector<unsigned> opened = differing(fn.getResultTypes(), *results);
    fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), *results));
    // Every call of it, its own first: its component's and its callers',
    // each of which waits on it. Its own calls take the opened types before
    // its tails give them, so a tail that a call of its own gives gives
    // that call's result, which is the opened type, cast no more.
    SmallVector<FunctionId> holders{id};
    for (FunctionId caller : schedule.callersOf(id))
      if (!llvm::is_contained(holders, caller))
        holders.push_back(caller);
    StringAttr name = fn.getSymNameAttr();
    SmallVector<std::pair<FuncOp, SmallVector<CallOp>>> converted;
    for (FunctionId holder : holders) {
      assert(!schedule.final(holder) && "a caller of a function not final waits on it");
      FuncOp caller = schedule.function(holder);
      SmallVector<CallOp> calls;
      caller.getBody().walk([&](CallOp call) {
        if (call.getCalleeAttr().getAttr() == name)
          calls.push_back(call);
      });
      for (CallOp call : calls)
        convertCall(call, fn);
      converted.emplace_back(caller, std::move(calls));
    }
    giveTails(*results, opened, spine);
    // Only what follows each converted call changed: a cast back after it,
    // or a cast on gone. Each is a tail call where its caller's tails now
    // reach it freely, a tail lost to a layout where a cast back re-packs
    // it, and ends no tail anywhere else.
    for (auto &[caller, calls] : converted) {
      SmallVector<Operation *> reached = tail::sourcesOf(caller);
      for (CallOp call : calls)
        call.setTailKind(llvm::is_contained(reached, call.getOperation())
                             ? TailKind::tail
                             : tail::withContext(call));
    }
    // A caller of its component may have lost a tail to the cast, and is
    // read again now; one outside is read when it is taken up.
    for (FunctionId holder : holders)
      if (holder != id && schedule.sameComponent(holder, id) && schedule.originOf(holder) == holder)
        work.push_back(holder);
  }
}

} // namespace idr::specialize
