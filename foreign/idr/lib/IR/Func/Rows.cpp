// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's row and per-parameter record, held to its body: the fold
// every derivation shares, the verifier's instantiation of it, and the
// hand values the specification's attributes hold (a termination proof, a
// put bound) with the parameter view their positions are read through.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <string>
#include <utility>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The attributes' hand values
//===----------------------------------------------------------------------===//

llvm::hash_code idr::hash_value(const TerminationProof &proof) {
  return idr::match(
      proof, [](InComponent in) { return llvm::hash_combine(0u, in.component); },
      [](Acyclic) { return llvm::hash_combine(1u); });
}

ParseResult idr::parseTerminationProof(AsmParser &parser, TerminationProof &proof) {
  if (succeeded(parser.parseOptionalKeyword("acyclic"))) {
    proof = Acyclic{};
    return success();
  }
  std::uint32_t component = 0;
  if (parser.parseKeyword("component") || parser.parseInteger(component))
    return failure();
  proof = InComponent{component};
  return success();
}

void idr::printTerminationProof(AsmPrinter &printer, const TerminationProof &proof) {
  idr::match(
      proof, [&](InComponent in) { printer << "component " << in.component; },
      [&](Acyclic) { printer << "acyclic"; });
}

llvm::hash_code idr::hash_value(const PutBound &bound) {
  return llvm::hash_combine(bound.parameter, bound.bytes);
}

ParseResult idr::parsePutBound(AsmParser &parser, PutBound &bound) {
  return failure(parser.parseInteger(bound.parameter) || parser.parseColon() ||
                 parser.parseInteger(bound.bytes));
}

void idr::printPutBound(AsmPrinter &printer, const PutBound &bound) {
  printer << bound.parameter << ": " << bound.bytes;
}

// Positions increase, each once: a parameter has at most one bound, and the
// record is read in one pass beside the parameters.
LogicalResult PutBoundsAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                    ArrayRef<PutBound> bounds) {
  for (auto [before, after] : llvm::zip(bounds, bounds.drop_front()))
    if (before.parameter >= after.parameter)
      return emitError() << "lists put parameter " << after.parameter << " after "
                         << before.parameter << ": positions increase, each once";
  return success();
}

//===----------------------------------------------------------------------===//
// The parameters' parts
//===----------------------------------------------------------------------===//

bool idr::admitsWrite(Type type) {
  std::optional<Hold> hold = holdOf(type);
  return hold && hold->release() == Release::Counted && hold->claims(Unique::Self);
}

bool idr::admitsPut(Type type) { return lifetimes::admitsPuts(type); }

idr::ParameterParts::ParameterParts(TypeRange parameters) {
  parts.reserve(parameters.size());
  for (Type type : parameters) {
    if (admitsWrite(type))
      parts.push_back(WritePart{writes++});
    else if (admitsPut(type))
      parts.push_back(PutPart{puts++});
    else
      parts.push_back(NoPart{});
  }
}

Termination idr::FuncOp::getTermination() {
  TerminatesAttr proof = getTerminatesAttr();
  if (!proof)
    return Unproved{};
  return idr::match(
      proof.getProof(), [](InComponent in) -> Termination { return in; },
      [](Acyclic acyclic) -> Termination { return acyclic; });
}

//===----------------------------------------------------------------------===//
// The fold
//===----------------------------------------------------------------------===//

void rows::copyRow(CallOp call, FuncOp callee) {
  call.setRow(callee.getRow());
  call.setUntouchedAttr(callee.getUntouchedAttr());
}

// A region branch says which of its regions may run again; an op with
// regions that is no region branch says nothing of how often they run, so
// they may run any number of times.
rows::Runs rows::detail::regionRuns(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return branch && !branch.isRepetitiveRegion(index) ? Runs::Once : Runs::Repeatedly;
}

// Idris's proof is the one input of the row that is no op: a function it
// did not prove may run forever by itself.
rows::Fold::Fold(FuncOp fn) : fn(fn), parts(fn.getArgumentTypes()) {
  derived.written.resize(parts.writable());
  derived.puts.assign(parts.puttable(), Amount::finite(0));
  idr::match(
      fn.getTermination(),
      [&](Unproved) { join(effects::Row{effects::Atom::divergence}); }, [](InComponent) {},
      [](Acyclic) {});
}

