// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.program and idr.func: the closed program, whose root is its property
// and whose region verifier checks the root and runs the program's rules;
// a function's text, its row before its symbol and no visibility written,
// since its program's root decides it; what its signature states beyond
// its types, held to that signature by its own verifier, and moved with
// the positions by every edit of its signature, whoever makes it; the
// lifetimes it states for its parameters;
// and the rules of one function, which run after the ops of its body are
// verified and in parallel with every other function's: its stage's and
// its row's in its one walk, then its tail calls'.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/TypeUtilities.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <variant>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// idr.program
//===----------------------------------------------------------------------===//

void idr::ProgramOp::build(OpBuilder &builder, OperationState &state, StringRef name,
                           StringRef root, Stage stage) {
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.sym_name = builder.getStringAttr(name);
  properties.root = FlatSymbolRefAttr::get(builder.getContext(), root);
  properties.stage = stage;
  state.addRegion()->emplaceBlock();
}

// A module holds one program, the closed world every pass reads: the first
// in its module's block, and none after it. Only that block's ops are
// read, which no pass on a program changes.
LogicalResult idr::ProgramOp::verify() {
  ProgramOp first = *(*this)->getBlock()->getOps<ProgramOp>().begin();
  if (first != *this)
    return emitOpError("@") << getSymName() << " is a second program beside @"
                            << first.getSymName() << ", and a module holds one program";
  return success();
}

FuncOp idr::ProgramOp::lookupRoot() {
  return dyn_cast_or_null<FuncOp>(
      mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr()));
}

// A program is the whole of what runs: nothing outside it discards it.
SymbolTable::Visibility idr::ProgramOp::getVisibility() { return SymbolTable::Visibility::Public; }
void idr::ProgramOp::setVisibility(SymbolTable::Visibility) {}

// The root, checked once: a function of the program that takes nothing.
// Before the program is lowered it is an idr.func whose every result holds
// no runtime value (a unit, an IO result of a unit); lowered, upstream's
// function, which gives nothing back. Which kind of function a stage holds
// is each op's legal stages, not this rule's: the root is whichever is
// there. Then the program's rules. MLIR runs this after every op of the
// program is verified and, by the program's symbol table, every call's
// symbol uses; on one thread; when the module is read and after every pass
// on the program, so a program pass that breaks a rule fails where it
// breaks it.
LogicalResult idr::ProgramOp::verifyRegions() {
  Operation *root = mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr());
  auto function = dyn_cast_or_null<FunctionOpInterface>(root);
  if (!function)
    return emitOpError("has root ") << getRootAttr() << ", which is no function of the program";
  if (!function.getArgumentTypes().empty())
    return root->emitOpError("is the root, so it takes nothing; it takes ")
           << function.getArgumentTypes().size() << " arguments";
  if (isa<FuncOp>(root)) {
    if (!llvm::all_of(function.getResultTypes(),
                      [](Type result) { return layout::holdsNoComponent(result); }))
      return root->emitOpError("is the root, so its results hold no runtime value");
  } else if (!function.getResultTypes().empty()) {
    return root->emitOpError("is the root of a lowered program, so it gives nothing back");
  }
  return verify::program(*this);
}

//===----------------------------------------------------------------------===//
// idr.func
//===----------------------------------------------------------------------===//

ProgramOp idr::FuncOp::getProgram() { return cast<ProgramOp>((*this)->getParentOp()); }

bool idr::FuncOp::isRoot() {
  auto program = dyn_cast_or_null<ProgramOp>((*this)->getParentOp());
  return program && program.getRootAttr() &&
         program.getRootAttr().getAttr() == getSymNameAttr();
}

// Symbol's visibility, read off the program's root: public for the root,
// private for every other function. isPublic, isPrivate and
// canDiscardOnUseEmpty all ask this. Setting it changes nothing: the root
// is the program's to name.
SymbolTable::Visibility idr::FuncOp::getVisibility() {
  return isRoot() ? SymbolTable::Visibility::Public : SymbolTable::Visibility::Private;
}
void idr::FuncOp::setVisibility(SymbolTable::Visibility) {}

StringRef idr::FuncOp::getDefaultDialect() { return IdrDialect::getDialectNamespace(); }

