// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a program at the stage its idr.program says. The program's
// own, which its symbol-use verifier runs once every op of it is verified,
// on one thread: its root; its data types, a memo sum only in a box, no
// array that can reach itself, and past the higher stage containment in
// place acyclic and no closure or suspension in a body; and the cells its
// reuses build in. And a function's, which its region verifier runs, in
// parallel with every other function's: what the stage lets its values
// hold, then its closures' flow, its linear values and its counting.
// The stage is read from the program, never from what a function holds.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether `type` names a closure or a suspension anywhere in it, through
// grades and element types. A data type's body is the program's rule to
// read, once per data type.
bool namesLabels(Type type) {
  return type
      .walk([](Type inner) {
        return isa<FnType, LazyType>(inner) ? WalkResult::interrupt() : WalkResult::advance();
      })
      .wasInterrupted();
}

// The root takes the world and returns what its IO does, or takes nothing
// and returns the program's exit status.
LogicalResult rootType(FuncOp root) {
  FunctionType type = root.getFunctionType();
  Builder b(root.getContext());
  bool intRoot =
      type.getInputs().empty() && type.getNumResults() == 1 && type.getResult(0) == b.getI64Type();
  bool ioRoot = type.getInputs().size() == 1 && isWorld(type.getInput(0));
  if (!intRoot && !ioRoot)
    return root.emitOpError("is the root, so its type must be () -> i64 or (!idr.world) -> (...), "
                            "not ")
           << type;
  return success();
}

// Every idr.reuse builds in a cell of its own size: its token comes from an
// idr.take of a cell of the same size, as the target lays cells out. Only a
// reuse needs the sizes of cells, and the program's verifier runs where no
// pass rewrites a function beside it, so the layouts are built here, once;
// layouts that cannot be built have said why, cell by cell, as they were.
LogicalResult reuses(ProgramOp program) {
  SmallVector<ReuseOp> reuses;
  program.walk([&](ReuseOp reuse) { reuses.push_back(reuse); });
  if (reuses.empty())
    return success();
  Layouts layouts(program.getOperation());
  if (failed(layouts.valid()))
    return failure();
  for (ReuseOp reuse : reuses) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    if (!take)
      return reuse.emitOpError("builds in a token that no idr.take made");
    auto cell = static_cast<unsigned>(take.getTag());
    unsigned have = layouts.box(take.getDataType(), cell).size;
    unsigned need = layouts.box(reuse.getDataType(), static_cast<unsigned>(reuse.getTag())).size;
    if (have != need)
      return reuse.emitOpError("builds a cell of ")
             << need << " bytes in the " << have << "-byte cell of @"
             << take.getDataType().getCtor(cell).name.getValue();
  }
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

// Whether an op of upstream's holds `value` at a type upstream fixes: makes
// it (a load from a buffer, a view of one, an allocation) or takes it (the
// value a store writes), not by forwarding it, which keeps whatever type it
// is given.
bool upstreamHolds(Value value) {
  auto upstream = [](Operation *op) {
    return !isa_and_nonnull<IdrDialect>(op->getDialect()) && op->getNumRegions() == 0;
  };
  if (Operation *def = value.getDefiningOp(); def && upstream(def))
    return true;
  for (OpOperand &use : value.getUses()) {
    if (!upstream(use.getOwner()))
      continue;
    bool forwarded = false;
    forwardedValues(use.getOwner(),
                    [&](OpOperand &operand, Value) { forwarded = forwarded || &operand == &use; });
    if (!forwarded)
      return true;
  }
  return false;
}

// Whether `value` holds references at the plain grade where the owned
// stage says what every reference is: a value of one of our types that
// holds one is owned, exclusive or borrowed then. Static data holds none a
// count reaches. A buffer's view stays plain, and so does an element an op
// of upstream's loads or stores: upstream's types hold no grade.
bool plainReference(Value value) {
  Type carrier = unrestricted(value.getType());
  if (gradeOf(value.getType()).permission != Permission::Plain ||
      !isa<IdrDialect>(carrier.getDialect()) || !holdsReferences(carrier))
    return false;
  return !ownership::isStatic(value) && !upstreamHolds(value);
}

