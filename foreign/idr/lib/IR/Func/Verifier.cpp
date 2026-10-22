// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.func's two verifiers. Its op verifier holds what its signature
// states beyond its types (its record, where each scoped value lives and
// the bounds between lifetimes, what it gives back) to that signature: a
// local fact of the op, checked before its body. Its region verifier runs
// the rules of one function, after the ops of its body are verified and in
// parallel with every other function's: its stage's and its row's in its
// one walk, then its tail calls'.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>
#include <cstdint>
#include <variant>

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
