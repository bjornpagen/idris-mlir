// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ownership rule the IR is held to: the local rule of exclusivity on
// every value that claims anything of its sharing (ownership::LocalCheck),
// one rule of the function's one walk.

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

// What `value`'s type claims of its sharing: nothing, its own cells, or
// everything it reaches.
Unique claimed(Value value) { return ownership::claimOf(value.getType()); }

bool claimsAny(Value value) { return claimed(value) != Unique::None; }

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

ownership::CellOf idr::ownership::cellOf(Value value) {
  if (std::optional<Value> same = sameValueSource(value))
    return SameCell{*same};
  Operation *op = value.getDefiningOp();
  auto declared = dyn_cast_or_null<FlowOpInterface>(op);
  if (!declared)
    return UnknownCell{};
  FlowEdges edges;
  declared.getFlowEdges(edges);
  bool made = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
    return match(
        edge.move, [&](const FlowEdges::Fresh &fresh) { return fresh.to == value; },
        [](const OneOf<FlowEdges::Flow, FlowEdges::Unify, FlowEdges::Source, FlowEdges::Release,
                       FlowEdges::Overwrite, FlowEdges::Fill, FlowEdges::Dispatch,
                       FlowEdges::Constant> auto &) { return false; });
  });
  if (!made)
    return UnknownCell{};
  return NewCell{op};
}

Unique idr::ownership::carriedClaim(Value value) {
  return match(
      cellOf(value), [](const SameCell &same) { return claimOfSource(same.of); },
      [&](const NewCell &cell) {
        FlowEdges edges;
        cast<FlowOpInterface>(cell.op).getFlowEdges(edges);
        llvm::SmallVector<Term<Value>, 4> terms;
        forEachTerm(
            edges,
            [&](Value target, const Term<Value> &term) {
              if (target == value)
                terms.push_back(term);
            },
            [](Value) {});
        return claimFrom<Value>(Origin::Fresh, terms, [](Value source) {
                 return claimOfSource(source);
               }).value_or(Unique::None);
      },
      [](const UnknownCell &) { return Unique::None; });
}

LogicalResult idr::ownership::LocalCheck::check(Operation *op) {
  // What `op` forwards into a value that claims anything: each predecessor
  // is held where it forwards, so a value with many is held to each.
  llvm::SmallVector<std::pair<OpOperand *, Value>, 2> intoClaimed;
  forwardedValues(op, [&](OpOperand &operand, Value input) {
    if (claimsAny(input))
      intoClaimed.emplace_back(&operand, input);
  });
  // Most ops touch nothing that claims anything, which settles them with
  // no edge read.
  auto inRegions = [&] {
    return llvm::any_of(op->getRegions(), [](Region &region) {
      return !region.empty() && llvm::any_of(region.front().getArguments(), claimsAny);
    });
  };
  if (intoClaimed.empty() && llvm::none_of(op->getResults(), claimsAny) &&
      llvm::none_of(op->getOperands(), claimsAny) && !inRegions())
    return success();

  for (auto [operand, input] : intoClaimed)
    if (!covers(claimOfSource(operand->get()), claimed(input)))
      return op->emitOpError("forwards operand #")
             << operand->getOperandNumber() << " of type " << operand->get().getType()
             << " into a value of type " << input.getType()
             << ", which claims more than the operand holds";

  auto declared = dyn_cast<FlowOpInterface>(op);
  if (!declared)
    return success();
  FlowEdges edges;
  declared.getFlowEdges(edges);

  // No value that claims anything is copied: a second reference reaches
  // its own cells at least.
  for (OpOperand &use : op->getOpOperands())
    if (claimsAny(use.get()) && copies(edges, use) && !takesOrGivesUp(edges, use))
      return op->emitOpError("copies operand #")
             << use.getOperandNumber() << " of type " << use.get().getType()
             << ", which claims that nothing else reaches its cells";

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
    return inferred.empty() ||
           !covers(claimOf(inferred[result.getResultNumber()]), claimed(result));
  };

  // Each value the op makes that claims anything, from the terms its edges
  // give; a value a callee gives is its callee's.
  llvm::SmallVector<Value, 4> judged;
  for (OpResult result : op->getResults())
    if (claimsAny(result) && beyondInference(result) && !givenByCallee(edges, result))
      judged.push_back(result);
  for (Region &region : op->getRegions())
    if (!region.empty())
      for (BlockArgument arg : region.front().getArguments())
        if (claimsAny(arg))
          judged.push_back(arg);
  for (Value value : judged) {
    llvm::SmallVector<Term<Value>, 4> terms;
    Made made = Made::Elsewhere;
    forEachTerm(
        edges,
        [&](Value target, const Term<Value> &term) {
          if (target == value)
            terms.push_back(term);
        },
        [&](Value target) {
          if (target == value)
            made = Made::New;
        });
    Origin origin = originOf<Value>(made, terms);
    // A value no edge of the op names is forwarded into from its regions (a
    // region branch's results, held at each terminator), bound by the op's
    // own rule (a token and fields a uniqueness match binds, held by its
    // verifier), or its operand's value at a grade that only forgets (a
    // share, which gives the operand's reference up and its claim down,
    // held by its verifier).
    if (origin == Origin::Unexplained && terms.empty() &&
        (isa<BlockArgument>(value) || isa<RegionBranchOpInterface>(op) ||
         op->hasTrait<ResultCarriesOperand>()))
      continue;
    // A cast that enters a value used many times as its one use carries
    // what the value's cell holds; every other source claims what its type
    // says. Open: what a callee keeps of what it is lent is the program's
    // marking, which idr-in-place asks, and no fact of the IR carries it yet
    // (a parameter scoped under a view lifetime, or a fact of the
    // signature, is the owner's to rule), so here every lend is taken to end
    // with its call and the rule's local half alone is checked: no other use
    // runs after the cast, and each hands the value on or is a call.
    auto entering = dyn_cast<LinCastOp>(op);
    auto sourceClaim = [&](Value source) {
      if (entering && entering.getDirection() == QuantityChange::Enter &&
          source == entering.getValue() &&
          std::holds_alternative<EntersAlone>(
              entryOf(entering, [](const FlowSource::Parameter &) { return Lent::Ends; })))
        return carriedClaim(source);
      return claimOfSource(source);
    };
    std::optional<Unique> claim = claimFrom<Value>(origin, terms, sourceClaim);
    if (claim && !covers(*claim, claimed(value))) {
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
