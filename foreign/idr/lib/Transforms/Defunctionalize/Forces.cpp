// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dispatch function of each memo sum, `<sum>.force`: what every force
// of a cell of the sum becomes, a call, so that the call graph sees each
// label a force may run, as it sees a call's callee. Its body matches the
// cell's state. A label's case is the exchange of the cell's state
// (idr.memo.run): the captures move out of the cell, which is Running while
// the label's function runs on them, and the value moves in, the cell
// Forced with it; a label `by_name` leaves the cell as it is, calling its
// function on views of the captures, so that every force runs its function
// and its effect. The Running case is a force that reached its own cell
// again before its value moved in, a loop the program would
// never leave: the program crashes there instead. The Forced case is the
// value. Each is defined once every sum has its body, before any function
// converts, so a conversion only names it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The places `loc` holds, without the names around them.
void placesIn(Location loc, SmallVectorImpl<Location> &places) {
  if (auto named = dyn_cast<NameLoc>(loc))
    return placesIn(named.getChildLoc(), places);
  if (auto fused = dyn_cast<FusedLoc>(loc)) {
    for (Location part : fused.getLocations())
      placesIn(part, places);
    return;
  }
  if (!isa<UnknownLoc>(loc))
    places.push_back(loc);
}

} // namespace

FailureOr<FuncOp> Slots::defineForce(const Key &key, DataType sum) {
  FlatSymbolRefAttr name = forceOf(key);
  const Signature &sig = signature(name.getAttr());
  ArrayRef<Ctor> ctors = sum.getCtors();
  // Each label's case is at the label's function, the code it runs. The
  // dispatch, and what no one label does (a suspension that forced itself,
  // whichever label it was running), is at the places of every label of
  // the sum, under the dispatch's own name alone: a function is named by
  // the names its location holds, and the dispatch is made from no
  // label's code.
  auto placeOf = [&](const Ctor &ctor) -> std::optional<Location> {
    const auto *label = std::get_if<role::Label>(&ctor.role);
    if (!label)
      return std::nullopt;
    return signature(label->fn.getAttr()).place;
  };
  SmallVector<Location> labelPlaces;
  for (const Ctor &ctor : ctors)
    if (std::optional<Location> place = placeOf(ctor))
      placesIn(*place, labelPlaces);
  Location loc = NameLoc::get(name.getAttr(), FusedLoc::get(ctx, labelPlaces));
  OpBuilder b(ctx);
  // Its own body bounds what it runs: a match, and a call of each label,
  // whose own termination the label's function answers for.
  FuncOp::Properties properties;
  properties.setSymName(name.getAttr());
  properties.setFunctionType(TypeAttr::get(sig.converted));
  properties.setTotal(b.getUnitAttr());
  auto fn = FuncOp::create(b, loc, TypeRange(), ValueRange(), properties);
  Type cellType = sig.converted.getInput(0);
  Type valueType = sig.converted.getResult(0);
  Block *entry = b.createBlock(&fn.getBody(), {}, cellType, loc);
  Value cell = entry->getArgument(0);

  // A case per constructor of the sum, and no default.
  auto tags = llvm::to_vector(sum.getTags());
  auto match = MatchOp::create(b, loc, TypeRange(valueType), cell, ArrayRef<Tag>(tags));
  for (auto [index, ctor] : llvm::enumerate(ctors)) {
    Location at = placeOf(ctor).value_or(loc);
    Region &region = match.getCaseRegion(static_cast<unsigned>(index));
    SmallVector<Type> bound;
    for (Type field : ctor.fields)
      bound.push_back(fieldType(cellType, field));
    Block *state =
        b.createBlock(&region, region.end(), bound, SmallVector<Location>(bound.size(), at));
    // The body states no typed view of a memo sum: its constructors are
    // its labels and its two states by the body's rule, which is the type's
    // and checked when it was made, and a constructor of any other role is
    // the compiler's error, named here.
    LogicalResult filled = std::visit(
        llvm::makeVisitor(
            [&](const role::Label &label) -> LogicalResult {
              const Signature &run = signature(label.fn.getAttr());
              // The label's function on `captures`, its value held as the
              // force gives it.
              auto call = [&](ValueRange captures) {
                SmallVector<Value> args;
                for (auto [capture, param] :
                     llvm::zip_equal(captures, run.converted.getInputs()))
                  args.push_back(heldAs(b, at, capture, param));
                auto called = CallOp::create(b, at, run.converted.getResults(), label.fn, args,
                                             /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
                return heldAs(b, at, called.getResult(0), valueType);
              };
              // By name: the captures the case binds, views of a cell that
              // is never written.
              if (label.byName) {
                YieldOp::create(b, at, call(state->getArguments()));
                return success();
              }
              // Memoized: the exchange moves the captures out of the cell,
              // runs the label on them, and moves the value in, which the
              // force also gives.
              auto memo = MemoRunOp::create(b, at, TypeRange(valueType), cell,
                                            tags[index]);
              SmallVector<Type> captures(ctor.fields);
              Block *body = b.createBlock(&memo.getRegion(), {}, captures,
                                          SmallVector<Location>(captures.size(), at));
              Value value = call(body->getArguments());
              ArrayYieldOp::create(b, at, ValueRange{value, value});
              b.setInsertionPointAfter(memo);
              YieldOp::create(b, at, memo.getResult(0));
              return success();
            },
            [&](const role::Running &) -> LogicalResult {
              CrashOp::create(b, loc, "a suspension forced itself");
              ub::UnreachableOp::create(b, loc);
              return success();
            },
            [&](const role::Forced &) -> LogicalResult {
              YieldOp::create(b, at, heldAs(b, at, state->getArgument(0), valueType));
              return success();
            },
            [&](const auto &) -> LogicalResult {
              return emitError(loc) << "internal error: idr-defunctionalize: the memo sum \""
                                    << sum.getName() << "\" has a constructor @"
                                    << ctor.name.getValue() << " of role "
                                    << stringifyCtorRole(kindOf(ctor.role))
                                    << ", which is no label and no state";
            }),
        ctor.role);
    if (failed(filled)) {
      fn->erase();
      return failure();
    }
  }
  b.setInsertionPointToEnd(entry);
  ReturnOp::create(b, loc, match.getResults());
  return fn;
}

} // namespace idr::defunctionalize
