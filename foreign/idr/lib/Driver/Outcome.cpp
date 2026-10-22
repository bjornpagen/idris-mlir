// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What MLIR reports of a compilation, folded into its outcome: each
// diagnostic, as the verdict it makes and the fields the report writes of
// it, then printed; and each pass's statistics, through MLIR's pass
// instrumentation.

#include "idr/Driver/Compile.h"

#include "idr/Driver/Report.h"
#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>

using namespace idr::driver;

namespace {

// A rule's phrase as one field of the report: each space written `-`. No
// phrase holds a `-`, so the field reads back as the phrase.
std::string asField(llvm::StringRef phrase) {
  std::string field = phrase.str();
  std::replace(field.begin(), field.end(), ' ', '-');
  return field;
}

// The severity as MLIR's printer writes it.
llvm::StringLiteral severityName(mlir::DiagnosticSeverity severity) {
  switch (severity) {
  case mlir::DiagnosticSeverity::Note:
    return "note";
  case mlir::DiagnosticSeverity::Warning:
    return "warning";
  case mlir::DiagnosticSeverity::Error:
    return "error";
  case mlir::DiagnosticSeverity::Remark:
    return "remark";
  }
  llvm_unreachable("every severity has its name");
}

// A diagnostic's fields in the report, `<severity> <rule> <file:line>`: the
// rule it refuses the program by and the first file location its location
// holds, each `-` where it has none. No field holds the rule's category: it
// is the specification's, a function of the rule, which a reader joins on
// the rule as refusalHead does. No field names a pass: a handler is
// given the diagnostic alone, and a group MLIR runs in parallel replays its
// diagnostics after the group, so where one is delivered says nothing of
// the pass that emitted it.
std::string fieldsOf(mlir::Diagnostic &diagnostic, std::optional<idr::Rule> rule) {
  std::string fields;
  llvm::raw_string_ostream os(fields);
  os << severityName(diagnostic.getSeverity()) << ' '
     << (rule ? asField(idr::stringifyRule(*rule)) : "-") << ' ';
  if (auto file = diagnostic.getLocation()->findInstanceOf<mlir::FileLineColRange>())
    os << file.getFilename().getValue() << ':' << file.getStartLine();
  else
    os << '-';
  return fields;
}

// What a diagnostic makes of the compilation: an error that names a rule
// refuses the program, any other error is the compiler's, and a note,
// warning or remark leaves the verdict as it was, which seeing Accepted,
// the least verdict, does.
Verdict verdictOf(mlir::DiagnosticSeverity severity, std::optional<idr::Rule> rule) {
  if (severity != mlir::DiagnosticSeverity::Error)
    return Verdict::Accepted;
  return rule ? Verdict::Refused : Verdict::Internal;
}

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

// The report's statistics, on MLIR's hooks around every run of every pass
// of the pipeline: as a run begins, the value of each of the pass's
// statistics, and as it ends, each one's increase over the run, added into
// the outcome under `<pass>.<statistic>`, the pass named by its argument,
// or by its name when it has none. No upstream reading of the totals fits:
// MLIR merges the statistics of a pass's copies only where it prints them,
// and the copies its groups and dynamic pipelines run are out of reach of
// its public API, so each run is read as it ends. A pass instance runs once
// at a time, a copy on one worker, so its values are held by instance for
// the length of its run. The runs of every copy add into the one sum, the
// same however many threads they were spread over.
class StatisticsInstrumentation : public mlir::PassInstrumentation {
public:
  explicit StatisticsInstrumentation(Outcome &outcome) : outcome(outcome) {}

  void runBeforePass(mlir::Pass *pass, mlir::Operation *) override {
    llvm::SmallVector<uint64_t, 4> values;
    for (const mlir::Pass::Statistic *statistic : pass->getStatistics())
      values.push_back(statistic->getValue());
    std::lock_guard<std::mutex> lock(mutex);
    before.insert_or_assign(pass, std::move(values));
  }

  void runAfterPass(mlir::Pass *pass, mlir::Operation *) override { end(pass); }

  void runAfterPassFailed(mlir::Pass *pass, mlir::Operation *) override { end(pass); }

private:
  void end(mlir::Pass *pass) {
    llvm::SmallVector<uint64_t, 4> values;
    {
      std::lock_guard<std::mutex> lock(mutex);
      auto found = before.find(pass);
      values = std::move(found->second);
      before.erase(found);
    }
    llvm::StringRef name = pass->getArgument().empty() ? pass->getName() : pass->getArgument();
    for (auto [statistic, value] : llvm::zip_equal(pass->getStatistics(), values))
      outcome.count((llvm::Twine(name) + "." + statistic->getName()).str(),
                    statistic->getValue() - value);
  }

  Outcome &outcome;
  std::mutex mutex;
  llvm::DenseMap<mlir::Pass *, llvm::SmallVector<uint64_t, 4>> before;
};

} // namespace

void idr::driver::foldDiagnostics(mlir::MLIRContext &context, Outcome &outcome) {
  context.getDiagEngine().registerHandler([&outcome](mlir::Diagnostic &diagnostic) {
    std::optional<idr::Rule> rule = idr::refusalRule(diagnostic);
    outcome.see(verdictOf(diagnostic.getSeverity(), rule));
    outcome.diagnostic(fieldsOf(diagnostic, rule));
    return mlir::failure();
  });
}

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

std::unique_ptr<mlir::PassInstrumentation> idr::driver::foldStatistics(Outcome &outcome) {
  return std::make_unique<StatisticsInstrumentation>(outcome);
}
