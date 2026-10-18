// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-knots: a program whose types let an array reach itself is refused,
// once every closure is a constructor of a sum, so that the program's type
// graph holds every cell a value may point at. No count frees a knot: the
// refusal is the memory model's, on the type graph's cycles, a total
// analysis (verify::knots).
#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/IR/Verify.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Pipeline.h"

namespace idr {
#define GEN_PASS_DEF_IDRKNOTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

struct Knots : idr::impl::IdrKnotsBase<Knots> {
  void runOnProgram(idr::ProgramOp program) override {
    if (mlir::failed(idr::verify::knots(program, getAnalysis<idr::TypeGraph>())))
      return signalPassFailure();
    markAllAnalysesPreserved();
  }
};

} // namespace
