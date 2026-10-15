// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// No array can hold a reference to itself. Idris is strict and its data
// immutable, so a new object only points at objects that exist before it,
// and the heap is acyclic: what lets counting free everything, with a
// release walk that marks nothing and a count of one that means nobody
// else. An array, of any rank (an IORef is one of rank 0), is the one cell
// written after it exists, so a knot needs an array whose element type can
// reach the array again, and whether one can is a question of types,
// answered once for the program by its type graph. A knot is outside the
// language this compiler implements, as a collector finalizer is: no count
// frees it. So the rule `cycle` is of the category OutsideLanguage, not a
// megamorphic construct; its refusal rests on the type graph's cycles, a
// total analysis, and no count bounds it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// Whether a location is a place in a source file. The program's own code
// has one, under the name of the binder it came from if any; a library's
// has only its name, since the prefix installs no library sources, and a
// diagnostic there would point nowhere the user can look.
bool inSource(Location loc) { return static_cast<bool>(loc->findInstanceOf<FileLineColRange>()); }

// A type as the message names it: a data type by its name, an array by
// what it holds, an array of rank 0 as the IORef it is.
void describe(InFlightDiagnostic &out, Type type) {
  if (auto array = dyn_cast<MemRefType>(type)) {
    out << (array.getRank() == 0 ? "IORef of " : "array of ");
    describe(out, array.getElementType());
  } else if (DataType data = dataTypeOf(type)) {
    out << data.getName();
  } else {
    out << type;
  }
}

} // namespace

// Each cycle is reported once, with the types on it, where the program's
// source shows it: at the first idr.array.new in the program's own code
// that makes one of its arrays; or else, when only a library makes them
// (an IORef that base's newIORef makes), at the first constructor in the
// program's own code of a type on the cycle, which is what closes the knot;
// or else at the program.
LogicalResult idr::verify::knots(ProgramOp program, const TypeGraph &graph) {
  SmallVector<SmallVector<unsigned>> knotted = graph.knots();
  if (knotted.empty())
    return success();

  // The array each message names: the one the first idr.array.new of the
  // knot in the program's own code makes, else the knot's first. The
  // program's rules run once every op of it is verified, so an array.new
  // is read through its own accessors.
  llvm::DenseMap<Type, std::pair<unsigned, unsigned>> knotOf;
  SmallVector<unsigned> named;
  // Where each knot is reported, once the program's own code shows it.
  SmallVector<std::optional<Location>> where(knotted.size());
  for (auto [knot, members] : llvm::enumerate(knotted)) {
    for (unsigned at : members)
      if (graph.isArray(at))
        knotOf[graph.type(at)] = {static_cast<unsigned>(knot), at};
    named.push_back(*llvm::find_if(members, [&](unsigned at) { return graph.isArray(at); }));
  }
  program.walk([&](ArrayNewOp array) {
    if (!inSource(array.getLoc()))
      return;
    auto found = knotOf.find(unrestricted(array.getArray().getType()));
    if (found == knotOf.end() || where[found->second.first])
      return;
    where[found->second.first] = array.getLoc();
    named[found->second.first] = found->second.second;
  });
  llvm::DenseMap<DataType, unsigned> knotOfData;
  for (auto [knot, members] : llvm::enumerate(knotted))
    for (unsigned at : members)
      if (auto data = dyn_cast<DataType>(graph.type(at)))
        knotOfData[data] = static_cast<unsigned>(knot);
  program.walk([&](ConOp con) {
    if (!inSource(con.getLoc()))
      return;
    auto found = knotOfData.find(con.getDataType());
    if (found != knotOfData.end() && !where[found->second])
      where[found->second] = con.getLoc();
  });

  for (auto [members, shown, array] : llvm::zip_equal(knotted, where, named)) {
    SmallVector<unsigned> cycle = graph.cycle(array, members);
    InFlightDiagnostic error = refuse(shown.value_or(program.getLoc()), Rule::Cycle);
    // The lead names the array itself, by its rank: the path after it runs
    // from what the array holds, through any types between, to the array
    // and back.
    error << "an ";
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
