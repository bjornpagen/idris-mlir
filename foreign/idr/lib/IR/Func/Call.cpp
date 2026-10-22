// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.call and idr.return. A call holds its callee's row and write part, as
// llvm.call holds its memory effects, and declares to MLIR what they stand
// for (its typed rule reads them), so every pass, upstream's among them,
// reads a call alone. Its symbol-use verifier, run once per verification of
// its program from the collection MLIR shares among every symbol user,
// holds the call to its callee: its types are the callee's signature at
// its index arguments, a lifetime of any kind standing where a view is
// asked; its row and write part are the callee's; and what its callee puts
// into a lifetime its caller passes on fits what the caller says it puts.
// Where it stands in its function is the tail calls' to check.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

void idr::CallOp::build(OpBuilder &builder, OperationState &state, FuncOp callee,
                        IndexArgsAttr indexArgs, TypeRange results, ValueRange args,
                        TailKind tail) {
  state.addTypes(results);
  state.addOperands(args);
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.callee = FlatSymbolRefAttr::get(callee.getSymNameAttr());
  properties.index_args = indexArgs;
  properties.tail = tail;
  properties.row = callee.getRow();
  properties.untouched = callee.getUntouchedAttr();
}

CallInterfaceCallable idr::CallOp::getCallableForCallee() { return getCalleeAttr(); }
void idr::CallOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  setCalleeAttr(cast<FlatSymbolRefAttr>(cast<SymbolRefAttr>(callee)));
}
Operation::operand_range idr::CallOp::getArgOperands() { return getArgs(); }
MutableOperandRange idr::CallOp::getArgOperandsMutable() { return getArgsMutable(); }

// The positions the call lists untouched name operands that admit a write
// part, as its callee's name parameters: a local fact of the call. Where
// it stands is the one definition of tail position's to check.
LogicalResult idr::CallOp::verify() {
  if (DenseI32ArrayAttr untouched = getUntouchedAttr(); untouched && !untouched.empty()) {
    auto writable = static_cast<std::int32_t>(
        llvm::count_if(getArgs().getTypes(), [](Type type) { return admitsWrite(type); }));
    if (untouched.asArrayRef().back() >= writable)
      return emitOpError("lists operand ")
             << untouched.asArrayRef().back() << " untouched among its " << writable
             << " that admit a write part";
  }
  return tail::verify(*this);
}

// A call may run where it would not have when it returns wherever it runs
// and the outside cannot hold it: its row says so.
Speculation::Speculatability idr::CallOp::getSpeculatability() {
  return rows::speculatable(getRow()) ? Speculation::Speculatable : Speculation::NotSpeculatable;
}

namespace {

// What a function says it puts into its put parameter at `position`.
Amount boundOf(FuncOp fn, std::uint32_t position) {
  if (PutBoundsAttr bounded = fn.getBoundedAttr())
    for (const PutBound &bound : bounded.getBounds())
      if (bound.parameter == position)
        return Amount::finite(bound.bytes);
  return Amount::unbounded();
}

// Whether `op` lies in a region of its function that may run more than
// once per run of the function: a put there has no bound. Climbed from the
// call, once per call that passes a put parameter on.
rows::Runs runsOf(Operation *op, FuncOp fn) {
  for (Region *region = op->getParentRegion(); region && region->getParentOp() != fn;
       region = region->getParentOp()->getParentRegion())
    if (rows::detail::regionRuns(region->getParentOp(), region->getRegionNumber()) ==
        rows::Runs::Repeatedly)
      return rows::Runs::Repeatedly;
  return rows::Runs::Once;
}

} // namespace

