// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of a program at the stage its idr.program says. The program's
// own, which its symbol-use verifier runs once every op of it is verified,
// on one thread: its root; each function's declared effects covering what
// its body may do; its data types, a memo sum only in a box, no array that
// can reach itself, and past the higher stage containment in place acyclic
// and no closure or suspension in a body; and the cells its reuses build
// in. And a function's, which its region verifier runs, in parallel with
// every other function's: what the stage lets its values hold, then its
// closures' flow, its linear values and its counting. The stage is read
// from the program, never from what a function holds.

#include "idr/IR/Flow.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/Support/ErrorHandling.h"

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

// Each function's declared effects cover what its body may do: what the
// body does itself (bodyEffect, the rule idr-effects solves by), what each
// function it calls declares, and everything for an idr.apply or an
// idr.force, whose callee is a value. A solve says too much of a function,
// never too little, so a set that misses a bit is the compiler's error, on
// which a pass that trusts it (idr-pure-calls) would drop an effect. A
// function without `effects` declares everything, which covers any body,
// so only a declared set is walked. Every callee is an idr.func of the
// program: the program's own verification ran each call's symbol-use check
// before its symbol-use verifier runs this.
LogicalResult effectsCovered(ProgramOp program) {
  SymbolTable symbols(program.getOperation());
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (!fn.getEffectsAttr())
      continue;
    Effect required = bodyEffect(fn);
    fn.getBody().walk([&](Operation *op) {
      if (auto call = dyn_cast<CallOp>(op))
        required = required | symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr()).getEffects();
      else if (isa<ApplyOp, ForceOp>(op))
        required = required | anyEffect;
    });
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
// never the program's; it is refused here, where every pass's input is
// checked, so that no layout is ever made for another target.
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

// Every idr.reuse builds in a cell of its own size: its token comes from an
// idr.take of a cell of the same size, as the target lays cells out. Only a
// reuse needs the sizes of cells, and the program's verifier runs where no
// pass rewrites a function beside it, so the layouts are built here, once.
LogicalResult reuses(ProgramOp program) {
  SmallVector<ReuseOp> reuses;
  program.walk([&](ReuseOp reuse) { reuses.push_back(reuse); });
  if (reuses.empty())
    return success();
  Layouts layouts(program.getOperation());
  for (ReuseOp reuse : reuses) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    if (!take)
      return reuse.emitOpError("builds in a token that no idr.take made");
    unsigned have = layouts.box(take.getDataType(), take.getTag()).size;
    unsigned need = layouts.box(reuse.getDataType(), reuse.getTag()).size;
    if (have != need)
      return reuse.emitOpError("builds a cell of ")
             << need << " bytes in the " << have << "-byte cell of @"
             << take.getDataType().getCtor(take.getTag()).name.getValue();
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

// What a stage says of the program's idr.func and data types, decided per
// stage with no default, so that a new stage decides each: whether
// closures and suspensions remain, which idr-defunctionalize makes sums,
// and with them the types that contain themselves in place, which it boxes
// (layout::fit); and whether references are counted, which idr-rc does,
// grading every value of ours that holds one and building its reuses.
// Nothing for the lowered stage, whose program holds upstream's functions
// and no idr.func.
struct StageFacts {
  bool closures;
  bool counted;
};

std::optional<StageFacts> factsOf(Stage stage) {
  switch (stage) {
  case Stage::Higher:
    return StageFacts{/*closures=*/true, /*counted=*/false};
  case Stage::First:
    return StageFacts{/*closures=*/false, /*counted=*/false};
  case Stage::Owned:
    return StageFacts{/*closures=*/false, /*counted=*/true};
  case Stage::Lowered:
    return std::nullopt;
  }
  llvm_unreachable("a stage of the program");
}

// What the program's stage lets the values of `fn` hold. A closure or a
// suspension exists only before idr-defunctionalize makes each a sum, and
// with it every idr.apply and idr.force, whose operands are such values; a
// grade own or excl only once idr-rc counts references, after which every
// reference of ours is graded.
LogicalResult stageRules(FuncOp fn, StageFacts stage) {
  bool pastHigher = !stage.closures;
  bool owned = stage.counted;
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
  if (failed(target(program)))
    return failure();
  // A lowered program is upstream's functions and globals: its root names
  // a func.func, and nothing of ours is left to hold to a rule.
  std::optional<StageFacts> stage = factsOf(program.getStage());
  if (!stage) {
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
  if (failed(rootType(root)) || failed(effectsCovered(program)))
    return failure();

  // The data types the program's values and bodies hold, each once.
  TypeGraph graph(program.getOperation());
  for (DataType data : graph.declarations()) {
    // A cell has one memo, which every reference to it sees.
    if (data.isMemo() && graph.inlined(data))
      return program.emitOpError("holds the memo sum \"")
             << data.getName() << "\" in place; a memo sum is held only in a box";
    if (stage->closures)
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
  if (!stage->closures)
    selfContained = graph.containsItself();
  if (!selfContained.empty())
    return program.emitOpError("holds the data type \"")
           << selfContained.front().getName()
           << "\", which contains itself in place; a recursive type is held through a box";
  if (failed(knots(program, graph)))
    return failure();
  return stage->counted ? reuses(program) : success();
}

LogicalResult idr::verify::function(FuncOp fn) {
  std::optional<StageFacts> stage = factsOf(fn.getProgram().getStage());
  if (!stage)
    return fn.emitOpError("is an idr.func in a lowered program, which holds upstream's functions");
  if (failed(stageRules(fn, *stage)) || failed(verifyFlow(fn)) || failed(linearity(fn)))
    return failure();
  return stage->counted ? owned(fn) : success();
}
