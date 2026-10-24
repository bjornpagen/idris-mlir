// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The call family (idr.call, idr.tail_call, idr.context_call) and
// idr.return. A call holds its callee's result types, row, write part and
// lives_in, as llvm.call holds its memory effects, each taken from the
// callee when the call is built and again when the callee's change
// (copyCallee), and declares to MLIR what they stand for (its typed rule
// reads them), so every pass, upstream's among them, reads a call alone.
// Its symbol-use verifier, run once per verification of its program from
// the collection MLIR shares among every symbol user, holds the call to its
// callee: its types are the callee's signature at its index arguments, a
// tensor operand meeting its parameter by MLIR's shape compatibility at the
// axes the callee's extents name, a lifetime of any kind standing where a
// view is asked and, until the specializer keys the call by it, an argument
// whose hold fits its parameter's crossing at the parameter's; its copies
// are the callee's; what its callee puts into a lifetime its caller passes
// on fits what the caller says it puts; and a tail call passes its caller's
// cursors each in its own place, and each result is laid out as its caller
// returns it. Where it stands in its function is the tail calls' to check.
// The members differ in that alone, so each definition here is one
// template, instantiated per member.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// The callee's signature at a call's index arguments: each binder replaced
// by the term the call gives it, and each bare tensor input's axis static
// where its extent's term becomes a size, as the callee's copy at those
// terms has it.
FunctionType signatureAt(FuncOp callee, IndexArgsAttr args) {
  return args ? families::substitute(callee.getFunctionType(), callee.getExtentsAttr(), args)
              : callee.getFunctionType();
}

// A call's result types are its callee's at its index arguments, as its
// row, write part and lives_in are its callee's: taken from the callee, so
// no builder states them apart.
template <CallFamily Call>
void buildCall(OperationState &state, FuncOp callee, IndexArgsAttr indexArgs, ValueRange args) {
  state.addTypes(signatureAt(callee, indexArgs).getResults());
  state.addOperands(args);
  auto &properties = state.getOrAddProperties<typename Call::Properties>();
  properties.callee = FlatSymbolRefAttr::get(callee.getSymNameAttr());
  properties.index_args = indexArgs;
  properties.row = callee.getRow();
  properties.untouched = callee.getUntouchedAttr();
  properties.lives_in = callee.getLivesInAttr();
}

// What a call holds of its callee, taken whole: the copies its symbol-use
// verifier holds equal, for a call whose callee changed or whose callee's
// facts did, a result's grade among them.
template <CallFamily Call>
void copyCalleeOf(Call call, FuncOp callee) {
  call.setRow(callee.getRow());
  call.setUntouchedAttr(callee.getUntouchedAttr());
  call.setLivesInAttr(callee.getLivesInAttr());
  for (auto [result, type] :
       llvm::zip(call.getResults(), signatureAt(callee, call.getIndexArgsAttr()).getResults()))
    result.setType(type);
}

template <CallFamily Call>
Speculation::Speculatability speculatabilityOf(Call call) {
  return rows::speculatable(call.getRow()) ? Speculation::Speculatable
                                           : Speculation::NotSpeculatable;
}

template <CallFamily Call>
void setCalleeOf(Call call, CallInterfaceCallable callee) {
  call.setCalleeAttr(cast<FlatSymbolRefAttr>(cast<SymbolRefAttr>(callee)));
}

// A scoped result lives in the lifetime operand at the position its
// callee's signature names, which the call's copy holds.
template <CallFamily Call>
Value statedLifetimeOf(Call call, Value made) {
  auto result = dyn_cast<OpResult>(made);
  LivesInAttr lives = call.getLivesInAttr();
  if (!result || !lives || result.getOwner() != call.getOperation())
    return nullptr;
  std::optional<std::uint32_t> lifetime = lives.lifetimeOfResult(result.getResultNumber());
  return lifetime ? call->getOperand(*lifetime) : Value();
}

