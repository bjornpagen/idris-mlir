// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a program at the stage its idr.program says, each stage's
// implications read from the stage table. The program's own, which its
// region verifier runs after checking its root, once every op of it is
// verified, on one thread, at the module's read and after every pass on the
// program: where its own upstream ops stand, and once counted the cells its
// recycles give. And a function's, which its region verifier runs, in
// parallel with every other function's: one walk of its body under every
// rule read per op (what the stage lets its values and ops hold, its scopes
// and refinements, its closures' flow while they exist, its effect row
// derived from its ops and held to what it says, what each value typed
// `unique deep` is given by its sources, its lifetimes), then its linear
// values. And an op's: whether its program stands at a stage its family is
// legal at, which the trait the specification gives it asks here. The stage
// is read from the program, never from what a function holds.
//
// The target is no rule here: idr-target holds every fact of the module's
// target to the build's where the module enters the pipeline, no pass
// changes one, and the runtime's word is the target's pointer when the
// compiler is built (idris_rt.h).
//
// Past the higher stage no value reaches a closure or a suspension: the
// function's rules ask each value's type, which answers from what its
// family computed when it was made.
//
// What a data type is held as, whether a memo sum is in a cell and whether
// a type contains itself in place, is no rule here: the class rule decides
// each when the type is made, so no program can say otherwise.

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Verify.h"

#include "idr/IR/Generated/StageFacts.h.inc"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;
using namespace idr;

namespace {

// Every idr.cell.recycle gives a cell of the size of every cell its token
// may hold (counting's rule). Only a recycle needs the sizes of cells, and
// the program's verifier runs where no pass rewrites a function beside it,
// so the layouts are built here, once, where the program has a recycle.
LogicalResult recycles(ProgramOp program) {
  SmallVector<CellRecycleOp> made;
  program.walk([&](CellRecycleOp recycle) { made.push_back(recycle); });
  if (made.empty())
    return success();
  Layouts layouts(program.getOperation());
  for (CellRecycleOp recycle : made)
    if (failed(verifyRecycle(recycle, layouts)))
      return failure();
  return success();
}

// How a diagnostic names a value of `op`: a result, or an argument of a
// block of one of its regions.
InFlightDiagnostic report(Operation *op, Value value) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    return op->emitOpError("binds argument #")
           << arg.getArgNumber() << " of region #" << arg.getParentRegion()->getRegionNumber()
           << ", of type " << arg.getType() << ", which ";
  return op->emitOpError("gives result #")
         << cast<OpResult>(value).getResultNumber() << ", of type " << value.getType()
         << ", which ";
}

// Whether a value of `type` claims more than a value at its uses may
// before references are counted (the grade's uncountedClaims): one used
// many times claims nothing, since counting makes each of its uses a
// reference of its own, each reaching what it holds.
bool claimsBeyondItsUses(Type type) {
  return !ownership::covers(uncountedClaims[static_cast<unsigned>(usesOf(type))],
                            ownership::claimOf(type));
}

// What the program's stage lets the ops and values of a function be. A
// closure or a suspension exists only before idr-defunctionalize makes
// each a sum, and with it every idr.fn.apply and idr.lazy.force, whose
// operands are such values, so past it no value's type reaches one; before
// references are counted no value claims more than its uses let it; no
// linalg op past the higher stage reads or writes an element that holds
// references, which idr-structure-loops makes only of arrays of words and
// counting so never meets; and once references are counted, a buffer
// allocated is a cell of the runtime, of the identity layout. While
// closures exist, each op is held to the flow rule.
class StageRules {
public:
  StageRules(StageClosures closures, StageCounting counting)
      : closures(closures), counting(counting) {}

  LogicalResult enter(Operation *op, Region &region) {
    for (Block &block : region)
      for (BlockArgument arg : block.getArguments())
        if (failed(value(op, arg)))
          return failure();
    return success();
  }

  LogicalResult check(Operation *op) {
    if (closures == StageClosures::Remain && failed(verifyFlowOf(op)))
      return failure();
    if (auto linalg = dyn_cast<linalg::LinalgOp>(op); linalg && closures == StageClosures::FirstOrder)
      for (BlockArgument element : linalg.getBlock()->getArguments())
        if (holdsReferences(element.getType()))
          return report(op, element) << "holds references, an element no linalg op reads or "
                                        "writes past the higher stage";
    if (auto alloc = dyn_cast<memref::AllocOp>(op);
        alloc && counting == StageCounting::Counted && !alloc.getType().getLayout().isIdentity())
      return alloc.emitOpError("allocates ")
             << alloc.getType() << ", whose layout is not a cell's, the identity";
    for (Value result : op->getResults())
      if (failed(value(op, result)))
        return failure();
    return success();
  }

  void leave() {}

private:
  LogicalResult value(Operation *op, Value value) {
    Type type = value.getType();
    if (closures == StageClosures::FirstOrder &&
        families::closureReach(type) == ClosureReach::ReachesClosure)
      return report(op, value) << "can reach a closure or a suspension in a program past the "
                                  "higher stage, where idr-defunctionalize has made each a sum";
    if (counting == StageCounting::Uncounted && claimsBeyondItsUses(type))
      return report(op, value) << "claims more of its sharing than a value used as often may "
                                  "before references are counted";
    return success();
  }

  StageClosures closures;
  StageCounting counting;
};

} // namespace

// The stages an op's family is legal at, which its trait asks when the op is
// verified: whether its program stands at one of them. The stage is one
// property of the program, which no op below it holds again, so the op
// reaches it through its parents. A module that holds no program (one a
// test writes of upstream's functions, or one idr-entry has taken apart)
// states no stage, so an op there is held to none.
LogicalResult idr::verifyLegalAt(Operation *op, Stage first, Stage last) {
  auto program = op->getParentOfType<ProgramOp>();
  if (!program)
    return success();
  Stage stage = program.getStage();
  if (first <= stage && stage <= last)
    return success();
  return op->emitOpError("stands in a program at the ")
         << stringifyStage(stage) << " stage, and is legal from the " << stringifyStage(first)
         << " stage to the " << stringifyStage(last);
}

LogicalResult idr::verify::program(ProgramOp program) {
  // A lowered program is upstream's functions and globals: nothing of ours
  // is left to hold to a rule.
  Stage stage = program.getStage();
  if (functionsAt[stage] == StageFunctions::Lowered)
    return success();
  // The program's own upstream ops (the static buffers bufferization makes)
  // stand where they are admitted, as each function's do in its walk.
  Admission admission(stage);
  for (Operation &op : program.getBody().front())
    if (failed(admission.check(&op)))
      return failure();
  if (countingAt[stage] == StageCounting::Counted)
    return recycles(program);
  return success();
}

LogicalResult idr::verify::function(FuncOp fn) {
  Stage stage = fn.getProgram().getStage();
  if (countingAt[stage] == StageCounting::Uncounted)
    for (auto [index, result] : llvm::enumerate(fn.getResultTypes()))
      if (claimsBeyondItsUses(result))
        return fn.emitOpError("gives result #")
               << index << " as " << result
               << ", which claims more of its sharing than a value used as often may before "
                  "references are counted";
  StageRules rules(closuresAt[stage], countingAt[stage]);
  families::ScopeWalk scopes(fn);
  rows::Check row(fn);
  ownership::LocalCheck local;
  LifetimeRules lifetimes(fn);
  Admission admission(stage);
  if (failed(families::walkFunction(fn, rules, scopes, row, local, lifetimes, admission)) ||
      failed(linearity(fn)))
    return failure();
  return success();
}
