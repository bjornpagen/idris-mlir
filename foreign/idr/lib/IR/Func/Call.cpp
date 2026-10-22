// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.call and idr.return. A call holds its callee's result types, row,
// write part and lives_in, as llvm.call holds its memory effects, each
// taken from the callee when the call is built and again when the callee's
// change (copyCallee), and declares to MLIR what they stand for (its typed
// rule reads them), so every pass, upstream's among them, reads a call
// alone. Its symbol-use verifier, run once per verification of its program
// from the collection MLIR shares among every symbol user, holds the call
// to its callee: its types are the callee's signature at its index
// arguments, a tensor operand meeting its parameter by MLIR's shape
// compatibility and a lifetime of any kind standing where a view is asked;
// its
// copies are the callee's; what its callee puts into a lifetime its caller
// passes on fits what the caller says it puts; and a tail call passes its
// caller's cursors each in its own place, and its callee gives back the
// same result components. Where it stands in its function is the tail
// calls' to check.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/TypeUtilities.h"
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

// Whether an operand of type `given` meets the parameter its callee's
// signature asks as `asked`: the same type, or two ranked tensors alike
// but for their shapes, whose shapes MLIR finds compatible, `?` meeting
// any size. A call at a known size to the general function then needs no
// cast, and only the specializer, retargeting a call to a copy, casts.
// Every other part of the type, a grade among them, is compared exactly: a
// graded array keeps its `?` in every copy, and no cast keeps a grade, so
// bufferizing a call could not reconcile two graded shapes.
bool meets(Type given, Type asked) {
  if (given == asked)
    return true;
  auto have = dyn_cast<RankedTensorType>(given);
  auto want = dyn_cast<RankedTensorType>(asked);
  return have && want && have.clone(want.getShape()) == want &&
         succeeded(verifyCompatibleShape(have, want));
}

} // namespace

// A call's result types are its callee's at its index arguments, as its
// row, write part and lives_in are its callee's: taken from the callee, so
// no builder states them apart.
void idr::CallOp::build(OpBuilder &builder, OperationState &state, FuncOp callee,
                        IndexArgsAttr indexArgs, ValueRange args, TailKind tail) {
  state.addTypes(signatureAt(callee, indexArgs).getResults());
  state.addOperands(args);
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.callee = FlatSymbolRefAttr::get(callee.getSymNameAttr());
  properties.index_args = indexArgs;
  properties.tail_kind = tail;
  properties.row = callee.getRow();
  properties.untouched = callee.getUntouchedAttr();
  properties.lives_in = callee.getLivesInAttr();
}

// What a call holds of its callee, taken whole: the copies its symbol-use
// verifier holds equal, for a call whose callee changed or whose callee's
// facts did, a result's grade among them.
void idr::CallOp::copyCallee(FuncOp callee) {
  setRow(callee.getRow());
  setUntouchedAttr(callee.getUntouchedAttr());
  setLivesInAttr(callee.getLivesInAttr());
  for (auto [result, type] :
       llvm::zip(getResults(), signatureAt(callee, getIndexArgsAttr()).getResults()))
    result.setType(type);
}

CallInterfaceCallable idr::CallOp::getCallableForCallee() { return getCalleeAttr(); }
void idr::CallOp::setCalleeFromCallable(CallInterfaceCallable callee) {
  setCalleeAttr(cast<FlatSymbolRefAttr>(cast<SymbolRefAttr>(callee)));
}
Operation::operand_range idr::CallOp::getArgOperands() { return getArgs(); }
MutableOperandRange idr::CallOp::getArgOperandsMutable() { return getArgsMutable(); }

// Where it stands is the one definition of tail position's to check; every
// copy the call holds is its callee's, which its symbol-use verifier holds.
LogicalResult idr::CallOp::verify() { return tail::verify(*this); }

// A call may run where it would not have when it returns wherever it runs
// and the outside cannot hold it: its row says so.
Speculation::Speculatability idr::CallOp::getSpeculatability() {
  return rows::speculatable(getRow()) ? Speculation::Speculatable : Speculation::NotSpeculatable;
}

//===----------------------------------------------------------------------===//
// The lifetimes a call states
//===----------------------------------------------------------------------===//

// A scoped result lives in the lifetime operand at the position its
// callee's signature names, which the call's copy holds.
Value idr::CallOp::getStatedLifetime(Value made) {
  auto result = dyn_cast<OpResult>(made);
  LivesInAttr lives = getLivesInAttr();
  if (!result || !lives || result.getOwner() != getOperation())
    return nullptr;
  std::optional<std::uint32_t> lifetime = lives.lifetimeOfResult(result.getResultNumber());
  return lifetime ? getOperand(*lifetime) : Value();
}

