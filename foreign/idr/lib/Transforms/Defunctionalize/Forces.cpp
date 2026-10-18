// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dispatch function of each memo sum, `<sum>.force`: what every force
// of a cell of the sum becomes, a call, so that the call graph sees each
// label a force may run, as it sees a call's callee. Its body matches the
// cell's state. A label's case marks the cell Running, calls the label's
// function with the captures it bound, and settles the cell Forced with
// the value; a label `by_name` leaves the cell as it is, so that every
// force runs its function and its effect. The Running case is a force that
// reached its own cell again before settling it, a loop the program would
// never leave: the program crashes there instead. The Forced case is the
// value. Each is defined once every sum has its body, before any function
// converts, so a conversion only names it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"

#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;

namespace idr::defunctionalize {

FailureOr<FuncOp> Slots::defineForce(const Key &key, DataType sum) {
  FlatSymbolRefAttr name = forceOf(key);
  const Signature &sig = signature(name.getAttr());
  Location loc = NameLoc::get(name.getAttr());
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
  ArrayRef<Ctor> ctors = sum.getCtors();
  auto tags = llvm::to_vector(sum.getTags());
  auto match = MatchOp::create(b, loc, TypeRange(valueType), cell, ArrayRef<Tag>(tags));
  for (auto [index, ctor] : llvm::enumerate(ctors)) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(index));
    SmallVector<Type> bound;
    for (Type field : ctor.fields)
      bound.push_back(fieldType(cellType, field));
    Block *state =
        b.createBlock(&region, region.end(), bound, SmallVector<Location>(bound.size(), loc));
    // The body states no typed view of a memo sum: its constructors are
    // its labels and its two states by the body's rule, which is the type's
    // and checked when it was made, and a constructor of any other role is
    // the compiler's error, named here.
    LogicalResult filled = std::visit(
        llvm::makeVisitor(
            [&](const role::Label &label) -> LogicalResult {
              const Signature &run = signature(label.fn.getAttr());
              SmallVector<Value> args;
              for (auto [capture, param] :
                   llvm::zip_equal(state->getArguments(), run.converted.getInputs()))
                args.push_back(heldAs(b, loc, capture, param));
              if (!label.byName)
                MemoEnterOp::create(b, loc, cell);
              auto call = CallOp::create(b, loc, run.converted.getResults(), label.fn, args,
                                         /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
              Value value = heldAs(b, loc, call.getResult(0), valueType);
              if (!label.byName)
                MemoSettleOp::create(b, loc, cell, value);
              YieldOp::create(b, loc, value);
              return success();
            },
            [&](const role::Running &) -> LogicalResult {
              CrashOp::create(b, loc, "a suspension forced itself");
              ub::UnreachableOp::create(b, loc);
              return success();
            },
            [&](const role::Forced &) -> LogicalResult {
              YieldOp::create(b, loc, heldAs(b, loc, state->getArgument(0), valueType));
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
