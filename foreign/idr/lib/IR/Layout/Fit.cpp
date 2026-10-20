// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The boxes that make every data type finite. A value held in place is
// stored where it is held, so a type that holds itself in place, directly or
// through others, has no size; a box leaves one pointer in its place. The
// frontend emits every data type in place and decides no box: the boxes are
// decided here, once, from the type graph, which holds the module's types
// whole. Every data type on a cycle of containment in place becomes a box
// wherever it is held in place, as the frontend's choice was, so every
// cycle passes through a box. The type of a value decides how it is held,
// so boxing a data type is the whole change, which every later pass and the
// lowering follow as they follow any box. A body is set once, so the types
// whose bodies held a boxed type in place are remade.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"

using namespace mlir;

namespace idr::layout {

FailureOr<unsigned> fit(ProgramOp root) {
  SmallVector<DataType> boxes = TypeGraph(root.getOperation()).containsItself();
  if (boxes.empty())
    return 0u;
  FailureOr<std::unique_ptr<DataRemap>> remap = DataRemap::create(
      root, "box",
      [](Type, std::optional<DataRemap::FieldPlace>) -> std::optional<Type> {
        return std::nullopt;
      },
      boxes);
  if (failed(remap))
    return failure();
  (*remap)->retype(root);
  return static_cast<unsigned>(boxes.size());
}

} // namespace idr::layout
