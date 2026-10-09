// idr.lower:closures: phase 2 of idr-lower for the force of a memo cell.
// idr-defunctionalize makes each lazy type a memo sum, whose cell is in one
// of its states: a label with the captures of the label's function,
// `running` while a force computes the value, or `forced` with the value.
// A force switches on the state and calls the label's function directly,
// so no cell holds code.
module;
// The runtime's C ABI: the stack mark of a cell's info is a macro.
#include "idris_rt.h"

export module idr.lower:closures;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// A label of a memo sum, and for each capture whether the label's function
// takes it owned: idr-rc may make the function borrow a parameter, whose
// type is then plain. Nothing when the module has no function of the
// label's name taking its captures.
struct Label {
  CtorOp ctor;
  std::optional<SmallVector<bool>> owned;
};

// A memo sum as a force reads it: its two states, read by name, and its
// labels.
struct Memo {
  CtorOp running, forced;
  SmallVector<Label> labels;
};

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
  // The memo sums are read before the conversion starts: it rewrites each
  // label function's signature, and the grades in it, when it meets the
  // function.
  LowerForce(const TypeConverter &converter, MLIRContext *ctx, layout::Layouts &layouts,
             Runtime &runtime)
      : IdrPattern(converter, ctx, layouts, runtime) {
    ModuleOp module = layouts.getModule();
    SymbolTable symbols(module);
    for (auto data : module.getOps<DataOp>()) {
      if (!idr::isMemo(data))
        continue;
      Memo &memo = memos[data.getSymNameAttr()];
      for (CtorOp ctor : data.getCtors()) {
        if (ctor.getSymName() == memoRunning) {
          memo.running = ctor;
          continue;
        }
        if (ctor.getSymName() == memoForced) {
          memo.forced = ctor;
          continue;
        }
        Label &label = memo.labels.emplace_back(Label{ctor, std::nullopt});
        auto fn = symbols.lookup<func::FuncOp>(ctor.getSymNameAttr());
        if (fn && fn.getNumArguments() == ctor.getFieldTypes().size())
          label.owned = llvm::map_to_vector(fn.getArgumentTypes(),
                                            [](Type type) { return isOwned(type); });
      }
    }
  }

  LogicalResult matchAndRewrite(ForceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type type = op.getSuspension().getType();
    FlatSymbolRefAttr sum = getSumName(unrestricted(type));
    auto it = sum ? memos.find(sum.getAttr()) : memos.end();
    if (it == memos.end())
      return op.emitError("internal error: idr-lower: a force of a value that is not a memo cell");
    const Memo &memo = it->second;
    if (!CtorOp(memo.running) || !CtorOp(memo.forced))
      return op.emitError() << "internal error: idr-lower: a memo sum without @" << memoRunning
                            << " or @" << memoForced;
    for (const Label &label : memo.labels)
      if (!label.owned)
        return op.emitError() << "internal error: idr-lower: no function @"
                              << CtorOp(label.ctor).getSymName()
                              << " takes the captures of its memo label";

    Value cell = adaptor.getSuspension().front();
    bool exclusive = isExclusive(type);
    Type result = op.getType();
    Value tag = runtime.loadTag(rewriter, loc, cell);
    runtime.crashIf(rewriter, loc,
                    LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, tag,
                                         i32Constant(rewriter, loc, tagOf(memo.running))),
                    "a suspension forced itself");
    SmallVector<int64_t> labels =
        llvm::map_to_vector(memo.labels, [](const Label &label) { return tagOf(label.ctor); });
    Value index = arith::IndexCastUIOp::create(rewriter, loc, rewriter.getIndexType(), tag);
    auto states = scf::IndexSwitchOp::create(rewriter, loc, layouts.components(result), index,
                                             labels, static_cast<unsigned>(labels.size()));
    for (auto [label, region] : llvm::zip_equal(memo.labels, states.getCaseRegions())) {
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
  static int64_t tagOf(CtorOp ctor) { return static_cast<int64_t>(ctor.getTag()); }

  // The force of a cell in the state of `label`.
  SmallVector<Value> forceLabel(OpBuilder &b, Location loc, const Memo &memo, const Label &label,
                                Value cell, Type result, bool exclusive) const {
    CtorOp ctor = label.ctor;
    SmallVector<SmallVector<Value>> captures;
    for (const auto &slots : layouts.box(ctor).fields)
      captures.push_back(runtime.load(b, loc, cell, slots));
    if (exclusive) {
      runtime.call(b, loc, "idris_rt_free_cell", Type(), cell);
      SmallVector<Value> value = callLabel(b, loc, ctor, captures, result);
      releaseBorrowed(b, loc, label, captures);
      return value;
    }
    if (ctor.getByName()) {
      // The cell keeps its captures: an owned parameter gets one more
      // reference, and a borrowed one the cell's.
      for (auto [i, capture] : llvm::enumerate(captures))
        if ((*label.owned)[i])
          runtime.inc(b, loc, capture,
                      layouts.counted(ctor.getFieldType(static_cast<unsigned>(i))));
      return callLabel(b, loc, ctor, captures, result);
    }
    // The stack mark stays in every state the cell is written in: its
    // memory is its frame's.
    Value stack = LLVM::AndOp::create(b, loc, runtime.loadInfo(b, loc, cell),
                                      i32Constant(b, loc, IDRIS_RT_STACK_CELL));
    runtime.storeInfo(b, loc, cell, infoOf(b, loc, memo.running, stack));
    SmallVector<Value> value = callLabel(b, loc, ctor, captures, result);
    runtime.store(b, loc, cell, layouts.box(memo.forced).fields.front(), value);
    runtime.storeInfo(b, loc, cell, infoOf(b, loc, memo.forced, stack));
    runtime.inc(b, loc, value, layouts.counted(result));
    releaseBorrowed(b, loc, label, captures);
    return value;
  }

  // The value of a forced cell: shared with the cell, one more reference,
  // or moved out of it by an exclusive force, which frees the cell.
  SmallVector<Value> forced(OpBuilder &b, Location loc, const Memo &memo, Value cell, Type result,
                            bool exclusive) const {
    SmallVector<Value> value = runtime.load(b, loc, cell, layouts.box(memo.forced).fields.front());
    if (exclusive)
      runtime.call(b, loc, "idris_rt_free_cell", Type(), cell);
    else
      runtime.inc(b, loc, value, layouts.counted(result));
    return value;
  }

  // A call of the label's function, whose name is the label's, with the
  // captures.
  SmallVector<Value> callLabel(OpBuilder &b, Location loc, CtorOp ctor,
                               ArrayRef<SmallVector<Value>> captures, Type result) const {
    SmallVector<Value> args;
    for (const SmallVector<Value> &capture : captures)
      llvm::append_range(args, capture);
    auto call =
        func::CallOp::create(b, loc, ctor.getSymNameAttr(), layouts.components(result), args);
    return SmallVector<Value>(call.getResults());
  }

  // The forcer owns each capture that moved out of the cell once: an owned
  // parameter took it over, and one the function borrowed is released
  // after the call.
  void releaseBorrowed(OpBuilder &b, Location loc, const Label &label,
                       ArrayRef<SmallVector<Value>> captures) const {
    CtorOp ctor = label.ctor;
    for (auto [i, capture] : llvm::enumerate(captures))
      if (!(*label.owned)[i])
        runtime.dec(b, loc, capture, layouts.counted(ctor.getFieldType(static_cast<unsigned>(i))));
  }

  // The info word of the state `state`, with the cell's stack mark.
  Value infoOf(OpBuilder &b, Location loc, CtorOp state, Value stack) const {
    return arith::OrIOp::create(b, loc, i32Constant(b, loc, layouts.box(state).info.word()), stack);
  }

  DenseMap<StringAttr, Memo> memos;
};

} // namespace

// The force of a memo cell. No suspension reaches the lowering:
// idr-defunctionalize has made each a constructor of a memo sum.
export void populateLazyPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerForce>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
