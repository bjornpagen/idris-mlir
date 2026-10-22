// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's row and per-parameter record, held to its body: the fold
// every derivation shares, the verifier's instantiation of it, what LLVM is
// told of a function, and the hand values the specification's attributes
// and properties hold (a row, a termination proof, a put bound) with the
// parameter view their positions are read through.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <string>
#include <utility>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The row, as the IR holds it
//===----------------------------------------------------------------------===//

namespace {

// An atom's printed name, from the effect system's generated table.
StringRef nameOf(effects::Atom atom) {
  return EnumTraits<effects::Atom>::names[static_cast<std::size_t>(std::to_underlying(atom))];
}

// The atoms a row holds, in their order.
auto atomsOf(effects::Row row) {
  static constexpr auto every = allOf<effects::Atom>();
  return llvm::make_filter_range(every, [row](effects::Atom atom) { return row.contains(atom); });
}

} // namespace

Attribute idr::convertRowToAttribute(MLIRContext *context, effects::Row row) {
  SmallVector<Attribute> names;
  for (effects::Atom atom : atomsOf(row))
    names.push_back(StringAttr::get(context, nameOf(atom)));
  return ArrayAttr::get(context, names);
}

// Text read at the boundary: each name is matched once against the
// table's, and the row holds the atoms from there on.
LogicalResult idr::convertRowFromAttribute(effects::Row &row, Attribute attribute,
                                           function_ref<InFlightDiagnostic()> emitError) {
  auto names = dyn_cast<ArrayAttr>(attribute);
  if (!names)
    return emitError() << "expected a row, the list of its atoms' names";
  static constexpr auto every = allOf<effects::Atom>();
  effects::Row read;
  for (Attribute name : names) {
    auto text = dyn_cast<StringAttr>(name);
    auto atom =
        text ? llvm::find_if(every,
                             [&](effects::Atom candidate) { return nameOf(candidate) == text.getValue(); })
             : every.end();
    if (atom == every.end())
      return emitError() << name << " is no atom of a row";
    read = read | effects::Row{*atom};
  }
  row = read;
  return success();
}

llvm::hash_code idr::hashRow(effects::Row row) {
  SmallVector<unsigned> numbers;
  for (effects::Atom atom : atomsOf(row))
    numbers.push_back(static_cast<unsigned>(std::to_underlying(atom)));
  return llvm::hash_combine_range(numbers);
}

void idr::writeRow(DialectBytecodeWriter &writer, effects::Row row) {
  writer.writeVarInt(row.size());
  for (effects::Atom atom : atomsOf(row))
    writer.writeVarInt(static_cast<std::uint64_t>(std::to_underlying(atom)));
}

LogicalResult idr::readRow(DialectBytecodeReader &reader, effects::Row &row) {
  std::uint64_t count = 0;
  if (failed(reader.readVarInt(count)))
    return failure();
  effects::Row read;
  for (std::uint64_t at = 0; at < count; ++at) {
    std::uint64_t number = 0;
    if (failed(reader.readVarInt(number)))
      return failure();
    if (number >= EnumTraits<effects::Atom>::count)
      return reader.emitError() << "atom " << number << " is no atom of a row";
    read = read | effects::Row{static_cast<effects::Atom>(number)};
  }
  row = read;
  return success();
}

//===----------------------------------------------------------------------===//
// Termination proofs and put bounds
//===----------------------------------------------------------------------===//

llvm::hash_code idr::hash_value(const TerminationProof &proof) {
  return idr::match(
      proof, [](InComponent in) { return llvm::hash_combine(0u, in.component); },
      [](Acyclic) { return llvm::hash_combine(1u); });
}

FailureOr<TerminationProof> idr::parseTerminationProof(AsmParser &parser) {
  if (succeeded(parser.parseOptionalKeyword("acyclic")))
    return TerminationProof(Acyclic{});
  std::uint32_t component = 0;
  if (parser.parseKeyword("component") || parser.parseInteger(component))
    return failure();
  return TerminationProof(InComponent{component});
}

void idr::printTerminationProof(AsmPrinter &printer, TerminationProof proof) {
  idr::match(
      proof, [&](InComponent in) { printer << "component " << in.component; },
      [&](Acyclic) { printer << "acyclic"; });
}

