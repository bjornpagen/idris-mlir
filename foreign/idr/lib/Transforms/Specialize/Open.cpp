// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's result returned open: a data type marked open is laid out
// as at an index unknown at compile time, its indices kept, and an array is
// returned open where its element is. A tail call and its caller lower to
// one return, and a re-pack between them would run after the call, so a
// result is returned open where a tail of its function gives it so and its
// own layout would close it.
//
// Two ways come to it. A tail call whose caller lays its result out open
// asks its callee's copy keyed open: the caller's layout is a fact of the
// call, which the request reads (layoutsAsked), and keyedResults gives the
// type that copy returns, which openTails gives from every tail of the
// copy. And the one rule here, for a result a tail gives at a layout the
// function's own type cannot agree with, decided once per function when the
// schedule takes it up: the function's result is marked open in its own
// type. The two cannot agree in the function where its type lays the
// result out closed and the tail gives it as at an unknown index (an index
// the language cannot express, a level of the function's own, a callee's
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
// made its value cast, at the grade that reindex gives by its own rule
// (DataReindexOp::givenType: the hold every building reindex gives, a fresh
// cell claiming its own cells, where it builds one from words; the
// operand's hold where it builds nothing), and
// its claim forgotten by idr.count.share, the one op that forgets a claim,
// which the stage table admits from the first-order program on, where the
// open type claims less.
// So an opened result is at the weakest hold its tails give, which every
// tail fits: one that gives a cell no one claims and one that builds from
// words share it. A copy keyed open is opened the same way, at the weakest
// hold the tails of its callee will give in it (keyedResults), each read in
// the callee before the copy is built: the copy's tails are given after its
// classes close the levels they close, so one whose value is laid out at
// such a level re-packs there by building, and the callee's own calls are
// tails like any other until the copy's round calls the copy instead. Its
// caller reads that hold through the re-pack, which builds nothing once the
// copy returns the result open, so the caller takes it when it is taken up
// (keyCalls): where its own result claims more, its return gives it shared
// down to that hold, which the result rule then gives its result, and the
// redirect that calls the copy gives the re-pack's readers what they read
// (convertResults).
//
// So a call may be given back less than its caller's type claimed. A claim
// is an optimization and a weaker one is always sound, so no cast raises
// one: the cast back after the call gives what its reindex gives, and the
// values of the caller that carry the result on are re-graded down where
// the call stands, each by its own op's rule (regrade). The walk stops
// where a grade is fixed exactly. At a call, the callee's parameter, which
// the caller's decision takes up when the caller is taken up. A final
// callee's copy is keyed to the hold it is passed, and each result that
// operand may reach on some path is keyed with it (keyGivenBack, read off
// the facts the callee's component published: exactly where the result is
// the operand on every path, as a bound elsewhere), so the call takes the
// key's results then, before the copy is built, and the walk goes on from
// them (keyCalls). A member of the caller's own component, which no copy
// is keyed for until the component is final, takes the weakest hold its
// component passes it as its parameter's, its body re-graded and every
// call of it sharing a stronger operand down (lowerParameters); a copy in
// the component is such a member, its node restating its signature for
// the calls made of it after. At the return, the caller's own signature:
// the caller's result takes that hold by the result rule when the caller
// is decided, beside opening (a copy's layouts are its key's, so it takes
// the hold alone), and every call of it is converted as a call of an
// opened function is. A layout opens once and a hold only descends a
// finite order, so every decision still ends by construction.
//
// Until the stage before counting, a value may also cross an edge at a
// hold that fits the one asked (crossedAs: static data where a counted
// value is asked, a claim forgotten), as the frontend's literals and
// contify's jumps do; from that stage on every edge is exact. So once a
// function is final, each edge it still crosses so is made exact, its
// operand shared down to the hold asked by idr.count.share
// (shareCrossings): a static cell's count is never touched, so counting
// one as a counted value changes nothing at run time.

#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <concepts>
#include <cstdint>
#include <iterator>
#include <optional>

using namespace mlir;

