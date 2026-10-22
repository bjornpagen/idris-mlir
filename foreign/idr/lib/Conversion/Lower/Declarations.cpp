// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower-runtime: every function of the runtime the lowering may call,
// declared once in the program, before any function is lowered, so that a
// function's lowering names its callee and writes nothing outside itself.
// Every function of the generated table is declared, in the table's order:
// which ones a program calls is decided only as its functions are lowered
// (the kind of each counted word, a cell's source), and a declaration no
// call names costs nothing past it. A runtime function's name is a C
// identifier, which holds no dot, and every program function's lowered
// name holds one (Mangle.h), so no declaration meets a program symbol.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

#define GEN_PASS_DEF_IDRLOWERRUNTIME
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

struct LowerRuntime : idr::impl::IdrLowerRuntimeBase<LowerRuntime> {
  using IdrLowerRuntimeBase::IdrLowerRuntimeBase;

  void runOnProgram(ProgramOp program) {
    Block &body = program->getRegion(0).front();
    Block::iterator first = body.begin();
    for (const idr::runtime::Function *function : idr::runtime::functions)
      body.getOperations().insert(first, runtimeDeclaration(program.getLoc(), *function));
    markAnalysesPreserved<Layouts>();
  }
};

} // namespace

} // namespace idr::conversion
