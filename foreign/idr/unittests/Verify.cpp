// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the program's verification between passes: a pass that says
// every function of a program does nothing, though its root writes to the
// world, then a pass that only notes it ran. The pass manager verifies the
// program after the first, which its rules refuse, so the second never
// runs.

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"

#include "gtest/gtest.h"

#include <memory>

using namespace mlir;

namespace {

// Says every function of the program does nothing.
struct ClearEffects : PassWrapper<ClearEffects, OperationPass<idr::ProgramOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ClearEffects)

  void runOnOperation() override {
    for (idr::FuncOp fn : getOperation().getOps<idr::FuncOp>())
      fn.setEffects(idr::Effect::none);
  }
};

// Notes that it ran.
struct Reached : PassWrapper<Reached, OperationPass<idr::ProgramOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Reached)

  explicit Reached(bool &reached) : reached(reached) {}
  void runOnOperation() override { reached = true; }

  bool &reached;
};

TEST(ProgramRules, ThePassManagerChecksThemAfterAProgramPass) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
idr.program @verified root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %nl = arith.constant 10 : i32
    %w1 = idr.io.put_char %nl, %w
    return %w1 : !idr.world
  }
}
)mlir",
                                                             &ctx);
  ASSERT_TRUE(module);
  // The refusal is the test's to expect, not to print.
  ScopedDiagnosticHandler quiet(&ctx, [](Diagnostic &) { return success(); });
  bool reached = false;
  PassManager pm(&ctx);
  OpPassManager &program = pm.nest<idr::ProgramOp>();
  program.addPass(std::make_unique<ClearEffects>());
  program.addPass(std::make_unique<Reached>(reached));
  EXPECT_TRUE(failed(pm.run(*module)));
  EXPECT_FALSE(reached);
}

} // namespace
