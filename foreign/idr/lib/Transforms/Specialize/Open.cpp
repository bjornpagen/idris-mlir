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
//
// So a call may be given back less than its caller's type claimed. A claim
// is an optimization and a weaker one is always sound, so no cast raises
// one: the cast back after the call gives what its reindex gives, and the
// values of the caller that carry the result on are re-graded down where
// the call stands, each by its own op's rule (regrade). The walk stops
// where a grade is fixed exactly. At a call, the callee's parameter: the
// next round keys a copy of the callee to the hold it is passed. At the
// return, the caller's own signature: the caller's result takes that hold
// by the result rule when the caller is decided, beside opening, and every
// call of it is converted as a call of an opened function is. A layout
// opens once and a hold only descends a finite order, so the rule still
// ends by construction.

#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <concepts>
#include <iterator>
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
// Giving a value at another type
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
  std::optional<Hold> hold;
  if (holdsReferences(carrier)) {
    hold = families::builds(from, carrier) ? Hold::counted(Unique::Self) : holdOf(from);
    assert(hold && "a re-pack into a value that holds references either builds it or holds "
                   "what its operand held");
  }
  return graded(Grade{usesOf(from), hold}, carrier);
}

// Whether a value of `type` claims no more of its sharing than one of
// `had`: what re-grading may write in its place.
bool claimsNoMore(Type type, Type had) {
  std::optional<Hold> now = holdOf(type);
  std::optional<Hold> was = holdOf(had);
  return !now || !was || was->claims(now->claim());
}

// What a value of `from` is given as where `asked` is: `asked`, where the
// reindex to its carrier gives what it claims or more, which a share
// forgets; else the reindex's own type, which claims less, since nothing
// raises a claim, and what reads it is re-graded down to it.
Type givenAs(Type from, Type asked) {
  Type cast = reindexed(from, asked);
  if (forgets(cast, asked))
    return asked;
  assert(claimsNoMore(cast, asked) &&
         "a reindex gives a claim no stronger than what it is asked for, or one a share forgets");
  return cast;
}

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
         "a value is given at a claim no greater than its reindex gives; a share forgets a "
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

// The strongest hold every one of `holds` fits, by the one order holds fit
// in (Hold::fits): the weakest claim among them, under the release they
// share, or static data among values that claim nothing. None where they
// share none.
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

//===----------------------------------------------------------------------===//
// Re-grading what a weaker claim reaches
//===----------------------------------------------------------------------===//

// What re-grades one value: `lower(value, type)` writes `type`, the value's
// carrier at a claim no greater, and walks on from it where that changed it.
template <class L>
concept Lowers = std::invocable<L &, Value, Type>;

// The operands `input` is given from, as its region branch says (upstream's
// predecessors of the input's successor): the branch's own entry operands,
// where the branch enters the region the input is an argument of, and each
// terminator's that branches to that region or out to the branch's results,
// at the input's position among the successor's inputs.
SmallVector<OpOperand *> operandsInto(Value input) {
  auto result = dyn_cast<OpResult>(input);
  Region *region = result ? nullptr : cast<BlockArgument>(input).getParentRegion();
  Operation *owner = result ? result.getOwner() : region->getParentOp();
  auto branch = cast<RegionBranchOpInterface>(owner);
  RegionSuccessor successor = result ? RegionSuccessor(owner) : RegionSuccessor(region);
  ValueRange inputs = branch.getSuccessorInputs(successor);
  auto found = llvm::find(inputs, input);
  assert(found != inputs.end() && "a value a branch forwards into is an input of its successor");
  auto index = static_cast<unsigned>(std::distance(inputs.begin(), found));
  SmallVector<RegionBranchPoint> points;
  branch.getPredecessors(successor, points);
  SmallVector<OpOperand *> operands;
  for (RegionBranchPoint point : points) {
    if (point.isParent()) {
      OperandRange entering = branch.getEntrySuccessorOperands(successor);
      operands.push_back(&MutableArrayRef<OpOperand>(entering.getBase(), entering.size())[index]);
      continue;
    }
    operands.push_back(
        &point.getTerminatorPredecessorOrNull().getMutableSuccessorOperands(successor)[index]);
  }
  return operands;
}

