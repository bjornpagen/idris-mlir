// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges, solved once
// for the program (Ranges); this pass only reads it and rewrites. Nothing
// it learns is stored: the rewritten IR is the fact. Versioning runs on the
// program, since a versioned loop's copy holds values the solve never saw
// and the program is solved again after it; the word rewrite then runs on
// each function in parallel, each verified on its own. A narrowed op
// becomes `arith` on the values, which idr.big.to_int and idr.big.from_int
// convert where the web meets a big it does not prove; the pairs they form
// inside a web fold away.

#include "idr/Transforms/Narrow.h"

#include "idr/Analysis/Ranges.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Support/TypeID.h"
#include "mlir/Transforms/FoldUtils.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROW
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::narrow {

namespace {

// The word rewrite of one function, under the ranges idr-narrow solved for
// the program, which it holds for as long as the nested run reads them. It
// runs only inside idr-narrow and keeps no statistics: what it counts only
// says whether it changed anything.
struct NarrowWords : PassWrapper<NarrowWords, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NarrowWords)

  explicit NarrowWords(const Ranges &ranges) : ranges(ranges) {}

  StringRef getArgument() const final { return "idr-narrow-words"; }
  StringRef getDescription() const final {
    return "Make the bigs and naturals of one function proved to fit a small i64 words";
  }

  void runOnOperation() override {
    FuncOp fn = getOperation();
    Facts facts(ranges, fn.getProgram());
    uint64_t carried = 0, narrowed = 0;
    // The joints first, while every value is still the one analysed; then
    // the ops, whose operands may by then be the bigs of words.
    {
      RewritePatternSet joints(&getContext());
      populateJointPatterns(joints, facts, carried);
      walkAndApplyPatterns(fn, std::move(joints));
    }
    {
      RewritePatternSet words(&getContext());
      populateWordPatterns(words, facts, narrowed);
      walkAndApplyPatterns(fn, std::move(words));
    }

    // A word made a big and back is the word, and a conversion of a
    // constant is its constant: each conversion is folded once by its own
    // folder, defs first, so a conversion meets its operand final. Then
    // what no one reads goes, users first: the conversions made, a
    // versioned loop's start once its copy took the word, and a big made
    // of a word that every reader now takes as the word. Each walk asks
    // each conversion once, and ends with them.
    SmallVector<Operation *> conversions;
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (facts.made(op) || isa<BigSmallOp, BigFromIntOp>(op))
        conversions.push_back(op);
    });
    bool changed = false;
    OperationFolder folder(&getContext());
    SmallVector<Operation *> left;
    for (Operation *op : conversions) {
      // The folders of idr.big.to_int, idr.big.small and idr.big.from_int
      // return a constant, another op's value or nothing, never the op's
      // own result: a fold runs once, and replaces and erases the op.
      if (!op->hasTrait<OpTrait::ConstantLike>() && succeeded(folder.tryToFold(op))) {
        changed = true;
        continue;
      }
      left.push_back(op);
    }
    IRRewriter rewriter(&getContext());
    for (Operation *op : llvm::reverse(left))
      if (isOpTriviallyDead(op)) {
        rewriter.eraseOp(op);
        changed = true;
      }
    if (carried == 0 && narrowed == 0 && !changed)
      markAllAnalysesPreserved();
  }

  const Ranges &ranges;
};

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnOperation() override {
    ProgramOp program = getOperation();
    auto unsolved = [&] {
      program.emitError("internal error: idr-narrow: the range analysis failed");
      signalPassFailure();
    };
    FailureOr<std::unique_ptr<const Ranges>> ranges = Ranges::solve(program);
    if (failed(ranges))
      return unsolved();
    uint64_t versioned = 0;
    {
      Facts facts(**ranges, program);
      RewritePatternSet patterns(&getContext());
      populateVersionPatterns(patterns, facts, versioned);
      walkAndApplyPatterns(program, std::move(patterns));
    }
    // A versioned loop's copy holds values the first solve never saw, so
    // the program is solved again; otherwise the first solve is the one
    // the functions read.
    if (versioned != 0 && failed(ranges = Ranges::solve(program)))
      return unsolved();

    // The functions read the program's ranges, which outlive the nested
    // run.
    OpPassManager nested(ProgramOp::getOperationName());
    nested.nest<FuncOp>().addPass(std::make_unique<NarrowWords>(**ranges));
    if (failed(runPipeline(nested, program)))
      return signalPassFailure();
    numVersioned += versioned;
    // No declaration changes, and no symbol is added or removed.
    markAnalysesPreserved<TypeGraph, Layouts, SymbolTable>();
  }
};

} // namespace

} // namespace idr::narrow
