// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ownership rules the IR is held to: no reference knot in the program's
// types (verify::knots, below), and the local rule of exclusivity on every
// value typed `unique deep` (ownership::LocalCheck, after it).
//
// No array can hold a reference to itself. Idris is strict and its data
// immutable, so a new object only points at objects that exist before it,
// and the heap is acyclic: what lets counting free everything, with a
// release walk that marks nothing and a count of one that means nobody
// else. Two kinds of cell are written after they exist: an array, of any
// rank (an IORef is one of rank 0), and a memo cell, whose force writes its
// value. A memo cell closes no knot of counted cells. A counted one's value
// is computed from its captures, which exist before it, and from globals:
// arrays, refused here, and constant applicative forms, whose memo labels'
// functions put their forced values into static data, never freed, so no
// counted cell is reached from one that a count would have to free. So a
// knot of counted cells needs an array whose element type can reach the
// array again, and whether one can is a question of types, answered once
// for the program by its type graph, over the families defunctionalization
// declared for every closure and memo sum. A knot is outside the language
// this compiler implements, as a collector finalizer is: no count frees
// it. So the rule `cycle` is of the category OutsideLanguage, generated
// with its phrase from the specification's rules, not a megamorphic
// construct; its refusal rests on the type graph's cycles, a total
// analysis, and no count bounds it. It refuses the user's program, so a
// pass runs it (idr-knots), not the verifier: a module with a knot still
// reads into every tool.

#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

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

//===----------------------------------------------------------------------===//
// The local rule of exclusivity
//===----------------------------------------------------------------------===//

namespace {

// Whether an edge of `edges` takes `use` over or gives its reference up:
// then a read of its value in the same op hands the one reference on.
bool takesOrGivesUp(const FlowEdges &edges, OpOperand &use) {
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move, [&](const FlowEdges::Flow &flow) { return flow.from.taken() == &use; },
        [&](const FlowEdges::Release &release) { return release.use == &use; },
        [](const ownership::KeepsUses auto &) { return false; });
  });
}

// Whether `edges` read `use`'s value whole into another value, a second
// reference to what it holds.
bool copies(const FlowEdges &edges, OpOperand &use) {
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    if (!edge.carries(Carrier::Reference))
      return false;
    return match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          bool read = match(
              flow.from.at,
              [&](const FlowSource::Whole &whole) { return whole.value == use.get(); },
              [](const OneOf<FlowSource::Taken, FlowSource::Part, FlowSource::Parameter,
                             FlowSource::Result> auto &) { return false; });
          return read && flow.to.value().has_value();
        },
        [](const ownership::NoFlow auto &) { return false; });
  });
}

bool claimsDeep(Value value) { return claims(value.getType(), Unique::Deep); }

} // namespace

LogicalResult idr::ownership::LocalCheck::check(Operation *op) {
  // What `op` forwards into a value typed unique deep: each predecessor is
  // held where it forwards, so a value with many is held to each.
  llvm::SmallVector<std::pair<OpOperand *, Value>, 2> intoDeep;
  forwardedValues(op, [&](OpOperand &operand, Value input) {
    if (claimsDeep(input))
      intoDeep.emplace_back(&operand, input);
  });
  // Most ops touch nothing typed unique deep, which settles them with no
  // edge read.
  auto inRegions = [&] {
    return llvm::any_of(op->getRegions(), [](Region &region) {
      return !region.empty() && llvm::any_of(region.front().getArguments(), claimsDeep);
    });
  };
  if (intoDeep.empty() && llvm::none_of(op->getResults(), claimsDeep) &&
      llvm::none_of(op->getOperands(), claimsDeep) && !inRegions())
    return success();

  for (auto [operand, input] : intoDeep)
    if (claimOfSource(operand->get()) != Unique::Deep)
      return op->emitOpError("forwards operand #")
             << operand->getOperandNumber() << " of type " << operand->get().getType()
             << " into a value of type " << input.getType()
             << ", which claims more than the operand holds";

  auto declared = dyn_cast<FlowOpInterface>(op);
  if (!declared)
    return success();
  FlowEdges edges;
  declared.getFlowEdges(edges);

  // No value typed unique deep is copied.
  for (OpOperand &use : op->getOpOperands())
    if (claimsDeep(use.get()) && copies(edges, use) && !takesOrGivesUp(edges, use))
      return op->emitOpError("copies operand #")
             << use.getOperandNumber() << " of type " << use.get().getType()
             << ", which claims that nothing else reaches what it holds";

  // A call's results are its callee's, held by its symbol-use verifier.
  if (isa<CallOpInterface>(op))
    return success();
  // An inferred result is its op's inference, which its verifier holds it
  // to; only a result its op admits at a claim beyond the inference (a
  // cell's init, at any grade) is the rule's.
  llvm::SmallVector<Type, 4> inferred;
  if (auto infer = dyn_cast<InferTypeOpInterface>(op))
    if (failed(infer.inferReturnTypes(op->getContext(), op->getLoc(), op->getOperands(),
                                      op->getRawDictionaryAttrs(), op->getPropertiesStorage(),
                                      op->getRegions(), inferred)))
      return failure();
  auto beyondInference = [&](OpResult result) {
    return inferred.empty() || !claims(inferred[result.getResultNumber()], Unique::Deep);
  };

  // Each value the op makes typed unique deep, from the terms its edges give.
  llvm::SmallVector<Value, 4> judged;
  for (OpResult result : op->getResults())
    if (claimsDeep(result) && beyondInference(result))
      judged.push_back(result);
  for (Region &region : op->getRegions())
    if (!region.empty())
      for (BlockArgument arg : region.front().getArguments())
        if (claimsDeep(arg))
          judged.push_back(arg);
  for (Value value : judged) {
    llvm::SmallVector<Term<Value>, 4> terms;
    bool fresh = false;
    forEachTerm(
        edges,
        [&](Value target, const Term<Value> &term) {
          if (target == value)
            terms.push_back(term);
        },
        [&](Value target) { fresh |= target == value; });
    Origin origin = originOf<Value>(fresh, terms);
    // A value no edge of the op names is forwarded into from its regions (a
    // region branch's results, held at each terminator), or bound by the
    // op's own rule (a token and fields a uniqueness match binds, held by
    // its verifier).
    if (origin == Origin::Unexplained && terms.empty() &&
        (isa<BlockArgument>(value) || isa<RegionBranchOpInterface>(op)))
      continue;
    std::optional<Unique> claim =
        claimFrom<Value>(origin, terms, [](Value source) { return claimOfSource(source); });
    if (claim && *claim != Unique::Deep) {
      InFlightDiagnostic error = op->emitOpError("makes a value of type ")
                                 << value.getType() << ", but ";
      if (origin == Origin::Unexplained)
        error << "no edge it declares explains it";
      else if (origin == Origin::Fresh)
        error << "a part moved into it may be shared";
      else
        error << "what moves into it may be shared";
      return error;
    }
  }
  return success();
}
