// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The facts of one function the word rewrite reads: its values numbered by
// the body's one numbering, each with the bounds Ranges read off its solve
// in that order, the steps of the rewrite recorded in its order, and the
// webs its joints carry; the words and smalls that stand for each other,
// and a small given where a value its count frees is asked; and how a big
// whose place a word takes in a use is read and gives its reference up.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Traits.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <optional>
#include <span>
#include <utility>

using namespace mlir;

namespace idr::narrow {

using ranges::Bounds;

namespace {

// `source`, an integer of at most 64 bits, as an i64, extended by
// `Extend`.
template <typename Extend>
Value widened(OpBuilder &b, Location loc, Value source) {
  Type i64 = b.getI64Type();
  if (source.getType() == i64)
    return source;
  return Extend::create(b, loc, i64, source).getResult();
}

bool touchesBigs(Operation *op) {
  return llvm::any_of(op->getOperandTypes(), isCarriedAsBig) ||
         llvm::any_of(op->getResultTypes(), isCarriedAsBig);
}

} // namespace

// Ranges and the numbering read the function in the one walk order, so
// they agree on how many values it holds, where the function is the one
// Ranges solved.
Bounded::Bounded(FuncOp fn, std::span<const Bounds> read) : numbering(fn), row(read) {
  assert(row.size() == numbering.size().value() &&
         "a function's bounds, read for the function as it is now");
}

IndexVector<ValueId, Value> Bounded::values() const {
  solver::Numbering<Analysed> copy = numbering;
  return std::move(copy).finish().values;
}

// A view holds references and none of its own: freed when its lifetime
// ends.
bool borrowed(Value value) { return freedBy(value.getType(), Release::Scoped); }

namespace {

// The small `value` is given as, where it is one (heldAs): a small cast
// into a linear position or shared as a value its count frees, each an op
// whose result carries its operand.
std::optional<Value> givenSmall(Value value) {
  for (Operation *def = value.getDefiningOp(); def; def = value.getDefiningOp()) {
    if (isa<BigSmallOp>(def))
      return value;
    if (!def->hasTrait<ResultCarriesOperand>())
      return std::nullopt;
    value = def->getOperand(0);
  }
  return std::nullopt;
}

} // namespace

// A small given as the big a use asks for is read as the small, which
// holds nothing the use's rule could move on: the use it was given for is
// the one a word now takes, and the ops that gave it go with it
// (eraseGiven).
Replaced replace(OpBuilder &b, Location loc, OpOperand &use) {
  Value big = use.get();
  if (std::optional<Value> small = givenSmall(big))
    return {*small, Reference::Kept};
  return {heldAs(b, loc, big, atUses(big.getType(), Uses::Many)), referenceAt(use)};
}

void eraseGiven(RewriterBase &rewriter, Value given) {
  while (given.use_empty() && !given.getDefiningOp<BigSmallOp>() && givenSmall(given)) {
    Operation *def = given.getDefiningOp();
    given = def->getOperand(0);
    rewriter.eraseOp(def);
  }
}

void giveUp(OpBuilder &b, Location loc, const Replaced &replaced) {
  if (replaced.reference == Reference::MovedOn)
    CountDropOp::create(b, loc, replaced.read);
}

Value word(OpBuilder &b, Location loc, Value value) {
  Type i64 = b.getI64Type();
  // The word of the program's poison is poison: no conversion runs on a
  // path that never reads it. The big poison goes once nothing reads it.
  if (value.getDefiningOp<ub::PoisonOp>())
    return ub::PoisonOp::create(b, loc, i64);
  // What made the big, through its casts into and out of linear positions:
  // a big made of an integer is that integer, a word as it is, a narrower
  // one extended as the op that made it reads it.
  if (auto of = throughLinear(value).getDefiningOp<BigOfIntegerOpInterface>()) {
    Value integer = of.getValue();
    return of.getSignedness() == numeric::Signedness::Signed
               ? widened<arith::ExtSIOp>(b, loc, integer)
               : widened<arith::ExtUIOp>(b, loc, integer);
  }
  // A big is read in place at any hold, so its conversion takes nothing of
  // it.
  return BigToIntOp::create(b, loc, i64, value);
}

Value small(OpBuilder &b, Location loc, Type type, Value word) {
  return BigSmallOp::create(b, loc, unrestricted(type), word);
}

Value WordRewriter::standIn(Location loc, Type type, Value word) {
  Value made = small(*this, loc, type, word);
  smalls.emplace_back(made, type);
  return made;
}

void giveSmalls(WordRewriter &rewriter) {
  for (auto [made, type] : rewriter.smalls) {
    // A small with no use is erased with the other conversions no one
    // reads; and only a value its count frees has a reference a use takes
    // over.
    if (!freedBy(type, Release::Counted))
      continue;
    // The uses first, since each small given adds a use of the small.
    SmallVector<OpOperand *, 4> takers;
    for (OpOperand &use : made.getUses())
      if (movesOf(use.getOwner()).test(use.getOperandNumber()))
        takers.push_back(&use);
    for (OpOperand *use : takers) {
      Operation *user = use->getOwner();
      rewriter.setInsertionPoint(user);
      Value held = heldAs(rewriter, user->getLoc(), made, type);
      rewriter.modifyOpInPlace(user, [&] { use->set(held); });
    }
  }
}

Facts::Facts(FuncOp fn, Bounded bounds)
    : bounded(std::move(bounds)), values(walk(fn)),
      carriers(values.size(),
               [&](ValueId v) {
                 return isCarriedAsBig(values[v].getType()) ? Carrier::Big : Carrier::NoBig;
               }),
      webs(join()) {}

IndexVector<ValueId, Value> Facts::walk(FuncOp fn) {
  // The joints the walk is inside, each with the place of its Enter step,
  // which its classes complete as the walk leaves it.
  footprint::Vector<std::size_t> open;
  fn->walk([&](Operation *op, const WalkStage &stage) {
    if (stage.isBeforeAllRegions() && isa<RegionBranchOpInterface>(op)) {
      open.push_back(walked.size());
      walked.push_back(Enter{op, 0, 0});
    }
    if (!stage.isAfterAllRegions())
      return;
    if (isa<RegionBranchOpInterface>(op)) {
      Classified joint = classify(op);
      walked[open.back()] = Enter{op, joint.arguments, joint.argumentsEnd};
      open.pop_back();
      walked.push_back(Leave{op, joint.carries, joint.carriesEnd, joint.results, joint.resultsEnd});
      return;
    }
    if (!touchesBigs(op))
      return;
    auto first = static_cast<std::uint32_t>(numbered.size());
    for (Value operand : op->getOperands())
      numbered.push_back(bounded.at(operand));
    for (Value result : op->getResults())
      numbered.push_back(bounded.at(result));
    walked.push_back(Word{op, first});
  });
  return bounded.values();
}

// What flows is what `joint` and the terminators of its regions forward:
// each forwarded operand moves into the values it becomes, and the values
// one operand becomes, with every operand that moves into any of them, are
// one class, as a loop's argument and its result are one with its start
// and what each iteration yields. A region that ends the program forwards
// nothing. The classes come in the order their first edge is met, each
// operand and each value once, in the order it is first met. The big
// arguments of the joint's regions follow the same order, those its
// classes hold first; one no class of its own holds is reached only by a
// jump from deeper inside it, as is a result no class of its own holds.
Facts::Classified Facts::classify(Operation *joint) {
  SmallVector<std::pair<OpOperand *, Value>> edges;
  auto add = [&](Operation *from) {
    forwardedValues(from, [&](OpOperand &operand, Value input) {
      if (!isCarriedAsBig(input.getType()))
        return;
      // What enters a match's region from its scrutinee is the match's own
      // binding of the value it reads, of the scrutinee's type, which the
      // match's verifier holds; no joint carries it.
      if (auto match = dyn_cast<MatchOpInterface>(from);
          match && operand.get() == match.getScrutinee())
        return;
      edges.emplace_back(&operand, input);
    });
  };
  add(joint);
  for (Region &region : joint->getRegions())
    for (Block &block : region)
      if (!block.empty() && block.back().hasTrait<OpTrait::IsTerminator>())
        add(&block.back());
  // Two edges are one class when they share an operand or a value. The
  // union keeps each class's first edge as its leader, so the classes are
  // numbered in the order their first edge is met.
  llvm::IntEqClasses joined(static_cast<unsigned>(edges.size()));
  for (unsigned at = 0; at < edges.size(); ++at)
    for (unsigned before = 0; before < at; ++before)
      if (edges[at].first == edges[before].first || edges[at].second == edges[before].second)
        joined.join(at, before);
  joined.compress();
  Classified out{static_cast<std::uint32_t>(classes.size()), 0,
                 static_cast<std::uint32_t>(owns.size()), 0, 0, 0};
  for (unsigned number = 0; number < joined.getNumClasses(); ++number) {
    Carry carry{static_cast<std::uint32_t>(passed.size()), 0,
                static_cast<std::uint32_t>(carried.size()), 0};
    for (auto [at, edge] : llvm::enumerate(edges)) {
      if (joined[static_cast<unsigned>(at)] != number)
        continue;
      auto [operand, input] = edge;
      ValueId into = bounded.at(input);
      auto passes = llvm::ArrayRef<Pass>(passed).drop_front(carry.passes);
      if (llvm::none_of(passes, [&](const Pass &pass) { return pass.operand == operand; }))
        passed.push_back(Pass{operand, bounded.at(operand->get()), into});
      if (llvm::is_contained(llvm::ArrayRef<ValueId>(carried).drop_front(carry.inputs), into))
        continue;
      carried.push_back(into);
      auto arg = dyn_cast<BlockArgument>(input);
      if (arg && arg.getOwner()->getParentOp() == joint)
        owns.push_back(into);
    }
    carry.passesEnd = static_cast<std::uint32_t>(passed.size());
    carry.inputsEnd = static_cast<std::uint32_t>(carried.size());
    classes.push_back(carry);
  }
  out.carriesEnd = static_cast<std::uint32_t>(classes.size());
  auto classed = static_cast<std::uint32_t>(owns.size());
  auto held = [&](ValueId v) {
    return llvm::is_contained(
        llvm::ArrayRef<ValueId>(carried).slice(classes[out.carries].inputs,
                                               carried.size() - classes[out.carries].inputs),
        v);
  };
  for (Region &region : joint->getRegions())
    for (Block &block : region)
      for (BlockArgument arg : block.getArguments()) {
        if (!isCarriedAsBig(arg.getType()))
          continue;
        ValueId v = bounded.at(arg);
        if (!llvm::is_contained(
                llvm::ArrayRef<ValueId>(owns).slice(out.arguments, classed - out.arguments), v))
          owns.push_back(v);
      }
  out.argumentsEnd = out.results = static_cast<std::uint32_t>(owns.size());
  for (OpResult result : joint->getResults()) {
    if (!isCarriedAsBig(result.getType()))
      continue;
    ValueId v = bounded.at(result);
    if (out.carries == out.carriesEnd || !held(v))
      owns.push_back(v);
  }
  out.resultsEnd = static_cast<std::uint32_t>(owns.size());
  return out;
}

// A value two joints both carry, as a jump forwards into an enclosing join
// point's region, joins their classes into one web.
IndexVector<ValueId, ValueId> Facts::join() const {
  llvm::IntEqClasses joined(values.size().value());
  for (const Carry &carry : classes) {
    llvm::ArrayRef<ValueId> into = inputs(carry);
    for (ValueId v : into.drop_front())
      joined.join(into.front().index(), v.index());
  }
  auto ids = values.size().ids();
  return IndexVector<ValueId, ValueId>(
      values.size(), [&](ValueId v) { return ids[joined.findLeader(v.index())]; });
}

} // namespace idr::narrow