LogicalResult idr::CallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FlatSymbolRefAttr name = getCalleeAttr();
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(getOperation(), name);
  if (!fn)
    return emitOpError("calls ") << name << ", which the program does not define as an idr.func";

  // The callee's signature at the call's index arguments, one argument per
  // binder: each operand's type is its parameter's, grade included, so
  // what the call takes over is read from the call alone; a lifetime of any
  // kind may stand where a view is asked, nothing happening to a view at
  // run time, and any other kind only where it is asked.
  IndexBindersAttr binders = fn.getBindersAttr();
  IndexArgsAttr args = getIndexArgsAttr();
  std::size_t binding = binders ? binders.getSorts().size() : 0;
  std::size_t giving = args ? args.getCount() : 0;
  if (binding != giving)
    return emitOpError("gives ") << giving << " index arguments to " << name << ", which binds "
                                 << binding;
  auto signature = cast<FunctionType>(
      args ? families::substitute(fn.getFunctionType(), args) : Type(fn.getFunctionType()));
  ArrayRef<Type> inputs = signature.getInputs();
  if (getArgs().size() != inputs.size())
    return emitOpError("passes ") << getArgs().size() << " arguments to " << name
                                  << ", which takes " << inputs.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getArgs().getTypes(), inputs))) {
    auto [given, asked] = pair;
    if (given != asked && !lifetimes::passesAs(given, asked))
      return emitOpError("passes ") << given << " as argument " << index << " of " << name
                                    << ", which takes " << asked;
  }
  ArrayRef<Type> results = signature.getResults();
  if (getNumResults() != results.size())
    return emitOpError("expects ") << getNumResults() << " results from " << name
                                   << ", which returns " << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getResultTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("expects ") << std::get<0>(pair) << " as result " << index << " of "
                                     << name << ", which returns " << std::get<1>(pair);

  // The call's copy of its callee's row and write part is exact, so what a
  // pass reads off the call alone says what the callee may do, no more.
  if (getRow() != fn.getRow())
    return emitOpError("holds a row other than ") << name << "'s";
  if (getUntouchedAttr() != fn.getUntouchedAttr())
    return emitOpError("lists other operands untouched than ") << name << " does";

  // What the callee puts into a lifetime its caller was given fits what
  // the caller says it puts into it: no more than its bound, and no bound
  // at all from a region that may run again. The sum over every call and
  // allocation of the caller is the writer's, exact where it writes.
  ParameterParts calleeParts(inputs);
  if (calleeParts.puttable() == 0)
    return success();
  auto caller = (*this)->getParentOfType<FuncOp>();
  ParameterParts callerParts(caller.getArgumentTypes());
  for (auto [index, operand] : llvm::enumerate(getArgs())) {
    auto parameter = dyn_cast<BlockArgument>(operand);
    if (!parameter || parameter.getOwner() != &caller.getBody().front())
      continue;
    LogicalResult fits = idr::match(
        calleeParts[static_cast<unsigned>(index)],
        [&](PutPart theirs) -> LogicalResult {
          Amount put = boundOf(fn, theirs.position);
          if (put.none())
            return success();
          return idr::match(
              callerParts[parameter.getArgNumber()],
              [&](PutPart mine) -> LogicalResult {
                if (runsOf(getOperation(), caller) == rows::Runs::Repeatedly)
                  put = Amount::unbounded();
                if (put.within(boundOf(caller, mine.position)))
                  return success();
                return emitOpError("passes its caller's put parameter #")
                       << parameter.getArgNumber() << " to " << name
                       << ", which puts more into it than the caller's bound";
              },
              [](WritePart) -> LogicalResult { return success(); },
              [](NoPart) -> LogicalResult { return success(); });
        },
        [](WritePart) -> LogicalResult { return success(); },
        [](NoPart) -> LogicalResult { return success(); });
    if (failed(fits))
      return failure();
  }
  return success();
}

LogicalResult idr::ReturnOp::verify() {
  auto fn = cast<FuncOp>((*this)->getParentOp());
  auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
  ArrayRef<Type> results = fn.getResultTypes();
  if (getNumOperands() != results.size())
    return emitOpError("returns ") << getNumOperands() << " values, but " << name << " returns "
                                   << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getOperandTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("returns ") << std::get<0>(pair) << " as result " << index << ", but "
                                     << name << " returns " << std::get<1>(pair);
  return success();
}