Region *idr::FuncOp::getCallableRegion() { return &getBody(); }
ArrayRef<Type> idr::FuncOp::getArgumentTypes() { return getFunctionType().getInputs(); }
ArrayRef<Type> idr::FuncOp::getResultTypes() { return getFunctionType().getResults(); }
Type idr::FuncOp::cloneTypeWith(TypeRange inputs, TypeRange results) {
  return FunctionType::get(getContext(), inputs, results);
}
// Every function of the program is defined in it, its body the one block
// its region holds.
bool idr::FuncOp::isExternal() { return false; }

// The function's body binds its index binders; nothing else of it binds.
ArrayRef<families::Sort> idr::FuncOp::getBoundSorts(Region &) {
  if (IndexBindersAttr binders = getBindersAttr())
    return binders.getSorts();
  return {};
}

namespace {

// The facts the function's text writes before its symbol, as properties
// (`<{row = ...}>`): every inherent attribute the function's own syntax
// writes stays there (its symbol, its type, its parameters' and results'
// attributes in the signature; the rest in `attributes`).
SmallVector<StringRef> writtenElsewhere(OperationName name) {
  return {FuncOp::getSymNameAttrName(name), FuncOp::getFunctionTypeAttrName(name),
          FuncOp::getArgAttrsAttrName(name),  FuncOp::getResAttrsAttrName(name),
          FuncOp::getBindersAttrName(name),   FuncOp::getUntouchedAttrName(name),
          FuncOp::getBoundedAttrName(name),   FuncOp::getTerminatesAttrName(name),
          FuncOp::getLivesInAttrName(name),   FuncOp::getGivenBackAttrName(name),
          FuncOp::getCopyAttrName(name)};
}

} // namespace

// func.func's syntax without its visibility, which the program's root
// decides, and with its row before its symbol, `idr.func <{row = ...}>
// @f(...)`, written only when it is not every atom. Then the body's ops
// without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  if (parseProperties(parser, result))
    return failure();
  auto buildFuncType = [](Builder &builder, ArrayRef<Type> inputs, ArrayRef<Type> results,
                          function_interface_impl::VariadicFlag, std::string &) {
    return FunctionType::get(builder.getContext(), inputs, results);
  };
  SMLoc loc = parser.getCurrentLocation();
  if (failed(function_interface_impl::parseFunctionOp(
          parser, result, /*allowVariadic=*/false, getFunctionTypeAttrName(result.name),
          buildFuncType, getArgAttrsAttrName(result.name), getResAttrsAttrName(result.name))))
    return failure();
  if (result.attributes.get(SymbolOpInterface::getDefaultVisibilityAttrName()))
    return parser.emitError(loc, "a function's visibility is not written: its program's root is "
                                 "public, and every other function private");
  // The facts arrive in `result.attributes` and become properties when
  // the op is created, which silently drops one of the wrong kind; the
  // generic parser checks them first, and a custom one must too.
  return verifyInherentAttrs(result.name, result.attributes, [&]() {
    return mlir::emitError(result.location) << "'" << result.name.getStringRef() << "' op ";
  });
}

void idr::FuncOp::print(OpAsmPrinter &printer) {
  printer << ' ';
  printProperties(getContext(), printer, getProperties(), writtenElsewhere(getOperation()->getName()));
  function_interface_impl::printFunctionOp(printer, *this, /*isVariadic=*/false,
                                           getFunctionTypeAttrName(), getArgAttrsAttrName(),
                                           getResAttrsAttrName());
}

namespace {

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
  ArrayRef<PutBound> bounds = bounded ? bounded.getBounds() : ArrayRef<PutBound>();
  if (!bounds.empty() && bounds.back().parameter >= parts.puttable())
    return fn.emitOpError("bounds put parameter ")
           << bounds.back().parameter << " among its " << parts.puttable()
           << " that admit an amount";
  for (auto [index, type] : llvm::enumerate(fn.getArgumentTypes())) {
    auto put = std::get_if<PutPart>(&parts[static_cast<unsigned>(index)]);
    if (!put || !isRoomLifetime(type))
      continue;
    if (!llvm::any_of(bounds, [&](const PutBound &bound) { return bound.parameter == put->position; }))
      return fn.emitOpError("puts into its room parameter #")
             << index << " with no bound, though a room's block has a static size";
  }
  return success();
}

