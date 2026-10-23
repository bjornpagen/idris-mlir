// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's result returned open: a data type marked open is laid out as
// at an index unknown at compile time, its indices kept. A tail call and its
// caller lower to one return, and a re-pack between them would run after
// the call, so a result is returned open where a tail of its function gives
// it so and its own layout would close it.
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
// declared at `Vect n` meets in its copy at 3. Either way no copy of the
// callee closes what the tail gives, so the result opens: the tail call is
// kept and the program is less optimized, never refused. The mark is part
// of the type, so every copy of the function returns the result open by the
// one substitution, which keeps the mark, and its classes no longer change
// that result's layout; no request reads the function's tails.
//
// Every call of the function takes the opened type as its view and casts
// it back after itself to the type it gave, which its uses read: a call that
// is no tail pays the re-pack there, and a tail call in a caller whose own
// result is closed becomes a tail lost to a layout, which opens that
// caller's result in turn, now where the caller is of the function's own
// component, or when the schedule takes it up. A result opens once, so the
// rule ends by construction. Each caller outside the component waits on it,
// not taken up, so between waves, on the pass thread, nothing reads what
// the rule rewrites.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize {

Type openResult(Type type, Type held) {
  DataType data = dataTypeOf(type);
  if (!data)
    return type;
  return graded(gradeOf(held), data.marked(LayoutMark::Open));
}

namespace {

// `value` at `type`, cast at `b` by one reindex from what the reindexes
// that made it cast, as the op's own fold composes two (a cast of a cast
// casts the first operand); the value itself where that is of `type`
// already. So a re-pack a tail made is replaced, never followed by another.
Value castTo(OpBuilder &b, Location loc, Type type, Value value) {
  while (auto cast = value.getDefiningOp<DataReindexOp>())
    value = cast.getValue();
  if (value.getType() == type)
    return value;
  return DataReindexOp::create(b, loc, type, value).getResult();
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

} // namespace

// Down its tails from the body, a region op a break crosses whose results a
// block gives on takes the open type at that result, as does each op after
// it that only gives one on; a block that ends a tail otherwise gives what
// it gives there cast to the open type before its terminator, the cast
// composed with the re-pack it may have given, so what the function gives
// at a tail it gives in its own block at the open type. A block whose end
// never returns gives nothing to cast. Only those blocks change what
// follows a call, and each ends a tail, as the walk down found it: the
// tails below each say what each call there now is. A call that reached
// the return through a re-pack now reaches it through a cast that builds
// nothing, a tail call, and one that gave a closed value on now gives it to
// a re-pack, a tail lost to a layout, which a copy's own turn asks its
// callee open for; a region op that gave its value to a re-pack and now
// gives it freely makes a tail of each region's end.
void openTails(FuncOp fn, ArrayRef<Type> results) {
  SmallVector<unsigned> opened;
  for (auto [position, types] : llvm::enumerate(llvm::zip_equal(fn.getResultTypes(), results)))
    if (std::get<0>(types) != std::get<1>(types))
      opened.push_back(static_cast<unsigned>(position));
  if (opened.empty())
    return;
  fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), results));
  Block &body = fn.getBody().front();
  SmallVector<Block *> spine, rewritten;
  if (body.getTerminator()->hasTrait<OpTrait::ReturnLike>())
    spine.push_back(&body);
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *terminator = block->getTerminator();
    Operation *source = tail::tailSource(*block);
    if (source && source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      // The ops after it give its results on, each in its place, to the
      // terminator, which forwards them in order: tailSource found the way
      // so.
      SmallVector<Value> values(source->getResults());
      for (unsigned position : opened)
        source->getResult(position).setType(results[position]);
      for (Operation *op = source->getNextNode(); op != terminator; op = op->getNextNode()) {
        auto *at = llvm::find(values, op->getOperand(0));
        auto position = static_cast<unsigned>(std::distance(values.begin(), at));
        *at = op->getResult(0);
        if (llvm::is_contained(opened, position))
          op->getResult(0).setType(results[position]);
      }
      for (Region &region : source->getRegions())
        if (!region.empty() && tail::rejoinOf(region.front().getTerminator()) == source)
          spine.push_back(&region.front());
      continue;
    }
    OpBuilder b(terminator);
    for (unsigned position : opened) {
      Value given = terminator->getOperand(position);
      terminator->setOperand(position, castTo(b, terminator->getLoc(), results[position], given));
      eraseDeadCasts(given);
    }
    rewritten.push_back(block);
  }
  for (Block *block : rewritten)
    for (const tail::Tail &each : tail::tailsOf(*block))
      if (auto call = dyn_cast<CallOp>(each.source))
        call.setTailKind(each.repack ? TailKind::nontail : TailKind::tail);
}

