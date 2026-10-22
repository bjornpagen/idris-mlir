// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the guards and of output (idr/IR/Ops/Rules.h).

#include "idr/IR/Ops/Rules.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

// An append is never empty where either part is not, which only its parts
// tell: essential, the one builder whose answer is its operands'. The walk
// enters the append that makes `str`, and below it only an append whose
// one use is the append it was reached from, so what it walks is a tree,
// each op entered once with nothing remembered of it. A shared append
// below the first is judged by its builder alone, an append, so a
// never-empty part under it goes unseen. A string's tree is as large as
// the program's text makes it.
bool idr::neverEmpty(Value str) {
  footprint::Vector<Value> work{str};
  while (!work.empty()) {
    Value next = work.back();
    work.pop_back();
    Operation *def = next.getDefiningOp();
    if (!def)
      continue;
    if (def->hasTrait<NeverEmpty>())
      return true;
    if (auto constant = dyn_cast<ConstantOp>(def)) {
      auto text = dyn_cast<StringAttr>(constant.getValue());
      if (text && !text.getValue().empty())
        return true;
      continue;
    }
    auto append = dyn_cast<StrAppendOp>(def);
    if (!append || (next != str && !next.hasOneUse()))
      continue;
    work.push_back(append.getLhs());
    work.push_back(append.getRhs());
  }
  return false;
}

namespace idr::egraph {

namespace {

// Erases every op after `op` in its block, the last first, so each op's
// users are gone before it: what follows a crash never runs.
void eraseAfter(RewriterBase &rewriter, Operation *op) {
  Block *block = op->getBlock();
  while (&block->back() != op)
    rewriter.eraseOp(&block->back());
}

// The interval an operand has where the e-graph knows none: every value of
// its type, or the one value of width 0 a value that holds no integer has.
ConstantIntRanges widest(Type type) {
  unsigned width = ConstantIntRanges::getStorageBitwidth(type);
  if (width == 0)
    return ConstantIntRanges::constant(APInt::getZero(0));
  return ConstantIntRanges::maxRange(width);
}

} // namespace

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// On constants the guard's own fold decides, which answers from its
// constants alone and rewrites nothing; where every operand is a constant
// and the fold gives nothing, the condition fails. On intervals the
// guard's own decision, the meaning of its condition over intervals.
std::optional<Edit> GuardDecided::decide(GuardOpInterface guard, const OperandFacts &facts) {
  Operation *op = guard.getOperation();
  unsigned count = op->getNumOperands();
  SmallVector<Attribute> constants(count);
  bool everyConstant = true;
  for (unsigned i = 0; i < count; ++i) {
    constants[i] = facts.constant(op->getOperand(i));
    everyConstant = everyConstant && constants[i];
  }
  if (everyConstant) {
    SmallVector<OpFoldResult> folded;
    if (succeeded(op->fold(constants, folded)) && !folded.empty())
      return Forward{{0}};
    return Rewrite{};
  }
  SmallVector<ConstantIntRanges> ranges;
  ranges.reserve(count);
  for (unsigned i = 0; i < count; ++i)
    ranges.push_back(
        facts.range(op->getOperand(i)).value_or(widest(op->getOperand(i).getType())));
  switch (guard.decide(ranges)) {
  case numeric::Known::Holds:
    return Forward{{0}};
  case numeric::Known::Fails:
    return Rewrite{};
  case numeric::Known::Unknown:
    return std::nullopt;
  }
  return std::nullopt;
}

// Only a refuted guard is rewritten, on the input as round 1 decided it:
// a crash of its cause at its site in its place, the end of its block.
void GuardDecided::rewrite(GuardOpInterface guard, const Rewrite &, RewriterBase &rewriter) {
  Operation *op = guard.getOperation();
  rewriter.setInsertionPoint(op);
  CrashCauseOp crash =
      CrashCauseOp::create(rewriter, op->getLoc(), guard.getCause(), guard.getSite());
  eraseAfter(rewriter, crash);
}

// The checked value is the result of the same guard op given the same
// other operands.
std::optional<Edit> GuardRepeated::decide(GuardOpInterface guard, const OperandFacts &) {
  Operation *op = guard.getOperation();
  Operation *before = op->getOperand(0).getDefiningOp();
  if (before && before->getName() == op->getName() &&
      llvm::equal(before->getOperands().drop_front(), op->getOperands().drop_front()))
    return Forward{{0}};
  return std::nullopt;
}

void GuardRepeated::rewrite(GuardOpInterface, const Rewrite &, RewriterBase &) {}

std::optional<Edit> NeverEmptyString::decide(CheckNonemptyOp guard, const OperandFacts &) {
  if (neverEmpty(guard.getStr()))
    return Forward{{0}};
  return std::nullopt;
}

void NeverEmptyString::rewrite(CheckNonemptyOp, const Rewrite &, RewriterBase &) {}

//===----------------------------------------------------------------------===//
// Output
//===----------------------------------------------------------------------===//

// Each output rule reads the input op that made the chosen form of the
// string written, and its rewrite reads the root's string again on the
// input as it now is: a root an earlier rewrite changed is left as it is.

std::optional<Edit> OutputOfAppend::decide(IoPutStrOp output, const OperandFacts &facts) {
  if (isa_and_present<StrAppendOp>(facts.origin(output.getStr())))
    return Rewrite{};
  return std::nullopt;
}

void OutputOfAppend::rewrite(IoPutStrOp output, const Rewrite &, RewriterBase &rewriter) {
  auto append = output.getStr().getDefiningOp<StrAppendOp>();
  if (!append)
    return;
  rewriter.setInsertionPoint(output);
  IoPutStrOp::create(rewriter, output.getLoc(), append.getLhs());
  IoPutStrOp::create(rewriter, output.getLoc(), append.getRhs());
  rewriter.eraseOp(output);
}

std::optional<Edit> OutputOfCons::decide(IoPutStrOp output, const OperandFacts &facts) {
  if (isa_and_present<StrConsOp>(facts.origin(output.getStr())))
    return Rewrite{};
  return std::nullopt;
}

void OutputOfCons::rewrite(IoPutStrOp output, const Rewrite &, RewriterBase &rewriter) {
  auto cons = output.getStr().getDefiningOp<StrConsOp>();
  if (!cons)
    return;
  rewriter.setInsertionPoint(output);
  IoPutCharOp::create(rewriter, output.getLoc(), cons.getHead());
  IoPutStrOp::create(rewriter, output.getLoc(), cons.getTail());
  rewriter.eraseOp(output);
}

std::optional<Edit> OutputOfChar::decide(IoPutStrOp output, const OperandFacts &facts) {
  if (isa_and_present<StrFromCharOp>(facts.origin(output.getStr())))
    return Rewrite{};
  return std::nullopt;
}

void OutputOfChar::rewrite(IoPutStrOp output, const Rewrite &, RewriterBase &rewriter) {
  auto one = output.getStr().getDefiningOp<StrFromCharOp>();
  if (!one)
    return;
  rewriter.setInsertionPoint(output);
  IoPutCharOp::create(rewriter, output.getLoc(), one.getValue());
  rewriter.eraseOp(output);
}

std::optional<Edit> OutputOfNothing::decide(IoPutStrOp output, const OperandFacts &facts) {
  auto text = dyn_cast_if_present<StringAttr>(facts.constant(output.getStr()));
  if (text && text.getValue().empty())
    return Rewrite{};
  return std::nullopt;
}

void OutputOfNothing::rewrite(IoPutStrOp output, const Rewrite &, RewriterBase &rewriter) {
  rewriter.eraseOp(output);
}

} // namespace idr::egraph