// Each entry of `entries` states a lifetime for a scoped value of `types`,
// a lifetime parameter of `parameters`; every scoped value of `types` has
// one. The entries increase by position, so counting the scoped values is
// enough for every one to be listed.
LogicalResult livesInFits(FuncOp fn, ArrayRef<LivesIn> entries, TypeRange types,
                          ArrayRef<Type> parameters, StringRef what) {
  for (const LivesIn &entry : entries) {
    if (entry.value >= types.size() || !freedBy(types[entry.value], Release::Scoped))
      return fn.emitOpError("states a lifetime for ")
             << what << " " << entry.value << ", which is no scoped " << what << " of it";
    if (entry.lifetime >= parameters.size() || !isa<LifetimeType>(parameters[entry.lifetime]))
      return fn.emitOpError("states that its ")
             << what << " " << entry.value << " lives in parameter " << entry.lifetime
             << ", which is no lifetime parameter of it";
  }
  auto scoped = static_cast<std::size_t>(
      llvm::count_if(types, [](Type type) { return freedBy(type, Release::Scoped); }));
  if (entries.size() != scoped)
    return fn.emitOpError("has ") << scoped << " scoped " << what
                                  << "s but states where only " << entries.size() << " live";
  return success();
}

// Where each scoped parameter and result lives names what the signature
// has, and so does each bound.
LogicalResult signatureFits(FuncOp fn) {
  ArrayRef<Type> parameters = fn.getArgumentTypes();
  LivesInAttr lives = fn.getLivesInAttr();
  ArrayRef<LivesIn> scopedParameters = lives ? lives.getParameters() : ArrayRef<LivesIn>();
  ArrayRef<LivesIn> scopedResults = lives ? lives.getResults() : ArrayRef<LivesIn>();
  if (failed(livesInFits(fn, scopedParameters, parameters, parameters, "parameter")) ||
      failed(livesInFits(fn, scopedResults, fn.getResultTypes(), parameters, "result")))
    return failure();
  if (lives)
    for (const Outlives &bound : lives.getBounds())
      for (std::uint32_t named : {bound.longer, bound.shorter})
        if (named >= parameters.size() || !isa<LifetimeType>(parameters[named]))
          return fn.emitOpError("bounds parameter ") << named << ", which is no lifetime parameter";
  return success();
}

// What the function gives back names its results and its parameters.
LogicalResult givenBackFits(FuncOp fn) {
  GivenBackAttr given = fn.getGivenBackAttr();
  if (!given)
    return success();
  for (GivenBackEntryAttr entry : given.getEntries())
    if (entry.getResult() >= fn.getResultTypes().size() ||
        entry.getArgument() >= fn.getArgumentTypes().size())
      return fn.emitOpError("gives back argument ")
             << entry.getArgument() << " as result " << entry.getResult()
             << ", which its signature does not have";
  return success();
}

} // namespace

