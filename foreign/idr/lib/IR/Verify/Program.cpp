// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a program at the stage its idr.program says, each stage's
// implications read through stageFacts. The program's own, which its
// region verifier runs after checking its root, once every op of it is
// verified, on one thread, at the module's read and after every pass on the
// program: its target; each function's declared effects covering what its
// body may do; its data types, a memo sum only in a box, and past the
// higher stage containment in place acyclic and no closure or suspension in
// a body; and in the owned stage its buffers' globals and the cells its
// recycles build in. And a function's, which its region verifier runs, in
// parallel with every other function's: what the stage lets its values and
// ops hold, then its closures' flow, its linear values and its counting.
// The stage is read from the program, never from what a function holds.

#include "idr/IR/Flow.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"

#include "idris_rt.h"

#include <optional>

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

// Each function's declared effects cover what its body may do: what the
// body does itself (bodyEffect, the rule idr-effects solves by, everything
// for an op that runs a label), and what each of its calls holds, which
// contains its callee's (the call's own verifier, which the program's
// symbol table runs before this). A solve says too much of a function,
// never too little, so a set that misses a bit is the compiler's error, on
// which a pass that reads a call's effects (CSE, dead-code removal) would
// drop an effect.
LogicalResult effectsCovered(ProgramOp program) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Effect required = bodyEffect(fn);
    fn.getBody().walk([&](CallOp call) { required = required | call.getEffects(); });
    Effect declared = fn.getEffects();
    if (!bitEnumContainsAll(declared, required))
      return fn.emitOpError("declares the effects ")
             << stringifyEffect(declared) << ", which do not cover what its body may do: "
             << stringifyEffect(required & ~declared);
  }
  return success();
}

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

// Every idr.cell.recycle gives a cell of its own size: its token comes
// from an idr.take of a cell of the same size, as the target lays cells
// out. Only a recycle needs the sizes of cells, and the program's verifier
// runs where no pass rewrites a function beside it, so the layouts are
// built here, once.
LogicalResult recycles(ProgramOp program) {
  SmallVector<CellRecycleOp> made;
  program.walk([&](CellRecycleOp recycle) { made.push_back(recycle); });
  if (made.empty())
    return success();
  Layouts layouts(program.getOperation());
  for (CellRecycleOp recycle : made) {
    auto take = recycle.getToken().getDefiningOp<TakeOp>();
    if (!take)
      return recycle.emitOpError("recycles a token that no idr.take made");
    CellType cell = recycle.getCell().getType();
    unsigned have = layouts.box(take.getDataType()).cell(take.getTag()).size;
    unsigned need = layouts.box(cell.getBox().getData()).cell(cell.getTag()).size;
    if (have != need)
      return recycle.emitOpError("gives a cell of ")
             << need << " bytes from the " << have << "-byte cell of @"
             << take.getDataType().getCtor(take.getTag()).name.getValue();
  }
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

// Whether `value` holds references at the plain grade where a graded
// program says what every reference is: a value of one of our types that
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

// What the program's stage lets an op of a function be, its values aside.
// No linalg op past the higher stage reads or writes an element that holds
// references, which idr-structure-loops makes only of arrays of words and
// counting so never meets. In the owned stage a buffer is a cell of the
// runtime: an allocation has the identity layout and an alignment of at
// most a word, its elements starting a word aligned and no more.
LogicalResult opRules(Operation *op, StageFacts stage) {
  if (auto linalg = dyn_cast<linalg::LinalgOp>(op); linalg && !stage.closures())
    for (BlockArgument element : linalg.getBlock()->getArguments())
      if (holdsReferences(element.getType()))
        return report(op, element) << "holds references, an element no linalg op reads or "
                                      "writes past the higher stage";
  if (auto alloc = dyn_cast<memref::AllocOp>(op); alloc && stage.counted()) {
    if (!alloc.getType().getLayout().isIdentity())
      return alloc.emitOpError("allocates ")
             << alloc.getType() << ", whose layout is not a cell's, the identity";
    if (std::optional<uint64_t> alignment = alloc.getAlignment();
        alignment && *alignment > IDRIS_RT_WORD_BYTES)
      return alloc.emitOpError("is aligned to ")
             << *alignment << " bytes, past a cell's element, whose alignment is at most "
             << IDRIS_RT_WORD_BYTES;
  }
  return success();
}

// What the program's stage lets the values of `fn` hold. A closure or a
// suspension exists only before idr-defunctionalize makes each a sum, and
// with it every idr.apply and idr.force, whose operands are such values; a
// grade own or excl only once idr-rc's grades step grades references, after
// which every reference of ours is graded; and once references are
// counted, every buffer is of a strided layout, whose descriptor the
// lowering reads.
LogicalResult stageRules(FuncOp fn, StageFacts stage) {
  bool pastHigher = !stage.closures();
  bool graded = stage.grades();
  if (pastHigher && llvm::any_of(fn.getResultTypes(), namesLabels))
    return fn.emitOpError("returns a closure or a suspension in a program past the higher stage, "
                          "where idr-defunctionalize has made each a sum");
  auto check = [&](Operation *op, Value value) -> LogicalResult {
    Type type = value.getType();
    if (pastHigher && namesLabels(type))
      return report(op, value) << "holds a closure or a suspension in a program past the higher "
                                  "stage, where idr-defunctionalize has made each a sum";
    if (!graded && isOwned(type))
      return report(op, value) << "is graded own or excl in a program before the graded stage, "
                                  "whose grades idr-rc gives";
    if (graded && plainReference(value))
      return report(op, value) << "holds references at the plain grade in a graded program, where "
                                  "a value of ours that holds one is owned, exclusive or "
                                  "borrowed";
    if (auto buffer = dyn_cast<MemRefType>(type);
        stage.counted() && buffer && !buffer.isStrided())
      return report(op, value) << "is a buffer of no strided layout, whose descriptor the "
                                  "lowering cannot read";
    return success();
  };
  WalkResult walked = fn->walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (failed(opRules(op, stage)))
      return WalkResult::interrupt();
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
  if (failed(target(program)))
    return failure();
  // A lowered program is upstream's functions and globals: nothing of ours
  // is left to hold to a rule.
  StageFacts stage = stageFacts(program.getStage());
  if (!stage.idrFunctions())
    return success();
  if (failed(effectsCovered(program)))
    return failure();

  // The data types the program's values and bodies hold, each once.
  TypeGraph graph(program.getOperation());
  for (DataType data : graph.declarations()) {
    // A cell has one memo, which every reference to it sees.
    if (data.isMemo() && graph.inlined(data))
      return program.emitOpError("holds the memo sum \"")
             << data.getName() << "\" in place; a memo sum is held only in a box";
    if (stage.closures())
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
  if (!stage.closures())
    selfContained = graph.containsItself();
  if (!selfContained.empty())
    return program.emitOpError("holds the data type \"")
           << selfContained.front().getName()
           << "\", which contains itself in place; a recursive type is held through a box";
  if (!stage.counted())
    return success();
  return failure(failed(globals(program)) || failed(recycles(program)));
}

LogicalResult idr::verify::function(FuncOp fn) {
  StageFacts stage = stageFacts(fn.getProgram().getStage());
  if (!stage.idrFunctions())
    return fn.emitOpError("is an idr.func in a lowered program, which holds upstream's functions");
  if (failed(stageRules(fn, stage)) || failed(verifyFlow(fn)) || failed(linearity(fn)))
    return failure();
  return stage.counted() ? owned(fn) : success();
}
