// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the guards and of output (idr/IR/Ops/Rules.h).

#include "idr/IR/Ops/Rules.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

// A string is never empty where the op that makes it says so (NeverEmpty),
// where it is a constant whose text is not (upstream's constant matcher),
// or where it is an append either of whose parts is never empty, which only
// its parts tell: essential, the one builder whose answer is its operands'.
// The walk enters the append that makes `str`, and below it only an append
// whose one use is the append it was reached from, so what it walks is a
// tree, each op entered once with nothing remembered of it. A shared append
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
    if (StringAttr text; matchPattern(def, m_Constant(&text))) {
      if (!text.getValue().empty())
        return true;
      continue;
    }
    auto append = next.getDefiningOp<StrAppendOp>();
    if (!append || (next != str && !next.hasOneUse()))
      continue;
    work.push_back(append.getLhs());
    work.push_back(append.getRhs());
  }
  return false;
}

void idr::eraseAfter(RewriterBase &rewriter, Operation *op) {
  Block *block = op->getBlock();
  while (&block->back() != op)
    rewriter.eraseOp(&block->back());
}

namespace idr::egraph {

//===----------------------------------------------------------------------===//
// Guards
//===----------------------------------------------------------------------===//

// The guard's own decision on what the graph knows of its operands, which
// the graph reads off the guard's op: each operand's interval, an integer
// the graph knows being its one value, and the string, Double or big past
// the small range its class holds, whether an op held it or the graph
// computed it. No fold is asked, and no attribute is made.
std::optional<Edit> GuardDecided::decide(GuardOpInterface guard, const OperandFacts &facts) {
  switch (facts.decision(guard)) {
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

// Each output rule asks for the input op of its class that builds the
// string written, a member computable where the output is, and its rewrite
// reads the root's string again on the input as it now is: a root an
// earlier rewrite changed is left as it is.

std::optional<Edit> OutputOfAppend::decide(IoPutStrOp output, const OperandFacts &facts) {
  if (facts.builtBy<StrAppendOp>(output.getStr()))
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
  if (facts.builtBy<StrConsOp>(output.getStr()))
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
  if (facts.builtBy<StrFromCharOp>(output.getStr()))
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

// The string is the empty one wherever the graph knows it, an op's
// constant or one the graph computed.
std::optional<Edit> OutputOfNothing::decide(IoPutStrOp output, const OperandFacts &facts) {
  std::optional<KnownConstant> known = facts.constant(output.getStr());
  bool empty = known && match(
                            *known, [](const Text *text) { return text->bytes().empty(); },
                            [](const OneOf<APInt, Real, const Big *> auto &) { return false; });
  if (empty)
    return Rewrite{};
  return std::nullopt;
}

void OutputOfNothing::rewrite(IoPutStrOp output, const Rewrite &, RewriterBase &rewriter) {
  rewriter.eraseOp(output);
}

} // namespace idr::egraph