// What the function's attributes say of its signature names what the
// signature has: a local fact of the op, checked before its body, so the
// derivation reads the record by position with no bound to test.
LogicalResult idr::FuncOp::verify() {
  if (failed(recordFits(*this, ParameterParts(getArgumentTypes()))) ||
      failed(signatureFits(*this)))
    return failure();
  return givenBackFits(*this);
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. Then the function's rules at its program's stage, read in its
// one walk, its row's among them, and its tail calls, each where it
// stands.
LogicalResult idr::FuncOp::verifyRegions() {
  if (failed(verify::function(*this)))
    return failure();
  return tail::verify(*this);
}

//===----------------------------------------------------------------------===//
// Editing the signature
//===----------------------------------------------------------------------===//

// Upstream's edits keep the type, the parameters' and results' attributes
// and the entry block's arguments. What the signature states by position
// beyond those (where each scoped value lives and the bounds between
// lifetimes, what it gives back, its untouched and bounded parameters) is
// the function's own, so these are its implementations of the function
// interface's four edits, which a caller reaches through the op or through
// the interface alike, and the single forms through them. One rule for the
// four: each says where every old parameter and result goes, and what is
// stated moves there, computed before the signature changes, since the
// parameters' parts are read off their old types.

namespace {

// Where each old position of a list goes: its new position, or none for
// one erased.
using Moves = SmallVector<std::optional<std::uint32_t>>;

// Each of `count` positions with those `erased` marks gone: down past every
// one erased before it.
Moves erasing(unsigned count, const llvm::BitVector &erased) {
  Moves moves;
  std::uint32_t kept = 0;
  for (unsigned at = 0; at < count; ++at)
    moves.push_back(erased[at] ? std::nullopt : std::optional<std::uint32_t>(kept++));
  return moves;
}

// Each of `count` positions with new ones inserted before the old positions
// `indices` lists, in increasing order: up past every one inserted at or
// before it. Inserting none moves nothing.
Moves inserting(unsigned count, ArrayRef<unsigned> indices) {
  Moves moves;
  const unsigned *next = indices.begin();
  for (unsigned at = 0; at < count; ++at) {
    while (next != indices.end() && *next <= at)
      ++next;
    moves.push_back(at + static_cast<std::uint32_t>(next - indices.begin()));
  }
  return moves;
}

// A part of the record, which names its parameter by its position among
// the parameters that admit it.
template <class Part>
concept PositionedPart = requires(Part part) {
  { part.position } -> std::convertible_to<std::uint32_t>;
};

// Each position among the parameters that admit `Part`, moved as its
// parameter moves. A parameter kept keeps its type, so it admits the same
// part, at the count of those that admit it before it now.
template <PositionedPart Part>
Moves amongThose(const ParameterParts &before, ArrayRef<std::optional<std::uint32_t>> parameters,
                 const ParameterParts &after) {
  SmallVector<std::uint32_t> counted;
  std::uint32_t seen = 0;
  for (unsigned at = 0; at < after.size(); ++at) {
    counted.push_back(seen);
    if (std::holds_alternative<Part>(after[at]))
      ++seen;
  }
  Moves moves;
  for (auto [at, to] : llvm::enumerate(parameters))
    if (std::holds_alternative<Part>(before[static_cast<unsigned>(at)]))
      moves.push_back(to ? std::optional<std::uint32_t>(counted[*to]) : std::nullopt);
  return moves;
}

// The untouched parameters at their new positions among those that admit
// a write part, one erased gone; none left is none known, as when absent.
DenseI32ArrayAttr moved(MLIRContext *context, DenseI32ArrayAttr untouched,
                        ArrayRef<std::optional<std::uint32_t>> writes) {
  if (!untouched)
    return {};
  SmallVector<std::int32_t> kept;
  for (std::int32_t position : untouched.asArrayRef())
    if (std::optional<std::uint32_t> at = writes[static_cast<unsigned>(position)])
      kept.push_back(static_cast<std::int32_t>(*at));
  return kept.empty() ? DenseI32ArrayAttr() : DenseI32ArrayAttr::get(context, kept);
}

// The bounded put parameters at their new positions among the put
// parameters, one erased gone; none left, absent.
PutBoundsAttr moved(MLIRContext *context, PutBoundsAttr bounded,
                    ArrayRef<std::optional<std::uint32_t>> puts) {
  if (!bounded)
    return {};
  SmallVector<PutBound> kept;
  for (const PutBound &bound : bounded.getBounds())
    if (std::optional<std::uint32_t> at = puts[bound.parameter])
      kept.push_back({*at, bound.bytes});
  return kept.empty() ? PutBoundsAttr() : PutBoundsAttr::get(context, kept);
}

// What the signature states by position, at the positions an edit moves
// each to.
struct Stated {
  LivesInAttr lives;
  GivenBackAttr given;
  DenseI32ArrayAttr untouched;
  PutBoundsAttr bounded;
};

// The edit `change` makes, its parameters becoming `inputs`, with what `fn`
// states moved as `parameters` and `results` say. It fails, with nothing
// changed, when a value kept would lose the lifetime it lives in: the
// function cannot have that signature.
template <std::invocable<> Change>
LogicalResult editSignature(FuncOp fn, TypeRange inputs, ArrayRef<std::optional<std::uint32_t>> parameters,
                            ArrayRef<std::optional<std::uint32_t>> results, Change &&change) {
  MLIRContext *context = fn.getContext();
  Stated stated{};
  if (LivesInAttr lives = fn.getLivesInAttr()) {
    FailureOr<LivesInAttr> renumbered = lives.renumber(parameters, results);
    if (failed(renumbered))
      return failure();
    stated.lives = *renumbered;
  }
  if (GivenBackAttr given = fn.getGivenBackAttr())
    stated.given = given.renumber(parameters, results);
  ParameterParts before(fn.getArgumentTypes()), after(inputs);
  stated.untouched =
      moved(context, fn.getUntouchedAttr(), amongThose<WritePart>(before, parameters, after));
  stated.bounded = moved(context, fn.getBoundedAttr(), amongThose<PutPart>(before, parameters, after));
  change();
  fn.setLivesInAttr(stated.lives);
  fn.setGivenBackAttr(stated.given);
  fn.setUntouchedAttr(stated.untouched);
  fn.setBoundedAttr(stated.bounded);
  return success();
}

} // namespace

LogicalResult idr::FuncOp::insertArguments(ArrayRef<unsigned> indices, TypeRange types,
                                          ArrayRef<DictionaryAttr> attrs, ArrayRef<Location> locs) {
  unsigned count = getNumArguments();
  SmallVector<Type> storage;
  TypeRange inputs = insertTypesInto(getArgumentTypes(), indices, types, storage);
  Type type = cloneTypeWith(inputs, getResultTypes());
  return editSignature(*this, inputs, inserting(count, indices), inserting(getNumResults(), {}), [&] {
    function_interface_impl::insertFunctionArguments(*this, indices, types, attrs, locs, count, type);
  });
}

LogicalResult idr::FuncOp::insertResults(ArrayRef<unsigned> indices, TypeRange types,
                                        ArrayRef<DictionaryAttr> attrs) {
  unsigned count = getNumResults();
  SmallVector<Type> storage;
  TypeRange outputs = insertTypesInto(getResultTypes(), indices, types, storage);
  Type type = cloneTypeWith(getArgumentTypes(), outputs);
  return editSignature(*this, getArgumentTypes(), inserting(getNumArguments(), {}),
                       inserting(count, indices), [&] {
                         function_interface_impl::insertFunctionResults(*this, indices, types, attrs,
                                                                        count, type);
                       });
}

LogicalResult idr::FuncOp::eraseArguments(const llvm::BitVector &arguments) {
  SmallVector<Type> storage;
  TypeRange inputs = filterTypesOut(getArgumentTypes(), arguments, storage);
  Type type = cloneTypeWith(inputs, getResultTypes());
  return editSignature(*this, inputs, erasing(getNumArguments(), arguments),
                       inserting(getNumResults(), {}),
                       [&] { function_interface_impl::eraseFunctionArguments(*this, arguments, type); });
}

LogicalResult idr::FuncOp::eraseResults(const llvm::BitVector &results) {
  SmallVector<Type> storage;
  TypeRange outputs = filterTypesOut(getResultTypes(), results, storage);
  Type type = cloneTypeWith(getArgumentTypes(), outputs);
  return editSignature(*this, getArgumentTypes(), inserting(getNumArguments(), {}),
                       erasing(getNumResults(), results),
                       [&] { function_interface_impl::eraseFunctionResults(*this, results, type); });
}

//===----------------------------------------------------------------------===//
// The lifetimes a function states
//===----------------------------------------------------------------------===//

// A scoped parameter lives in the lifetime parameter its signature names,
// one search away; nothing else of the function is stated here.
Value idr::FuncOp::getStatedLifetime(Value made) {
  auto parameter = dyn_cast<BlockArgument>(made);
  LivesInAttr lives = getLivesInAttr();
  if (!parameter || !lives || parameter.getOwner() != &getBody().front())
    return nullptr;
  std::optional<std::uint32_t> lifetime = lives.lifetimeOfParameter(parameter.getArgNumber());
  return lifetime ? getBody().front().getArgument(*lifetime) : Value();
}

// A function states a parameter's lifetime only as one of its own
// parameters; given null, as a copy whose parameter is no longer scoped is
// restated, or anything else, it states none, and its verifier names a
// scoped parameter left without one. One entry per parameter, so stating
// it again replaces it.
void idr::FuncOp::setStatedLifetime(Value made, Value lifetime) {
  Block &entry = getBody().front();
  auto parameter = dyn_cast<BlockArgument>(made);
  if (!parameter || parameter.getOwner() != &entry)
    return;
  auto in = dyn_cast_or_null<BlockArgument>(lifetime);
  std::optional<std::uint32_t> stated;
  if (in && in.getOwner() == &entry)
    stated = in.getArgNumber();
  setLivesInAttr(LivesInAttr::restateParameter(getContext(), getLivesInAttr(),
                                               parameter.getArgNumber(), stated));
}