// A call states a result's lifetime only as one of its own operands; given
// null, as a call of a copy whose result is no longer scoped is restated,
// or anything else, it states none. Its statement is a copy of its
// callee's signature, so whoever restates it restates the callee's too and
// copies it (copyCallee); a statement of the call's alone fails its
// symbol-use verifier. Its lifetime is an operand it passes already, at
// the position its callee's signature names, so no operand of its own
// states it again.
template <CallFamily Call>
void stateLifetimeOf(Call call, Value made, Value lifetime) {
  auto result = dyn_cast<OpResult>(made);
  if (!result || result.getOwner() != call.getOperation())
    return;
  auto operand = lifetime ? llvm::find(call->getOperands(), lifetime) : call->getOperands().end();
  std::optional<std::uint32_t> stated;
  if (operand != call->getOperands().end())
    stated = static_cast<std::uint32_t>(std::distance(call->getOperands().begin(), operand));
  call.setLivesInAttr(LivesInAttr::restateResult(call.getContext(), call.getLivesInAttr(),
                                                 result.getResultNumber(), stated));
}

} // namespace

void idr::CallOp::build(OpBuilder &, OperationState &state, FuncOp callee,
                        IndexArgsAttr indexArgs, ValueRange args) {
  buildCall<CallOp>(state, callee, indexArgs, args);
}
void idr::TailCallOp::build(OpBuilder &, OperationState &state, FuncOp callee,
                            IndexArgsAttr indexArgs, ValueRange args) {
  buildCall<TailCallOp>(state, callee, indexArgs, args);
}
void idr::ContextCallOp::build(OpBuilder &, OperationState &state, FuncOp callee,
                               IndexArgsAttr indexArgs, ValueRange args) {
  buildCall<ContextCallOp>(state, callee, indexArgs, args);
}

void idr::CallOp::copyCallee(FuncOp callee) { copyCalleeOf(*this, callee); }
void idr::TailCallOp::copyCallee(FuncOp callee) { copyCalleeOf(*this, callee); }
void idr::ContextCallOp::copyCallee(FuncOp callee) { copyCalleeOf(*this, callee); }

CallInterfaceCallable idr::CallOp::getCallableForCallee() { return getCalleeAttr(); }
CallInterfaceCallable idr::TailCallOp::getCallableForCallee() { return getCalleeAttr(); }
CallInterfaceCallable idr::ContextCallOp::getCallableForCallee() { return getCalleeAttr(); }
void idr::CallOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  setCalleeOf(*this, callee);
}
void idr::TailCallOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  setCalleeOf(*this, callee);
}
void idr::ContextCallOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  setCalleeOf(*this, callee);
}
Operation::operand_range idr::CallOp::getArgOperands() { return getArgs(); }
Operation::operand_range idr::TailCallOp::getArgOperands() { return getArgs(); }
Operation::operand_range idr::ContextCallOp::getArgOperands() { return getArgs(); }
MutableOperandRange idr::CallOp::getArgOperandsMutable() { return getArgsMutable(); }
MutableOperandRange idr::TailCallOp::getArgOperandsMutable() { return getArgsMutable(); }
MutableOperandRange idr::ContextCallOp::getArgOperandsMutable() { return getArgsMutable(); }

// Where it stands is the one definition of tail position's to check; every
// copy the call holds is its callee's, which its symbol-use verifier holds.
LogicalResult idr::CallOp::verify() { return tail::verify(*this); }
LogicalResult idr::TailCallOp::verify() { return tail::verify(*this); }
LogicalResult idr::ContextCallOp::verify() { return tail::verify(*this); }

// A call may run where it would not have when it returns wherever it runs
// and the outside cannot hold it: its row says so, whatever its member.
Speculation::Speculatability idr::CallOp::getSpeculatability() {
  return speculatabilityOf(*this);
}
Speculation::Speculatability idr::TailCallOp::getSpeculatability() {
  return speculatabilityOf(*this);
}
Speculation::Speculatability idr::ContextCallOp::getSpeculatability() {
  return speculatabilityOf(*this);
}

//===----------------------------------------------------------------------===//
// The lifetimes a call states
//===----------------------------------------------------------------------===//

Value idr::CallOp::getStatedLifetime(Value made) { return statedLifetimeOf(*this, made); }
Value idr::TailCallOp::getStatedLifetime(Value made) { return statedLifetimeOf(*this, made); }
Value idr::ContextCallOp::getStatedLifetime(Value made) { return statedLifetimeOf(*this, made); }
void idr::CallOp::setStatedLifetime(Value made, Value lifetime) {
  stateLifetimeOf(*this, made, lifetime);
}
void idr::TailCallOp::setStatedLifetime(Value made, Value lifetime) {
  stateLifetimeOf(*this, made, lifetime);
}
void idr::ContextCallOp::setStatedLifetime(Value made, Value lifetime) {
  stateLifetimeOf(*this, made, lifetime);
}