// In bytecode: zero for acyclic, else the component plus one.
LogicalResult idr::readTerminationProof(DialectBytecodeReader &reader, TerminationProof &proof) {
  std::uint64_t word = 0;
  if (failed(reader.readVarInt(word)))
    return failure();
  if (word == 0) {
    proof = Acyclic{};
    return success();
  }
  if (word - 1 > std::numeric_limits<std::uint32_t>::max())
    return reader.emitError() << "termination component " << (word - 1) << " out of range";
  proof = InComponent{static_cast<std::uint32_t>(word - 1)};
  return success();
}

void idr::writeTerminationProof(DialectBytecodeWriter &writer, TerminationProof proof) {
  idr::match(
      proof, [&](InComponent in) { writer.writeVarInt(std::uint64_t{in.component} + 1); },
      [&](Acyclic) { writer.writeVarInt(0); });
}

Termination idr::FuncOp::getTermination() {
  TerminatesAttr proof = getTerminatesAttr();
  if (!proof)
    return Unproved{};
  return idr::match(
      proof.getProof(), [](InComponent in) -> Termination { return in; },
      [](Acyclic acyclic) -> Termination { return acyclic; });
}

llvm::hash_code idr::hash_value(const PutBound &bound) {
  return llvm::hash_combine(bound.parameter, bound.bytes);
}

LogicalResult idr::readPutBound(DialectBytecodeReader &reader, PutBound &bound) {
  std::uint64_t parameter = 0;
  if (failed(reader.readVarInt(parameter)) || failed(reader.readVarInt(bound.bytes)))
    return failure();
  if (parameter > std::numeric_limits<std::uint32_t>::max())
    return reader.emitError() << "put parameter " << parameter << " out of range";
  bound.parameter = static_cast<std::uint32_t>(parameter);
  return success();
}

void idr::writePutBound(DialectBytecodeWriter &writer, const PutBound &bound) {
  writer.writeVarInt(bound.parameter);
  writer.writeVarInt(bound.bytes);
}

// `<[0: 64, 2: 128]>`.
Attribute PutBoundsAttr::parse(AsmParser &parser, Type) {
  SmallVector<PutBound> bounds;
  auto one = [&]() -> ParseResult {
    PutBound bound{};
    if (parser.parseInteger(bound.parameter) || parser.parseColon() ||
        parser.parseInteger(bound.bytes))
      return failure();
    bounds.push_back(bound);
    return success();
  };
  if (parser.parseLess() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one) || parser.parseGreater())
    return {};
  return PutBoundsAttr::getChecked([&] { return parser.emitError(parser.getNameLoc()); },
                                   parser.getContext(), bounds);
}

void PutBoundsAttr::print(AsmPrinter &printer) const {
  printer << "<[";
  llvm::interleaveComma(getBounds(), printer, [&](const PutBound &bound) {
    printer << bound.parameter << ": " << bound.bytes;
  });
  printer << "]>";
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

idr::ParameterParts::ParameterParts(TypeRange parameters) {
  parts.reserve(parameters.size());
  for (Type type : parameters) {
    if (admitsWrite(type))
      parts.push_back(WritePart{writes++});
    else if (admitsPuts(type))
      parts.push_back(PutPart{puts++});
    else
      parts.push_back(NoPart{});
  }
}

//===----------------------------------------------------------------------===//
// What LLVM is told
//===----------------------------------------------------------------------===//

// A write through a parameter is argument memory written, which the row's
// atoms do not hold: the record says it wherever it lists fewer untouched
// parameters than admit a write part.
effects::Told rows::told(FuncOp fn) {
  effects::Told facts = effects::told(fn.getRow());
  std::size_t untouched = 0;
  if (DenseI32ArrayAttr listed = fn.getUntouchedAttr())
    untouched = listed.size();
  if (ParameterParts(fn.getArgumentTypes()).writable() > untouched)
    facts = effects::withParameterWrite(facts);
  return facts;
}

//===----------------------------------------------------------------------===//
// The fold
//===----------------------------------------------------------------------===//

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

const Layouts &rows::Fold::layouts() {
  if (!laidOut)
    laidOut.emplace(fn.getOperation());
  return *laidOut;
}

void rows::Fold::declared(Operation *op, Runs runs) {
  join(effects::reportedBy(op));
  // Only a put into a put parameter is the record's, and one in a region
  // that runs again has no bound whatever its size: the bytes are read
  // only for a put once per run into a put parameter.
  if (auto putter = dyn_cast<LifetimePutOpInterface>(op)) {
    Value lifetime = putter.getPutLifetime();
    if (std::holds_alternative<PutPart>(partOf(lifetime)))
      put(lifetime,
          runs == Runs::Repeatedly ? Amount::unbounded()
                                   : Amount::finite(putter.getPutBytes(layouts())),
          runs);
  }
  auto declaring = dyn_cast<MemoryEffectOpInterface>(op);
  if (!declaring) {
    // An op of another dialect is bounded by its regions alone where it
    // says so; with neither a declaration nor that, it may do anything.
    if (!op->hasTrait<OpTrait::HasRecursiveMemoryEffects>())
      anything();
    return;
  }
  SmallVector<MemoryEffects::EffectInstance, 4> instances;
  declaring.getEffects(instances);
  for (const MemoryEffects::EffectInstance &instance : instances)
    effect(effects::effectOf(instance));
}

// An acquisition is the function's own business only through what it
// acquired: the effect itself is what `alloc` reports. Any other effect on
// memory the function acquired is the function's own. A write in place
// through a write-admitting parameter, what the row would hold as `write`,
// is the record's; anything else done there is the row's.
void rows::Fold::effect(const effects::Effect &effect) {
  effects::Row atoms = effects::project(effect);
  if (!effect.value || effect.kind == effects::Kind::Allocate) {
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
      .kind = effects::Kind::Write, .resource = effects::ResourceId::Contents, .value = value});
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
  call.forEachWritten([&](OpOperand &operand) { fold.writeThrough(operand.get()); });
}