// A call states a result's lifetime only as one of its own operands; given
// null, as a call of a copy whose result is no longer scoped is restated,
// or anything else, it states none. Its statement is a copy of its
// callee's signature, so whoever restates it restates the callee's too and
// copies it (copyCallee); a statement of the call's alone fails its
// symbol-use verifier. Its lifetime is an operand it passes already, at
// the position its callee's signature names, so no operand of its own
// states it again.
void idr::CallOp::setStatedLifetime(Value made, Value lifetime) {
  auto result = dyn_cast<OpResult>(made);
  if (!result || result.getOwner() != getOperation())
    return;
  auto operand = lifetime ? llvm::find(getOperands(), lifetime) : getOperands().end();
  std::optional<std::uint32_t> stated;
  if (operand != getOperands().end())
    stated = static_cast<std::uint32_t>(std::distance(getOperands().begin(), operand));
  setLivesInAttr(LivesInAttr::restateResult(getContext(), getLivesInAttr(),
                                            result.getResultNumber(), stated));
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
rows::Runs runsOf(Operation *op, FuncOp fn) {
  for (Region *region = op->getParentRegion(); region && region->getParentOp() != fn;
       region = region->getParentOp()->getParentRegion())
    if (rows::detail::regionRuns(region->getParentOp(), region->getRegionNumber()) ==
        rows::Runs::Repeatedly)
      return rows::Runs::Repeatedly;
  return rows::Runs::Once;
}

// The result components a function gives back, in their order.
auto givenBackResults(FuncOp fn) {
  GivenBackAttr given = fn.getGivenBackAttr();
  return llvm::map_range(given ? given.getEntries() : ArrayRef<GivenBackEntryAttr>(),
                         [](GivenBackEntryAttr entry) { return entry.entry().result; });
}

// A tail call's callee takes, as its k-th cursor parameter, its caller's
// k-th cursor parameter, and every one of them. The two lower to one
// return, which hands back the cursors the callee returns as the caller's
// own, by position: a cursor passed out of its place would come back in
// another's, and one not passed would not come back at all. Equal counts
// are not enough: two cursors swapped have them. `inputs` are the callee's
// parameter types at the call, one per argument.
LogicalResult cursorsInPlace(CallOp call, FuncOp caller, ArrayRef<Type> inputs,
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
LogicalResult putFits(CallOp call, FuncOp fn, FuncOp caller, BlockArgument parameter,
                      PutPart theirs, PutPart mine) {
  Amount put = boundOf(fn, theirs.position);
  if (put.none())
    return success();
  if (runsOf(call.getOperation(), caller) == rows::Runs::Repeatedly)
    put = Amount::unbounded();
  if (put.within(boundOf(caller, mine.position)))
    return success();
  return call.emitOpError("passes its caller's put parameter #")
         << parameter.getArgNumber() << " to " << call.getCalleeAttr()
         << ", which puts more into it than the caller's bound";
}

} // namespace

LogicalResult idr::CallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FlatSymbolRefAttr name = getCalleeAttr();
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(getOperation(), name);
  if (!fn)
    return emitOpError("calls ") << name << ", which the program does not define as an idr.func";

  // The callee's signature at the call's index arguments, one argument per
  // binder: each operand's type is its parameter's, grade included, so
  // what the call takes over is read from the call alone, but for a
  // tensor's shape, which meets the parameter's where MLIR finds the two
  // compatible; a lifetime of any kind may stand where a view is asked,
  // nothing happening to a view at run time, and any other kind only where
  // it is asked.
  IndexBindersAttr binders = fn.getBindersAttr();
  IndexArgsAttr args = getIndexArgsAttr();
  std::size_t binding = binders ? binders.getSorts().size() : 0;
  std::size_t giving = args ? args.getCount() : 0;
  if (binding != giving)
    return emitOpError("gives ") << giving << " index arguments to " << name << ", which binds "
                                 << binding;
  FunctionType signature = signatureAt(fn, args);
  ArrayRef<Type> inputs = signature.getInputs();
  if (getArgs().size() != inputs.size())
    return emitOpError("passes ") << getArgs().size() << " arguments to " << name
                                  << ", which takes " << inputs.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getArgs().getTypes(), inputs))) {
    auto [given, asked] = pair;
    if (!meets(given, asked) && !lifetimes::passesAs(given, asked))
      return emitOpError("passes ") << given << " as argument " << index << " of " << name
                                    << ", which takes " << asked;
  }
  // Each result's type is the callee's, its grade included, so a result's
  // exclusivity is read off the call alone, as fresh as its callee says.
  ArrayRef<Type> results = signature.getResults();
  if (getNumResults() != results.size())
    return emitOpError("expects ") << getNumResults() << " results from " << name
                                   << ", which returns " << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getResultTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("expects ") << std::get<0>(pair) << " as result " << index << " of "
                                     << name << ", which returns " << std::get<1>(pair);

  // The call's copies of its callee's facts are exact, so what a pass reads
  // off the call alone says what the callee may do and where its results
  // live, no more.
  if (getRow() != fn.getRow())
    return emitOpError("holds a row other than ") << name << "'s";
  if (getUntouchedAttr() != fn.getUntouchedAttr())
    return emitOpError("lists other operands untouched than ") << name << " does";
  if (getLivesInAttr() != fn.getLivesInAttr())
    return emitOpError("states other lifetimes for its results than ") << name << " does";

  auto caller = (*this)->getParentOfType<FuncOp>();

  // A tail call and its caller lower to one return: each cursor comes back
  // in its place, and each gives back the same result components, so a
  // result one drops is dropped by both.
  if (getTailKind() == TailKind::tail) {
    if (failed(cursorsInPlace(*this, caller, inputs, name)))
      return failure();
    if (!llvm::equal(givenBackResults(caller), givenBackResults(fn)))
      return emitOpError("is a tail call of ")
             << name << ", which gives back other result components than its caller";
  }

  // What the callee puts into a lifetime its caller was given fits what
  // the caller says it puts into it: no more than its bound, and no bound
  // at all from a region that may run again. The sum over every call and
  // allocation of the caller is the writer's, exact where it writes.
  ParameterParts calleeParts(inputs);
  if (calleeParts.puttable() == 0)
    return success();
  ParameterParts callerParts(caller.getArgumentTypes());
  for (auto [index, operand] : llvm::enumerate(getArgs())) {
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
              [&](PutPart mine) { return putFits(*this, fn, caller, parameter, theirs, mine); },
              [](WritePart) { return success(); }, [](NoPart) { return success(); });
        },
        [](WritePart) { return success(); }, [](NoPart) { return success(); });
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