//===----------------------------------------------------------------------===//
// The call against its callee
//===----------------------------------------------------------------------===//

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
Runs runsOf(Operation *op, FuncOp fn) {
  for (Region *region = op->getParentRegion(); region && region->getParentOp() != fn;
       region = region->getParentOp()->getParentRegion())
    if (regionRuns(region->getParentOp(), region->getRegionNumber()) == Runs::Repeatedly)
      return Runs::Repeatedly;
  return Runs::Once;
}

// A tail call's callee takes, as its k-th cursor parameter, its caller's
// k-th cursor parameter, and every one of them. The two lower to one
// return, which hands back the cursors the callee returns as the caller's
// own, by position: a cursor passed out of its place would come back in
// another's, and one not passed would not come back at all. Equal counts
// are not enough: two cursors swapped have them. `inputs` are the callee's
// parameter types at the call, one per argument.
LogicalResult cursorsInPlace(TailCallOp call, FuncOp caller, ArrayRef<Type> inputs,
                             FlatSymbolRefAttr name) {
  auto mine = llvm::make_filter_range(
      caller.getBody().front().getArguments(),
      [](BlockArgument parameter) { return isCursorLifetime(parameter.getType()); });
  auto next = mine.begin();
  std::uint32_t position = 0;
  for (auto [operand, asked] : llvm::zip_equal(call.getArgs(), inputs)) {
    if (!isCursorLifetime(asked))
      continue;
    if (next == mine.end() || operand != *next)
      return call.emitOpError("is a tail call of ")
             << name << ", which takes as its cursor " << position
             << " another value than its caller's cursor parameter " << position;
    ++next;
    ++position;
  }
  if (next != mine.end())
    return call.emitOpError("is a tail call of ")
           << name << ", which takes " << position << " cursors, fewer than its caller";
  return success();
}

// What `fn` puts into its put parameter `theirs`, which `call` passes its
// caller's put parameter `mine` at `parameter`, fits what the caller says
// it puts there: no more than its bound, and no bound at all from a region
// that may run again.
LogicalResult putFits(FunctionCallOpInterface call, FuncOp fn, FuncOp caller,
                      BlockArgument parameter, PutPart theirs, PutPart mine) {
  Amount put = boundOf(fn, theirs.position);
  if (put.none())
    return success();
  if (runsOf(call.getOperation(), caller) == Runs::Repeatedly)
    put = Amount::unbounded();
  if (put.within(boundOf(caller, mine.position)))
    return success();
  return call->emitOpError("passes its caller's put parameter #")
         << parameter.getArgNumber() << " to " << call.getCalleeAttr()
         << ", which puts more into it than the caller's bound";
}

