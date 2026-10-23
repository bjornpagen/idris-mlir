// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.lit.match: its rules, its builder, the region a constant takes, the
// edges upstream's control-flow interfaces read off it, what each region
// knows of its scrutinee, and the lifetimes it states. What it shares
// with idr.data.match is idr/IR/Control/MatchFamily.h.
//
// Its scrutinee is a word, a char, a double, a string, a big integer or a
// natural, read in place and never taken apart: a case binds nothing, since
// in it the scrutinee equals its literal (a double's zero key is taken by
// either zero), and the default, which it always has since no set of
// literals is exhaustive, binds the scrutinee, none of the keys, at its own
// type. A condition is chosen on by scf.if.

#include "idr/IR/Control/MatchFamily.h"
#include "idr/IR/Control/Stated.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::control;

// Keys are literals of the scrutinee's type, as the type says, each its
// value's one literal, so two keys are one exactly when they are one
// attribute. A case binds nothing, since in it the scrutinee equals its
// literal; the default binds the scrutinee, none of the keys, at its own
// type.
LogicalResult LitMatchOp::verify() {
  auto literals = cast<LiteralTypeInterface>(unrestricted(getScrutinee().getType()));
  for (Attribute key : getCases())
    if (!literals.isLiteral(key))
      return emitOpError("has a key ") << key << " that is not a literal of " << literals;
  if (failed(verifyKeys(*this)))
    return failure();
  for (Region &region : getCaseRegions())
    if (region.getNumArguments())
      return emitOpError("region #") << region.getRegionNumber()
                                     << " binds an argument, and a literal case binds none";
  Region &fallback = getDefaultRegion();
  if (TypeRange(fallback.getArgumentTypes()) != TypeRange(getScrutinee().getType()))
    return emitOpError("expects a default that binds its scrutinee, of type ")
           << getScrutinee().getType();
  return verifyYields(*this);
}

void LitMatchOp::build(OpBuilder &, OperationState &state, TypeRange results, Value scrutinee,
                       ArrayAttr cases) {
  state.addOperands(scrutinee);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = cases;
  addRegions(state, cases.size());
}

unsigned LitMatchOp::getNumCases() { return static_cast<unsigned>(getCaseRegions().size()); }

Region &LitMatchOp::getCaseRegion(unsigned index) { return getCaseRegions()[index]; }

unsigned LitMatchOp::caseOf(Region &region) { return region.getRegionNumber() - 1; }

// A case binds nothing, and in it the scrutinee equals the case's literal;
// the default binds the scrutinee at its own type, none of the keys.
CaseScrutinee LitMatchOp::getRegionScrutinee(Region &region) {
  if (&region == &getDefaultRegion())
    return case_scrutinee::Bound{region.getArgument(0)};
  return case_scrutinee::Equals{getCases()[caseOf(region)]};
}

// The cases kept by their keys, and the default, which a literal match
// always has: the scrutinee it binds is none of fewer keys still.
Operation *LitMatchOp::keepCases(RewriterBase &rewriter, ArrayRef<unsigned> kept,
                                 Region *fallback) {
  return keepCasesOf(*this, rewriter, kept, fallback, [&] {
    SmallVector<Attribute> keys =
        llvm::map_to_vector(kept, [&](unsigned index) { return getCases()[index]; });
    return LitMatchOp::create(rewriter, getLoc(), getResultTypes(), getScrutinee(),
                              rewriter.getArrayAttr(keys));
  });
}

Value LitMatchOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void LitMatchOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

unsigned LitMatchOp::getScopedBindings() { return scopedBindings(*this); }

std::optional<unsigned> LitMatchOp::getBindingEntry(Value made) { return bindingEntry(*this, made); }

void LitMatchOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  successorsOf(*this, point, successors);
}

// The scrutinee enters the default alone; the lifetimes the match states,
// its last operands, enter none.
OperandRange LitMatchOp::getEntrySuccessorOperands(RegionSuccessor successor) {
  return getOperation()->getOperands().take_front(
      successor.getSuccessor() == &getDefaultRegion() ? 1 : 0);
}

ValueRange LitMatchOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return successor.getSuccessor()->getArguments();
}

namespace {

// The region a constant scrutinee takes: the case whose key is that very
// literal (takenRegion), its value's one form, or the default's for a
// literal that is no key. Only a literal is looked up: a constant that is
// none (a double's NaN or negative zero, or a constant of no value of the
// type, a poison's) is found by no key here, so every region may run, and
// the lowering's comparison decides it.
Region *takenBy(LitMatchOp op, Attribute value) {
  auto literals = cast<LiteralTypeInterface>(unrestricted(op.getScrutinee().getType()));
  return value && literals.isLiteral(value) ? takenRegion(op, value) : nullptr;
}

} // namespace

void LitMatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  entrySuccessorsOf(*this, takenBy(*this, operands.front()), successors);
}

void LitMatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  boundsOf(*this, takenBy(*this, operands.front()), bounds);
}
