// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of the module, which the root's symbol-use verifier runs once
// every op of the module is verified: one root; every data type with a
// body, a box under the header's tags, a memo sum only in a box; and the
// containment of the data types. What one function does with its values is
// its own verifier's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"

#include "idris_rt.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::verify::program(ModuleOp module) {
  // One root, which is the only public function.
  unsigned roots = 0;
  for (auto fn : module.getOps<FuncOp>())
    roots += fn.isPublic() ? 1 : 0;
  if (roots != 1)
    return module.emitOpError("expects exactly one public function (the root), found ") << roots;

  // The data types the module's values and bodies hold, each once.
  TypeGraph graph(module.getOperation());
  for (unsigned at = 0, n = graph.size(); at < n; ++at) {
    DataType data = graph.declaration(at);
    if (!data)
      continue;
    if (!data.hasBody())
      return module.emitOpError("holds the data type \"") << data.getName()
                                                         << "\", which has no body";
    // A box's tag is in its header, which has room for this many
    // constructors; a sum held in place has a tag slot as wide as its count
    // needs.
    if (graph.boxed(at) && data.getCtors().size() > IDRIS_RT_TAG_LIMIT)
      return refuse(module, Rule::Layout)
             << "the boxed type \"" << data.getName() << "\" has " << data.getCtors().size()
             << " constructors, and a boxed type has at most " << IDRIS_RT_TAG_LIMIT;
    // A cell has one memo, which every reference to it sees.
    if (data.isMemo() && graph.inlined(at))
      return module.emitOpError("holds the memo sum \"")
             << data.getName() << "\" in place; a memo sum is held only in a box";
  }

  // Containment in place is acyclic, so every cycle of types passes through
  // a box: a value held in place is stored where it is, and one that holds
  // itself would have no size.
  SmallVector<DataType> selfContained = graph.containsItself();
  if (!selfContained.empty())
    return module.emitOpError("holds the data type \"")
           << selfContained.front().getName()
           << "\", which contains itself in place; a recursive type is held through a box";
  return knots(module, graph);
}
