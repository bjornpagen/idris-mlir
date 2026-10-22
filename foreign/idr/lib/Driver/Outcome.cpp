// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A compilation's diagnostics, folded into its outcome (Fold.h, the fold
// idris-mlir-opt's report shares) and then printed: an unlocated error in
// the driver's own form, any other diagnostic by MLIR's handler.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Fold.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

using namespace idr::driver;

namespace {

// The driver's printer: an error whose location holds no place in a file,
// which no source line shows, in the driver's own form, `<tool>: `, then
// the class of what it makes of the compilation, then its message, and its
// notes as MLIR's handler prints them. A refusal's message begins with its
// rule's head (refusalHead), so its class is in it; an internal error's is
// written here. Any other diagnostic goes on to MLIR's handler.
mlir::LogicalResult printUnlocated(mlir::Diagnostic &diagnostic,
                                   mlir::SourceMgrDiagnosticHandler &located) {
  if (diagnostic.getLocation()->findInstanceOf<mlir::FileLineColRange>())
    return mlir::failure();
  Verdict verdict = verdictOf(diagnostic.getSeverity(), idr::refusalRule(diagnostic));
  if (verdict == Verdict::Accepted)
    return mlir::failure();
  llvm::errs() << toolName << ": " << (verdict == Verdict::Internal ? "internal error: " : "")
               << diagnostic.str() << '\n';
  for (mlir::Diagnostic &note : diagnostic.getNotes())
    located.emitDiagnostic(note.getLocation(), note.str(), note.getSeverity());
  return mlir::success();
}

} // namespace

// The handlers run newest first: the fold sees every diagnostic, then the
// driver's printer takes the unlocated errors, and MLIR's handler prints the
// rest.
idr::driver::Diagnostics::Diagnostics(mlir::MLIRContext &context, Outcome &outcome)
    : located(sourceMgr, &context),
      unlocated(&context, [this](mlir::Diagnostic &diagnostic) {
        return printUnlocated(diagnostic, located);
      }) {
  context.getOrLoadDialect<idr::IdrDialect>();
  foldDiagnostics(context, outcome);
}
