// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the force of a memo cell. idr-defunctionalize
// makes each lazy type a memo sum, whose cell is in one of its states: a
// label with the captures of the label's function, `running` while a force
// computes the value, or `forced` with the value. A force switches on the
// state and calls the label's function directly, so no cell holds code.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Mangle.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the stack mark of a cell's info is a macro.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

FailureOr<Memos> readMemos(ModuleOp module, SymbolTable &symbols) {
  Memos memos;
  WalkResult result = module.walk([&](ForceOp force) {
    DataType memo = dataTypeOf(force.getSuspension().getType());
    if (!memo || !memo.isMemo()) {
      force.emitError("internal error: idr-lower: a force of a value that is not a memo cell");
      return WalkResult::interrupt();
    }
    auto [it, inserted] = memos.try_emplace(memo);
    if (!inserted)
      return WalkResult::advance();
    for (auto [tag, ctor] : llvm::enumerate(memo.getCtors())) {
      if (!memo.isLabel(static_cast<unsigned>(tag)))
        continue;
      auto callee = FlatSymbolRefAttr::get(module.getContext(), mangle(ctor.name.getValue()));
      auto fn = symbols.lookup<func::FuncOp>(callee.getAttr());
      if (!fn || fn.getNumArguments() != ctor.fields.size()) {
        force.emitError() << "internal error: idr-lower: no function @" << ctor.name.getValue()
                          << " takes the captures of its memo label";
        return WalkResult::interrupt();
      }
      it->second.push_back(MemoLabel{static_cast<unsigned>(tag), callee,
                                     llvm::map_to_vector(fn.getArgumentTypes(), [](Type type) {
                                       return isOwned(type);
                                     })});
    }
    return WalkResult::advance();
  });
  if (result.wasInterrupted())
    return failure();
  return memos;
}

namespace {

// One switch on the state of the cell. Its result is owned: one reference,
// the caller's.
//
// A view's force memoizes. A label moves the captures out to the forcer
// and marks the cell running, calls the function, then stores the value
// and marks the cell forced: the cell keeps one reference to the value,
// and the forcer gets another. A `by_name` label leaves the cell as it is,
// so that its function runs, with its effects, at every force. A forced
// cell's value gets one more reference. An owned force does the same, then
// gives up its reference to the cell.
//
// An exclusive force is the only one: nothing is memoized. The captures,
// or the value, move out, and the cell's memory goes.
//
// A running cell is one whose force forced it again before it had its
// value, which would never end.
struct LowerForce : IdrPattern<ForceOp> {
  LowerForce(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
             Runtime &runtime, const Memos &memos)
      : IdrPattern(converter, ctx, layouts, runtime), memos(memos) {}

