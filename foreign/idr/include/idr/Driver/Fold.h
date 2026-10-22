// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a run comes to its outcome, and the report written from it: each
// diagnostic folded into the verdict and the report's fields, each pass's
// statistics and footprint into the report's sums, and the refusals a
// module of the frontend's holds re-emitted as the diagnostics they are.
// idris-mlir and idris-mlir-opt write the one report, so both read it here;
// idris-mlir-opt links no driver library, and the definitions are inline.
#ifndef IDR_DRIVER_FOLD_H
#define IDR_DRIVER_FOLD_H

#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <system_error>
#include <utility>

namespace idr::driver {

namespace detail {

// A rule's phrase as one field of the report: each space written `-`. No
// phrase holds a `-`, so the field reads back as the phrase.
inline std::string asField(llvm::StringRef phrase) {
  std::string field = phrase.str();
  std::replace(field.begin(), field.end(), ' ', '-');
  return field;
}

// The severity as MLIR's printer writes it.
inline llvm::StringLiteral severityName(mlir::DiagnosticSeverity severity) {
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
inline std::string fieldsOf(mlir::Diagnostic &diagnostic, std::optional<idr::Rule> rule) {
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
class StatisticsInstrumentation final : public mlir::PassInstrumentation {
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

} // namespace detail

// What a diagnostic makes of the compilation: an error that names a rule
// refuses the program, any other error is the compiler's, and a note,
// warning or remark leaves the verdict as it was, which seeing Accepted,
// the least verdict, does.
inline Verdict verdictOf(mlir::DiagnosticSeverity severity, std::optional<idr::Rule> rule) {
  if (severity != mlir::DiagnosticSeverity::Error)
    return Verdict::Accepted;
  return rule ? Verdict::Refused : Verdict::Internal;
}

// Every diagnostic of `context`, from whichever thread delivers it, into
// `outcome`: the verdict it makes and its fields in the report. The handler
// then passes it on, to the ones registered before it that print it, so it
// is registered after them.
inline void foldDiagnostics(mlir::MLIRContext &context, Outcome &outcome) {
  context.getDiagEngine().registerHandler([&outcome](mlir::Diagnostic &diagnostic) {
    std::optional<idr::Rule> rule = idr::refusalRule(diagnostic);
    outcome.see(verdictOf(diagnostic.getSeverity(), rule));
    outcome.diagnostic(detail::fieldsOf(diagnostic, rule));
    return mlir::failure();
  });
}

// What every pass the manager runs adds to the report, as each of its runs
// ends: its footprint, the bytes the shared containers held beyond what
// they held when the run began, under `<pass>.footprint`, and each
// statistic's increase, each summed over the runs of every copy. A pass
// with no argument has no footprint of its own in the report: it is the
// manager's adaptor that runs a nest of them, whose name is a sentence the
// report's one-word key cannot hold, and what its nest holds is each nested
// pass's own footprint.
inline void foldPasses(mlir::PassManager &pm, Outcome &outcome) {
  pm.addInstrumentation(
      idr::profile::footprints([&outcome](mlir::Pass &pass, std::uint64_t bytes) {
        if (!pass.getArgument().empty())
          outcome.count((llvm::Twine(pass.getArgument()) + ".footprint").str(), bytes);
      }));
  pm.addInstrumentation(std::make_unique<detail::StatisticsInstrumentation>(outcome));
}

// The refusals the frontend left in the module in place of a program: one
// idr.refusal op each, at the module's top level, in the order found, its
// site the op's location and its rule a property. Each is emitted as the
// driver's diagnostic, its rule as data: this is their one printer, and
// foldDiagnostics their one fold into the verdict. A module the frontend
// could compile holds a program and no refusal. Failure when the module
// held one, which has then been said.
inline mlir::LogicalResult reemitRefusals(mlir::ModuleOp module) {
  auto refusals = module.getOps<idr::RefusalOp>();
  for (idr::RefusalOp refusal : refusals)
    idr::refuse(refusal.getLoc(), refusal.getRule()) << refusal.getMessage();
  return mlir::failure(!refusals.empty());
}

// The report at `path`, written from `outcome`, kept only once it is
// written whole; why it could not be otherwise, which each tool says in
// its own way: idris-mlir as its compilation's error, so the compilation
// keeps nothing, and idris-mlir-opt, whose contexts are gone by then, on
// standard error.
inline std::error_code writeReport(llvm::StringRef path, const Outcome &outcome) {
  std::error_code error;
  llvm::ToolOutputFile file(path, error, llvm::sys::fs::OF_Text);
  if (error)
    return error;
  outcome.write(file.os());
  file.os().flush();
  if (std::error_code written = file.os().error()) {
    file.os().clear_error();
    return written;
  }
  file.keep();
  return {};
}

} // namespace idr::driver

#endif // IDR_DRIVER_FOLD_H
