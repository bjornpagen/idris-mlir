// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The facts of one function the word rewrite reads: its values numbered by
// the body's one numbering, the steps of the rewrite recorded in its order,
// each value's bounds read off the solve once, and the webs its joints
// carry; and the words and bigs that stand for each other.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::narrow {

using ranges::Bounds;

bool isBig(Type type) { return isa<BigType, NatType>(unrestricted(type)); }

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
  return llvm::any_of(op->getOperandTypes(), isBig) || llvm::any_of(op->getResultTypes(), isBig);
}

} // namespace

Bounds boundsOf(const Ranges::Solved &analysis, Value value) {
  // The program's poison may be taken to be any value, so a small one.
  if (value.getDefiningOp<ub::PoisonOp>())
    return {0, 0};
  // Code the analysis never reached has no range, and proves nothing.
  std::optional<ConstantIntRanges> range = analysis.rangeOf(value);
  if (!range)
    return {};
  // What the value's type proves holds wherever the analysis lost it, as a
  // natural's lower bound 0; a type that proves no range leaves the
  // analysis's as it is.
  IntegerValueRange proved = ranges::ofType(value.getType());
  if (!proved.isUninitialized())
    range = range->intersection(proved.getValue());
  return ranges::boundsOf(*range);
}

// The grade says whether a big holds a reference of its own: freed by its
// count. Static data, which its type says is static, holds none.
bool owned(Value value) { return freedBy(value.getType(), Release::Counted); }

// A view holds references and none of its own: freed when its lifetime
// ends.
bool borrowed(Value value) { return freedBy(value.getType(), Release::Scoped); }

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

Value big(OpBuilder &b, Location loc, Type type, Value word) {
  return BigSmallOp::create(b, loc, type, word);
}

Facts::Facts(FuncOp fn, const Ranges::Solved &analysis)
    : numbering(fn), values(walk(fn)), carriers(values.size(),
                                 [&](ValueId v) {
                                   Value value = values[v];
                                   if (!isBig(value.getType()))
                                     return Carrier::NoBig;
                                   return value.getDefiningOp<BigSmallOp>() ? Carrier::SmallBig
                                                                            : Carrier::Big;
                                 }),
      bounded(read(analysis)), webs(join()) {}

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
      numbered.push_back(numbering.at(operand));
    for (Value result : op->getResults())
      numbered.push_back(numbering.at(result));
    walked.push_back(Word{op, first});
  });
  // The numbering's table of values, its map kept for the questions that
  // arrive by value.
  solver::Numbering<Analysed> copy = numbering;
  return std::move(copy).finish().values;
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
      if (!isBig(input.getType()))
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
      ValueId into = numbering.at(input);
      auto passes = llvm::ArrayRef<Pass>(passed).drop_front(carry.passes);
      if (llvm::none_of(passes, [&](const Pass &pass) { return pass.operand == operand; }))
        passed.push_back(Pass{operand, numbering.at(operand->get()), into});
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
        if (!isBig(arg.getType()))
          continue;
        ValueId v = numbering.at(arg);
        if (!llvm::is_contained(
                llvm::ArrayRef<ValueId>(owns).slice(out.arguments, classed - out.arguments), v))
          owns.push_back(v);
      }
  out.argumentsEnd = out.results = static_cast<std::uint32_t>(owns.size());
  for (OpResult result : joint->getResults()) {
    if (!isBig(result.getType()))
      continue;
    ValueId v = numbering.at(result);
    if (out.carries == out.carriesEnd || !held(v))
      owns.push_back(v);
  }
  out.resultsEnd = static_cast<std::uint32_t>(owns.size());
  return out;
}

// The values a step reads, each read off the solve once; no other value is
// ever asked its bounds.
IndexVector<ValueId, Bounds> Facts::read(const Ranges::Solved &analysis) const {
  BitSet<ValueId> wanted(values.size());
  for (const Pass &pass : passed) {
    (void)wanted.raise(pass.from);
    (void)wanted.raise(pass.into);
  }
  for (ValueId v : carried)
    (void)wanted.raise(v);
  for (ValueId v : owns)
    (void)wanted.raise(v);
  for (ValueId v : numbered)
    (void)wanted.raise(v);
  return IndexVector<ValueId, Bounds>(values.size(), [&](ValueId v) {
    return wanted.test(v) ? boundsOf(analysis, values[v]) : Bounds{};
  });
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
