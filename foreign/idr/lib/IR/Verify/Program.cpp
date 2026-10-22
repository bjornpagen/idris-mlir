// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a program at the stage its idr.program says, each stage's
// implications read from the stage table. The program's own, which its
// region verifier runs after checking its root, once every op of it is
// verified, on one thread, at the module's read and after every pass on the
// program: its target; past the higher stage no family whose fields hold a
// closure or a suspension; and once counted its buffers' globals and the
// cells its recycles give. And a
// function's, which its region verifier runs, in parallel with every other
// function's: one walk of its body under every rule read per op (what the
// stage lets its values and ops hold, its scopes and refinements, its
// closures' flow while they exist, its effect row derived from its ops and
// held to what it says), then its linear values and its lifetimes. The
// stage is read from the program, never from what a function holds.
//
// What a data type is held as, whether a memo sum is in a cell and whether
// a type contains itself in place, is no rule here: the class rule decides
// each when the type is made, so no program can say otherwise.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "idr/IR/Generated/StageFacts.h.inc"

#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"

#include "idris_rt.h"

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// The runtime frees a cell by its object slots, which it reads as pointers
// of the target it is compiled for, one word each, and the layouts place
// them so. The module's data layout is the target entry's (idr-target),
// the one the runtime is built for, so a mismatch is the compiler's error,
// never the program's; it is refused with the program's rules, at the
// module's read and after every pass on the program, so that no layout is
// ever made for another target.
LogicalResult target(ProgramOp program) {
  DataLayout layout = DataLayout::closest(program);
  Type pointer = LLVM::LLVMPointerType::get(program.getContext());
  auto size = static_cast<uint64_t>(layout.getTypeSize(pointer).getFixedValue());
  uint64_t alignment = layout.getTypeABIAlignment(pointer);
  if (size != IDRIS_RT_WORD_BYTES || alignment != IDRIS_RT_WORD_BYTES)
    return program->emitError() << "the module's target is not the runtime's: its pointers take "
                                << size << " bytes at an alignment of " << alignment
                                << ", and the runtime's object slots are words of "
                                << IDRIS_RT_WORD_BYTES;
  return success();
}

// A buffer's static data is a cell of the runtime too, whose elements start
// a word aligned and no more.
LogicalResult globals(ProgramOp program) {
  for (memref::GlobalOp global : program.getOps<memref::GlobalOp>())
    if (std::optional<uint64_t> alignment = global.getAlignment();
        alignment && *alignment > IDRIS_RT_WORD_BYTES)
      return global.emitOpError("is aligned to ")
             << *alignment << " bytes, past a cell's element, whose alignment is at most "
             << IDRIS_RT_WORD_BYTES;
  return success();
}

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

// Past the higher stage every closure is a constructor of a sum, so no
// family the program's values reach declares a field of a closure or a
// suspension: each family the type graph reaches answers once.
LogicalResult firstOrderFamilies(ProgramOp program) {
  TypeGraph graph(program.getOperation());
  for (unsigned at = 0; at < graph.size(); ++at) {
    auto data = dyn_cast<DataType>(graph.type(at));
    if (data && data.getGroup().namesLabels())
      return program.emitOpError("holds the family of ")
             << data << ", a field of which holds a closure or a suspension past the higher "
             << "stage, where idr-defunctionalize has made each a sum";
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

// What the program's stage lets the ops and values of a function be. A
// closure or a suspension exists only before idr-defunctionalize makes
// each a sum, and with it every idr.fn.apply and idr.lazy.force, whose
// operands are such values; no linalg op past the higher stage reads or
// writes an element that holds references, which idr-structure-loops makes
// only of arrays of words and counting so never meets; and once references
// are counted, every buffer is of a strided layout, whose descriptor the
// lowering reads, and a buffer is a cell of the runtime: an allocation has
// the identity layout and an alignment of at most a word, its elements
// starting a word aligned and no more. While closures exist, each op is
// held to the flow rule.
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
    if (auto alloc = dyn_cast<memref::AllocOp>(op); alloc && counting == StageCounting::Counted) {
      if (!alloc.getType().getLayout().isIdentity())
        return alloc.emitOpError("allocates ")
               << alloc.getType() << ", whose layout is not a cell's, the identity";
      if (std::optional<uint64_t> alignment = alloc.getAlignment();
          alignment && *alignment > IDRIS_RT_WORD_BYTES)
        return alloc.emitOpError("is aligned to ")
               << *alignment << " bytes, past a cell's element, whose alignment is at most "
               << IDRIS_RT_WORD_BYTES;
    }
    for (Value result : op->getResults())
      if (failed(value(op, result)))
        return failure();
    return success();
  }

  void leave() {}

private:
  LogicalResult value(Operation *op, Value value) {
    Type type = value.getType();
    if (closures == StageClosures::FirstOrder && families::namesLabels(type))
      return report(op, value) << "holds a closure or a suspension in a program past the higher "
                                  "stage, where idr-defunctionalize has made each a sum";
    if (auto buffer = dyn_cast<MemRefType>(type);
        buffer && counting == StageCounting::Counted && !buffer.isStrided())
      return report(op, value) << "is a buffer of no strided layout, whose descriptor the "
                                  "lowering cannot read";
    return success();
  }

  StageClosures closures;
  StageCounting counting;
};

} // namespace

LogicalResult idr::verify::program(ProgramOp program) {
  if (failed(target(program)))
    return failure();
  // A lowered program is upstream's functions and globals: nothing of ours
  // is left to hold to a rule.
  Stage stage = program.getStage();
  if (functionsAt[stage] == StageFunctions::Lowered)
    return success();
  if (closuresAt[stage] == StageClosures::FirstOrder && failed(firstOrderFamilies(program)))
    return failure();
  if (countingAt[stage] == StageCounting::Counted)
    return failure(failed(globals(program)) || failed(recycles(program)));
  return success();
}

LogicalResult idr::verify::function(FuncOp fn) {
  Stage stage = fn.getProgram().getStage();
  if (functionsAt[stage] == StageFunctions::Lowered)
    return fn.emitOpError("is an idr.func in a lowered program, which holds upstream's functions");
  StageRules rules(closuresAt[stage], countingAt[stage]);
  families::ScopeWalk scopes(fn);
  rows::Check row(fn);
  if (failed(families::walkFunction(fn, rules, scopes, row)) || failed(linearity(fn)) ||
      failed(lifetimes(fn)))
    return failure();
  return success();
}
