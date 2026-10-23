// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A destination: the right to write a place once. Used exactly once by its
// type, which the one linearity rule holds after every pass, so a second
// write and a forgotten one are each a use too many or too few; the write
// gives nothing back. Its type says what the place takes at the grade the
// place keeps, which a write meets and the slot gives back, so a claim is
// not lost on the way. Where the place is belongs to the op that made it.
// One op makes places of its own, the answer slots: a region bound to one
// destination per result of a row, each value written read out when the
// region ends.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// !idr.dest
//===----------------------------------------------------------------------===//

// What a place holds is a value's type, at the grade it keeps: a type used
// once by its type is consumed where it is, so a place that kept one would
// be read back as a second use; and a lifetime is never stored. A graded
// type is neither, its own verifier says. Every op that makes a destination
// asks this, so what a hole or a slot may be is said here alone.
LogicalResult DestType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  switch (byTypeOf(value)) {
  case ByType::UsedOnceByType:
    return emitError() << "a destination never takes " << value
                       << ", which is used exactly once by its type";
  case ByType::UsedFreelyByType:
    return emitError() << "a destination never takes a lifetime";
  case ByType::UsedAsGraded:
    return success();
  }
  return success();
}

//===----------------------------------------------------------------------===//
// idr.dest.write
//===----------------------------------------------------------------------===//

// The value stands where the place's type is asked, as a value pushed into
// a frame stands where its field's grade is: it fills a field of that type
// (its carrier, perhaps refined; used once only where the place is) and
// its hold fits the place's, its claim forgotten down to the place's or
// static data standing for a value that claims nothing. The place keeps
// what its type states, and the slot gives that back, so a write that
// claimed less would be a claim forged at the read.
LogicalResult DestWriteOp::verify() {
  Type value = getValue().getType();
  Type place = getDest().getType().getValue();
  std::optional<Hold> kept = holdOf(place);
  std::optional<Hold> given = holdOf(value);
  if (!fillsField(value, place, kept) || (kept && !(given && given->fits(*kept))))
    return emitOpError("writes ") << value << " through a destination of " << place
                                  << ", where it does not stand: a value of its carrier or a "
                                  << "refinement of it, used once only where it is, claiming "
                                  << "at least what it claims";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.dest.answer
//===----------------------------------------------------------------------===//

// The region is entered once from the op and leaves to after it. Nothing
// is forwarded either way: the destinations the region binds are the op's
// own, and the results are read out of the slots, never given by the
// yield, so the yield's end is no rejoin and no call before it is in tail
// position.
void DestAnswerOp::getSuccessorRegions(RegionBranchPoint point,
                                       SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&getBody()));
  else
    regions.push_back(RegionSuccessor(getOperation()));
}

ValueRange DestAnswerOp::getSuccessorInputs(RegionSuccessor) { return ValueRange(); }

void DestAnswerOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                             SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// Each scoped result lives in its own entry of `outers`, paired in the
// order of the results, as every op that makes scoped values pairs them;
// the op gives no result of its own before them.
Value DestAnswerOp::getStatedLifetime(Value made) {
  return lifetimes::statedOuter(*this, made, 0);
}

void DestAnswerOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// The region binds one destination per result, of the result's type, and
// nothing else. What a slot may hold is the destination type's rule, asked
// here as everywhere a place is made. That the region gives nothing back
// is the region-branch interface's own check: its end forwards to no
// input. Each scoped result states its lifetime, as every op that makes a
// scoped value does.
LogicalResult DestAnswerOp::verifyRegions() {
  Block &entry = getBody().front();
  if (entry.getNumArguments() != getNumResults())
    return emitOpError("binds ") << entry.getNumArguments() << " destinations for "
                                 << getNumResults() << " results";
  for (auto [result, bound] : llvm::zip_equal(getResults(), entry.getArguments())) {
    Type answer = result.getType();
    if (failed(DestType::verify([&] { return emitOpError(); }, answer)))
      return failure();
    if (bound.getType() != DestType::get(getContext(), answer))
      return emitOpError("binds exactly the destination ")
             << DestType::get(getContext(), answer) << " of result #"
             << result.getResultNumber() << ", and nothing else";
  }
  return lifetimes::verifyOuters(*this, 0);
}