// What the program's stage lets the values of `fn` hold. A closure or a
// suspension exists only before idr-defunctionalize makes each a sum, and
// with it every idr.apply and idr.force, whose operands are such values; a
// grade own or excl only once idr-rc counts references, after which every
// reference of ours is graded.
LogicalResult stageRules(FuncOp fn, Stage stage) {
  bool pastHigher = stage != Stage::Higher;
  bool owned = stage == Stage::Owned;
  if (pastHigher && llvm::any_of(fn.getResultTypes(), namesLabels))
    return fn.emitOpError("returns a closure or a suspension in a program past the higher stage, "
                          "where idr-defunctionalize has made each a sum");
  auto check = [&](Operation *op, Value value) -> LogicalResult {
    Type type = value.getType();
    if (pastHigher && namesLabels(type))
      return report(op, value) << "holds a closure or a suspension in a program past the higher "
                                  "stage, where idr-defunctionalize has made each a sum";
    if (!owned && isOwned(type))
      return report(op, value) << "is graded own or excl in a program before the owned stage, "
                                  "whose grades idr-rc gives";
    if (owned && plainReference(value))
      return report(op, value) << "holds references at the plain grade in the owned stage, where "
                                  "a value of ours that holds one is owned, exclusive or "
                                  "borrowed";
    return success();
  };
  WalkResult walked = fn->walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (Value result : op->getResults())
      if (failed(check(op, result)))
        return WalkResult::interrupt();
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          if (failed(check(op, arg)))
            return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return failure(walked.wasInterrupted());
}

} // namespace

LogicalResult idr::verify::program(ProgramOp program) {
  // A lowered program is upstream's functions and globals: its root names
  // a func.func, and nothing of ours is left to hold to a rule.
  Stage stage = program.getStage();
  if (stage == Stage::Lowered) {
    if (!isa_and_nonnull<func::FuncOp>(
            SymbolTable::lookupSymbolIn(program, program.getRootAttr())))
      return program.emitOpError("is lowered, so its root ")
             << program.getRootAttr() << " names a func.func of it";
    return success();
  }
  FuncOp root = program.lookupRoot();
  if (!root)
    return program.emitOpError("has root ")
           << program.getRootAttr() << ", which is no idr.func of the program";
  if (failed(rootType(root)))
    return failure();

  // The data types the program's values and bodies hold, each once.
  TypeGraph graph(program.getOperation());
  for (unsigned at = 0, n = graph.size(); at < n; ++at) {
    DataType data = graph.declaration(at);
    if (!data)
      continue;
    // A cell has one memo, which every reference to it sees.
    if (data.isMemo() && graph.inlined(at))
      return program.emitOpError("holds the memo sum \"")
             << data.getName() << "\" in place; a memo sum is held only in a box";
    if (stage == Stage::Higher)
      continue;
    for (const Ctor &ctor : data.getCtors())
      for (Type field : ctor.fields)
        if (namesLabels(field))
          return program.emitOpError("holds the data type \"")
                 << data.getName() << "\", whose constructor " << ctor.name
                 << " has a field of type " << field
                 << ", a closure or a suspension, past the higher stage";
  }

  // Containment in place is acyclic, so every cycle of types passes through
  // a box: a value held in place is stored where it is, and one that holds
  // itself would have no size. The frontend holds every type in place and
  // layout::fit boxes the cycles, which idr-defunctionalize runs, so the rule
  // holds from the first-order stage on.
  SmallVector<DataType> selfContained;
  if (stage != Stage::Higher)
    selfContained = graph.containsItself();
  if (!selfContained.empty())
    return program.emitOpError("holds the data type \"")
           << selfContained.front().getName()
           << "\", which contains itself in place; a recursive type is held through a box";
  if (failed(knots(program, graph)))
    return failure();
  return stage == Stage::Owned ? reuses(program) : success();
}

LogicalResult idr::verify::function(FuncOp fn) {
  Stage stage = fn.getProgram().getStage();
  if (stage == Stage::Lowered)
    return fn.emitOpError("is an idr.func in a lowered program, which holds upstream's functions");
  if (failed(stageRules(fn, stage)) || failed(verifyFlow(fn)) || failed(linearity(fn)))
    return failure();
  return stage == Stage::Owned ? owned(fn) : success();
}