rows::Declares rows::Fold::declared(Operation *op, Runs runs) {
  join(effects::reportedBy(op));
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op))
    put(putter.getPutLifetime(), Amount::finite(putter.getPutBytes(DataLayout::closest(op))),
        runs);
  auto declaring = dyn_cast<MemoryEffectOpInterface>(op);
  if (!declaring) {
    // An op of another dialect is bounded by its regions alone where it
    // says so; with neither a declaration nor that, it may do anything.
    if (op->hasTrait<OpTrait::HasRecursiveMemoryEffects>())
      return Declares::Bounded;
    anything();
    return Declares::Anything;
  }
  SmallVector<MemoryEffects::EffectInstance, 4> instances;
  declaring.getEffects(instances);
  for (const MemoryEffects::EffectInstance &instance : instances)
    effect(effects::effectOf(instance));
  return Declares::Bounded;
}

// An acquisition is the function's own business only through what it
// acquired: the effect itself is what `alloc` reports. Any other effect on
// memory the function acquired is the function's own. A write in place
// through a write-admitting parameter, what the row would hold as `write`,
// is the record's; anything else done there is the row's.
void rows::Fold::effect(const effects::Effect &effect) {
  effects::Row atoms = effects::project(effect);
  if (!effect.value || effect.kind == effects::EffectKind::Allocate) {
    join(atoms);
    return;
  }
  idr::match(
      landing(effect.value), [](Local) {},
      [&](Through through) {
        if (atoms == effects::Row{effects::Atom::write})
          derived.written.set(through.position);
        else
          join(atoms);
      },
      [&](Elsewhere) { join(atoms); });
}

void rows::Fold::writeThrough(Value value) {
  effect(effects::Effect{
      .kind = effects::EffectKind::Write, .resource = effects::ResourceId::Contents, .value = value});
}

void rows::Fold::put(Value lifetime, Amount amount, Runs runs) {
  if (amount.none())
    return;
  idr::match(
      partOf(lifetime),
      [&](PutPart part) {
        Amount &total = derived.puts[part.position];
        total = total.plus(runs == Runs::Repeatedly ? Amount::unbounded() : amount);
      },
      [](WritePart) {}, [](NoPart) {});
}

RecordPart rows::Fold::partOf(Value value) const {
  auto parameter = dyn_cast<BlockArgument>(value);
  if (!parameter || parameter.getOwner() != &fn.getBody().front())
    return NoPart{};
  return parts[parameter.getArgNumber()];
}

// Through views to the value whose memory they are, then: a parameter's,
// read by its part; or what the op that made it acquired on the heap or in
// the function's frame, the function's own; or anything else. A view's
// source is one hop, and the chain is as long as the views are deep.
rows::Lands rows::Fold::landing(Value value) const {
  while (auto view = value.getDefiningOp<ViewLikeOpInterface>()) {
    if (view.getViewDest() != value)
      break;
    value = view.getViewSource();
  }
  auto acquiredHere = [&] {
    auto made = value.getDefiningOp<MemoryEffectOpInterface>();
    if (!made)
      return false;
    std::optional<MemoryEffects::EffectInstance> acquisition =
        made.getEffectOnValue<MemoryEffects::Allocate>(value);
    if (!acquisition)
      return false;
    effects::ResourceId where = effects::effectOf(*acquisition).resource;
    return where == effects::ResourceId::Heap || where == effects::ResourceId::Frame;
  };
  return idr::match(
      partOf(value), [](WritePart part) -> Lands { return Through{part.position}; },
      [](PutPart) -> Lands { return Elsewhere{}; },
      [&](NoPart) -> Lands {
        if (acquiredHere())
          return Local{};
        return Elsewhere{};
      });
}

void rows::Fold::anything() {
  join(effects::Row::top());
  derived.written.set();
  for (Amount &amount : derived.puts)
    amount = Amount::unbounded();
}

void rows::CallCopies::call(CallOp call, Fold &fold, Runs) {
  fold.join(call.getRow());
  forEachWritten(call, [&](OpOperand &operand) { fold.writeThrough(operand.get()); });
}

template rows::Derived rows::derive<rows::CallCopies>(FuncOp fn, rows::CallCopies &reader);

//===----------------------------------------------------------------------===//
// The function's check
//===----------------------------------------------------------------------===//

namespace {

// The atoms of `row`, as the row prints them.
std::string spell(effects::Row row) {
  std::string text;
  llvm::raw_string_ostream out(text);
  static constexpr auto atoms = allOf<effects::Atom>();
  llvm::interleaveComma(
      llvm::make_filter_range(atoms, [&](effects::Atom atom) { return row.contains(atom); }),
      out, [&](effects::Atom atom) {
        out << EnumTraits<effects::Atom>::names[static_cast<std::size_t>(std::to_underlying(atom))];
      });
  return text;
}

// The first op whose own part of the row holds one of `missing`.
struct Blame {
  effects::Row missing;
  Operation *culprit = nullptr;

