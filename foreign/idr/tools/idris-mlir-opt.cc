// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered. Like idris-mlir-cc, it runs on the runtime's reserved-stack
// runner, so the nested constants MLIR's parser and printer recurse over
// are bounded by memory, not by the process's stack.
// PIN(mlir-recursion) — see PINS.md

#include "idr/Idr.h"

#include "idris_rt.h"

#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include <unistd.h>

namespace {

// Upstream's test pass of the same name, which the pinned mlir-opt, built
// without MLIR's test passes, lacks: tests/upstream/uplift-final-counter
// runs upstream's reproducer through it. PIN(uplift-final-counter)
struct UpliftWhileToFor
    : mlir::PassWrapper<UpliftWhileToFor, mlir::OperationPass<void>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(UpliftWhileToFor)
  llvm::StringRef getArgument() const final { return "test-scf-uplift-while-to-for"; }
  llvm::StringRef getDescription() const final {
    return "Apply upstream's scf.while to scf.for uplift patterns";
  }
  void runOnOperation() override {
    mlir::RewritePatternSet patterns(&getContext());
    mlir::scf::populateUpliftWhileToForPatterns(patterns);
    if (mlir::failed(mlir::applyPatternsGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};

struct Invocation {
  int argc;
  char **argv;
  int status = 1;
};

void optMain(void *argument) {
  auto &invocation = *static_cast<Invocation *>(argument);
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  mlir::PassRegistration<UpliftWhileToFor>();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdr(registry);
  invocation.status = mlir::asMainReturnCode(mlir::MlirOptMain(
      invocation.argc, invocation.argv, "idris-mlir-opt: the idr dialect\n", registry));
}

// From the fault handler: only write and _exit.
[[noreturn]] void exhausted() {
  static constexpr char message[] = "idris-mlir-opt: the stack is exhausted\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(1);
}

} // namespace

int main(int argc, char **argv) {
  Invocation invocation{argc, argv};
  if (idris_rt_run_on_stack(optMain, &invocation, size_t{1} << 44, size_t{1} << 20,
                            exhausted) != 0) {
    static constexpr char message[] = "idris-mlir-opt: no stack could be reserved\n";
    (void)!write(2, message, sizeof message - 1);
    return 1;
  }
  return invocation.status;
}
