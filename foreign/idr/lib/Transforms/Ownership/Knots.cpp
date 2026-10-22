// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-knots: no array can hold a reference to itself. It runs once every
// closure is a constructor of a sum, so that the program's type graph holds
// every cell a value may point at.
//
// Idris is strict and its data immutable, so a new object only points at
// objects that exist before it, and the heap is acyclic: what lets counting
// free everything, with a release walk that marks nothing and a count of
// one that means nobody else. Two kinds of cell are written after they
// exist: an array, of any rank (an IORef is one of rank 0), and a memo
// cell, whose force writes its value. A memo cell closes no knot of counted
// cells. A counted one's value is computed from its captures, which exist
// before it, and from globals: arrays, refused here, and constant
// applicative forms, whose memo labels' functions put their forced values
// into static data, never freed, so no counted cell is reached from one
// that a count would have to free. So a knot of counted cells needs an
// array whose element type can reach the array again, and whether one can
// is a question of types, answered once for the program by its type graph,
// over the families defunctionalization declared for every closure and
// memo sum. A knot is outside the language this compiler implements, as a
// collector finalizer is: no count frees it. So the rule `cycle` is of the
// category OutsideLanguage, generated with its phrase from the
// specification's rules, not a megamorphic construct; its refusal rests on
// the type graph's cycles, a total analysis, and no count bounds it. It
// refuses the user's program, so this pass runs it, not the verifier: a
// module with a knot still reads into every tool.
#include "idr/Analysis/Solver/TypeGraph.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

#define GEN_PASS_DEF_IDRKNOTS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace idr;

namespace {

// Whether a location is a place in a source file. The program's own code
// has one, under the name of the binder it came from if any; a library's
// has only its name, since the prefix installs no library sources, and a
// diagnostic there would point nowhere the user can look.
bool inSource(Location loc) { return static_cast<bool>(loc->findInstanceOf<FileLineColRange>()); }

// A family as the message and the knot's lookup name it: its group and
// member, whatever its index terms and refinement; its label is for the
// reader.
using Family = std::pair<Attribute, uint32_t>;
std::optional<Family> familyOf(Type type) {
  if (auto data = dyn_cast<DataType>(unrestricted(type)))
    return Family(data.getGroup(), data.getMember());
  return std::nullopt;
}

// A type as the message names it: a data type by its family's label, an
// array by what it holds, an array of rank 0 as the IORef it is. Arrays
// nest only as deep as the program wrote them, so the element is named by
// a loop, not a recursion.
void describe(InFlightDiagnostic &out, Type type) {
  while (auto array = dyn_cast<MemRefType>(type)) {
    out << (array.getRank() == 0 ? "IORef of " : "array of ");
    type = array.getElementType();
  }
  if (auto data = dyn_cast<DataType>(unrestricted(type)))
    out << data.getGroup().label(data.getMember()).getValue();
  else
    out << type;
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

// Each cycle is reported once, with the types on it, where the program's
// source shows it: at the first idr.array.new in the program's own code
// that makes one of its arrays; or else, when only a library makes them
// (an IORef that base's newIORef makes), at the first constructor in the
// program's own code of a type on the cycle, which is what closes the knot;
// or else at the program.
LogicalResult refuseKnots(ProgramOp program, const TypeGraph &graph) {
  // Built whole before any pointer into it is taken.
  SmallVector<Knot> knots;
  for (SmallVector<unsigned> &members : graph.knots()) {
    unsigned named = *llvm::find_if(members, [&](unsigned at) { return graph.isArray(at); });
    knots.push_back({std::move(members), named, std::nullopt});
  }
  if (knots.empty())
    return success();

  // The types on each knot, by their content's identity, for the cold
  // path that finds where the source shows the knot.
  llvm::DenseMap<Type, ArrayIn> arrays;
  llvm::DenseMap<Family, Knot *> datas;
  for (Knot &knot : knots)
    for (unsigned at : knot.members) {
      if (graph.isArray(at))
        arrays[graph.type(at)] = {&knot, at};
      if (std::optional<Family> family = familyOf(graph.type(at)))
        datas[*family] = &knot;
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
  program.walk([&](DataConOp con) {
    std::optional<Family> family = familyOf(con.getResult().getType());
    if (!inSource(con.getLoc()) || !family)
      return;
    auto found = datas.find(*family);
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

struct Knots : idr::impl::IdrKnotsBase<Knots> {
  void runOnProgram(ProgramOp program) {
    if (failed(refuseKnots(program, getAnalysis<TypeGraph>())))
      return signalPassFailure();
    markAllAnalysesPreserved();
  }
};

} // namespace