  LogicalResult matchAndRewrite(ForceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type type = op.getSuspension().getType();
    DataType memo = dataTypeOf(type);
    ArrayRef<MemoLabel> labels = memos.find(memo)->second;
    Value cell = adaptor.getSuspension().front();
    bool exclusive = isExclusive(type);
    Type result = op.getType();
    Value tag = runtime.loadTag(rewriter, loc, cell);
    runtime.crashIf(rewriter, loc,
                    LLVM::ICmpOp::create(
                        rewriter, loc, LLVM::ICmpPredicate::eq, tag,
                        i32Constant(rewriter, loc, static_cast<int64_t>(memo.getRunningTag()))),
                    "a suspension forced itself");
    SmallVector<int64_t> tags = llvm::map_to_vector(
        labels, [](const MemoLabel &label) { return static_cast<int64_t>(label.tag); });
    Value index = arith::IndexCastUIOp::create(rewriter, loc, rewriter.getIndexType(), tag);
    auto states = scf::IndexSwitchOp::create(rewriter, loc, layouts.components(result), index,
                                             tags, static_cast<unsigned>(tags.size()));
    for (auto [label, region] : llvm::zip_equal(labels, states.getCaseRegions())) {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.createBlock(&region);
      scf::YieldOp::create(rewriter, loc,
                           forceLabel(rewriter, loc, memo, label, cell, result, exclusive));
    }
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.createBlock(&states.getDefaultRegion());
      scf::YieldOp::create(rewriter, loc, forced(rewriter, loc, memo, cell, result, exclusive));
    }
    if (isOwned(type) && !exclusive)
      runtime.dec(rewriter, loc, cell, {true});
    rewriter.replaceOpWithMultiple(op, {states.getResults()});
    return success();
  }

private:
  // The force of a cell in the state of `label`.
  SmallVector<Value> forceLabel(OpBuilder &b, Location loc, DataType memo, const MemoLabel &label,
                                Value cell, Type result, bool exclusive) const {
    const Ctor &ctor = memo.getCtor(label.tag);
    SmallVector<SmallVector<Value>> captures;
    for (const auto &slots : layouts.box(memo, label.tag).fields)
      captures.push_back(runtime.load(b, loc, cell, slots));
    if (exclusive) {
      runtime.call(b, loc, "idris_rt_free_cell", Type(), cell);
      SmallVector<Value> value = callLabel(b, loc, label, captures, result);
      releaseBorrowed(b, loc, ctor, label, captures);
      return value;
    }
    if (ctor.byName) {
      // The cell keeps its captures: an owned parameter gets one more
      // reference, and a borrowed one the cell's.
      for (auto [i, capture] : llvm::enumerate(captures))
        if (label.owned[i])
          runtime.inc(b, loc, capture, layouts.counted(ctor.fields[i]));
      return callLabel(b, loc, label, captures, result);
    }
    // The stack mark stays in every state the cell is written in: its
    // memory is its frame's.
    Value stack = LLVM::AndOp::create(b, loc, runtime.loadInfo(b, loc, cell),
                                      i32Constant(b, loc, IDRIS_RT_STACK_CELL));
    runtime.storeInfo(b, loc, cell, infoOf(b, loc, memo, memo.getRunningTag(), stack));
    SmallVector<Value> value = callLabel(b, loc, label, captures, result);
    runtime.store(b, loc, cell, layouts.box(memo, memo.getForcedTag()).fields.front(), value);
    runtime.storeInfo(b, loc, cell, infoOf(b, loc, memo, memo.getForcedTag(), stack));
    runtime.inc(b, loc, value, layouts.counted(result));
    releaseBorrowed(b, loc, ctor, label, captures);
    return value;
  }

  // The value of a forced cell: shared with the cell, one more reference,
  // or moved out of it by an exclusive force, which frees the cell.
  SmallVector<Value> forced(OpBuilder &b, Location loc, DataType memo, Value cell, Type result,
                            bool exclusive) const {
    SmallVector<Value> value =
        runtime.load(b, loc, cell, layouts.box(memo, memo.getForcedTag()).fields.front());
    if (exclusive)
      runtime.call(b, loc, "idris_rt_free_cell", Type(), cell);
    else
      runtime.inc(b, loc, value, layouts.counted(result));
    return value;
  }

  // A call of the label's function, whose name is the label's, with the
  // captures.
  SmallVector<Value> callLabel(OpBuilder &b, Location loc, const MemoLabel &label,
                               ArrayRef<SmallVector<Value>> captures, Type result) const {
    SmallVector<Value> args;
    for (const SmallVector<Value> &capture : captures)
      llvm::append_range(args, capture);
    auto call = func::CallOp::create(b, loc, label.callee, layouts.components(result), args);
    return SmallVector<Value>(call.getResults());
  }

  // The forcer owns each capture that moved out of the cell once: an owned
  // parameter took it over, and one the function borrowed is released
  // after the call.
  void releaseBorrowed(OpBuilder &b, Location loc, const Ctor &ctor, const MemoLabel &label,
                       ArrayRef<SmallVector<Value>> captures) const {
    for (auto [i, capture] : llvm::enumerate(captures))
      if (!label.owned[i])
        runtime.dec(b, loc, capture, layouts.counted(ctor.fields[i]));
  }

  // The info word of the state `state`, with the cell's stack mark.
  Value infoOf(OpBuilder &b, Location loc, DataType memo, unsigned state, Value stack) const {
    return arith::OrIOp::create(b, loc, i32Constant(b, loc, layouts.box(memo, state).info.word()),
                                stack);
  }

  const Memos &memos;
};

} // namespace

// The force of a memo cell. No suspension reaches the lowering:
// idr-defunctionalize has made each a constructor of a memo sum.
void populateLazyPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime, const Memos &memos) {
  patterns.add<LowerForce>(converter, patterns.getContext(), layouts, runtime, memos);
}

} // namespace idr::conversion
