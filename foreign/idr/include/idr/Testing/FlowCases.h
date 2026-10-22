// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the control-flow box, and the facts its judgement compares:
// each case a function holding a nest of idr.join, idr.loop and lit.match
// whose regions end in idr.yield or idr.jump, built from a seed, with what
// its builder meant as it built it. A fact names the IR it is about by
// identity, and each op the builder makes is located at a name of its own
// (a NameLoc), which a failure prints.
#ifndef IDR_TESTING_FLOWCASES_H
#define IDR_TESTING_FLOWCASES_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/PointerUnion.h"

#include <cstdint>
#include <vector>

namespace idr::box::flow {

// Where control goes: a region, or out of an op to its results.
using Place = llvm::PointerUnion<mlir::Region *, mlir::Operation *>;

// A successor of a branch point: `from` is the op itself, entered, or a
// terminator of one of its regions.
struct Edge {
  mlir::Operation *from;
  Place to;
};
// An operand a branch point forwards, and the value it becomes there.
struct Move {
  mlir::OpOperand *use;
  mlir::Value input;
};
// A branch point that arrives at `at`, a region of the join point's op
// `group` or its results: `from` is the op itself, entering its body, or a
// terminator.
struct Arrival {
  mlir::Operation *group;
  Place at;
  mlir::Operation *from;
};

struct Facts {
  std::vector<Edge> edges;
  std::vector<Move> moves;
  std::vector<Arrival> arrivals;
};

// A case: its module, which owns its function, and what its builder meant.
struct Case {
  mlir::OwningOpRef<mlir::ModuleOp> module;
  Facts meant;
};

// The case of `seed`, built in `context`, which has the idr and func
// dialects loaded.
Case caseOf(mlir::MLIRContext &context, std::uint64_t seed);

} // namespace idr::box::flow

#endif // IDR_TESTING_FLOWCASES_H
