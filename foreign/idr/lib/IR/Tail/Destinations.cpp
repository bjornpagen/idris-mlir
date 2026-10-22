// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A destination: the right to write a place once. Used exactly once by its
// type, which the one linearity rule holds after every pass, so a second
// write and a forgotten one are each a use too many or too few; the write
// gives nothing back. Its type says only what the place takes. Where the
// place is belongs to the op that made it, so what a value written through
// it may be is what fills a field of its type in any cell. One op makes a
// place of its own, the answer slot: a region bound to the slot's
// destination, the value written read out when the region ends.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// !idr.dest
//===----------------------------------------------------------------------===//

// What a place holds is a carrier a value may be: a grade is how a value
// is used, which the value written carries and the place does not; a type
// used once by its type is consumed where it is, so a place that kept one
// would be read back as a second use; and a lifetime is never stored. Every
// op that makes a destination asks this, so what a hole may be is said
// here alone.
LogicalResult DestType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (isa<GradedType>(value))
    return emitError() << "a destination takes the carrier written through it, not the grade "
                       << value;
  if (idr::isLinearByType(value))
    return emitError() << "a destination never takes " << value
                       << ", which is used exactly once by its type";
  if (isa<LifetimeType>(value))
    return emitError() << "a destination never takes a lifetime";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.dest.write
//===----------------------------------------------------------------------===//

// The value fills a field of the destination's carrier as a counted cell's
// field is filled: its carrier, perhaps refined; freed by its count or
// never; used freely. That holds wherever the place is, which the type
// does not say: a counted cell takes no scoped value, and the place's own
// uses are its field's, so a value used once could be read back freely.
LogicalResult DestWriteOp::verify() {
  Type value = getValue().getType();
  Type held = getDest().getType().getValue();
  if (!fillsField(value, held, Hold::counted()))
    return emitOpError("writes ") << value << " through a destination of " << held
                                  << ", which it does not fill: a value of " << held
                                  << " or a refinement of it, counted or static, used freely";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.dest.answer
//===----------------------------------------------------------------------===//

// The region is entered once from the op and leaves to after it. Nothing
// is forwarded either way: the destination the region binds is the op's
// own, and the result is read out of the slot, never given by the yield,
// so the yield's end is no rejoin and no call before it is in tail
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

// The region binds the destination of the slot, of the result's type, and
// nothing else. What the slot may hold is the destination type's rule,
// asked here as everywhere a place is made. That the region gives nothing
// back is the region-branch interface's own check: its end forwards to no
// input.
LogicalResult DestAnswerOp::verifyRegions() {
  Type answer = getResult().getType();
  if (failed(DestType::verify([&] { return emitOpError(); }, answer)))
    return failure();
  Block &entry = getBody().front();
  if (entry.getNumArguments() != 1 ||
      entry.getArgument(0).getType() != DestType::get(getContext(), answer))
    return emitOpError("binds exactly the destination ")
           << DestType::get(getContext(), answer) << " of its slot, and nothing else";
  return success();
}
