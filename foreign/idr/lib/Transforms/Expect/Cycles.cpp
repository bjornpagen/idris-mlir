// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cycles of the graphs the properties of recursion are stated over:
// references among functions, as the loop breakers and the inliner see
// them, or symbol uses after lowering.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

SmallVector<Operation *> referencedBy(References &references, Operation *fn) {
  SmallVector<Operation *> out;
  for (const References::Site &site : references.of(cast<FuncOp>(fn)))
    out.push_back(site.target);
  return out;
}

SmallVector<SmallVector<Operation *>>
cycles(ArrayRef<Operation *> nodes, function_ref<SmallVector<Operation *>(Operation *)> edges) {
  SmallVector<SmallVector<Operation *>> out;
  for (SmallVector<Operation *> &component : idr::stronglyConnected<Operation *>(nodes, edges))
    if (component.size() > 1 || llvm::is_contained(edges(component.front()), component.front()))
      out.push_back(std::move(component));
  return out;
}

} // namespace idr::expect
