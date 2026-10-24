// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ownership rule the IR is held to: the local rule of exclusivity on
// every value typed `unique deep` (ownership::LocalCheck), one rule of the
// function's one walk.

#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;
using namespace idr;

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

// Whether `edges` say a callee gives `value`: brought back whole from a
// result of a function by name, which the call's symbol-use verifier holds
// to that result's type, or a result of a call whose callee is a value,
// which runs the labels its closure holds and is held to the closure's
// type.
bool givenByCallee(const FlowEdges &edges, Value value) {
  return llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          bool returned = match(
              flow.from.at, [](const FlowSource::Result &) { return true; },
              [](const OneOf<FlowSource::Taken, FlowSource::Whole, FlowSource::Part,
                             FlowSource::Parameter> auto &) { return false; });
          bool intoValue = match(
              flow.to.at, [&](const FlowSource::Whole &into) { return into.value == value; },
              [](const OneOf<FlowPlace::Part, FlowSource::Parameter, FlowSource::Result> auto &) {
                return false;
              });
          return returned && intoValue;
        },
        [&](const FlowEdges::Dispatch &dispatch) {
          return llvm::is_contained(dispatch.call->getResults(), value);
        },
        [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh, FlowEdges::Release,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Constant> auto &) {
          return false;
        });
  });
}

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

  // Each value the op makes typed unique deep, from the terms its edges give;
  // a value a callee gives is its callee's.
  llvm::SmallVector<Value, 4> judged;
  for (OpResult result : op->getResults())
    if (claimsDeep(result) && beyondInference(result) && !givenByCallee(edges, result))
      judged.push_back(result);
  for (Region &region : op->getRegions())
    if (!region.empty())
      for (BlockArgument arg : region.front().getArguments())
        if (claimsDeep(arg))
          judged.push_back(arg);
  // A part built in, once references are counted, is the one reference it
  // is, whatever its grade's uses (the class's two stages).
  auto atStage = [&](Term<Value> term) {
    if (counting == StageCounting::Counted &&
        (term.via == Via::Built || term.via == Via::Filled))
      term.uses = Uses::Once;
    return term;
  };
  for (Value value : judged) {
    llvm::SmallVector<Term<Value>, 4> terms;
    Made made = Made::Elsewhere;
    forEachTerm(
        edges,
        [&](Value target, const Term<Value> &term) {
          if (target == value)
            terms.push_back(atStage(term));
        },
        [&](Value target) {
          if (target == value)
            made = Made::New;
        });
    Origin origin = originOf<Value>(made, terms);
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
