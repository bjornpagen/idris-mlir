// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// stage: the stage a program is at, as its idr.program says it, the one
// place it is said: what a pass that sets it set.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The module's program is at the stage written. A module idr-entry has
// taken the lowered functions out of holds no program, and so no stage.
LogicalResult stage(const Request<StageIs> &request) {
  Stage wanted = request.argument.stage;
  auto program = dyn_cast<ProgramOp>(programOf(request.module));
  if (!program)
    return fail(request.module->getLoc(), request.property) << "the module holds no program";
  if (program.getStage() == wanted)
    return success();
  return fail(program.getLoc(), request.property)
         << "the program is at stage " << stringifyStage(program.getStage()) << ", not "
         << stringifyStage(wanted);
}

} // namespace idr::expect
