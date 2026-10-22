// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-columns: every array of records of the program held as its columns,
// in one partial conversion of the program. The conversion is total on the
// program: every op it takes has its pattern, and every op it does not
// take keeps the array whole, gathered and taken apart where it meets it.
// A pattern that fails would be this pass's own error, never the
// program's.

#include "idr/Transforms/Columns.h"

#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRCOLUMNS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::columns {

void populateColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                            ConversionTarget &target) {
  // Every op the conversion does not take holds an array of records whole:
  // the conversion leaves it, gathering the array it is given and taking
  // apart the one it gives. Each op it takes is legal by the legality its
  // pattern is added with.
  target.markUnknownOpDynamicallyLegal([](Operation *) { return true; });
  populateCallColumnPatterns(converter, patterns, target);
  populateTensorColumnPatterns(converter, patterns, target);
  populateArrayColumnPatterns(converter, patterns, target);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, patterns, target);
}

namespace {

// idr-columns holds the program's arrays of records as their columns, in
// one conversion; the unit is the program.
struct ColumnsConvertAction : idr::support::TaggedAction<ColumnsConvertAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::columnsConvert;
};

struct Columns : idr::impl::IdrColumnsBase<Columns> {
  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = &getContext();
    Records records(program);
    ColumnConverter converter(records);
    RewritePatternSet patterns(ctx);
    ConversionTarget target(*ctx);
    populateColumnPatterns(converter, patterns, target);
    // A function whose signature carries an array of records is remade
    // with its columns, its facts moved by position; each call holds
    // copies of its callee's, which it takes again once every signature
    // is final, and stands where its columns now flow, its tail fact
    // decided again there.
    bool remade = llvm::any_of(program.getOps<FuncOp>(), [&](FuncOp fn) {
      return !converter.isSignatureLegal(fn.getFunctionType());
    });
    (void)idr::support::perform<ColumnsConvertAction>(program, [&] {
      if (failed(applyPartialConversion(program, target, std::move(patterns)))) {
        program.emitError("internal error: idr-columns: an array of records was left "
                          "neither held as its columns nor gathered");
        return signalPassFailure();
      }
      if (!remade)
        return;
      SymbolTable functions(program);
      program.walk([&](CallOp call) {
        call.copyCallee(functions.lookup<FuncOp>(call.getCalleeAttr().getAttr()));
        call.setTailKind(tail::decide(call));
      });
    });
  }
};

} // namespace

} // namespace idr::columns
