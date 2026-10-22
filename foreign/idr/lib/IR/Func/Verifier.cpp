// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.func's two verifiers. Its op verifier holds what its signature
// states beyond its types (its record, where each scoped value lives and
// the bounds between lifetimes, what it gives back, the index term each
// unknown axis is) to that signature and its binders: a local fact of the
// op, checked before its body. Its region verifier runs the rules of one
// function, after the ops of its body are verified and in parallel with
// every other function's: its stage's and its row's in its one walk, then
// its tail calls'.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>
#include <cstdint>

using namespace mlir;
using namespace idr;

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
    LogicalResult fits = idr::match(
        parts[static_cast<unsigned>(index)],
        [&](PutPart put) -> LogicalResult {
          if (!isRoomLifetime(type) ||
              llvm::any_of(bounds, [&](const PutBound &bound) { return bound.parameter == put.position; }))
            return success();
          return fn.emitOpError("puts into its room parameter #")
                 << index << " with no bound, though a room's block has a static size";
        },
        [](WritePart) { return success(); }, [](NoPart) { return success(); });
    if (failed(fits))
      return failure();
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

// Each extent names an axis its signature's type leaves `?`, by a term over
// the function's own binders. The attributes hold the rest themselves: the
// entries' order, and each term whole and naming a binder. The value's
// shape is a ranked tensor, or the buffer bufferization makes of it with
// the same axes, which upstream's function bufferization sets as the
// signature's type with no edit of it: the entry names the same axis of
// either.
LogicalResult extentsFit(FuncOp fn) {
  ExtentsAttr extents = fn.getExtentsAttr();
  if (!extents)
    return success();
  std::size_t binders = fn.getBoundSorts(fn.getBody()).size();
  for (ExtentAttr attr : extents.getEntries()) {
    Extent entry = attr.extent();
    ArrayRef<Type> values = onSide(entry.at.side, fn.getArgumentTypes(), fn.getResultTypes());
    StringRef side = stringifyExtentSide(entry.at.side);
    if (entry.at.position >= values.size())
      return fn.emitOpError("names an axis of ")
             << side << " " << entry.at.position << ", which its signature does not have";
    auto shape = dyn_cast<ShapedType>(unrestricted(values[entry.at.position]));
    if (!shape || !shape.hasRank() || entry.at.axis >= shape.getRank() ||
        !shape.isDynamicDim(entry.at.axis))
      return fn.emitOpError("names axis ")
             << entry.at.axis << " of " << side << " " << entry.at.position
             << ", which is no unknown axis of a ranked shape";
    if (entry.term.freeLevels() > binders)
      return fn.emitOpError("names axis ")
             << entry.at.axis << " of " << side << " " << entry.at.position << " by binder v"
             << entry.term.freeLevels() - 1 << ", though it binds " << binders;
  }
  return success();
}

} // namespace

// What the function's attributes say of its signature names what the
// signature has, and its extents' terms what it binds: a local fact of the
// op, checked before its body, so the derivation reads the record by
// position with no bound to test.
LogicalResult idr::FuncOp::verify() {
  if (failed(recordFits(*this, ParameterParts(getArgumentTypes()))) ||
      failed(signatureFits(*this)) || failed(givenBackFits(*this)))
    return failure();
  return extentsFit(*this);
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