namespace idr::specialize {

namespace {

// Where the data type that lays a value out stands in its carrier: the
// carrier itself, or the element of an array, which lays out every element
// alike and so the array, whose descriptor its axes alone decide. `data` is
// null for a value no index lays out.
struct LaidOut {
  DataType data;
  ShapedType array;
  // The carrier laid out open: that data type marked open where it stands,
  // its indices kept.
  Type opened() const {
    assert(data && "only a value a data type lays out opens");
    DataType open = data.marked(LayoutMark::Open);
    return array ? Type(array.cloneWith(std::nullopt, open)) : Type(open);
  }
};

LaidOut laidOut(Type type) {
  Type carrier = unrestricted(type);
  if (auto array = dyn_cast<ShapedType>(carrier))
    return LaidOut{dyn_cast<DataType>(array.getElementType()), array};
  return LaidOut{dataTypeOf(carrier), ShapedType()};
}

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

// Whether a value of `type` claims no more of its sharing than one of
// `had`: what re-grading may write in its place.
bool claimsNoMore(Type type, Type had) {
  std::optional<Hold> now = holdOf(type);
  std::optional<Hold> was = holdOf(had);
  return !now || !was || was->claims(now->claim());
}

// What a value of `from` is given as where `asked` is: `asked`, where the
// reindex to its carrier gives what it claims or more (the reindex's own
// rule, DataReindexOp::givenType), which a share forgets; else the
// reindex's own type, which claims less, since nothing raises a claim, and
// what reads it is re-graded down to it.
Type givenAs(Type from, Type asked) {
  Type cast = DataReindexOp::givenType(from, asked);
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
  Type cast = DataReindexOp::givenType(from.getType(), type);
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

SmallVector<CallOp> regrade(FuncOp fn, ArrayRef<Value> lowered) {
  // The body's return, where it returns: a body that ends otherwise gives
  // no result.
  Operation *returned = fn.getBody().front().getTerminator();
  if (!returned->hasTrait<OpTrait::ReturnLike>())
    returned = nullptr;
  SmallVector<CallOp> reached;
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
      // A call passes each operand at its callee's parameter's type, so the
      // walk stops there, and the call is the caller's decision's: a final
      // callee's copy is keyed to the hold the operand is passed at
      // (signatureOf), whose results the call takes first (keyCalls); a
      // member of the caller's own component takes that hold as its
      // parameter's (lowerParameters).
      if (auto call = dyn_cast<CallOp>(op)) {
        reached.push_back(call);
        continue;
      }
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
      // An op whose result is its first operand's value gives it on at the
      // type the op's own rule gives that operand: one that only changes a
      // grade (a share, a linear cast), at the weakest hold the two fit; a
      // reindex, at what its re-pack gives; a tie of an array's sizes, at
      // its operand's own.
      if (auto carries = dyn_cast<CarriesOnOpInterface>(op)) {
        assert(use->getOperandNumber() == 0 &&
               "re-grading lowers values that hold references, and an op that gives its first "
               "operand on takes no other such value");
        lower(op->getResult(0), carries.getCarriedType(value.getType()));
        continue;
      }
      // An op that infers its results has them inferred again, by the one
      // rule substitution follows an operand by too; one that refuses is the
      // op's own problem and keeps what it had.
      if (auto infer = dyn_cast<InferTypeOpInterface>(op)) {
        if (std::optional<SmallVector<Type>> types = families::takenTypes(infer))
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
  return reached;
}

SmallVector<std::optional<Hold>> passedHolds(CallOp call, TypeRange params) {
  assert(call.getArgs().size() == params.size() &&
         "a call passes one argument per parameter of its callee");
  SmallVector<std::optional<Hold>> passed;
  for (auto [arg, param] : llvm::zip_equal(call.getArgs().getTypes(), params)) {
    std::optional<Hold> held = holdOf(arg);
    std::optional<Hold> asked = holdOf(param);
    passed.push_back(held && asked && *held != *asked ? held : std::nullopt);
  }
  return passed;
}

void keyGivenBack(identities::FactsView given, ArrayRef<std::optional<Hold>> passed,
                  MutableArrayRef<Type> results) {
  // A result that claims more than `reaches`, the bound one lowered
  // parameter puts on it, takes the weakest of its own hold and that bound;
  // one that claims no more keeps its own, as static data does, which
  // claims nothing and which no parameter makes counted.
  auto bound = [&](Type &result, Hold reaches) {
    std::optional<Hold> own = holdOf(result);
    if (!own || reaches.claims(own->claim()))
      return;
    std::optional<Hold> hold = weakest({*own, reaches});
    assert(hold && "a callee's result and what reaches it are freed by one release, or one is "
                   "static data a share gives where nothing is claimed");
    result = atHold(result, *hold);
  };
  for (std::uint32_t position = 0, end = static_cast<std::uint32_t>(results.size());
       position < end; ++position) {
    Type &result = results[position];
    // A result given back whole on every path is that argument's part: the
    // facts that say so are exact, and what may reach it adds nothing. The
    // parameter itself claims what it is passed at; a part of it, what that
    // claim reaches into the part, which the part's field decides and is at
    // least nothing at the same release.
    auto exact = llvm::make_filter_range(given.givesBack, [&](const identities::GivesBack &fact) {
      return fact.result.index == position && fact.result.fields.empty();
    });
    if (!exact.empty()) {
      for (const identities::GivesBack &fact : exact) {
        assert(fact.argument.index < passed.size() &&
               "what a function gives back names its parameters");
        if (std::optional<Hold> at = passed[fact.argument.index])
          bound(result, fact.argument.fields.empty() ? *at : at->refined(Unique::None));
      }
      continue;
    }
    // Elsewhere each parameter that may reach the result on some path
    // bounds it as it may reach it: whole, at its own hold; by a part, at
    // that hold claiming nothing.
    for (const identities::MayReach &fact : given.mayReach) {
      if (fact.result != position)
        continue;
      assert(fact.argument < passed.size() && "what may reach a result names its parameters");
      if (std::optional<Hold> at = passed[fact.argument])
        bound(result, fact.reach == identities::Reach::Whole ? *at : at->refined(Unique::None));
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
// a callee's result already open). An array's are its element's.
bool disagrees(Type given, Type result) {
  DataType gives = laidOut(given).data;
  LaidOut returned = laidOut(result);
  DataType returns = returned.data;
  if (!gives || !returns || returns.getMark() == LayoutMark::Open)
    return false;
  if (families::layoutMatch(given, returned.opened()) != LayoutMatch::SameLayout)
    return false;
  if (families::layoutMatch(given, result) == LayoutMatch::OtherLayout)
    return true;
  return returns.freeLevels() != 0 && (gives.getMark() == LayoutMark::Open || holdsOpaque(gives));
}

// Where the tails of a function whose result opens are given the opened
// type: in the function itself, whose own calls take the opened type before
// its tails are given it (decideResults); or in a copy of it a key opens,
// built from it after the key is made (Signatures::edit), whose tails are
// given it once the key's classes close the levels they close, and whose
// calls of the function still give what the function gives until the
// copy's round calls the copy instead.
enum class TailsGiven : std::uint8_t { InItself, InCopy };

// Whether a value laid out by `type` may be laid out otherwise in a copy:
// its data type, or its array's element, marked by its indices with a
// level a class may close, so that its index is known there.
bool mayClose(Type type) {
  DataType data = laidOut(type).data;
  return data && data.getMark() == LayoutMark::ByIndices && data.freeLevels() != 0;
}

// What a tail of a function `self` names gives at `open` in a copy of it,
// where `given`, its value, is re-packed there: its layout is not the open
// one, or a class may make it so. The re-pack builds, so it gives no more
// than a building reindex gives. And where `given` is what a call of
// another function gives, that call is a tail lost to a layout in the copy,
// which the copy's own round keys open in turn at the hold that callee's
// tails give, which nothing here reads: so no more than the weakest counted
// hold, which every such key's hold fits, so the copy's result never
// claims more than what its own tail call will give it. None where the copy
// gives the value as it is.
std::optional<Hold> repackedInCopy(Value given, Type open, StringAttr self) {
  Type type = given.getType();
  if (!mayClose(type) && families::layoutMatch(type, open) == LayoutMatch::SameLayout)
    return std::nullopt;
  if (auto call = given.getDefiningOp<CallOp>(); call && call.getCalleeAttr().getAttr() != self)
    return Hold::counted();
  return families::builtHold(usesOf(type), Unique::None);
}

// The hold `fn`'s result `position` opens at, laid out as `open`: the
// weakest each tail's value gives there, the hold its reindex to `open`
// gives, so every tail fits it, a stronger one through a share. Given in
// the function itself, a value a call of `fn` gives is no tail's: that
// call gives the opened type, whatever it is. Given in a copy, such a call
// is a tail like any other, and a value the copy re-packs gives no more
// than repackedInCopy says, whatever it gives in `fn`. Where no tail gives
// one, the result's own, or a counted one where it holds none.
Hold openHold(FuncOp fn, const Spine &spine, unsigned position, Type open, TailsGiven at) {
  StringAttr self = fn.getSymNameAttr();
  SmallVector<Hold> holds;
  for (Block *end : spine.ends) {
    Value given = uncast(end->getTerminator()->getOperand(position));
    if (auto call = given.getDefiningOp<CallOp>();
        at == TailsGiven::InItself && call && call.getCalleeAttr().getAttr() == self)
      continue;
    std::optional<Hold> hold = holdOf(DataReindexOp::givenType(given.getType(), open));
    assert(hold && "an open value holds references");
    holds.push_back(*hold);
    if (at == TailsGiven::InCopy)
      if (std::optional<Hold> repacked = repackedInCopy(given, open, self))
        holds.push_back(*repacked);
  }
  if (holds.empty())
    return holdOf(fn.getResultTypes()[position]).value_or(Hold::counted());
  std::optional<Hold> hold = weakest(holds);
  assert(hold && "a function's tails give holds of one release before lifetimes");
  return *hold;
}

} // namespace

SmallVector<Type> detail::keyedResults(FuncOp callee, ArrayRef<ResultLayout> layouts,
                                       identities::FactsView given,
                                       ArrayRef<std::optional<Hold>> passed) {
  SmallVector<Type> results(callee.getResultTypes());
  if (llvm::is_contained(layouts, ResultLayout::AtOpen)) {
    Spine spine = spineOf(callee);
    for (auto [index, layout] : llvm::enumerate(layouts)) {
      if (layout == ResultLayout::AsGiven)
        continue;
      auto position = static_cast<unsigned>(index);
      Type result = results[position];
      LaidOut at = laidOut(result);
      assert(at.data && "a call asks open only a result a data type lays out");
      Type open = at.opened();
      Hold hold = openHold(callee, spine, position, open, TailsGiven::InCopy);
      results[position] = graded(Grade{usesOf(result), hold}, open);
    }
  }
  keyGivenBack(given, passed, results);
  return results;
}

namespace {

// Whose a function's result layouts are: a function the program held has
// them decided by the result rule; a copy's are its key's, which its
// callers asked for and read, so only its holds follow its return.
enum class Layouts : std::uint8_t { Decided, Keyed };

// `fn`'s results, each retyped where what its tails give no longer agrees
// with it; none where every result stands. Where `layouts` are decided, a
// result some tail cannot agree with in layout opens, at the hold its
// tails give (openHold); a tail here is a call whose results reach the
// function's return, freely or through a re-pack, each in its place. A
// result its return gives at a weaker hold, one re-grading lowered on the
// way, takes that hold: the result rule's other half, which keeps the
// layout. A value the return gives at a hold that fits the result's
// crosses at it (crossedAs), and is shared down to it once the function is
// final (shareCrossings): the result keeps its own.
std::optional<SmallVector<Type>> openedResults(FuncOp fn, const Spine &spine, Layouts layouts) {
  ArrayRef<Type> own = fn.getResultTypes();
  // The layout each result opens to, where one does.
  SmallVector<std::optional<Type>> opened(own.size());
  if (layouts == Layouts::Decided)
    for (const tail::Tail &each : tail::tailsOf(fn)) {
      auto call = dyn_cast<CallOp>(each.source);
      if (!call)
        continue;
      assert(call->getNumResults() == own.size() &&
             "a tail's results are its function's, one for one");
      for (auto [position, given] : llvm::enumerate(call.getResultTypes()))
        if (disagrees(given, own[position]))
          opened[position] = laidOut(own[position]).opened();
    }
  // What the body's return gives, where it returns: the type each result
  // has, a weaker hold a re-graded value brought to it, or a hold that
  // crosses at the result's.
  Operation *end = fn.getBody().front().getTerminator();
  bool returns = end->hasTrait<OpTrait::ReturnLike>();
  SmallVector<Type> results;
  for (auto [index, result] : llvm::enumerate(own)) {
    auto position = static_cast<unsigned>(index);
    if (std::optional<Type> open = opened[position]) {
      Hold hold = openHold(fn, spine, position, *open, TailsGiven::InItself);
      results.push_back(graded(Grade{usesOf(result), hold}, *open));
      continue;
    }
    Type given = returns ? end->getOperand(position).getType() : result;
    if (given != result && forgets(given, result)) {
      results.push_back(result);
      continue;
    }
    assert((given == result || forgets(result, given)) &&
           "a return gives its result's type, the weaker hold a re-graded value claims, or one "
           "that crosses at it; nothing raises a claim");
    results.push_back(given);
  }
  if (llvm::equal(results, own))
    return std::nullopt;
  return results;
}

} // namespace

void convertResults(CallOp call, ArrayRef<Type> had) {
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
  // The calls the walk reaches are the caller's decision's when it is
  // decided: here where it is of the callee's component, which is read
  // again, and when it is taken up otherwise. A redirect's walk goes from a
  // tail lost to a layout to its caller's return, which no call stands on.
  (void)regrade(call->getParentOfType<FuncOp>(), lowered);
}

namespace {

// `call`, a call of `callee` whose results changed, takes its callee's
// types again, as every call holds its callee's, and gives what its uses
// read as they read it (convertResults).
void convertCall(CallOp call, FuncOp callee) {
  SmallVector<Type> had(call.getResultTypes());
  call.copyCallee(callee);
  convertResults(call, had);
}

// Every call of `id`, by the function that holds it: its own first, then
// each other holder's (Schedule::holdersOf), each once. A caller of a
// function not final waits on it or is of its component, so between waves
// nothing reads what a decision rewrites in it.
SmallVector<std::pair<FunctionId, SmallVector<CallOp>>> callsOf(const optimize::Schedule &schedule,
                                                                FunctionId id) {
  SmallVector<FunctionId> holders{id};
  for (FunctionId holder : schedule.holdersOf(id))
    if (!llvm::is_contained(holders, holder))
      holders.push_back(holder);
  StringAttr name = schedule.symbolOf(id);
  SmallVector<std::pair<FunctionId, SmallVector<CallOp>>> calls;
  for (FunctionId holder : holders) {
    assert(!schedule.final(holder) && "a caller of a function not final waits on it");
    SmallVector<CallOp> held;
    schedule.function(holder).getBody().walk([&](CallOp call) {
      if (call.getCalleeAttr().getAttr() == name)
        held.push_back(call);
    });
    calls.emplace_back(holder, std::move(held));
  }
  return calls;
}

//===----------------------------------------------------------------------===//
// The decisions taken when a function is taken up
//===----------------------------------------------------------------------===//

// `id`'s parameters, each at the weakest hold the calls of its own
// component pass it, by the one order holds fit in: no copy of a member is
// keyed until its component is final, so a member a call of its component
// passes less than its parameter claims takes that claim itself, as its
// result takes the hold its return gives. A copy of the component is such
// a member too: no key is made inside a component, so it takes the hold
// its component passes as a function the program held does, and its key's
// signature is restated after (openResults). Its body is re-graded from
// each parameter lowered. Then each call of it passes an operand that fits
// its parameter at the parameter's hold, shared down to it, the operand's
// carrier kept, which is the parameter's at the call's index arguments
// since a hold names no index variable. The two kinds of caller differ in
// what they may still key: a call within the component keys nothing, so
// every operand that fits is shared down, static data included; a caller
// outside keys a copy once the component is final, to a weaker hold or to
// static data where the parameter counts, so there only a claim stronger
// than the parameter's, which no key may raise, is shared down.
void lowerParameters(const optimize::Schedule &schedule, FunctionId id) {
  FuncOp fn = schedule.function(id);
  SmallVector<std::pair<FunctionId, SmallVector<CallOp>>> calls = callsOf(schedule, id);
  SmallVector<Type> inputs(fn.getArgumentTypes());
  for (auto [position, input] : llvm::enumerate(inputs)) {
    std::optional<Hold> own = holdOf(input);
    if (!own)
      continue;
    SmallVector<Hold> holds{*own};
    for (auto &[holder, held] : calls) {
      if (!schedule.sameComponent(holder, id))
        continue;
      for (CallOp call : held)
        if (std::optional<Hold> hold =
                holdOf(call.getArgs()[static_cast<unsigned>(position)].getType()))
          holds.push_back(*hold);
    }
    std::optional<Hold> joined = weakest(holds);
    assert(joined && "what a parameter is passed within its component is freed by one release, or "
                     "is static data a share gives where nothing is claimed");
    input = atHold(input, *joined);
  }
  SmallVector<unsigned> lowered = differing(fn.getArgumentTypes(), inputs);
  if (!lowered.empty()) {
    fn.setFunctionType(FunctionType::get(fn.getContext(), inputs, fn.getResultTypes()));
    Block &entry = fn.getBody().front();
    SmallVector<Value> parameters;
    for (unsigned position : lowered) {
      BlockArgument parameter = entry.getArgument(position);
      parameter.setType(inputs[position]);
      parameters.push_back(parameter);
    }
    // The calls the walk reaches in its own body are decided next, by
    // keyCalls and by passOn.
    (void)regrade(fn, parameters);
  }
  auto sharedDown = [&](FunctionId holder, Hold given, Hold asked) {
    if (given == asked || !given.fits(asked))
      return false;
    return schedule.sameComponent(holder, id) || given.claim() != asked.claim();
  };
  for (auto &[holder, held] : calls)
    for (CallOp call : held)
      for (auto [operand, input] : llvm::zip_equal(call.getArgsMutable(), inputs)) {
        std::optional<Hold> given = holdOf(operand.get().getType());
        std::optional<Hold> asked = holdOf(input);
        if (!given || !asked || !sharedDown(holder, *given, *asked))
          continue;
        OpBuilder b(call);
        operand.set(
            heldAs(b, call.getLoc(), operand.get(), atHold(operand.get().getType(), *asked)));
      }
}

// Each call in `fn` of a final function that passes an operand at another
// hold than its parameter's takes, at each result that operand may reach,
// the hold the callee's copy keyed to the operands' (keyGivenBack, the one
// rule signatureOf keys by) will give it, read off what the callee's
// component published: so the caller reads the key's results before the
// copy is built, as a call of an opened function takes the opened type,
// and the redirect that calls the copy changes no result. The values the
// call's results carry on are re-graded down, and each call that walk
// reaches is decided in turn; a hold only descends, so the work ends. A
// call of a member of the caller's component, a copy's among them, waits
// for that member's parameters instead (lowerParameters).
//
// Then each tail lost to a layout whose callee is final, which in the
// caller's round calls the callee's copy keyed open at each result the
// caller lays out otherwise (layoutsAsked): that copy gives the result at
// the hold its key's results give it (keyedResults, the one rule
// signatureOf keys by), the weakest the callee's tails give it. The caller
// reads it through the re-pack, which builds nothing once the copy gives
// the result open; so where that hold claims less than the caller's own
// result, the caller's return gives it so now, shared down to it, and the
// result rule gives the caller's result that hold (decideResults), every
// call of the caller converted with it. The redirect that calls the copy
// then gives the re-pack's readers what they read (convertResults).
void keyCalls(const optimize::Schedule &schedule, FuncOp fn) {
  SmallVector<CallOp> work;
  fn.getBody().walk([&](CallOp call) { work.push_back(call); });
  while (!work.empty()) {
    CallOp call = work.pop_back_val();
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    assert(callee && "between waves every copy a call names is placed");
    std::optional<optimize::Readable> known = schedule.final(*callee);
    if (!known)
      continue;
    SmallVector<std::optional<Hold>> passed = passedHolds(call, known->fn.getArgumentTypes());
    SmallVector<Type> results(call.getResultTypes());
    keyGivenBack(schedule.callees.of(*callee), passed, results);
    SmallVector<Value> lowered;
    for (auto [result, type] : llvm::zip_equal(call->getResults(), results)) {
      if (result.getType() == type)
        continue;
      result.setType(type);
      lowered.push_back(result);
    }
    llvm::append_range(work, regrade(fn, lowered));
  }
  // The weakest hold a copy keyed open gives each result, over the tails
  // lost to a layout that ask for one there.
  SmallVector<std::optional<Hold>> opened(fn.getNumResults());
  for (CallOp call : detail::lostTails(fn)) {
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    assert(callee && "between waves every copy a call names is placed");
    std::optional<optimize::Readable> known = schedule.final(*callee);
    if (!known)
      continue;
    SmallVector<detail::ResultLayout> layouts =
        detail::layoutsAsked(call, detail::TailStanding::LostToLayout);
    SmallVector<Type> keyed =
        detail::keyedResults(known->fn, layouts, schedule.callees.of(*callee),
                             passedHolds(call, known->fn.getArgumentTypes()));
    for (auto [position, layout] : llvm::enumerate(layouts)) {
      if (layout == detail::ResultLayout::AsGiven)
        continue;
      std::optional<Hold> gives = holdOf(keyed[position]);
      assert(gives && "an open value holds references");
      std::optional<Hold> &weakestSoFar = opened[position];
      weakestSoFar = weakestSoFar ? weakest({*weakestSoFar, *gives}) : gives;
      assert(weakestSoFar && "the copies a function's tails call give holds of one release before "
                             "lifetimes");
    }
  }
  Operation *end = fn.getBody().front().getTerminator();
  for (auto [position, gives] : llvm::enumerate(opened)) {
    if (!gives)
      continue;
    std::optional<Hold> own = holdOf(fn.getResultTypes()[position]);
    assert(own && "a result a tail re-packs from an open layout holds references");
    if (gives->fits(*own))
      continue;
    OpOperand &returned = end->getOpOperand(static_cast<unsigned>(position));
    Value value = returned.get();
    std::optional<Hold> target = weakest({*holdOf(value.getType()), *gives});
    assert(target && "a return gives a hold of the release its open copies give");
    OpBuilder b(end);
    returned.set(heldAs(b, end->getLoc(), value, atHold(value.getType(), *target)));
  }
}

// The result rule for `id` (openedResults), its layouts decided where the
// program held it and its key's for a copy: its results retyped where its
// tails or its return no longer agree with them, every call of it
// converted, and each holder of its component, which may have lost a tail
// to the cast or had its return re-graded, put on `work` to be decided
// again; one outside is decided when it is taken up.
void decideResults(const optimize::Schedule &schedule, FunctionId id,
                   SmallVectorImpl<FunctionId> &work) {
  FuncOp fn = schedule.function(id);
  Spine spine = spineOf(fn);
  Layouts layouts = schedule.originOf(id) == id ? Layouts::Decided : Layouts::Keyed;
  std::optional<SmallVector<Type>> results = openedResults(fn, spine, layouts);
  if (!results)
    return;
  SmallVector<unsigned> changed = differing(fn.getResultTypes(), *results);
  fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), *results));
  // Every call of it, its own first: its own calls take the new types
  // before its tails give them, so a tail that a call of its own gives
  // gives that call's result, which is the new type, cast no more.
  SmallVector<std::pair<FunctionId, SmallVector<CallOp>>> calls = callsOf(schedule, id);
  for (auto &[holder, held] : calls)
    for (CallOp call : held)
      convertCall(call, fn);
  giveTails(*results, changed, spine);
  // Only what follows each converted call changed: a cast back after it,
  // or a cast on gone, and the shares re-grading put where its values
  // join, which give their operands on freely. Each is a tail call where
  // its caller's tails now reach it freely, a tail lost to a layout where
  // a cast back re-packs it, and ends no tail anywhere else.
  for (auto &[holder, held] : calls) {
    SmallVector<Operation *> reached = tail::sourcesOf(schedule.function(holder));
    for (CallOp call : held)
      call.setTailKind(llvm::is_contained(reached, call.getOperation())
                           ? TailKind::tail
                           : tail::withContext(call));
  }
  for (auto &[holder, held] : calls)
    if (schedule.sameComponent(holder, id))
      work.push_back(holder);
}

// Each member of `id`'s component, the program's function or a copy, that
// a call in `id` passes an operand at another hold than its parameter's,
// put on `work`: its parameters are decided again.
void passOn(const optimize::Schedule &schedule, FunctionId id, SmallVectorImpl<FunctionId> &work) {
  schedule.function(id).getBody().walk([&](CallOp call) {
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    assert(callee && "between waves every copy a call names is placed");
    if (!schedule.sameComponent(*callee, id))
      return;
    if (llvm::any_of(passedHolds(call, schedule.function(*callee).getArgumentTypes()),
                     [](const std::optional<Hold> &passed) { return passed.has_value(); }))
      work.push_back(*callee);
  });
}

} // namespace

void openResults(optimize::Schedule &schedule, Nodes &nodes, ArrayRef<FunctionId> starters) {
  SmallVector<FunctionId> work(starters.begin(), starters.end());
  while (!work.empty()) {
    FunctionId id = work.pop_back_val();
    FuncOp fn = schedule.function(id);
    FunctionType before = fn.getFunctionType();
    lowerParameters(schedule, id);
    keyCalls(schedule, fn);
    decideResults(schedule, id, work);
    passOn(schedule, id, work);
    // A copy whose decisions changed its signature is called as its node
    // says from now on: every call made of it before was converted above,
    // and a request of its key made after passes the parameters restated,
    // or is refused where its results changed.
    if (schedule.originOf(id) != id && fn.getFunctionType() != before)
      nodes.restate(id, before, fn.getFunctionType());
  }
}

void shareCrossings(const optimize::Schedule &schedule, FunctionId id) {
  FuncOp fn = schedule.function(id);
  // Each operand that crosses its edge at a hold that fits the one asked,
  // with the type it crosses at, each operand once: the edge's own rule
  // (crossedAs) finds it.
  SmallVector<std::pair<OpOperand *, Type>> crossing;
  auto note = [&](OpOperand &operand, Type asked) {
    Type given = operand.get().getType();
    Type crossed = crossedAs(operand.getOwner(), given, asked);
    if (crossed == given ||
        llvm::any_of(crossing, [&](const auto &noted) { return noted.first == &operand; }))
      return;
    crossing.emplace_back(&operand, crossed);
  };
  fn.getBody().walk([&](Operation *op) {
    forwardedValues(op, [&](OpOperand &operand, Value input) { note(operand, input.getType()); });
    if (auto call = dyn_cast<CallOp>(op)) {
      std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
      assert(callee && "once a component is final, every copy its calls name is placed");
      for (auto [operand, parameter] : llvm::zip_equal(
               call.getArgsMutable(), schedule.function(*callee).getArgumentTypes()))
        note(operand, parameter);
    }
  });
  Operation *end = fn.getBody().front().getTerminator();
  if (end->hasTrait<OpTrait::ReturnLike>())
    for (auto [operand, result] : llvm::zip_equal(end->getOpOperands(), fn.getResultTypes()))
      note(operand, result);
  for (auto [operand, type] : crossing) {
    OpBuilder b(operand->getOwner());
    operand->set(
        CountShareOp::create(b, operand->getOwner()->getLoc(), type, operand->get()).getResult());
  }
}

} // namespace idr::specialize