// `input`, a successor input of a region branch, one of whose operands now
// claims less: what a branch forwards is given at the input's own grade, so
// the input takes the weakest hold its operands give (Hold::fits, the one
// order), and each operand that holds more is shared down to it where it
// is given, by idr.count.share, the one op that forgets a claim. An input
// whose carrier holds no reference (a scrutinee refined to a constructor
// with no fields) has no hold to lower.
template <Lowers Lower>
void joinDown(Value input, Lower &lower) {
  std::optional<Hold> own = holdOf(input.getType());
  if (!own)
    return;
  SmallVector<OpOperand *> operands = operandsInto(input);
  SmallVector<Hold> holds{*own};
  for (OpOperand *operand : operands)
    if (std::optional<Hold> hold = holdOf(operand->get().getType()))
      holds.push_back(*hold);
  std::optional<Hold> joined = weakest(holds);
  assert(joined && "what one input is given is freed by one release, or is static data a share "
                   "gives where nothing is claimed");
  lower(input, atHold(input.getType(), *joined));
  for (OpOperand *operand : operands) {
    Value given = operand->get();
    Type type = atHold(given.getType(), *joined);
    if (type == given.getType())
      continue;
    OpBuilder b(operand->getOwner());
    operand->set(CountShareOp::create(b, operand->getOwner()->getLoc(), type, given).getResult());
  }
}

// The types `infer`'s op gives its results from its operands as they now
// are, each result's carrier its own and its hold the inferred one: its own
// types where they still agree with that inference by the op's own
// compatibility; none where the op refuses its operands, or its results at
// those holds, which is the op's own problem and keeps what it had.
// Inference is asked with no location, so a refusal reports nothing.
std::optional<SmallVector<Type>> regradedResults(InferTypeOpInterface infer) {
  Operation *op = infer.getOperation();
  SmallVector<Type> inferred;
  if (failed(infer.inferReturnTypes(op->getContext(), std::nullopt, op->getOperands(),
                                    op->getRawDictionaryAttrs(), op->getPropertiesStorage(),
                                    op->getRegions(), inferred)))
    return std::nullopt;
  SmallVector<Type> own(op->getResultTypes());
  if (infer.isCompatibleReturnTypes(inferred, own))
    return own;
  SmallVector<Type> taken;
  for (auto [type, had] : llvm::zip_equal(inferred, own)) {
    std::optional<Hold> hold = holdOf(type);
    taken.push_back(hold ? atHold(had, *hold) : had);
  }
  if (!infer.isCompatibleReturnTypes(inferred, taken))
    return std::nullopt;
  return taken;
}

// Each value `op` makes, its results and its regions' arguments, built of
// `value` among others, held to what the local rule of exclusivity gives it
// from the edges `op` declares, each source's claim its type's: a value
// that claims more is lowered to it. A constructor whose own cells include
// what `value` holds claims no more than `value` does of them.
template <Lowers Lower>
void lowerMade(Operation *op, Value value, Lower &lower) {
  auto declared = dyn_cast<FlowOpInterface>(op);
  if (!declared)
    return;
  FlowEdges edges;
  declared.getFlowEdges(edges);
  SmallVector<Value> made(op->getResults());
  for (Region &region : op->getRegions())
    if (!region.empty())
      llvm::append_range(made, region.front().getArguments());
  for (Value target : made) {
    std::optional<Hold> hold = holdOf(target.getType());
    if (!hold)
      continue;
    SmallVector<ownership::Term<Value>, 4> terms;
    ownership::Made fresh = ownership::Made::Elsewhere;
    ownership::forEachTerm(
        edges,
        [&](Value to, const ownership::Term<Value> &term) {
          if (to == target)
            terms.push_back(term);
        },
        [&](Value to) {
          if (to == target)
            fresh = ownership::Made::New;
        });
    if (llvm::none_of(terms, [&](const ownership::Term<Value> &term) { return term.from == value; }))
      continue;
    std::optional<Unique> claim = ownership::claimFrom<Value>(
        ownership::originOf<Value>(fresh, terms), terms,
        [](Value source) { return ownership::claimOfSource(source); });
    if (claim && !ownership::covers(*claim, hold->claim()))
      lower(target, atHold(target.getType(), hold->refined(*claim)));
  }
}

} // namespace

