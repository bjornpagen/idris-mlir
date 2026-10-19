// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// No array can hold a reference to itself. Idris is strict and its data
// immutable, so a new object only points at objects that exist before it,
// and the heap is acyclic: what lets counting free everything, with a
// release walk that marks nothing and a count of one that means nobody
// else. Two kinds of cell are written after they exist: an array, of any
// rank (an IORef is one of rank 0), and a memo cell, whose force writes its
// value. A memo cell closes no knot of counted cells. A counted one's value
// is computed from its captures, which exist before it, and from globals:
// arrays, refused here, and constant applicative forms, whose memo cells
// are static data and make what they hold persistent when forced
// (idris_rt_persist_held), so no counted cell reaches one. So a knot of
// counted cells needs an array whose element type can reach the array
// again, and whether one can is a question of types, answered once for the
// program by its type graph. A knot is outside the
// language this compiler implements, as a collector finalizer is: no count
// frees it. So the rule `cycle` is of the category OutsideLanguage, not a
// megamorphic construct; its refusal rests on the type graph's cycles, a
// total analysis, and no count bounds it. It refuses the user's program, so
// a pass runs it (idr-knots), not the verifier: a module with a knot still
// reads into every tool.

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

// One cycle of the program's type graph, as it is reported: its members,
// the array its message names (the one the first idr.array.new of the
// cycle in the program's own code makes, else its first array), and where
// the program's own code shows it, once found.
struct Knot {
  SmallVector<unsigned> members;
  unsigned named;
  std::optional<Location> at;
};

// An array type on a knot, and its member there: TypeGraph gives no member
// of a type, so the one the knot has is kept with it.
struct ArrayIn {
  Knot *knot;
  unsigned member;
};

} // namespace

// Each cycle is reported once, with the types on it, where the program's
// source shows it: at the first idr.array.new in the program's own code
// that makes one of its arrays; or else, when only a library makes them
// (an IORef that base's newIORef makes), at the first constructor in the
// program's own code of a type on the cycle, which is what closes the knot;
// or else at the program.
LogicalResult idr::verify::knots(ProgramOp program, const TypeGraph &graph) {
  // Built whole before any pointer into it is taken.
  SmallVector<Knot> knots;
  for (SmallVector<unsigned> &members : graph.knots()) {
    unsigned named = *llvm::find_if(members, [&](unsigned at) { return graph.isArray(at); });
    knots.push_back({std::move(members), named, std::nullopt});
  }
  if (knots.empty())
    return success();

  llvm::DenseMap<Type, ArrayIn> arrays;
  llvm::DenseMap<DataType, Knot *> datas;
  for (Knot &knot : knots)
    for (unsigned at : knot.members) {
      if (graph.isArray(at))
        arrays[graph.type(at)] = {&knot, at};
      if (auto data = dyn_cast<DataType>(graph.type(at)))
        datas[data] = &knot;
    }
  program.walk([&](ArrayNewOp array) {
    if (!inSource(array.getLoc()))
      return;
    auto found = arrays.find(unrestricted(array.getArray().getType()));
    if (found == arrays.end() || found->second.knot->at)
      return;
    found->second.knot->at = array.getLoc();
    found->second.knot->named = found->second.member;
  });
  program.walk([&](ConOp con) {
    if (!inSource(con.getLoc()))
      return;
    auto found = datas.find(con.getDataType());
    if (found != datas.end() && !found->second->at)
      found->second->at = con.getLoc();
  });

  for (const Knot &knot : knots) {
    SmallVector<unsigned> cycle = graph.cycle(knot.named, knot.members);
    InFlightDiagnostic error = refuse(knot.at.value_or(program.getLoc()), Rule::Cycle);
    // The lead names the array itself, by its rank: the path after it runs
    // from what the array holds, through any types between, to the array
    // and back.
    error << "an ";
    describe(error, graph.type(knot.named));
    error << " can hold a reference to itself through ";
    for (auto [step, at] : llvm::enumerate(cycle)) {
      if (step != 0)
        error << " -> ";
      describe(error, graph.type(at));
    }
  }
  return failure();
}
