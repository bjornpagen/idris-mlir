// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// stage: the stage a program is at, as its idr.program says it, the one
// place it is said: what a pass that sets it set.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// `stage=<higher|first|owned|lowered>`: the module's program is at it.
LogicalResult stage(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "stage";
  std::optional<Stage> wanted = symbolizeStage(argument);
  if (!wanted)
    return fail(module.getLoc(), property) << "name the stage, as stage=first";
  auto program = dyn_cast<ProgramOp>(programOf(module));
  if (!program)
    return fail(module.getLoc(), property) << "the module holds no program";
  if (program.getStage() == *wanted)
    return success();
  return fail(program.getLoc(), property) << "the program is at stage "
                                          << stringifyStage(program.getStage()) << ", not "
                                          << argument;
}

} // namespace idr::expect
