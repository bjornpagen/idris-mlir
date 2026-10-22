// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// --idr-expect-at: the properties a test states of a stage, checked as the
// pipeline runs (Expect.h says when each holds and when it fails).

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The stage a module's program is at, as its program says it; once the
// lowering has taken the program apart, the lowered one.
Stage stageOf(ModuleOp module) {
  if (auto program = dyn_cast<ProgramOp>(programOf(module)))
    return program.getStage();
  return Stage::Lowered;
}

// A run is checked when its op is the module or its program, which run on
// the pass manager's own thread; a pass on each function is checked as the
// nest that runs it on the program.
bool checked(Operation *op) { return isa<ModuleOp>(op) || isa<ProgramOp>(op); }

ModuleOp moduleOf(Operation *op) {
  if (auto module = dyn_cast<ModuleOp>(op))
    return module;
  return op->getParentOfType<ModuleOp>();
}

// The pass as MLIR writes it in a pipeline, for a person reading the error.
std::string nameOf(Pass *pass) {
  std::string name;
  llvm::raw_string_ostream os(name);
  pass->printAsTextualPipeline(os);
  return name;
}

// The property's text up to the next comma outside brackets and quotes,
// as MLIR reads a list option's items.
std::pair<StringRef, StringRef> nextItem(StringRef text) {
  unsigned depth = 0;
  char quote = 0;
  for (size_t at = 0; at != text.size(); ++at) {
    char c = text[at];
    if (quote) {
      quote = c == quote ? 0 : quote;
      continue;
    }
    switch (c) {
    case '"':
      quote = c;
      break;
    case '[':
    case '{':
    case '(':
    case '<':
      ++depth;
      break;
    case ']':
    case '}':
    case ')':
    case '>':
      depth -= depth != 0;
      break;
    case ',':
      if (depth == 0)
        return {text.take_front(at), text.drop_front(at + 1)};
      break;
    default:
      break;
    }
  }
  return {text, StringRef()};
}

// A request run once: its property's check of the module, its errors
// reported only when `report` says the request is held to it.
enum class Report : std::uint8_t { Quiet, Loud };

LogicalResult runOnce(const StageRequest &request, ModuleOp module, Report report) {
  ModuleAnalysisManager mam(module, /*passInstrumentor=*/nullptr);
  AnalysisManager analyses = mam;
  if (report == Report::Loud)
    return request.property->run(module, analyses, request.property->name, request.text);
  // Pending, a failure is no error: the property may not hold yet.
  ScopedDiagnosticHandler quiet(module.getContext(), [](Diagnostic &) { return success(); });
  return request.property->run(module, analyses, request.property->name, request.text);
}

} // namespace

FailureOr<SmallVector<StageRequest>> parseStageRequests(MLIRContext *context, StringRef written) {
  auto [stageText, rest] = written.split(':');
  std::optional<Stage> stage = symbolizeStage(stageText);
  if (!stage) {
    emitError(UnknownLoc::get(context)) << "--idr-expect-at: no stage named " << stageText;
    return failure();
  }
  SmallVector<StageRequest> out;
  while (!rest.empty()) {
    auto [item, after] = nextItem(rest);
    rest = after;
    auto [name, text] = item.split('=');
    const Property *property = lookup(name);
    if (!property) {
      emitError(UnknownLoc::get(context)) << "--idr-expect-at: no property named " << name;
      return failure();
    }
    out.push_back({*stage, property, text.str()});
  }
  return out;
}

StageInstrumentation::StageInstrumentation(SmallVector<StageRequest> requests) {
  for (StageRequest &request : requests)
    tracked.push_back({std::move(request), Seen::Pending});
}

bool StageInstrumentation::closePending(Stage stage, ModuleOp module) {
  bool held = true;
  for (Tracked &t : tracked) {
    if (t.request.stage != stage || t.seen == Seen::Held)
      continue;
    // Its own errors say where it fails.
    (void)runOnce(t.request, module, Report::Loud);
    module.emitError() << "expected " << t.request.property->name << " at the "
                       << stringifyStage(stage) << " stage: it never held there";
    held = false;
  }
  return held;
}

void StageInstrumentation::runAfterPass(Pass *pass, Operation *op) {
  if (!checked(op))
    return;
  ModuleOp module = moduleOf(op);
  Stage now = stageOf(module);
  bool held = true;
  if (current && *current != now)
    held = closePending(*current, module);
  current = now;
  for (Tracked &t : tracked) {
    if (t.request.stage != now)
      continue;
    switch (t.seen) {
    case Seen::Pending:
      if (succeeded(runOnce(t.request, module, Report::Quiet)))
        t.seen = Seen::Held;
      break;
    case Seen::Held:
      if (succeeded(runOnce(t.request, module, Report::Loud)))
        break;
      module.emitError() << "expected " << t.request.property->name << " at the "
                         << stringifyStage(now) << " stage: broken by " << nameOf(pass);
      held = false;
      break;
    }
  }
  if (!held)
    signalPassFailure(pass);
}

LogicalResult StageInstrumentation::finish(ModuleOp module) {
  if (!current)
    return success();
  return success(closePending(*current, module));
}

} // namespace idr::expect
