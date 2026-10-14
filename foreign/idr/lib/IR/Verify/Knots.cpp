// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// No array can hold a reference to itself. Idris is strict and its data
// immutable, so a new object only points at objects that exist before it,
// and the heap is acyclic: what lets counting free everything, with a
// release walk that marks nothing and a count of one that means nobody
// else. An array, of any rank (an IORef is one of rank 0), is the one cell
// written after it exists, so a knot needs an array whose element type can
// reach the array again, and whether one can is a question of types,
// answered once for the module by its type graph.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether a location is a place in a source file. The program's own code
// has one, under the name of the binder it came from if any; a library's
// has only its name, since the prefix installs no library sources, and a
// diagnostic there would point nowhere the user can look.
bool inSource(Location loc) { return static_cast<bool>(loc->findInstanceOf<FileLineColRange>()); }

// A type as the message names it: a declaration by its symbol, an array by
// what it holds, an array of rank 0 as the IORef it is.
void describe(InFlightDiagnostic &out, Type type) {
  if (auto array = dyn_cast<MemRefType>(type)) {
    out << (array.getRank() == 0 ? "IORef of " : "array of ");
    describe(out, array.getElementType());
  } else if (auto data = dyn_cast<DataType>(type)) {
    out << data.getName().getValue();
  } else if (auto box = dyn_cast<BoxType>(type)) {
    out << box.getName().getValue();
  } else {
    out << type;
  }
}

} // namespace

// Each cycle is reported once, with the types on it, where the program's
// source shows it: at the first idr.array.new in the program's own code
// that makes one of its arrays; or else, when only a library makes them
// (an IORef that base's newIORef makes), at a type on the cycle that the
// program declares, which is what closes the knot; or else at the module.
LogicalResult idr::verify::knots(ModuleOp module, const TypeGraph &graph) {
  SmallVector<SmallVector<unsigned>> knotted = graph.knots();
  if (knotted.empty())
    return success();

  // The array each message names: the one the first idr.array.new of the
  // knot in the program's own code makes, else the knot's first. This runs
  // before the ops are verified, so an array.new is read by the type of its
  // result alone.
  llvm::DenseMap<Type, std::pair<unsigned, unsigned>> knotOf;
  SmallVector<unsigned> named;
  SmallVector<Operation *> made(knotted.size(), nullptr);
  for (auto [knot, members] : llvm::enumerate(knotted)) {
    for (unsigned at : members)
      if (graph.isArray(at))
        knotOf[graph.type(at)] = {static_cast<unsigned>(knot), at};
    named.push_back(*llvm::find_if(members, [&](unsigned at) { return graph.isArray(at); }));
  }
  module.walk([&](Operation *op) {
    if (!isa<ArrayNewOp>(op) || op->getNumResults() == 0 || !inSource(op->getLoc()))
      return;
    auto found = knotOf.find(unrestricted(op->getResult(0).getType()));
    if (found == knotOf.end() || made[found->second.first])
      return;
    made[found->second.first] = op;
    named[found->second.first] = found->second.second;
  });
  for (auto [knot, members] : llvm::enumerate(knotted)) {
    if (made[knot])
      continue;
    for (unsigned at : members)
      if (DataOp data = graph.declaration(at); data && inSource(data.getLoc())) {
        made[knot] = data;
        break;
      }
  }

  for (auto [members, op, array] : llvm::zip_equal(knotted, made, named)) {
    SmallVector<unsigned> cycle = graph.cycle(array, members);
    InFlightDiagnostic error = op ? op->emitError() : module.emitError();
    // The lead names the array itself, by its rank: the path after it runs
    // from what the array holds, through any types between, to the array
    // and back.
    error << "unsupported (cycle): an ";
    describe(error, graph.type(array));
    error << " can hold a reference to itself through ";
    for (auto [step, at] : llvm::enumerate(cycle)) {
      if (step != 0)
        error << " -> ";
      describe(error, graph.type(at));
    }
  }
  return failure();
}