namespace {

// Whether `data` holds an index no substitution closes: one the language
// cannot express, which Emit writes `_`.
bool holdsOpaque(DataType data) {
  return llvm::any_of(data.getIndices(), [](const families::TermNode &node) {
    return node.kind == TermKind::Opaque;
  });
}

// The type `result`, one of a function's results, opens to where a tail of
// the function gives it as `given` and the two cannot agree: marked open, at
// the function's uses and at the hold the tail gives, so the tail's cast to
// it builds nothing and keeps that hold. None where the two agree, or where
// no mark would make them: opening agrees only with a tail laid out as at
// an unknown index. They cannot agree in the function where its type lays
// the result out otherwise than the tail; nor in a copy whose classes close
// the result's levels, where the tail holds what no substitution closes.
std::optional<Type> openedAgainst(Type given, Type result) {
  DataType gives = dataTypeOf(given);
  DataType returns = dataTypeOf(result);
  if (!gives || !returns || returns.getMark() == LayoutMark::Open)
    return std::nullopt;
  Type open = graded(Grade{usesOf(result), holdOf(given)}, returns.marked(LayoutMark::Open));
  if (families::layoutMatch(given, open) != LayoutMatch::SameLayout)
    return std::nullopt;
  if (families::layoutMatch(given, result) == LayoutMatch::OtherLayout)
    return open;
  if (returns.freeLevels() != 0 && (gives.getMark() == LayoutMark::Open || holdsOpaque(gives)))
    return open;
  return std::nullopt;
}

// `fn`'s results with each one a tail cannot agree with opened, against the
// first such tail in the function's walk; none where every tail agrees. A
// tail here is a call whose results reach the function's return, freely or
// through a re-pack, each in its place: a call among the function's tails.
std::optional<SmallVector<Type>> openedResults(FuncOp fn) {
  ArrayRef<Type> own = fn.getResultTypes();
  SmallVector<Type> results(own);
  SmallVector<Operation *> tails;
  for (const tail::Tail &each : tail::tailsOf(fn))
    if (isa<CallOp>(each.source))
      tails.push_back(each.source);
  fn.walk([&](CallOp call) {
    if (!llvm::is_contained(tails, call.getOperation()))
      return;
    assert(call->getNumResults() == own.size() && "a tail's results are its function's, one for one");
    for (auto [position, given] : llvm::enumerate(call.getResultTypes()))
      if (results[position] == own[position])
        if (std::optional<Type> open = openedAgainst(given, own[position]))
          results[position] = *open;
  });
  if (llvm::equal(results, own))
    return std::nullopt;
  return results;
}

// `call`, a call of `callee` whose results opened, takes its callee's types
// again, as every call holds its callee's; each result it gave at another
// type reaches its uses through one cast after the call back to that type,
// and a use that cast the result on casts the call's result itself.
void convertCall(CallOp call, FuncOp callee) {
  SmallVector<Type> had(call.getResultTypes());
  call.copyCallee(callee);
  OpBuilder b(call->getContext());
  b.setInsertionPointAfter(call);
  for (auto [result, type] : llvm::zip_equal(call->getResults(), had)) {
    if (result.getType() == type)
      continue;
    auto back = DataReindexOp::create(b, call.getLoc(), type, result);
    result.replaceAllUsesExcept(back.getResult(), back);
    for (OpOperand &use : llvm::make_early_inc_range(back->getUses())) {
      auto on = dyn_cast<DataReindexOp>(use.getOwner());
      if (!on)
        continue;
      if (on.getType() != result.getType()) {
        use.set(result);
        continue;
      }
      on.getResult().replaceAllUsesWith(result);
      on->erase();
    }
    if (back->use_empty())
      back->erase();
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
    std::optional<SmallVector<Type>> results = openedResults(fn);
    if (!results)
      continue;
    openTails(fn, *results);
    // Every call of it: its own, its component's, and its callers', each of
    // which waits on it.
    SmallVector<FunctionId> holders{id};
    for (FunctionId caller : schedule.callersOf(id))
      if (!llvm::is_contained(holders, caller))
        holders.push_back(caller);
    StringAttr name = fn.getSymNameAttr();
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
      // Only what follows each converted call changed: a cast back after
      // it, or a cast on gone. Each is a tail call where the caller's tails
      // now reach it freely, a tail lost to a layout where a cast back
      // re-packs it, and ends no tail anywhere else.
      SmallVector<Operation *> reached = tail::sourcesOf(caller);
      for (CallOp call : calls)
        call.setTailKind(llvm::is_contained(reached, call.getOperation())
                             ? TailKind::tail
                             : tail::withContext(call));
      // A caller of its component may have lost a tail to the cast, and is
      // read again now; one outside is read when it is taken up.
      if (holder != id && schedule.sameComponent(holder, id) && schedule.originOf(holder) == holder)
        work.push_back(holder);
    }
  }
}

} // namespace idr::specialize