void regrade(FuncOp fn, ArrayRef<Value> lowered) {
  // The body's return, where it returns: a body that ends otherwise gives
  // no result.
  Operation *returned = fn.getBody().front().getTerminator();
  if (!returned->hasTrait<OpTrait::ReturnLike>())
    returned = nullptr;
  SmallVector<Value> work(lowered.begin(), lowered.end());
  auto lower = [&](Value value, Type type) {
    if (value.getType() == type)
      return;
    assert(unrestricted(value.getType()) == unrestricted(type) &&
           claimsNoMore(type, value.getType()) &&
           "re-grading lowers a value's claim, its carrier kept, and never raises one");
    value.setType(type);
    work.push_back(value);
  };
  while (!work.empty()) {
    Value value = work.pop_back_val();
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : value.getUses())
      uses.push_back(&use);
    for (OpOperand *use : uses) {
      // A use a share took over since it was listed reads the share, which
      // already gives what its input asks.
      if (use->get() != value)
        continue;
      Operation *op = use->getOwner();
      // The return gives the function's results at its signature's types.
      // A value that claims more than its result (static data where the
      // result counts) is shared down to it there; one that claims less, or
      // is laid out otherwise, is the result rule's when the function is
      // decided, which gives its result what its tails give.
      if (returned && op == returned) {
        Type asked = fn.getResultTypes()[use->getOperandNumber()];
        if (value.getType() != asked && forgets(value.getType(), asked)) {
          OpBuilder b(op);
          use->set(CountShareOp::create(b, op->getLoc(), asked, value).getResult());
        }
        continue;
      }
      // A call passes each operand at its callee's parameter's type: the
      // next round of the caller keys a copy of the callee to the hold it is
      // passed (signatureOf).
      if (isa<CallOp>(op))
        continue;
      // A value a branch forwards is its input, at the input's grade.
      bool forwarded = false;
      forwardedValues(op, [&](OpOperand &operand, Value input) {
        if (&operand != use)
          return;
        forwarded = true;
        joinDown(input, lower);
      });
      if (forwarded)
        continue;
      // An op that only changes a grade (a share, a linear cast) gives its
      // operand on at a hold the operand's fits: the weakest of the two.
      if (op->hasTrait<ResultCarriesOperand>()) {
        Value result = op->getResult(0);
        std::optional<Hold> from = holdOf(value.getType());
        std::optional<Hold> at = holdOf(result.getType());
        if (from && at && !from->fits(*at))
          if (std::optional<Hold> joined = weakest({*from, *at}))
            lower(result, atHold(result.getType(), *joined));
        continue;
      }
      // A reindex gives the grade its own rule gives its operand.
      if (auto cast = dyn_cast<DataReindexOp>(op)) {
        lower(cast.getResult(), reindexed(value.getType(), cast.getType()));
        continue;
      }
      // An op that infers its results has them inferred again.
      if (auto infer = dyn_cast<InferTypeOpInterface>(op)) {
        if (std::optional<SmallVector<Type>> types = regradedResults(infer))
          for (auto [result, type] : llvm::zip_equal(op->getResults(), *types))
            lower(result, type);
        continue;
      }
      // Any other op takes the value at its own rule, which admits the
      // weaker hold or reports the op; what it makes of the value claims
      // what the local rule gives it.
      lowerMade(op, value, lower);
    }
  }
}

