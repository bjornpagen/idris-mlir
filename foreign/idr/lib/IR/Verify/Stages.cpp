// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where upstream's ops stand (Admission, idr/IR/Verify.h): each admitted
// op's stages, the specification's, read off the op's class through the
// generated table, whose classes the backend aliases from upstream's own
// defs, so no op is named and no stage restated here.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "idr/IR/Generated/AdmittedStages.h.inc"

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// The stages from `first` to `last` of the chain an admitted op may stand
// at.
struct Bounds {
  Stage first;
  Stage last;
};

// The stages of the admitted op whose class is `id`, by one fold over every
// admitted op; none where no list admits it, which the problem has, since
// upstream's models write ops of their own. Which registered op an
// operation is, is the one fact paid for here: the op set is open, so the
// class is known only when the program is verified.
template <class... Ops>
std::optional<Bounds> admittedAt(admitted::Rows<Ops...>, TypeID id) {
  std::optional<Bounds> found;
  auto row = [&]<class Row>() {
    if (id != TypeID::get<typename Row::Class>())
      return false;
    found = Bounds{Row::first, Row::last};
    return true;
  };
  (row.template operator()<Ops>() || ...);
  return found;
}

} // namespace

LogicalResult idr::verify::Admission::check(Operation *op) const {
  // An op of ours is held to its family's stages, never an admitted record's.
  if (isa_and_present<IdrDialect>(op->getDialect()))
    return success();
  if (std::optional<Bounds> bounds = admittedAt(admitted::Every{}, op->getName().getTypeID())) {
    if (bounds->first <= stage && stage <= bounds->last)
      return success();
    return op->emitOpError("stands in a program at the ")
           << stringifyStage(stage) << " stage, and is admitted from the "
           << stringifyStage(bounds->first) << " stage to the " << stringifyStage(bounds->last);
  }
  // An op no list names: past the frontend's stage it is one of upstream's
  // models', which no stage bounds.
  if (stage > admitted::listedThrough)
    return success();
  return op->emitOpError("stands in a program at the ")
         << stringifyStage(stage)
         << " stage, where every upstream op is admitted, and no admitted list names it";
}
