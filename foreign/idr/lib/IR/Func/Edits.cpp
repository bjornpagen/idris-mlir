// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.func's implementations of the function interface's four edits of a
// signature, and their one rule. Upstream's edits keep the type, the
// parameters' and results' attributes and the entry block's arguments.
// What the signature states by position beyond those (where each scoped
// value lives and the bounds between lifetimes, the index term each
// unknown axis is, its untouched and bounded parameters)
// is the function's own, so a caller reaches these through the op or
// through the interface alike, and the single forms through them. Each
// edit says where every old parameter and result goes, and what is stated
// moves there, computed before the signature changes, since the
// parameters' parts are read off their old types. Each builds its new
// type from the function's own function type, which always has the clone
// it asks for, so the type it sets is never null and no edit has a failure
// of its type to answer.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <concepts>
#include <cstdint>
#include <optional>

using namespace mlir;
using namespace idr;

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

// Where each of `count` new positions comes from: the old position `moves`
// sends there, or none for one inserted. An edit sends each old position to
// at most one new one, so each new one has at most one source.
Moves comingFrom(ArrayRef<std::optional<std::uint32_t>> moves, unsigned count) {
  Moves from(count, std::nullopt);
  for (auto [at, to] : llvm::enumerate(moves))
    if (to) {
      assert(!from[*to] && "an edit sends one old position to each new one it fills");
      from[*to] = static_cast<std::uint32_t>(at);
    }
  return from;
}

// A part of the record, which names its parameter by its position among
// the parameters that admit it.
template <class Part>
concept PositionedPart = requires(Part part) {
  { part.position } -> std::convertible_to<std::uint32_t>;
};

// Where a parameter's part puts it among the parameters that admit that
// part; a parameter that admits none has no such place.
std::optional<std::uint32_t> placeOf(const RecordPart &part) {
  return idr::match(
      part,
      [](PositionedPart auto positioned) -> std::optional<std::uint32_t> {
        return positioned.position;
      },
      [](NoPart) -> std::optional<std::uint32_t> { return std::nullopt; });
}

// Each write part's and each put part's position, moved as its parameter
// moves. A parameter kept keeps its type, so it admits the same part, and
// its part in the new signature holds its position among those that admit
// it now.
struct PartMoves {
  Moves writes;
  Moves puts;
};

PartMoves amongThose(const ParameterParts &before, ArrayRef<std::optional<std::uint32_t>> parameters,
                     const ParameterParts &after) {
  PartMoves moves;
  for (auto [at, to] : llvm::enumerate(parameters)) {
    std::optional<std::uint32_t> now = to ? placeOf(after[*to]) : std::nullopt;
    idr::match(
        before[static_cast<unsigned>(at)], [&](WritePart) { moves.writes.push_back(now); },
        [&](PutPart) { moves.puts.push_back(now); }, [](NoPart) {});
  }
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
  ExtentsAttr extents;
  DenseI32ArrayAttr untouched;
  PutBoundsAttr bounded;
};

// The edit `change` makes, the function's type becoming `type`, with what
// `fn` states moved as `parameters` and `results` say. It fails, with
// nothing changed, when a value kept would lose the lifetime it lives in:
// the function cannot have that signature.
template <std::invocable<> Change>
LogicalResult editSignature(FuncOp fn, FunctionType type, ArrayRef<std::optional<std::uint32_t>> parameters,
                            ArrayRef<std::optional<std::uint32_t>> results, Change &&change) {
  MLIRContext *context = fn.getContext();
  Stated stated{};
  if (LivesInAttr lives = fn.getLivesInAttr()) {
    FailureOr<LivesInAttr> renumbered = lives.renumber(parameters, results);
    if (failed(renumbered))
      return failure();
    stated.lives = *renumbered;
  }
  stated.extents = extentsFrom(fn.getExtentsAttr(), comingFrom(parameters, type.getNumInputs()),
                               comingFrom(results, type.getNumResults()));
  PartMoves parts =
      amongThose(ParameterParts(fn.getArgumentTypes()), parameters, ParameterParts(type.getInputs()));
  stated.untouched = moved(context, fn.getUntouchedAttr(), parts.writes);
  stated.bounded = moved(context, fn.getBoundedAttr(), parts.puts);
  change();
  fn.setLivesInAttr(stated.lives);
  fn.setExtentsAttr(stated.extents);
  fn.setUntouchedAttr(stated.untouched);
  fn.setBoundedAttr(stated.bounded);
  return success();
}

} // namespace

LogicalResult idr::FuncOp::insertArguments(ArrayRef<unsigned> indices, TypeRange types,
                                          ArrayRef<DictionaryAttr> attrs, ArrayRef<Location> locs) {
  unsigned count = getNumArguments();
  FunctionType type = getFunctionType().getWithArgsAndResults(indices, types, {}, {});
  return editSignature(*this, type, inserting(count, indices), inserting(getNumResults(), {}), [&] {
    function_interface_impl::insertFunctionArguments(*this, indices, types, attrs, locs, count, type);
  });
}

LogicalResult idr::FuncOp::insertResults(ArrayRef<unsigned> indices, TypeRange types,
                                        ArrayRef<DictionaryAttr> attrs) {
  unsigned count = getNumResults();
  FunctionType type = getFunctionType().getWithArgsAndResults({}, {}, indices, types);
  return editSignature(*this, type, inserting(getNumArguments(), {}), inserting(count, indices), [&] {
    function_interface_impl::insertFunctionResults(*this, indices, types, attrs, count, type);
  });
}

LogicalResult idr::FuncOp::eraseArguments(const llvm::BitVector &arguments) {
  FunctionType type = getFunctionType().getWithoutArgsAndResults(arguments, llvm::BitVector());
  return editSignature(*this, type, erasing(getNumArguments(), arguments), inserting(getNumResults(), {}),
                       [&] { function_interface_impl::eraseFunctionArguments(*this, arguments, type); });
}

LogicalResult idr::FuncOp::eraseResults(const llvm::BitVector &results) {
  FunctionType type = getFunctionType().getWithoutArgsAndResults(llvm::BitVector(), results);
  return editSignature(*this, type, inserting(getNumArguments(), {}), erasing(getNumResults(), results),
                       [&] { function_interface_impl::eraseFunctionResults(*this, results, type); });
}