namespace {

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

// A function whose results at `changed` are now `results`, its tails read
// down from its body into `spine`, gives them so at every tail: a region op
// a break crosses whose results a block gives on takes the new type at each
// changed result, as does each op after it that only gives one on; a block
// that ends a tail otherwise gives what it gives there at the new type
// before its terminator (giveAs), so what the function gives at a tail it
// gives in its own block at the new type, unless it gives that type
// already. Only those blocks change what follows a call, and each ends a
// tail, as the walk down found it: the tails below each say what each call
// there now is. A call that reached the return through a re-pack now
// reaches it through no cast, a tail call, and one that gave a closed value
// on now gives it to a re-pack, a tail lost to a layout, which a copy's own
// turn asks its callee open for; a region op that gave its value to a
// re-pack and now gives it freely makes a tail of each region's end.
void giveTails(ArrayRef<Type> results, ArrayRef<unsigned> changed, const Spine &spine) {
  for (Operation *source : spine.rejoins) {
    // The ops after it give its results on, each in its place, to the
    // terminator, which forwards them in order: tailSource found the way
    // so.
    SmallVector<Value> values(source->getResults());
    for (unsigned position : changed)
      source->getResult(position).setType(results[position]);
    // One that only changes a grade (a share re-grading put where values
    // join) and now has its operand's type changes nothing, and goes.
    Operation *terminator = source->getBlock()->getTerminator();
    for (Operation *op = source->getNextNode(), *next = nullptr; op != terminator; op = next) {
      next = op->getNextNode();
      auto *at = llvm::find(values, op->getOperand(0));
      auto position = static_cast<unsigned>(std::distance(values.begin(), at));
      if (!llvm::is_contained(changed, position)) {
        *at = op->getResult(0);
        continue;
      }
      op->getResult(0).setType(results[position]);
      if (op->hasTrait<ResultCarriesOperand>() &&
          op->getOperand(0).getType() == results[position]) {
        op->getResult(0).replaceAllUsesWith(op->getOperand(0));
        op->erase();
        continue;
      }
      *at = op->getResult(0);
    }
  }
  for (Block *end : spine.ends) {
    Operation *terminator = end->getTerminator();
    OpBuilder b(terminator);
    for (unsigned position : changed) {
      Value given = terminator->getOperand(position);
      if (given.getType() == results[position])
        continue;
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
// Which results change
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

// `fn`'s results, each retyped where what its tails give no longer agrees
// with it; none where every result stands. A result some tail cannot agree
// with in layout opens, at the hold its tails give (openHold); a tail here
// is a call whose results reach the function's return, freely or through a
// re-pack, each in its place. A result its return gives at a weaker hold,
// one re-grading lowered on the way, takes that hold: the result rule's
// other half, which keeps the layout.
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
  // What the body's return gives, where it returns: the type each result
  // has, or a weaker hold a re-graded value brought to it.
  Operation *end = fn.getBody().front().getTerminator();
  bool returns = end->hasTrait<OpTrait::ReturnLike>();
  SmallVector<Type> results;
  for (auto [index, result] : llvm::enumerate(own)) {
    auto position = static_cast<unsigned>(index);
    if (opens[position]) {
      Type open = dataTypeOf(result).marked(LayoutMark::Open);
      Hold hold = openHold(fn, spine, position, open);
      results.push_back(graded(Grade{usesOf(result), hold}, open));
      continue;
    }
    Type given = returns ? end->getOperand(position).getType() : result;
    assert((given == result || forgets(result, given)) &&
           "a return gives its result's type, or the weaker hold a re-graded value claims; "
           "nothing raises a claim");
    results.push_back(given);
  }
  if (llvm::equal(results, own))
    return std::nullopt;
  return results;
}

// `call`, a call of `callee` whose results changed, takes its callee's
// types again, as every call holds its callee's; each result it gave at
// another type reaches each use through one cast from the call's result: a
// use that cast it on, at the type that use asked, and every other use at
// the type the call gave, each where the cast gives what was asked, a
// share forgetting the rest. Where the cast gives less (the result opened
// at a weaker hold than the call's type claimed), it gives that, and the
// values of the caller that read it are re-graded down (regrade). A result
// whose layout stayed needs no cast, only its readers re-graded.
void convertCall(CallOp call, FuncOp callee) {
  SmallVector<Type> had(call.getResultTypes());
  call.copyCallee(callee);
  OpBuilder b(call->getContext());
  b.setInsertionPointAfter(call);
  SmallVector<Value> lowered;
  for (auto [result, type] : llvm::zip_equal(call->getResults(), had)) {
    if (result.getType() == type)
      continue;
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : result.getUses())
      uses.push_back(&use);
    SmallVector<OpOperand *> reading;
    for (OpOperand *use : uses) {
      auto on = dyn_cast<DataReindexOp>(use->getOwner());
      if (!on) {
        reading.push_back(use);
        continue;
      }
      Type asked = on.getType();
      OpBuilder at(on);
      Value given = giveAs(at, on.getLoc(), givenAs(result.getType(), asked), result);
      on.getResult().replaceAllUsesWith(given);
      on->erase();
      if (given.getType() != asked)
        lowered.push_back(given);
    }
    if (reading.empty())
      continue;
    Value back = giveAs(b, call.getLoc(), givenAs(result.getType(), type), result);
    for (OpOperand *use : reading)
      use->set(back);
    if (back.getType() != type)
      lowered.push_back(back);
  }
  regrade(call->getParentOfType<FuncOp>(), lowered);
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
    SmallVector<unsigned> changed = differing(fn.getResultTypes(), *results);
    fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), *results));
    // Every call of it, its own first: its component's and its callers',
    // each of which waits on it. Its own calls take the new types before
    // its tails give them, so a tail that a call of its own gives gives
    // that call's result, which is the new type, cast no more.
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
    giveTails(*results, changed, spine);
    // Only what follows each converted call changed: a cast back after it,
    // or a cast on gone, and the shares re-grading put where its values
    // join, which give their operands on freely. Each is a tail call where
    // its caller's tails now reach it freely, a tail lost to a layout where
    // a cast back re-packs it, and ends no tail anywhere else.
    for (auto &[caller, calls] : converted) {
      SmallVector<Operation *> reached = tail::sourcesOf(caller);
      for (CallOp call : calls)
        call.setTailKind(llvm::is_contained(reached, call.getOperation())
                             ? TailKind::tail
                             : tail::withContext(call));
    }
    // A holder of its component, the function itself among them, may have
    // lost a tail to the cast or had its return re-graded, and is read
    // again now; one outside is read when it is taken up.
    for (FunctionId holder : holders)
      if (schedule.sameComponent(holder, id) && schedule.originOf(holder) == holder)
        work.push_back(holder);
  }
}

} // namespace idr::specialize
