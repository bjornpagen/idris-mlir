// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A destination: the right to write a place once. Used exactly once by its
// type, which the one linearity rule holds after every pass, so a second
// write and a forgotten one are each a use too many or too few; the write
// gives nothing back. Its type says only what the place takes. Where the
// place is belongs to the op that made it, so what a value written through
// it may be is what fills a field of its type in any cell.

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