  void call(CallOp call, rows::Fold &fold, rows::Runs runs) {
    rows::CallCopies copies;
    copies.call(call, fold, runs);
  }
  rows::Read other(Operation *, rows::Fold &, rows::Runs) { return rows::Read::ByDeclaration; }
  void after(Operation *op, rows::Fold &fold) {
    if (!culprit && !(fold.sofar().atoms & missing).empty())
      culprit = op;
  }
};

// What the function says it puts into each put parameter: its bound, or
// none.
llvm::SmallVector<Amount, 2> declaredPuts(FuncOp fn, std::uint32_t puttable) {
  llvm::SmallVector<Amount, 2> declared(puttable, Amount::unbounded());
  if (PutBoundsAttr bounded = fn.getBoundedAttr())
    for (const PutBound &bound : bounded.getBounds())
      declared[bound.parameter] = Amount::finite(bound.bytes);
  return declared;
}

// The record names only parameters that admit its part, and a room, whose
// block has a static size, has a bound.
LogicalResult recordFits(FuncOp fn, const ParameterParts &parts) {
  if (DenseI32ArrayAttr untouched = fn.getUntouchedAttr();
      untouched && !untouched.empty() &&
      static_cast<std::uint32_t>(untouched.asArrayRef().back()) >= parts.writable())
    return fn.emitOpError("lists parameter ")
           << untouched.asArrayRef().back() << " untouched among its " << parts.writable()
           << " that admit a write part";
  PutBoundsAttr bounded = fn.getBoundedAttr();
  if (bounded && !bounded.getBounds().empty() &&
      bounded.getBounds().back().parameter >= parts.puttable())
    return fn.emitOpError("bounds put parameter ")
           << bounded.getBounds().back().parameter << " among its " << parts.puttable()
           << " that admit an amount";
  llvm::SmallVector<Amount, 2> declared = declaredPuts(fn, parts.puttable());
  for (auto [index, type] : llvm::enumerate(fn.getArgumentTypes())) {
    LogicalResult fits = idr::match(
        parts[static_cast<unsigned>(index)],
        [&](PutPart part) -> LogicalResult {
          if (!lifetimes::isRoom(type) || declared[part.position] != Amount::unbounded())
            return success();
          return fn.emitOpError("puts into its room parameter #")
                 << index << " with no bound, though a room's block has a static size";
        },
        [](WritePart) -> LogicalResult { return success(); },
        [](NoPart) -> LogicalResult { return success(); });
    if (failed(fits))
      return failure();
  }
  return success();
}

} // namespace

// Containment after every pass, equality only right after the writer: a
// pass that deletes an effectful op (a known case folded, a dead read
// erased) leaves a row that says too much, which is sound, and no pass of
// another's can rewrite every caller's copy on the spot.
LogicalResult rows::verify(FuncOp fn) {
  ParameterParts parts(fn.getArgumentTypes());
  if (failed(recordFits(fn, parts)))
    return failure();
  CallCopies copies;
  Derived derived = derive(fn, copies);

  effects::Row row = fn.getRow();
  if (effects::Row missing = derived.atoms - row; !missing.empty()) {
    effects::Row seeded =
        idr::match(
            fn.getTermination(),
            [](Unproved) { return effects::Row{effects::Atom::divergence}; },
            [](InComponent) { return effects::Row{}; }, [](Acyclic) { return effects::Row{}; }) &
        missing;
    if (!seeded.empty())
      return fn.emitOpError("holds effects<")
             << spell(row) << ">, which lack " << spell(seeded)
             << ": Idris did not prove its loops end";
    Blame blame{missing};
    (void)derive(fn, blame);
    InFlightDiagnostic diag = fn.emitOpError("holds effects<")
                              << spell(row) << ">, which lack " << spell(missing);
    if (blame.culprit)
      diag.attachNote(blame.culprit->getLoc())
          << "'" << blame.culprit->getName() << "' needs them";
    return diag;
  }

  if (DenseI32ArrayAttr untouched = fn.getUntouchedAttr())
    for (std::int32_t position : untouched.asArrayRef())
      if (derived.written.test(static_cast<unsigned>(position)))
        return fn.emitOpError("lists its write-admitting parameter ")
               << position << " untouched, which its body writes through";

  llvm::SmallVector<Amount, 2> declared = declaredPuts(fn, parts.puttable());
  for (auto [position, put] : llvm::enumerate(derived.puts))
    if (!put.within(declared[position]))
      return fn.emitOpError("bounds what it puts into its put parameter ")
             << position << ", which its body exceeds";
  return success();
}