template <CallFamily Call>
LogicalResult verifyCallee(Call call, SymbolTableCollection &symbols) {
  FlatSymbolRefAttr name = call.getCalleeAttr();
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(call.getOperation(), name);
  if (!fn)
    return call.emitOpError("calls ")
           << name << ", which the program does not define as an idr.func";

  // The callee's signature at the call's index arguments, one argument per
  // binder: each operand's type is its parameter's, grade included, so
  // what the call takes over is read from the call alone, but for a bare
  // tensor's axis the callee's extents name, which meets the parameter's
  // where MLIR finds the two compatible (meets); a graded array is compared
  // whole, since no cast keeps a grade and bufferizing the call could not
  // reconcile two graded shapes. A lifetime of any kind may stand where a
  // view is asked, nothing happening to a view at run time, and any other
  // kind only where it is asked. Before the specializer has keyed each call
  // by the hold its argument is passed at, an argument whose hold fits its
  // parameter's crosses at the parameter's (crossedAs): static data where
  // the callee counts, a fresh value's claim where it claims nothing.
  IndexBindersAttr binders = fn.getBindersAttr();
  IndexArgsAttr args = call.getIndexArgsAttr();
  std::size_t binding = binders ? binders.getSorts().size() : 0;
  std::size_t giving = args ? args.getCount() : 0;
  if (binding != giving)
    return call.emitOpError("gives ")
           << giving << " index arguments to " << name << ", which binds " << binding;
  FunctionType signature = signatureAt(fn, args);
  ArrayRef<Type> inputs = signature.getInputs();
  if (call.getArgs().size() != inputs.size())
    return call.emitOpError("passes ") << call.getArgs().size() << " arguments to " << name
                                  << ", which takes " << inputs.size();
  ExtentsAttr extents = fn.getExtentsAttr();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(call.getArgs().getTypes(), inputs))) {
    auto [given, asked] = pair;
    if (!meets(crossedAs(call.getOperation(), given, asked), asked, extents, ExtentSide::Input,
               static_cast<std::uint32_t>(index)) &&
        !lifetimes::passesAs(given, asked))
      return call.emitOpError("passes ") << given << " as argument " << index << " of " << name
                                    << ", which takes " << asked;
  }
  // Each result's type is the callee's, its grade included, so a result's
  // exclusivity is read off the call alone, as fresh as its callee says.
  ArrayRef<Type> results = signature.getResults();
  if (call->getNumResults() != results.size())
    return call.emitOpError("expects ") << call->getNumResults() << " results from " << name
                                   << ", which returns " << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(call->getResultTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return call.emitOpError("expects ") << std::get<0>(pair) << " as result " << index << " of "
                                     << name << ", which returns " << std::get<1>(pair);

  // The call's copies of its callee's facts are exact, so what a pass reads
  // off the call alone says what the callee may do and where its results
  // live, no more.
  if (call.getRow() != fn.getRow())
    return call.emitOpError("holds a row other than ") << name << "'s";
  if (call.getUntouchedAttr() != fn.getUntouchedAttr())
    return call.emitOpError("lists other operands untouched than ") << name << " does";
  if (call.getLivesInAttr() != fn.getLivesInAttr())
    return call.emitOpError("states other lifetimes for its results than ") << name << " does";

  auto caller = call->template getParentOfType<FuncOp>();

  // A tail call and its caller lower to one return: each cursor comes back
  // in its place, and each result is laid out as its caller returns it, so
  // no re-pack runs after the call.
  if constexpr (standingOf<Call> == CallStanding::Tail) {
    if (failed(cursorsInPlace(call, caller, inputs, name)))
      return failure();
    if (failed(tail::verifyLayouts(call, caller)))
      return failure();
  }

  // What the callee puts into a lifetime its caller was given fits what
  // the caller says it puts into it: no more than its bound, and no bound
  // at all from a region that may run again. The sum over every call and
  // allocation of the caller is the writer's, exact where it writes.
  ParameterParts calleeParts(inputs);
  if (calleeParts.puttable() == 0)
    return success();
  ParameterParts callerParts(caller.getArgumentTypes());
  for (auto [index, operand] : llvm::enumerate(call.getArgs())) {
    auto parameter = dyn_cast<BlockArgument>(operand);
    if (!parameter || parameter.getOwner() != &caller.getBody().front())
      continue;
    // Only a put parameter of the caller's, passed as one of the callee's,
    // has a bound to keep.
    LogicalResult fits = idr::match(
        calleeParts[static_cast<unsigned>(index)],
        [&](PutPart theirs) {
          return idr::match(
              callerParts[parameter.getArgNumber()],
              [&](PutPart mine) { return putFits(call, fn, caller, parameter, theirs, mine); },
              [](WritePart) { return success(); }, [](NoPart) { return success(); });
        },
        [](WritePart) { return success(); }, [](NoPart) { return success(); });
    if (failed(fits))
      return failure();
  }
  return success();
}

} // namespace

LogicalResult idr::CallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyCallee(*this, symbols);
}
LogicalResult idr::TailCallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyCallee(*this, symbols);
}
LogicalResult idr::ContextCallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  return verifyCallee(*this, symbols);
}

// A return gives its function's results at their own types, or, before the
// specializer, at a hold that fits each (crossedAs).
LogicalResult idr::ReturnOp::verify() {
  auto fn = cast<FuncOp>((*this)->getParentOp());
  auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
  ArrayRef<Type> results = fn.getResultTypes();
  if (getNumOperands() != results.size())
    return emitOpError("returns ") << getNumOperands() << " values, but " << name << " returns "
                                   << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getOperandTypes(), results)))
    if (crossedAs(getOperation(), std::get<0>(pair), std::get<1>(pair)) != std::get<1>(pair))
      return emitOpError("returns ") << std::get<0>(pair) << " as result " << index << ", but "
                                     << name << " returns " << std::get<1>(pair);
  return success();
}
