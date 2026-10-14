// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-isolate: the body of every idr.lambda and idr.delay gets a private
// function of its own, and the op becomes an idr.closure or an idr.suspend
// of it over the values the body uses from above.
//
// It goes innermost first: a lambda inside another is already a closure of
// its own function when the outer body is isolated, and the outer body then
// captures what that closure takes from above it. The bodies are collected
// first and outlined after, so that the walk never meets an op this pass
// moved. MLIR's isolation finds the captures, and clones into the body each
// constant it uses: a constant is code the function rebuilds, not a value
// the closure has to carry.
//
// An evaluated suspension, a delay whose body only yields a value from
// above, stays: forcing it computes nothing, and the dialect folds a force
// of it to the value. One whose value is a closure or a suspension is
// outlined like any other: a cell already forced holds it in its forced
// state, whose slot the keys of its type do not follow, so as a label of
// the cell it is one the analysis of labels sees.
#include "idr/Transforms/Isolate.h"

#include "idr/Analysis/Holds.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Twine.h"

namespace idr {
#define GEN_PASS_DEF_IDRISOLATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The results of the function a body becomes: the closure's, or the
// suspension's value. A body that never returns has them too.
SmallVector<Type> resultsOf(Operation *op) {
  if (auto lambda = dyn_cast<idr::LambdaOp>(op))
    return SmallVector<Type>(lambda.getType().getResults());
  return {cast<idr::LazyType>(idr::unrestricted(op->getResult(0).getType())).getValue()};
}

// What one function has had outlined from it: the bodies of each kind,
// which number the next one, and the last function made, which the next
// one follows, so that a function's code stays together in the order it is
// written.
struct Outlined {
  unsigned lambdas = 0;
  unsigned delays = 0;
  Operation *last = nullptr;
};

struct Isolate : idr::impl::IdrIsolateBase<Isolate> {
  void runOnOperation() override;
};

// The function of a body in `f` is `<f>.lam<n>` or `<f>.delay<n>`, `n`
// counting `f`'s bodies of that kind in the order they are outlined, from
// one, and its location names `f`'s Idris definition, by which idr-expect
// finds a definition's code wherever it was lifted to. Its code is `f`'s,
// so it breaks last when `f` does, and it is total: a body has no loop of
// its own, since a recursion goes through a function of the program, which
// carries its own proof or its absence.
void Isolate::runOnOperation() {
  ModuleOp module = getOperation();
  SmallVector<Operation *> bodies;
  module.walk<WalkOrder::PostOrder>([&](Operation *op) {
    if (isa<idr::LambdaOp>(op))
      bodies.push_back(op);
    else if (auto delay = dyn_cast<idr::DelayOp>(op)) {
      Value evaluated = idr::evaluatedValue(delay);
      if (!evaluated || idr::isClosureType(evaluated.getType()) ||
          idr::isLazyType(evaluated.getType()))
        bodies.push_back(op);
    }
  });
  if (bodies.empty())
    return markAllAnalysesPreserved();

  MLIRContext *ctx = module.getContext();
  SymbolTable &symbols = getAnalysis<SymbolTable>();
  IRRewriter rewriter(ctx);
  DenseMap<Operation *, Outlined> outlined;
  for (Operation *op : bodies) {
    auto enclosing = op->getParentOfType<idr::FuncOp>();
    if (!enclosing) {
      op->emitOpError("is outside a function, so its code has no definition");
      return signalPassFailure();
    }
    Outlined &from = outlined.try_emplace(enclosing, Outlined{0, 0, enclosing}).first->second;
    bool lambda = isa<idr::LambdaOp>(op);

    // Isolation appends the captures to the block's arguments; the function
    // takes them first, then the lambda's parameters.
    Region &body = op->getRegion(0);
    SmallVector<Value> captures = makeRegionIsolatedFromAbove(rewriter, body, [](Operation *def) {
      return isa<idr::ConstantOp, arith::ConstantOp>(def);
    });
    Block &isolated = body.front();
    size_t n = captures.size();
    SmallVector<BlockArgument> order;
    llvm::append_range(order, isolated.getArguments().take_back(n));
    llvm::append_range(order, isolated.getArguments().drop_back(n));
    SmallVector<Type> inputs;
    SmallVector<Location> locs;
    for (BlockArgument arg : order) {
      inputs.push_back(arg.getType());
      locs.push_back(arg.getLoc());
    }
    SmallVector<Type> results = resultsOf(op);

    std::string name = lambda ? (enclosing.getSymName() + ".lam" + Twine(++from.lambdas)).str()
                              : (enclosing.getSymName() + ".delay" + Twine(++from.delays)).str();
    // Emit gives every function a NameLoc of its definition, inside a fused
    // location for library code.
    auto definition = enclosing.getLoc()->findInstanceOf<NameLoc>();
    Location loc =
        NameLoc::get(definition ? definition.getName() : enclosing.getSymNameAttr(), op->getLoc());
    // Built unattached: the table places it.
    OpBuilder detached(ctx);
    auto fn = idr::FuncOp::create(detached, loc, name, FunctionType::get(ctx, inputs, results),
                                  rewriter.getStringAttr("private"), /*arg_attrs=*/{},
                                  /*res_attrs=*/{}, /*total=*/true,
                                  /*break_last=*/enclosing.getBreakLast(), /*no_inline=*/false,
                                  /*effects=*/{}, /*instance=*/{}, /*clone=*/{});
    // The table renames a name another function already has.
    StringAttr symbol = symbols.insert(fn, std::next(from.last->getIterator()));
    from.last = fn;

    Block *entry = rewriter.createBlock(&fn.getBody(), fn.getBody().end(), inputs, locs);
    SmallVector<Value> moved;
    llvm::append_range(moved, entry->getArguments().drop_front(n));
    llvm::append_range(moved, entry->getArguments().take_front(n));
    rewriter.mergeBlocks(&isolated, entry, moved);
    // The body's own yield returns; those of the matches in it stay theirs.
    if (auto yield = dyn_cast<idr::YieldOp>(entry->back())) {
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<idr::ReturnOp>(yield, yield.getResults());
    }

    rewriter.setInsertionPoint(op);
    auto callee = FlatSymbolRefAttr::get(symbol);
    Type type = op->getResult(0).getType();
    Value made =
        lambda ? Value(idr::ClosureOp::create(rewriter, op->getLoc(), type, callee, captures))
               : Value(idr::SuspendOp::create(rewriter, op->getLoc(), type, callee, captures));
    // A body that uses a linear value from above makes a closure or a
    // suspension holding it, whose one use must run it where it is made
    // or enter it into a linear type (their verifiers). The region form
    // has no such use to show: where the lambda was not taken once --
    // returned, as PrimIO.io_bind returns the action it builds over its
    // linear halves -- enter the closure into a linear type and use it
    // back out. The pair is its one use, and what reads the use reads an
    // ordinary value, as one read out of a linear field is.
    bool holds = llvm::any_of(captures, [](Value capture) {
      return idr::quantityOf(capture.getType()) == idr::Quantity::One;
    });
    if (holds && idr::quantityOf(type) == idr::Quantity::Many &&
        !idr::takenOnce(op->getResult(0))) {
      Value entered = idr::LinEnterOp::create(rewriter, op->getLoc(), idr::linear(type), made);
      made = idr::LinUseOp::create(rewriter, op->getLoc(), type, entered);
    }
    rewriter.replaceOp(op, made);
  }
  // Every function went in through the table; no declaration changed.
  markAnalysesPreserved<SymbolTable, idr::Holds, idr::TypeGraph, idr::Layouts>();
}

} // namespace
