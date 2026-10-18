// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: idr.func, idr.call and idr.return become func.func,
// func.call and func.return under the mangled names. A function's other
// facts were for the passes that are over, and go with the op.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/FuncToFunc.h"
#include "idr/Conversion/Mangle.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// Each function's name, mangled.
using Renames = DenseMap<StringAttr, StringAttr>;

// An idr.func as the func.func of its mangled name, its body moved whole;
// every use of the name already names the mangled one.
struct LowerFunc : OpRewritePattern<idr::FuncOp> {
  LowerFunc(MLIRContext *ctx, const Renames &mangled, StringAttr root)
      : OpRewritePattern(ctx), mangled(mangled), root(root) {}

  LogicalResult matchAndRewrite(idr::FuncOp fn, PatternRewriter &rewriter) const override {
    StringAttr name = mangled.at(fn.getSymNameAttr());
    auto lowered =
        func::FuncOp::create(rewriter, fn.getLoc(), name.getValue(), fn.getFunctionType());
    // The root is the one function the outside enters.
    lowered.setVisibility(name == root ? SymbolTable::Visibility::Public
                                       : SymbolTable::Visibility::Private);
    rewriter.inlineRegionBefore(fn.getBody(), lowered.getBody(), lowered.getBody().end());
    rewriter.eraseOp(fn);
    return success();
  }

  const Renames &mangled;
  StringAttr root;
};

struct LowerCall : OpRewritePattern<idr::CallOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<func::CallOp>(call, call.getCalleeAttr(), call.getResultTypes(),
                                              call.getArgs());
    return success();
  }
};

struct LowerReturn : OpRewritePattern<idr::ReturnOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(idr::ReturnOp ret, PatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<func::ReturnOp>(ret, ret.getOperands());
    return success();
  }
};

} // namespace

LogicalResult lowerFunctions(ProgramOp program) {
  MLIRContext *ctx = program.getContext();
  Region &body = program->getRegion(0);
  // The names of the program's other symbols, which keep theirs.
  DenseSet<StringAttr> kept;
  for (Operation &op : body.getOps())
    if (auto name = op.getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName());
        name && !isa<idr::FuncOp>(op))
      kept.insert(name);
  // The mangling is injective, so two functions keep two names; the one
  // meeting left is a function's mangled name with the name of another
  // symbol, which keeps its own, and which a symbol table would answer by
  // renaming one of the two.
  Renames mangled;
  for (auto fn : body.getOps<idr::FuncOp>()) {
    auto name = StringAttr::get(ctx, mangle(fn.getSymName()));
    if (kept.contains(name))
      return fn.emitError() << "internal error: idr-lower: @" << name.getValue()
                            << " names another symbol of the program";
    mangled[fn.getSymNameAttr()] = name;
  }

  // Every use of a function's name, whatever op holds it, names it mangled.
  // Types are left as they are: a data type's body is set once, and no
  // symbol of a function is held in one.
  AttrTypeReplacer rename;
  rename.addReplacement([&](FlatSymbolRefAttr ref) -> std::optional<Attribute> {
    // A reference to another symbol (a constant array) is not handled here,
    // and keeps its name.
    StringAttr to = mangled.lookup(ref.getAttr());
    return to ? std::optional<Attribute>(FlatSymbolRefAttr::get(to)) : std::nullopt;
  });
  rename.addReplacement(
      [](Type type) { return std::make_optional(std::make_pair(type, WalkResult::skip())); });
  rename.recursivelyReplaceElementsIn(program, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                      /*replaceTypes=*/false);

  // The ops themselves, each once, one for one. Serial: renaming the
  // definitions writes what every function's conversion reads.
  RewritePatternSet patterns(ctx);
  patterns.add<LowerFunc>(ctx, mangled, program.getRootAttr().getAttr());
  patterns.add<LowerCall, LowerReturn>(ctx);
  walkAndApplyPatterns(program, FrozenRewritePatternSet(std::move(patterns)));
  return success();
}

} // namespace idr::conversion