template class rows::Derivation<rows::CallCopies>;

//===----------------------------------------------------------------------===//
// The function's check
//===----------------------------------------------------------------------===//

namespace {

// The atoms of `row`, as the row prints them.
std::string spell(effects::Row row) {
  std::string text;
  llvm::raw_string_ostream out(text);
  llvm::interleaveComma(atomsOf(row), out, [&](effects::Atom atom) { out << nameOf(atom); });
  return text;
}

// What the function says it puts into each put parameter: its bound, or
// none.
llvm::SmallVector<Amount, 2> declaredPuts(FuncOp fn) {
  llvm::SmallVector<Amount, 2> declared(ParameterParts(fn.getArgumentTypes()).puttable(),
                                        Amount::unbounded());
  if (PutBoundsAttr bounded = fn.getBoundedAttr())
    for (const PutBound &bound : bounded.getBounds())
      declared[bound.parameter] = Amount::finite(bound.bytes);
  return declared;
}

} // namespace

rows::Check::Check(FuncOp fn)
    : fn(fn), derivation(fn, copies), row(fn.getRow()), bounds(declaredPuts(fn)) {
  if (DenseI32ArrayAttr listed = fn.getUntouchedAttr())
    untouched = listed.asArrayRef();
}

// Idris's proof is read before the body: the row of a function it did not
// prove holds divergence before any op adds to it.
LogicalResult rows::Check::enter(Operation *op, Region &region) {
  (void)derivation.enter(op, region);
  if (op != fn.getOperation())
    return success();
  if (effects::Row missing = derivation.state().sofar().atoms - row; !missing.empty())
    return fn.emitOpError("holds effects<")
           << spell(row) << ">, which lack " << spell(missing)
           << ": Idris did not prove its loops end";
  return success();
}

LogicalResult rows::Check::check(Operation *op) {
  (void)derivation.check(op);
  return covered(*op);
}

// The atoms, writes and amounts only grow as the walk goes on, so the
// first op after which one exceeds what the function says is the op that
// needs it.
LogicalResult rows::Check::covered(Operation &by) {
  const Derived &sofar = derivation.state().sofar();
  auto blame = [&](InFlightDiagnostic diag) -> LogicalResult {
    diag.attachNote(by.getLoc()) << "'" << by.getName() << "' needs it";
    return diag;
  };
  if (effects::Row missing = sofar.atoms - row; !missing.empty())
    return blame(fn.emitOpError("holds effects<") << spell(row) << ">, which lack "
                                                  << spell(missing));
  for (std::int32_t position : untouched)
    if (sofar.written.test(static_cast<unsigned>(position)))
      return blame(fn.emitOpError("lists its write-admitting parameter ")
                   << position << " untouched, which its body writes through");
  for (auto [position, put] : llvm::enumerate(sofar.puts))
    if (!put.within(bounds[position]))
      return blame(fn.emitOpError("bounds what it puts into its put parameter ")
                   << position << ", which its body exceeds");
  return success();
}
